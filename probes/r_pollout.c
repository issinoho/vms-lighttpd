/* r_pollout.c - does poll() report POLLOUT when a full TCP send buffer drains?
   lighttpd writes until EAGAIN, then waits for POLLOUT.  Phase 2 saw large
   downloads crawl at ~0.1 MB/s (about one send buffer per second, the
   poll() timeout), which this probe checks directly.  Also reports the
   socket buffer sizes and how much one write() takes. */
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static double ms_since(struct timeval *t0)
{
  struct timeval t1;
  gettimeofday(&t1, NULL);
  return (t1.tv_sec - t0->tv_sec) * 1000.0 + (t1.tv_usec - t0->tv_usec) / 1000.0;
}

static char buf[1048576], sink[65536];

int main(void)
{
  struct sockaddr_in sa;
  socklen_t len = sizeof sa;
  int ls, cs, as, one = 1, r, i, sz;
  long queued = 0, drained = 0;
  struct pollfd p;
  struct timeval t0;

  ls = socket(AF_INET, SOCK_STREAM, 0);
  setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, (char *) &one, sizeof one);
  memset(&sa, 0, sizeof sa);
  sa.sin_family = AF_INET; sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  bind(ls, (struct sockaddr *) &sa, sizeof sa); listen(ls, 5);
  getsockname(ls, (struct sockaddr *) &sa, &len);
  cs = socket(AF_INET, SOCK_STREAM, 0);
  connect(cs, (struct sockaddr *) &sa, sizeof sa);
  as = accept(ls, NULL, NULL);          /* as = server side, writes */
  fcntl(as, F_SETFL, fcntl(as, F_GETFL) | O_NONBLOCK);
  fcntl(cs, F_SETFL, fcntl(cs, F_GETFL) | O_NONBLOCK);

  len = sizeof sz; getsockopt(as, SOL_SOCKET, SO_SNDBUF, (char *) &sz, &len);
  printf("POLLOUT SO_SNDBUF %d\n", sz);
  len = sizeof sz; getsockopt(cs, SOL_SOCKET, SO_RCVBUF, (char *) &sz, &len);
  printf("POLLOUT SO_RCVBUF %d\n", sz);

  r = (int) write(as, buf, sizeof buf);
  printf("POLLOUT first write(1 MB) returned %d %s\n", r, r < 0 ? strerror(errno) : "");
  if (r > 0) queued += r;
  while ((r = (int) write(as, buf, sizeof buf)) > 0) queued += r;
  printf("POLLOUT filled: %ld bytes queued, then write -> %d errno %d (%s)\n", queued, r, errno, strerror(errno));

  p.fd = as; p.events = POLLOUT; p.revents = 0;
  gettimeofday(&t0, NULL);
  r = poll(&p, 1, 0);
  printf("POLLOUT poll(timeout 0) while full: %d revents %#x\n", r, p.revents);

  for (i = 0; i < 5; i++) {
    /* drain everything the peer can read now */
    long d = 0;
    while ((r = (int) read(cs, sink, sizeof sink)) > 0) d += r;
    drained += d;
    p.fd = as; p.events = POLLOUT; p.revents = 0;
    gettimeofday(&t0, NULL);
    r = poll(&p, 1, 3000);
    printf("POLLOUT round %d: drained %ld; poll(POLLOUT, 3 s) -> %d revents %#x after %.1f ms\n",
           i, d, r, p.revents, ms_since(&t0));
    r = (int) write(as, buf, sizeof buf);
    printf("POLLOUT round %d: write -> %d %s\n", i, r, r < 0 ? strerror(errno) : "");
  }

  /* the same with a 100 ms drain delay: is POLLOUT edge- or level-like? */
  {
    long d = 0;
    usleep(100000);
    while ((r = (int) read(cs, sink, sizeof sink)) > 0) d += r;
    p.fd = as; p.events = POLLOUT | POLLIN; p.revents = 0;
    gettimeofday(&t0, NULL);
    r = poll(&p, 1, 3000);
    printf("POLLOUT after 100 ms + drain %ld: poll(POLLOUT|POLLIN) -> %d revents %#x after %.1f ms\n",
           d, r, p.revents, ms_since(&t0));
  }
  printf("R_POLLOUT DONE\n");
  return 0;
}
