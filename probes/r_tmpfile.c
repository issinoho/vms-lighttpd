/* r_tmpfile.c - lighttpd keeps request bodies over 64 KB in a temporary file:
   fd = mkostemp(path, O_CLOEXEC | O_APPEND), write() pieces, then pread()
   from the same fd to forward them (chunk.c; with HAVE_PWRITE the pieces
   are written with pwrite() at the current length).  Phase 3: on VMS the pread()
   came back empty (503 for uploads).  Try each step with and without
   O_APPEND, and pread() with and without fsync() first. */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static char wbuf[100000], rbuf[100000];

static void trial(int flags, int do_fsync, int use_pwrite, const char *what)
{
  char path[64];
  struct stat st;
  int fd, i, r, w = 0, ok;
  strcpy(path, "tmpprobe-XXXXXX");
  fd = mkostemp(path, O_CLOEXEC | flags);
  if (fd < 0) { printf("TMP %-28s mkostemp failed: %s\n", what, strerror(errno)); return; }
  for (i = 0; i < (int) sizeof wbuf; i += 16384) {
    int n = (int) sizeof wbuf - i < 16384 ? (int) sizeof wbuf - i : 16384;
    r = use_pwrite ? (int) pwrite(fd, wbuf + i, n, (off_t) w) : (int) write(fd, wbuf + i, n);
    if (r > 0) w += r;
  }
  if (do_fsync) fsync(fd);
  fstat(fd, &st);
  printf("TMP %-28s wrote %d, fstat size %ld, rfm %d\n", what, w, (long) st.st_size, (int) st.st_fab_rfm);
  errno = 0;
  r = (int) pread(fd, rbuf, 16384, 0);
  ok = r == 16384 && memcmp(rbuf, wbuf, 16384) == 0;
  printf("TMP %-28s pread(16384 @ 0)     -> %d %s %s\n", what, r, ok ? "match" : "MISMATCH", r < 0 ? strerror(errno) : "");
  errno = 0;
  r = (int) pread(fd, rbuf, 16384, 65536);
  ok = r == 16384 && memcmp(rbuf, wbuf + 65536, 16384) == 0;
  printf("TMP %-28s pread(16384 @ 65536) -> %d %s %s\n", what, r, ok ? "match" : "MISMATCH", r < 0 ? strerror(errno) : "");
  /* a second descriptor, as a FastCGI backend reading the file would */
  {
    int fd2 = open(path, O_RDONLY);
    errno = 0;
    r = fd2 >= 0 ? (int) pread(fd2, rbuf, 16384, 0) : -1;
    printf("TMP %-28s 2nd fd pread @ 0    -> %d %s\n", what, r, r < 0 ? strerror(errno) : "");
    if (fd2 >= 0) close(fd2);
  }
  close(fd);
  unlink(path);
}

int main(void)
{
  int i;
  for (i = 0; i < (int) sizeof wbuf; i++) wbuf[i] = (char) (i * 7);
  trial(O_APPEND, 0, 0, "O_APPEND write");
  trial(O_APPEND, 1, 0, "O_APPEND write + fsync");
  trial(0, 0, 0, "no O_APPEND write");
  trial(O_APPEND, 0, 1, "O_APPEND pwrite (lighttpd)");
  trial(0, 0, 1, "no O_APPEND pwrite");
  trial(0, 1, 1, "no O_APPEND pwrite + fsync");
  printf("R_TMPFILE DONE\n");
  return 0;
}
