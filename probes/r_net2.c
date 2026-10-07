/* r_net2.c - socket behaviour lighttpd's event loop relies on, beyond
   r_net.c: how many connections one process can hold and poll(), writev()
   of many buffers, half-close, IPv6 dual stack, quick re-bind after a
   restart, FD_CLOEXEC. */
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
#include <sys/types.h>
#include <sys/uio.h>
#include <sys/resource.h>
#include <unistd.h>

static void say(const char *what, int ok, const char *detail)
{
  printf("NET2 %-38s %s %s\n", what, ok ? "yes" : "NO ", detail ? detail : "");
  fflush(stdout);
}

static char errbuf[200];
static const char *err(void)
{
  snprintf(errbuf, sizeof errbuf, "errno=%d (%s)", errno, strerror(errno));
  return errbuf;
}

static int listener(struct sockaddr_in *sa, int backlog)
{
  int ls = socket(AF_INET, SOCK_STREAM, 0), one = 1;
  socklen_t len = sizeof *sa;
  setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, (char *) &one, sizeof one);
  memset(sa, 0, sizeof *sa);
  sa->sin_family = AF_INET;
  sa->sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  bind(ls, (struct sockaddr *) sa, sizeof *sa);
  listen(ls, backlog);
  getsockname(ls, (struct sockaddr *) sa, &len);
  return ls;
}

#define MAXC 2000

int main(void)
{
  char d[200];
  int r;

  {
    struct rlimit rl;
    r = getrlimit(RLIMIT_NOFILE, &rl);
    snprintf(d, sizeof d, "cur=%lld max=%lld  sysconf(_SC_OPEN_MAX)=%ld", (long long) rl.rlim_cur,
             (long long) rl.rlim_max, sysconf(_SC_OPEN_MAX));
    say("RLIMIT_NOFILE", r == 0, r ? err() : d);
  }

  /* Many concurrent connections: open client+server pairs until failure. */
  {
    static int cfd[MAXC], afd[MAXC];
    static struct pollfd p[MAXC];
    struct sockaddr_in sa;
    struct timeval t0, t1;
    int ls = listener(&sa, 1024), n = 0, i, ready;
    const char *why = "limit of probe";
    while (n < MAXC) {
      cfd[n] = socket(AF_INET, SOCK_STREAM, 0);
      if (cfd[n] < 0) { why = err(); break; }
      if (connect(cfd[n], (struct sockaddr *) &sa, sizeof sa) != 0) { why = err(); close(cfd[n]); break; }
      afd[n] = accept(ls, NULL, NULL);
      if (afd[n] < 0) { why = err(); close(cfd[n]); break; }
      n++;
    }
    snprintf(d, sizeof d, "%d connections (%d fds) before stop: %s", n, 2 * n + 1, why);
    say("concurrent connections", n >= 500, d);
    /* poll() over every accepted socket with one in ten readable */
    for (i = 0; i < n; i += 10) send(cfd[i], "x", 1, 0);
    for (i = 0; i < n; i++) { p[i].fd = afd[i]; p[i].events = POLLIN; p[i].revents = 0; }
    gettimeofday(&t0, NULL);
    for (r = 0; r < 100; r++) ready = poll(p, (nfds_t) n, 1000);
    gettimeofday(&t1, NULL);
    snprintf(d, sizeof d, "%d fds, %d ready (expect %d), %.3f ms per call", n, ready, (n + 9) / 10,
             ((t1.tv_sec - t0.tv_sec) * 1000.0 + (t1.tv_usec - t0.tv_usec) / 1000.0) / 100);
    say("poll() over all connections", ready == (n + 9) / 10, d);
    for (i = 0; i < n; i++) { close(cfd[i]); close(afd[i]); }
    close(ls);
  }

  /* writev() of 16 x 4 KB on a socket, read back in order. */
  {
    struct sockaddr_in sa;
    int ls = listener(&sa, 5), cs = socket(AF_INET, SOCK_STREAM, 0), as, i, total = 0, n, ok = 1;
    static char bufs[16][4096], in[16 * 4096];
    struct iovec iov[16];
    connect(cs, (struct sockaddr *) &sa, sizeof sa);
    as = accept(ls, NULL, NULL);
    for (i = 0; i < 16; i++) { memset(bufs[i], 'A' + i, sizeof bufs[i]); iov[i].iov_base = bufs[i]; iov[i].iov_len = sizeof bufs[i]; }
    r = (int) writev(as, iov, 16);
    snprintf(d, sizeof d, "returned %d", r);
    say("writev 16 x 4KB", r == 16 * 4096, r < 0 ? err() : d);
    while (total < r && (n = (int) recv(cs, in + total, sizeof in - total, 0)) > 0) total += n;
    for (i = 0; i < total; i++) if (in[i] != 'A' + i / 4096) { ok = 0; break; }
    say("writev data in order", ok && total == r, NULL);

    /* half-close: shutdown(SHUT_WR) then the peer sees EOF but can still send */
    shutdown(as, SHUT_WR);
    n = (int) recv(cs, in, sizeof in, 0);
    say("recv EOF after peer SHUT_WR", n == 0, n < 0 ? err() : NULL);
    n = (int) send(cs, "late", 4, 0);
    r = (int) recv(as, in, sizeof in, 0);
    say("send after peer SHUT_WR still arrives", n == 4 && r == 4, r < 0 ? err() : NULL);
    close(cs); close(as); close(ls);
  }

  /* Restart: close a listener with a connection in TIME_WAIT, re-bind at once. */
  {
    struct sockaddr_in sa, sb;
    int ls = listener(&sa, 5), cs = socket(AF_INET, SOCK_STREAM, 0), as, ls2, one = 1;
    connect(cs, (struct sockaddr *) &sa, sizeof sa);
    as = accept(ls, NULL, NULL);
    close(as); close(cs); close(ls);
    ls2 = socket(AF_INET, SOCK_STREAM, 0);
    setsockopt(ls2, SOL_SOCKET, SO_REUSEADDR, (char *) &one, sizeof one);
    sb = sa;
    r = bind(ls2, (struct sockaddr *) &sb, sizeof sb);
    say("re-bind same port right after close", r == 0, r ? err() : NULL);
    close(ls2);
  }

  /* IPv6 dual stack: [::] listener accepting an IPv4 client. */
  {
    int s6 = socket(AF_INET6, SOCK_STREAM, 0), zero = 0, one = 1, cs, as;
    struct sockaddr_in6 a6;
    struct sockaddr_in a4;
    socklen_t len = sizeof a6;
    if (s6 < 0) say("AF_INET6 socket", 0, err());
    else {
      setsockopt(s6, SOL_SOCKET, SO_REUSEADDR, (char *) &one, sizeof one);
#ifdef IPV6_V6ONLY
      setsockopt(s6, IPPROTO_IPV6, IPV6_V6ONLY, (char *) &zero, sizeof zero);
#endif
      memset(&a6, 0, sizeof a6);
      a6.sin6_family = AF_INET6;
      a6.sin6_addr = in6addr_any;
      r = bind(s6, (struct sockaddr *) &a6, sizeof a6);
      listen(s6, 5);
      getsockname(s6, (struct sockaddr *) &a6, &len);
      say("bind [::]:0", r == 0, r ? err() : NULL);
      cs = socket(AF_INET, SOCK_STREAM, 0);
      memset(&a4, 0, sizeof a4);
      a4.sin_family = AF_INET;
      a4.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
      a4.sin_port = a6.sin6_port;
      r = connect(cs, (struct sockaddr *) &a4, sizeof a4);
      as = r == 0 ? accept(s6, NULL, NULL) : -1;
      say("IPv4 client reaches [::] listener", as >= 0, r ? err() : NULL);
      if (as >= 0) close(as);
      close(cs); close(s6);
    }
  }

  /* FD_CLOEXEC (lighttpd sets it on every fd), and fcntl O_NONBLOCK read back. */
  {
    int s = socket(AF_INET, SOCK_STREAM, 0);
    r = fcntl(s, F_SETFD, FD_CLOEXEC);
    say("fcntl F_SETFD FD_CLOEXEC", r == 0 && (fcntl(s, F_GETFD) & FD_CLOEXEC), r ? err() : NULL);
    fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK);
    say("F_GETFL shows O_NONBLOCK", (fcntl(s, F_GETFL) & O_NONBLOCK) != 0, NULL);
    close(s);
  }
#ifdef TCP_DEFER_ACCEPT
  say("TCP_DEFER_ACCEPT defined", 1, NULL);
#else
  say("TCP_DEFER_ACCEPT defined", 0, NULL);
#endif
#ifdef SO_ACCEPTFILTER
  say("SO_ACCEPTFILTER defined", 1, NULL);
#else
  say("SO_ACCEPTFILTER defined", 0, NULL);
#endif
  printf("R_NET2 DONE\n");
  return 0;
}
