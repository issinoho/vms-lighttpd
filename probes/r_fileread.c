/* r_fileread.c <file> - how fast can a process read a large stream-LF file
   the ways lighttpd does: read() in 16 KB and 64 KB blocks, pread() at
   increasing offsets, and mmap() of 512 KB windows (chunk.c).  Phase 2
   downloads ran at ~100-160 KB/s with the server mostly idle. */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

static double secs(struct timeval *t0)
{
  struct timeval t1;
  gettimeofday(&t1, NULL);
  return (t1.tv_sec - t0->tv_sec) + (t1.tv_usec - t0->tv_usec) / 1e6;
}

static char buf[65536];
#define LIMIT (20L * 1048576)   /* read the first 20 MB in each test */

static void by_read(const char *f, int bs)
{
  struct timeval t0;
  long total = 0;
  int n, fd = open(f, O_RDONLY);
  gettimeofday(&t0, NULL);
  while (total < LIMIT && (n = (int) read(fd, buf, bs)) > 0) total += n;
  printf("READ read(%5d): %ld bytes in %.2f s = %.1f MB/s\n", bs, total, secs(&t0),
         total / 1048576.0 / secs(&t0));
  close(fd);
}

static void by_pread(const char *f, int bs)
{
  struct timeval t0;
  long total = 0;
  int n, fd = open(f, O_RDONLY);
  gettimeofday(&t0, NULL);
  while (total < LIMIT && (n = (int) pread(fd, buf, bs, total)) > 0) total += n;
  printf("READ pread(%5d): %ld bytes in %.2f s = %.1f MB/s\n", bs, total, secs(&t0),
         total / 1048576.0 / secs(&t0));
  close(fd);
}

static void by_reopen(const char *f, int bs)
{
  /* open + pread + close per block, as a server might per request piece */
  struct timeval t0;
  long total = 0;
  int n = 1, fd;
  gettimeofday(&t0, NULL);
  while (total < 2L * 1048576 && n > 0) {
    fd = open(f, O_RDONLY);
    n = (int) pread(fd, buf, bs, total);
    close(fd);
    if (n > 0) total += n;
  }
  printf("READ open+pread(%5d)+close: %ld bytes in %.2f s = %.1f MB/s\n", bs, total, secs(&t0),
         total / 1048576.0 / secs(&t0));
}

static void by_mmap(const char *f, long win)
{
  struct timeval t0;
  long off = 0, sum = 0;
  int fd = open(f, O_RDONLY), i;
  gettimeofday(&t0, NULL);
  while (off < LIMIT) {
    char *m = mmap(NULL, (size_t) win, PROT_READ, MAP_PRIVATE, fd, off);
    if (m == MAP_FAILED) { printf("READ mmap failed at %ld: %s\n", off, strerror(errno)); break; }
    for (i = 0; i < win; i += 512) sum += m[i];   /* touch every block */
    munmap(m, (size_t) win);
    off += win;
  }
  printf("READ mmap(%ld windows): %ld bytes in %.2f s = %.1f MB/s (sum %ld)\n", win, off,
         secs(&t0), off / 1048576.0 / secs(&t0), sum & 1);
  close(fd);
}

int main(int argc, char **argv)
{
  struct stat st;
  const char *f = argc > 1 ? argv[1] : "big.bin";
  if (stat(f, &st) != 0) { printf("READ stat %s: %s\n", f, strerror(errno)); return 1; }
  printf("READ %s: %ld bytes\n", f, (long) st.st_size);
  by_read(f, 16384);
  by_read(f, 65536);
  by_pread(f, 65536);
  by_reopen(f, 65536);
  by_mmap(f, 524288);
  printf("R_FILEREAD DONE\n");
  return 0;
}
