/* r_blast.c [port] [mode] [sndbuf] - a minimal HTTP/1.0 server for one request, to
   tell the platform's TCP throughput from lighttpd's.  Sends 10 MB from
   memory: mode "block" uses blocking write() of 64 KB; mode "poll" (default)
   uses non-blocking write() and poll(POLLOUT), as lighttpd does, and counts
   EAGAINs and poll() waits.  Listens on 0.0.0.0:port (default 18090). */
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#define TOTAL (10L * 1048576)
static char buf[65536];

int main(int argc, char **argv)
{
  int port = argc > 1 ? atoi(argv[1]) : 18090;
  int poll_mode = !(argc > 2 && strcmp(argv[2], "block") == 0);
  struct sockaddr_in sa;
  int ls, as, one = 1, r, eagain = 0, polls = 0;
  long sent = 0;
  double pollms = 0;
  char req[4096], hdr[128];
  struct timeval t0, t1, p0, p1;

  memset(buf, 'x', sizeof buf);
  ls = socket(AF_INET, SOCK_STREAM, 0);
  setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, (char *) &one, sizeof one);
  setsockopt(ls, IPPROTO_TCP, TCP_NODELAY, (char *) &one, sizeof one);
  memset(&sa, 0, sizeof sa);
  sa.sin_family = AF_INET; sa.sin_port = htons(port); sa.sin_addr.s_addr = htonl(INADDR_ANY);
  if (bind(ls, (struct sockaddr *) &sa, sizeof sa) != 0) { printf("BLAST bind: %s\n", strerror(errno)); return 1; }
  listen(ls, 5);
  printf("BLAST listening on %d, mode %s\n", port, poll_mode ? "poll" : "block");
  fflush(stdout);
  as = accept(ls, NULL, NULL);
  if (argc > 3) {
    int sb = atoi(argv[3]), got = 0;
    socklen_t gl = sizeof got;
    r = setsockopt(as, SOL_SOCKET, SO_SNDBUF, (char *) &sb, sizeof sb);
    getsockopt(as, SOL_SOCKET, SO_SNDBUF, (char *) &got, &gl);
    printf("BLAST SO_SNDBUF set %d -> %d (now %d)\n", sb, r, got);
  }
  r = (int) recv(as, req, sizeof req, 0);   /* the request; not parsed */
  snprintf(hdr, sizeof hdr, "HTTP/1.0 200 OK\r\nContent-Length: %ld\r\n\r\n", TOTAL);
  send(as, hdr, strlen(hdr), 0);
  if (poll_mode) fcntl(as, F_SETFL, fcntl(as, F_GETFL) | O_NONBLOCK);
  gettimeofday(&t0, NULL);
  while (sent < TOTAL) {
    long want = TOTAL - sent > (long) sizeof buf ? (long) sizeof buf : TOTAL - sent;
    r = (int) write(as, buf, (size_t) want);
    if (r > 0) { sent += r; continue; }
    if (r < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
      struct pollfd p;
      eagain++;
      p.fd = as; p.events = POLLOUT; p.revents = 0;
      gettimeofday(&p0, NULL);
      poll(&p, 1, 1000);
      gettimeofday(&p1, NULL);
      polls++;
      pollms += (p1.tv_sec - p0.tv_sec) * 1000.0 + (p1.tv_usec - p0.tv_usec) / 1000.0;
      continue;
    }
    printf("BLAST write error after %ld: %s\n", sent, strerror(errno));
    break;
  }
  gettimeofday(&t1, NULL);
  {
    double s = (t1.tv_sec - t0.tv_sec) + (t1.tv_usec - t0.tv_usec) / 1e6;
    printf("BLAST sent %ld bytes in %.2f s = %.2f MB/s; EAGAIN %d, poll waits %d, %.1f ms in poll\n",
           sent, s, sent / 1048576.0 / s, eagain, polls, pollms);
  }
  close(as); close(ls);
  return 0;
}
