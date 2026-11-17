# Wi-Fi Bring-up Notes (ESP32-C3 Super Mini)

Operational notes gathered while validating the NuttX Wi-Fi station path on
`esp32c3-supermini`. Most items here are pitfalls that cost time once; keep
them in mind before re-debugging from scratch.

## Current status

- STA association and WPA2-PSK 4-way handshake work.
- DHCP works once the link is stable and no stale static address is present.
- Verified session: `invo-lan`, channel 11, BSSID `ca:cd:55:b8:52:81`,
  RSSI about -60 dBm, lease `10.4.70.3/23`, gateway `10.4.71.250`.
- Remaining risk: link stability is sensitive to the board's antenna/ground
  contact and to transmit power. This is a hardware issue, not a NuttX one.

## Hardware notes

1. Antenna / ground contact
   - Symptom observed: Wi-Fi associates (`connected`, `WPA2-PSK`, about
     -60 dBm), then drops after a few seconds with `reason 2` /
     `reason 205`, then cannot re-associate until the board is touched.
   - Touching or pressing the board immediately restored the link. That only
     happens when the antenna feed, ground plane, or shield contact is
     intermittent.
   - Keep the board-edge antenna area clear of fingers, metal cases, batteries
     and metal tables. Reflow/check the antenna feed and matching parts, or
     swap in a known-good board.

2. Supply / transmit power
   - ESP32-C3 transmit peaks can exceed 300 mA. Thin or long USB cables, weak
     hubs, and marginal LDOs cause drops that look like Wi-Fi failures.
   - Use a short, thick cable and a powered port.
   - If the boot banner timestamp restarts around the disconnect, the board is
     actually browning out and resetting; the disconnect is a symptom.
   - With the local setup, 8 dBm was noticeably more stable than the default
     20 dBm:

     ```console
     nsh> wapi txpower wlan0 8 WAPI_TXPOWER_DBM
     ```

     This is not persistent; put it in `/data/boot.nsh`.

3. RF environment
   - `invo-lan` is served by many BSSIDs (channels 1/6/11). Automatic AP
     selection can land on a -80 dBm BSSID and then fail at the auth stage.
     Pinning a strong BSSID helped in this environment:

     ```console
     nsh> wapi ap wlan0 ca:cd:55:b8:52:81
     ```

     Note that `wapi ap` returns `ESP_ERR_WIFI_SSID` when the SSID has not been
     configured yet; the BSSID is still stored, so the following `wapi essid`
     connects with it.

## Required command sequence

`ifup` must come first: the driver only calls `esp_wifi_start()` from the
netdev `ifup` hook, so scans and WPA configuration fail before that.

```console
nsh> ifconfig wlan0 0.0.0.0        # drop any stale static address
nsh> ifup wlan0
nsh> wapi psk wlan0 invo@123456 3  # 3 = CCMP; optional 4th arg = WPA version
nsh> wapi essid wlan0 invo-lan 1   # 1 = ON, triggers connect
nsh> renew wlan0
```

Semantics worth knowing:

- `wapi psk <if> <pass> <alg> [wpa]`
  - `alg` is the cipher flag (`1` WEP, `2` TKIP, `3` CCMP), not the WPA
    version.
  - The optional 4th argument selects the WPA version (`1` WPA, `2` WPA2,
    default, `3` WPA3).
  - The command writes the key and then disconnects; it does not connect.
- `wapi essid <if> <ssid> 1`
  - `1` means `WAPI_ESSID_ON`. The netdev layer calls the driver connect hook
    right after the SSID is set, and blocks for
    `CONFIG_ESPRESSIF_WIFI_CONNECT_TIMEOUT` (10 s default).
  - A timeout return code does not mean the link will never come up: the
    driver keeps reconnecting in the background (`g_sta_reconnect`), so verify
    with `ifconfig` instead of the command status.
- DHCP uses the address already assigned to the interface as the source for
  `DHCPDISCOVER`/`DHCPREQUEST`. A stale address from another subnet can get the
  broadcasts dropped by DHCP snooping; clear it with
  `ifconfig wlan0 0.0.0.0` before `renew`.

## Interpreting status output

- `ifconfig` is the authoritative link indicator:
  - `at RUNNING` -> associated and carrier on;
  - `at UP` -> interface up but not associated;
  - `at DOWN` -> interface down.
- `wapi show <if>` has misleading fields:
  - `Flag: WAPI_ESSID_OFF` is always shown because the ESP driver's get path
    does not fill `u.essid.flags`;
  - `AP: ff:ff:ff:ff:ff:ff` means "not associated" and is reliable;
  - `Sense: -65` (or any value while not associated) is a stale stack value,
    not a real RSSI;
  - `IP` reflects whatever is configured, including a stale static address.
- `wapi scan` prints an empty list when the scan was not allowed (for example
  while the STA is still connecting: `ESP_ERR_WIFI_STATE`, 12294).

## Error codes seen in practice

| Message | Meaning |
| --- | --- |
| `reason: 2` (`AUTH_EXPIRE`) | auth frame sent, AP did not answer: weak BSSID, RF/antenna problem, or AP policy |
| `reason: 205` (`CONNECTION_FAIL`) | aggregate connection failure, usually follows repeated auth failures |
| `ESP_ERR_WIFI_SSID` (12298) | SSID not configured when a connect was triggered |
| `ESP_ERR_WIFI_CONN` (12295) | connect requested while another connect was in flight |
| `dhcpc request failed: -1` | generic `ERROR`; does not distinguish send failure from "no OFFER received" |

For DHCP, compare `cat /proc/net/dev` before and after `renew`: TX growth means
DISCOVER left the interface; RX growth means an OFFER came back. The duration
also helps: an immediate failure is a send-path problem, roughly 9 s means
3 x 3 s of receive timeouts.

## Debug logging pitfall

All NuttX `DEBUG_*` options live inside `if DEBUG_FEATURES` in `nuttx/Kconfig`.
Without `CONFIG_DEBUG_FEATURES=y`, entries such as
`CONFIG_DEBUG_WIRELESS_ERROR=y` or `CONFIG_DEBUG_NET_ERROR=y` are silently
dropped by Kconfig, and the firmware stays silent even though the defconfig
claims otherwise. Enable the umbrella switch plus the per-subsystem ones
temporarily:

```
CONFIG_DEBUG_ERROR=y
CONFIG_DEBUG_FEATURES=y
CONFIG_DEBUG_INFO=y
CONFIG_DEBUG_NET=y
CONFIG_DEBUG_NET_ERROR=y
CONFIG_DEBUG_WIRELESS=y
CONFIG_DEBUG_WIRELESS_ERROR=y
CONFIG_DEBUG_WIRELESS_INFO=y
```

Verify after configuring with `grep CONFIG_DEBUG_FEATURES nuttx/.config`.
These options are for debugging only and are not kept in the board defconfig.
`dmesg` is not available in this configuration; syslog goes straight to the
serial console.

## TODO

- Persist the working sequence (power, BSSID, credentials, `renew`) in
  `/data/boot.nsh`.
- Validate link stability over a long run once the antenna/ground contact and
  supply are fixed.
- Re-check whether BSSID pinning is still needed when the hardware is stable.
