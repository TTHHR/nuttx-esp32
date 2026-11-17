#!/usr/bin/env bash

set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
nuttx_dir=${NUTTX_DIR:-"$root_dir/nuttx"}
apps_dir=${NUTTX_APPS_DIR:-"$root_dir/nuttx-apps"}
board_dir="$nuttx_dir/boards/risc-v/esp32c3/esp32c3-supermini"

if [ ! -f "$nuttx_dir/tools/configure.sh" ]; then
  echo "Missing NuttX source. Run: git submodule update --init --recursive" >&2
  exit 1
fi

if [ ! -f "$apps_dir/Application.mk" ]; then
  echo "Missing NuttX apps source. Run: git submodule update --init --recursive" >&2
  exit 1
fi

install -d "$board_dir/configs/clawdmochi"
install -m 0644 "$root_dir/config/clawdmochi/defconfig" \
  "$board_dir/configs/clawdmochi/defconfig"

# The application overlay lives in nuttx-apps so that "configure.sh -a" can
# see it.  Copying it here is idempotent; if the copy and the tracked overlay
# differ, the nuttx-apps submodule reports a modified file instead of silently
# building a stale application.

apps_overlay="$root_dir/apps/clawdmochi_posix"

if [ -d "$apps_overlay" ]; then
  install -d "$apps_dir/examples/clawdmochi_posix"

  for src in "$apps_overlay"/*; do
    [ -f "$src" ] || continue
    install -m 0644 "$src" "$apps_dir/examples/clawdmochi_posix/$(basename "$src")"
  done
fi

lock_headers=(
  "$nuttx_dir/arch/risc-v/src/common/espressif/platform_include/sys/lock.h"
  "$nuttx_dir/arch/risc-v/src/chip/esp-hal-3rdparty/components/esp_libc/platform_include/sys/lock.h"
  "$nuttx_dir/arch/risc-v/src/esp32c3/esp-hal-3rdparty/components/esp_libc/platform_include/sys/lock.h"
)

for header in "${lock_headers[@]}"; do
  [ -f "$header" ] || continue
  python3 - "$header" <<'PY'
import sys

path = sys.argv[1]
needle = "#include_next <sys/lock.h>"
replacement = """#ifndef _RETARGETABLE_LOCKING
#define _RETARGETABLE_LOCKING 1
#endif

#ifndef _LOCK_T
#define _LOCK_T int
#endif

#ifndef _LOCK_RECURSIVE_T
#define _LOCK_RECURSIVE_T int
#endif

#ifndef _LOCK_INITIALIZER
#define _LOCK_INITIALIZER 0
#endif"""

with open(path, encoding="utf-8") as f:
    text = f.read()

if needle in text:
    text = text.replace(needle, replacement, 1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
PY
done

# NuttX's libc does not provide the newlib headers that the Espressif HAL
# sources expect.  Install minimal shims into the arch platform_include
# directory (already on the include path via hal_<chip>.mk).

platform_include="$nuttx_dir/arch/risc-v/src/common/espressif/platform_include"

if [ -d "$platform_include" ]; then
  install -d "$platform_include/sys" "$platform_include/machine"

  cat > "$platform_include/sys/cdefs.h" <<'EOF'
/*
 * NuttX compatibility shim for <sys/cdefs.h>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef _SYS_CDEFS_H_
#define _SYS_CDEFS_H_

#ifdef __cplusplus
#  define __BEGIN_DECLS extern "C" {
#  define __END_DECLS   }
#else
#  define __BEGIN_DECLS
#  define __END_DECLS
#endif

#ifndef __P
#  ifdef __STDC__
#    define __P(args) args
#  else
#    define __P(args) ()
#  endif
#endif

#ifndef __THROW
#  ifdef __cplusplus
#    define __THROW noexcept(true)
#  else
#    define __THROW
#  endif
#endif

#ifndef __THROWNL
#  define __THROWNL __THROW
#endif

#ifndef __nonnull
#  define __nonnull(params) __attribute__((__nonnull__ params))
#endif

#ifndef __pure
#  define __pure __attribute__((__pure__))
#endif

#ifndef __const
#  define __const __attribute__((__const__))
#endif

#ifndef __dead2
#  define __dead2 __attribute__((__noreturn__))
#endif

#ifndef __packed
#  define __packed __attribute__((__packed__))
#endif

#ifndef __offsetof
#  define __offsetof(type, field) __builtin_offsetof(type, field)
#endif

#ifndef __containerof
#  define __containerof(ptr, type, member) \
    ((type *)((unsigned char *)(ptr) - __offsetof(type, member)))
#endif

#ifndef __aligned
#  define __aligned(x) __attribute__((__aligned__(x)))
#endif

#ifndef __unused
#  define __unused __attribute__((__unused__))
#endif

#ifndef __used
#  define __used __attribute__((__used__))
#endif

#ifndef __printflike
#  define __printflike(fmtarg, firstvararg) \
    __attribute__((__format__(__printf__, fmtarg, firstvararg)))
#endif

#ifndef __scanflike
#  define __scanflike(fmtarg, firstvararg) \
    __attribute__((__format__(__scanf__, fmtarg, firstvararg)))
#endif

#ifndef __weak_reference
#  define __weak_reference(sym, alias) \
    __asm__(".weak " #alias);          \
    __asm__(".equ " #alias ", " #sym)
#endif

#ifndef __RCSID
#  define __RCSID(s)
#endif

#ifndef __FBSDID
#  define __FBSDID(s)
#endif

#ifndef __IDSTRING
#  define __IDSTRING(name, string)
#endif

#ifndef __COPYRIGHT
#  define __COPYRIGHT(s)
#endif

#endif /* _SYS_CDEFS_H_ */
EOF

  cat > "$platform_include/sys/reent.h" <<'EOF'
/*
 * NuttX compatibility shim for <sys/reent.h>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef _SYS_REENT_H_
#define _SYS_REENT_H_

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

struct _reent
{
  int _nuttx_placeholder;
};

/* Note: __getreent() is a real function implemented by the port, do not
 * provide a macro for it here.
 */

#ifdef __cplusplus
}
#endif

#endif /* _SYS_REENT_H_ */
EOF

  cat > "$platform_include/reent.h" <<'EOF'
/*
 * NuttX compatibility shim for <reent.h>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef _REENT_H_
#define _REENT_H_

#include <sys/reent.h>

#endif /* _REENT_H_ */
EOF

  for hdr in errno unistd termios utime; do
    guard=$(printf '_SYS_%s_H_' "$(printf '%s' "$hdr" | tr 'a-z' 'A-Z')")
    cat > "$platform_include/sys/$hdr.h" <<EOF
/*
 * NuttX compatibility shim for <sys/$hdr.h>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef $guard
#define $guard

#include <$hdr.h>

#endif /* $guard */
EOF
  done

  cat > "$platform_include/machine/endian.h" <<'EOF'
/*
 * NuttX compatibility shim for <machine/endian.h>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#ifndef _MACHINE_ENDIAN_H_
#define _MACHINE_ENDIAN_H_

#include <sys/endian.h>

#endif /* _MACHINE_ENDIAN_H_ */
EOF
fi

echo "NuttX integration files installed."
