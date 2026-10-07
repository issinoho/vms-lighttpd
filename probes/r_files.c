/* r_files.c - can lighttpd serve a file's bytes with a correct Content-Length?
   lighttpd takes the length from stat().st_size and then sends the file with
   pread()/read() or mmap().  On VMS that only adds up for stream files:
   for variable/fixed record files the CRTL adds or removes record
   terminators, so the bytes read differ from st_size.  For each record
   format, compare st_size, bytes from read(), from pread() at an offset, and
   from mmap(). */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define LINES 40
#define LINELEN 50   /* 49 characters + '\n' */

static void make_text(char *buf)
{
  int i, j;
  for (i = 0; i < LINES; i++) {
    for (j = 0; j < LINELEN - 1; j++) buf[i * LINELEN + j] = (char) ('a' + (i + j) % 26);
    buf[i * LINELEN + LINELEN - 1] = '\n';
  }
}

static void trial(const char *name, const char *rfm, const char *rat, const char *mrs)
{
  char want[LINES * LINELEN], got[LINES * LINELEN * 2];
  struct stat st;
  FILE *f;
  int fd, n, r, i;
  long total = 0;
  void *m;

  make_text(want);
  remove(name);
  if (mrs)
    f = fopen(name, "w", rfm, mrs);
  else if (rat)
    f = fopen(name, "w", rfm, rat);
  else
    f = fopen(name, "w", rfm);
  if (!f) { printf("FILE %-8s create failed: %s\n", name, strerror(errno)); return; }
  for (i = 0; i < LINES; i++) fwrite(want + i * LINELEN, 1, LINELEN, f);
  fclose(f);

  stat(name, &st);
  fd = open(name, O_RDONLY);
  while ((n = (int) read(fd, got + total, sizeof got - total)) > 0) total += n;
  printf("FILE %-8s %-9s wrote %d  st_size %ld  read %ld  same-bytes %s\n", name, rfm,
         LINES * LINELEN, (long) st.st_size, total,
         total == LINES * LINELEN && memcmp(want, got, total) == 0 ? "yes" : "NO");

  r = (int) pread(fd, got, 100, 1000);
  printf("FILE %-8s pread(100 @ 1000) %d  matches %s\n", name, r,
         r == 100 && memcmp(got, want + 1000, 100) == 0 ? "yes" : "NO");
  printf("FILE %-8s lseek(SEEK_END) %ld\n", name, (long) lseek(fd, 0, SEEK_END));

  m = mmap(NULL, (size_t) st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
  if (m == MAP_FAILED)
    printf("FILE %-8s mmap failed: %s\n", name, strerror(errno));
  else {
    printf("FILE %-8s mmap ok  first-%d-bytes-match %s\n", name, LINES * LINELEN,
           st.st_size >= LINES * LINELEN && memcmp(m, want, LINES * LINELEN) == 0 ? "yes" : "NO");
    munmap(m, (size_t) st.st_size);
  }
  close(fd);
  remove(name);
}

int main(void)
{
  trial("f_stmlf.txt", "rfm=stmlf", NULL, NULL);
  trial("f_stm.txt", "rfm=stm", NULL, NULL);
  trial("f_var.txt", "rfm=var", "rat=cr", NULL);
  trial("f_fix.txt", "rfm=fix", NULL, "mrs=512");
  trial("f_udf.txt", "rfm=udf", NULL, NULL);

  /* A large stream-LF file: pread at offsets past 2 GB is not needed, but
     files of tens of MB are (phpBB attachments, downloads). */
  {
    static char block[65536];
    int fd = open("f_big.dat", O_WRONLY | O_CREAT | O_TRUNC, 0644), i, r;
    struct stat st;
    for (i = 0; i < (int) sizeof block; i++) block[i] = (char) i;
    for (i = 0; i < 160; i++) write(fd, block, sizeof block);   /* 10 MB */
    close(fd);
    stat("f_big.dat", &st);
    fd = open("f_big.dat", O_RDONLY);
    r = (int) pread(fd, block, 4096, 9 * 1048576 + 7);
    printf("FILE f_big   st_size %ld  pread(4096 @ 9MB+7) %d  first byte %s\n", (long) st.st_size,
           r, r > 0 && (unsigned char) block[0] == (unsigned char) ((9 * 1048576 + 7) & 0xff) ? "ok" : "WRONG");
    close(fd);
    remove("f_big.dat");
  }

  /* Directory semantics lighttpd relies on (index files, dir listings). */
  {
    struct stat st;
    int fd;
    mkdir("f_dir", 0755);
    printf("FILE stat(dir) S_ISDIR %s\n", stat("f_dir", &st) == 0 && S_ISDIR(st.st_mode) ? "yes" : "NO");
    printf("FILE stat(\"f_dir/\") %s\n", stat("f_dir/", &st) == 0 ? "ok" : strerror(errno));
    fd = open("f_dir", O_RDONLY);
    printf("FILE open(dir, O_RDONLY) %s\n", fd >= 0 ? "ok" : strerror(errno));
    if (fd >= 0) close(fd);
    printf("FILE stat(\"nope/x.html\") errno %d (%s)\n", stat("nope/x.html", &st) == 0 ? 0 : errno,
           strerror(errno));
    rmdir("f_dir");
  }
  printf("R_FILES DONE\n");
  return 0;
}
