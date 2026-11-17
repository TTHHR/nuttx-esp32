/****************************************************************************
 * ClawdMochi POSIX validation application.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 ****************************************************************************/

#include <nuttx/config.h>

#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <semaphore.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>

#ifndef CONFIG_EXAMPLES_CLAWDMOCHI_POSIX_ITERATIONS
#  define CONFIG_EXAMPLES_CLAWDMOCHI_POSIX_ITERATIONS 25
#endif

#define WORKER_COUNT 4
#define ITERATIONS CONFIG_EXAMPLES_CLAWDMOCHI_POSIX_ITERATIONS

static pthread_mutex_t g_lock;
static pthread_cond_t g_condition;
static sem_t g_start_sem;
static sem_t g_done_sem;
static volatile uint32_t g_counter;
static volatile uint32_t g_done_count;
static volatile int g_error;

static int test_fail(const char *name, int error)
{
  fprintf(stderr, "FAIL: %s (%d)\n", name, error);
  return -1;
}

static void *worker_main(void *argument)
{
  int i;

  (void)argument;

  if (sem_wait(&g_start_sem) != 0)
    {
      g_error = errno;
      return NULL;
    }

  for (i = 0; i < ITERATIONS; i++)
    {
      if (pthread_mutex_lock(&g_lock) != 0)
        {
          g_error = EINVAL;
          return NULL;
        }

      g_counter++;

      if (pthread_mutex_unlock(&g_lock) != 0)
        {
          g_error = EINVAL;
          return NULL;
        }

      sched_yield();
    }

  if (pthread_mutex_lock(&g_lock) != 0)
    {
      g_error = EINVAL;
      return NULL;
    }

  g_done_count++;
  if (g_done_count == WORKER_COUNT &&
      pthread_cond_broadcast(&g_condition) != 0)
    {
      g_error = EINVAL;
    }

  if (pthread_mutex_unlock(&g_lock) != 0)
    {
      g_error = EINVAL;
    }

  if (sem_post(&g_done_sem) != 0)
    {
      g_error = errno;
    }

  return NULL;
}

int main(int argc, FAR char *argv[])
{
  pthread_t threads[WORKER_COUNT];
  struct timespec start;
  struct timespec finish;
  int64_t elapsed_ns = 0;
  int mutex_ready = 0;
  int condition_ready = 0;
  int start_ready = 0;
  int done_ready = 0;
  int created = 0;
  int result = 0;
  int i;
  int ret;

  (void)argc;
  (void)argv;

  printf("ClawdMochi NuttX POSIX validation\n");
  printf("workers=%d iterations=%d\n", WORKER_COUNT, ITERATIONS);

  g_counter = 0;
  g_done_count = 0;
  g_error = 0;

  ret = pthread_mutex_init(&g_lock, NULL);
  if (ret != 0)
    {
      return test_fail("pthread_mutex_init", ret);
    }

  mutex_ready = 1;

  ret = pthread_cond_init(&g_condition, NULL);
  if (ret != 0)
    {
      result = test_fail("pthread_cond_init", ret);
      goto out;
    }

  condition_ready = 1;

  if (sem_init(&g_start_sem, 0, 0) != 0)
    {
      result = test_fail("sem_init(start)", errno);
      goto out;
    }

  start_ready = 1;

  if (sem_init(&g_done_sem, 0, 0) != 0)
    {
      result = test_fail("sem_init(done)", errno);
      goto out;
    }

  done_ready = 1;

  if (clock_gettime(CLOCK_MONOTONIC, &start) != 0)
    {
      result = test_fail("clock_gettime(start)", errno);
      goto out;
    }

  for (i = 0; i < WORKER_COUNT; i++)
    {
      ret = pthread_create(&threads[i], NULL, worker_main, NULL);
      if (ret != 0)
        {
          result = test_fail("pthread_create", ret);
          goto out;
        }

      created++;
    }

  for (i = 0; i < WORKER_COUNT; i++)
    {
      if (sem_post(&g_start_sem) != 0)
        {
          result = test_fail("sem_post(start)", errno);
          goto out;
        }
    }

  for (i = 0; i < WORKER_COUNT; i++)
    {
      if (sem_wait(&g_done_sem) != 0)
        {
          result = test_fail("sem_wait(done)", errno);
          goto out;
        }
    }

  if (pthread_mutex_lock(&g_lock) != 0)
    {
      result = test_fail("pthread_mutex_lock(main)", EINVAL);
      goto out;
    }

  while (g_done_count < WORKER_COUNT)
    {
      ret = pthread_cond_wait(&g_condition, &g_lock);
      if (ret != 0)
        {
          pthread_mutex_unlock(&g_lock);
          result = test_fail("pthread_cond_wait", ret);
          goto out;
        }
    }

  pthread_mutex_unlock(&g_lock);

  if (clock_gettime(CLOCK_MONOTONIC, &finish) != 0)
    {
      result = test_fail("clock_gettime(finish)", errno);
      goto out;
    }

  elapsed_ns =
    ((int64_t)finish.tv_sec - (int64_t)start.tv_sec) * 1000000000LL +
    ((int64_t)finish.tv_nsec - (int64_t)start.tv_nsec);

  if (g_error != 0)
    {
      result = test_fail("worker", g_error);
    }
  else if (g_counter != WORKER_COUNT * ITERATIONS)
    {
      fprintf(stderr, "FAIL: counter=%lu expected=%u\n",
              (unsigned long)g_counter,
              (unsigned int)(WORKER_COUNT * ITERATIONS));
      result = -1;
    }

out:
  for (i = 0; i < created; i++)
    {
      pthread_join(threads[i], NULL);
    }

  if (done_ready)
    {
      sem_destroy(&g_done_sem);
    }

  if (start_ready)
    {
      sem_destroy(&g_start_sem);
    }

  if (condition_ready)
    {
      pthread_cond_destroy(&g_condition);
    }

  if (mutex_ready)
    {
      pthread_mutex_destroy(&g_lock);
    }

  if (result == 0)
    {
      printf("elapsed_ns=%lld counter=%lu\n",
             (long long)elapsed_ns, (unsigned long)g_counter);
      printf("PASS: pthread + mutex + cond + sem + clock + sched\n");
      return 0;
    }

  printf("FAIL: POSIX validation\n");
  return 1;
}
