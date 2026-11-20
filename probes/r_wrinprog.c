/* r_wrinprog.c - when does write() on a TCP socket fail with EINPROGRESS?
   The live x86 server logs "(network_write.c.119) write() N: operation in
   progress" under load: lighttpd retries only EAGAIN/EWOULDBLOCK/EINTR and
   drops the connection on anything else.  Cases:
   1. write() while a non-blocking connect() is still pending (lighttpd's
      FastCGI GW_STATE_CONNECT_DELAYED path checks SO_ERROR, not POLLOUT),
      a) to a local listener whose backlog is full, b) to an address that
      does not answer (192.0.2.1, TEST-NET-1; optional: argv[1] = "nonet"
      skips it);
   2. write()/writev() into a full send buffer (expected EAGAIN);
   3. write() after the peer reset the connection.
   Usage: r_wrinprog [nonet] ; listens on 127.0.0.1:18095. */
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <unistd.h>

#define PORT 18095
static char buf[1048576], sink[65536];

static const char *ename(int e)
{
  switch (e) {
  case 0: return "0";
  case EAGAIN: return "EAGAIN";
#if defined(EWOULDBLOCK) && EWOULDBLOCK != EAGAIN
  case EWOULDBLOCK: return "EWOULDBLOCK";
#endif
  case EINPROGRESS: return "EINPROGRESS";
  case EALREADY: return "EALREADY";
  case ENOTCONN: return "ENOTCONN";
  case EPIPE: return "EPIPE";
  case ECONNRESET: return "ECONNRESET";
  case ECONNREFUSED: return "ECONNREFUSED";
  case ETIMEDOUT: return "ETIMEDOUT";
  case EINTR: return "EINTR";
  default: return "other";
  }
}

static void nb(int s) { fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK); }

/* a connected pair through listener ls: *cs the peer (client), *as the
   non-blocking server side that lighttpd would write to */
static void pair(int ls, struct sockaddr_in *sa, int *cs, int *as)
{
  *cs = socket(AF_INET, SOCK_STREAM, 0);
  connect(*cs, (struct sockaddr *) sa, sizeof *sa);
  *as = accept(ls, NULL, NULL);
  nb(*as);
}

static void fillup(int as)
{
  while (write(as, buf, 65536) > 0) ;
}

/* n writes of len bytes with a short pause between, reporting each */
static void writes(const char *what, int as, int n, int len)
{
  int i, r, e;
  for (i = 0; i < n; i++) {
    errno = 0;
    r = (int) write(as, buf, (size_t) len);
    e = errno;
    printf("WRINPROG %s #%d: write(%d) -> %d errno %d %s\n", what, i + 1, len, r, r < 0 ? e : 0, r < 0 ? ename(e) : "-");
    poll(NULL, 0, 100);
  }
}

static int soerr(int s)
{
  int e = -1; socklen_t l = sizeof e;
  if (getsockopt(s, SOL_SOCKET, SO_ERROR, (char *) &e, &l) != 0) return -errno;
  return e;
}

static void try_write(const char *what, int s)
{
  int r, e;
  errno = 0;
  r = (int) write(s, "x", 1);
  e = errno;
  printf("WRINPROG %s: write -> %d errno %d %s (%s)\n", what, r, e, ename(e), r < 0 ? strerror(e) : "-");
}

static int pollout(int s, int ms)
{
  struct pollfd p; p.fd = s; p.events = POLLOUT; p.revents = 0;
  return poll(&p, 1, ms) > 0 ? p.revents : 0;
}

/* a non-blocking connect that is still pending: write at once, after
   SO_ERROR (as lighttpd), and after a short POLLOUT wait */
static void pending(const char *what, struct sockaddr_in *to)
{
  int s = socket(AF_INET, SOCK_STREAM, 0), r, e, rev;
  char t[96];
  nb(s);
  errno = 0;
  r = connect(s, (struct sockaddr *) to, sizeof *to);
  e = errno;
  printf("WRINPROG %s: connect -> %d errno %d %s\n", what, r, e, ename(e));
  if (r == 0) { printf("WRINPROG %s: connected at once (not pending)\n", what); close(s); return; }
  printf("WRINPROG %s: SO_ERROR before write = %d %s\n", what, soerr(s), ename(soerr(s)));
  sprintf(t, "%s immediately", what); try_write(t, s);
  try_write(what, s);   /* second write: same answer? */
  rev = pollout(s, 300);
  printf("WRINPROG %s: poll(POLLOUT, 300 ms) revents 0x%x, SO_ERROR now %d %s\n", what, rev, soerr(s), ename(soerr(s)));
  sprintf(t, "%s after poll", what); try_write(t, s);
  close(s);
}

int main(int argc, char **argv)
{
  struct sockaddr_in sa, far;
  int ls, cs, as, i, r, e, one = 1, fill[16], nfill = 0;
  long total = 0;
  struct linger lg;
  struct iovec iov[4];

  signal(SIGPIPE, SIG_IGN);   /* as lighttpd */
  memset(buf, 'x', sizeof buf);
  memset(&sa, 0, sizeof sa);
  sa.sin_family = AF_INET; sa.sin_port = htons(PORT); sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  ls = socket(AF_INET, SOCK_STREAM, 0);
  setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, (char *) &one, sizeof one);
  if (bind(ls, (struct sockaddr *) &sa, sizeof sa) != 0) { printf("WRINPROG bind: %s\n", strerror(errno)); return 1; }
  listen(ls, 1);

  /* 1a: fill the backlog (never accept), then one more connect */
  for (i = 0; i < 8; i++) {
    int s = socket(AF_INET, SOCK_STREAM, 0);
    nb(s);
    r = connect(s, (struct sockaddr *) &sa, sizeof sa);
    e = errno;
    fill[nfill++] = s;
    printf("WRINPROG backlog fill %d: connect -> %d %s, poll 0x%x\n", i, r, r ? ename(e) : "ok", pollout(s, 50));
  }
  pending("1a full-backlog", &sa);
  for (i = 0; i < nfill; i++) close(fill[i]);

  /* 1b: an address that never answers */
  if (!(argc > 1 && strcmp(argv[1], "nonet") == 0)) {
    memset(&far, 0, sizeof far);
    far.sin_family = AF_INET; far.sin_port = htons(9); far.sin_addr.s_addr = inet_addr("192.0.2.1");
    pending("1b no-answer", &far);
  }
  close(ls);

  /* 2: full send buffer, peer not reading */
  ls = socket(AF_INET, SOCK_STREAM, 0);
  setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, (char *) &one, sizeof one);
  bind(ls, (struct sockaddr *) &sa, sizeof sa);
  listen(ls, 5);
  cs = socket(AF_INET, SOCK_STREAM, 0);
  connect(cs, (struct sockaddr *) &sa, sizeof sa);
  as = accept(ls, NULL, NULL);
  nb(as);
  for (;;) {
    errno = 0;
    r = (int) write(as, buf, sizeof buf);
    if (r > 0) { total += r; continue; }
    e = errno;
    printf("WRINPROG 2 write: full after %ld bytes: -> %d errno %d %s\n", total, r, e, ename(e));
    break;
  }
  for (i = 0; i < 4; i++) { iov[i].iov_base = buf; iov[i].iov_len = sizeof buf; }
  errno = 0;
  r = (int) writev(as, iov, 4);
  e = errno;
  printf("WRINPROG 2 writev on full buffer: -> %d errno %d %s\n", r, e, ename(e));

  /* 3: the peer resets the connection (SO_LINGER 0 close) */
  lg.l_onoff = 1; lg.l_linger = 0;
  setsockopt(cs, SOL_SOCKET, SO_LINGER, (char *) &lg, sizeof lg);
  close(cs);
  poll(NULL, 0, 200);
  for (i = 0; i < 3; i++) {
    errno = 0;
    r = (int) write(as, buf, 1024);
    e = errno;
    printf("WRINPROG 3 write after peer reset #%d: -> %d errno %d %s\n", i + 1, r, e, ename(e));
    if (r < 0 && e != EAGAIN) break;
  }
  close(as);

  /* 4: writes bigger than the send buffer while the peer drains slowly
     (lighttpd writes up to its max per call without polling first) */
  {
    static const int sizes[3] = { 65536, 262144, 1048576 };
    int k;
    for (k = 0; k < 3; k++) {
      int full = 0, part = 0, ewb = 0, einp = 0, oth = 0, othe = 0, it;
      pair(ls, &sa, &cs, &as);
      nb(cs);
      for (it = 0; it < 3000; it++) {
        errno = 0;
        r = (int) write(as, buf, (size_t) sizes[k]);
        e = errno;
        if (r == sizes[k]) full++;
        else if (r > 0) part++;
        else if (e == EWOULDBLOCK || e == EAGAIN) ewb++;
        else if (e == EINPROGRESS) einp++;
        else { oth++; othe = e; }
        (void) read(cs, sink, it % 3 ? 4096 : 32768);   /* slow, uneven reader */
      }
      printf("WRINPROG 4 write(%d) x3000: full %d partial %d EWOULDBLOCK %d EINPROGRESS %d other %d (last %d %s)\n",
             sizes[k], full, part, ewb, einp, oth, othe, ename(othe));
      close(cs); close(as);
    }
  }

  /* 5: the peer closes normally (FIN) with our data still unread */
  pair(ls, &sa, &cs, &as);
  fillup(as);
  close(cs);
  writes("5 after peer close (unread data)", as, 4, 65536);
  close(as);

  /* 6: the peer half-closes (shutdown SHUT_WR, as a proxy ending a
     keep-alive connection may), then closes */
  pair(ls, &sa, &cs, &as);
  shutdown(cs, SHUT_WR);
  writes("6a after peer SHUT_WR", as, 3, 65536);
  fillup(as);
  writes("6b after peer SHUT_WR, buffer full", as, 2, 65536);
  close(cs);
  writes("6c after peer close", as, 4, 65536);
  close(as);

  /* 7: full buffer, then the peer reads everything at once: does the
     first write after the drain succeed? */
  pair(ls, &sa, &cs, &as);
  fillup(as);
  nb(cs);
  while (read(cs, sink, sizeof sink) > 0) ;
  writes("7 after full drain", as, 3, 1048576);
  close(cs); close(as);

  /* 8: writev() with many small chunks into a buffer that fills part-way
     (lighttpd's network_writev_mem_chunks: headers + body pieces) */
  {
    static const int cnts[4] = { 2, 8, 32, 64 };
    static const int lens[3] = { 512, 4096, 16384 };
    static struct iovec v[64];
    int k, m, j;
    for (k = 0; k < 4; k++)
      for (m = 0; m < 3; m++) {
        int full = 0, part = 0, ewb = 0, einp = 0, oth = 0, othe = 0, it, want = cnts[k] * lens[m];
        for (j = 0; j < cnts[k]; j++) { v[j].iov_base = buf + j * lens[m]; v[j].iov_len = lens[m]; }
        pair(ls, &sa, &cs, &as);
        nb(cs);
        for (it = 0; it < 1500; it++) {
          errno = EINPROGRESS;   /* stale value, as after lighttpd's FastCGI connect() */
          r = (int) writev(as, v, cnts[k]);
          e = errno;
          if (r == want) full++;
          else if (r > 0) part++;
          else if (e == EWOULDBLOCK || e == EAGAIN) ewb++;
          else if (e == EINPROGRESS) einp++;
          else { oth++; othe = e; }
          (void) read(cs, sink, it % 3 ? 2048 : 24576);
        }
        printf("WRINPROG 8 writev(%d x %d) x1500: full %d partial %d EWOULDBLOCK %d EINPROGRESS %d other %d (last %d %s)\n",
               cnts[k], lens[m], full, part, ewb, einp, oth, othe, ename(othe));
        close(cs); close(as);
      }
  }

  /* 9: does a failing write()/writev() always set errno?  (stale
     EINPROGRESS before the call; full buffer) */
  pair(ls, &sa, &cs, &as);
  fillup(as);
  errno = EINPROGRESS; r = (int) write(as, buf, 4096); e = errno;
  printf("WRINPROG 9 write on full buffer, stale EINPROGRESS before: -> %d errno %d %s\n", r, e, ename(e));
  iov[0].iov_base = buf; iov[0].iov_len = 4096; iov[1].iov_base = buf; iov[1].iov_len = 4096;
  errno = EINPROGRESS; r = (int) writev(as, iov, 2); e = errno;
  printf("WRINPROG 9 writev on full buffer, stale EINPROGRESS before: -> %d errno %d %s\n", r, e, ename(e));
  close(cs); close(as);

  /* 10: the writev() failures of case 8, exactly: return value and errno,
     with errno set beforehand to a value no socket call uses (EDOM) */
  {
    static struct iovec v[8];
    int j, it, shown = 0, neg_set = 0, neg_unset = 0, zero = 0, pos = 0, part = 0;
    for (j = 0; j < 8; j++) { v[j].iov_base = buf + j * 4096; v[j].iov_len = 4096; }
    pair(ls, &sa, &cs, &as);
    nb(cs);
    for (it = 0; it < 1500; it++) {
      errno = EDOM;
      r = (int) writev(as, v, 8);
      e = errno;
      if (r == 32768) pos++;
      else if (r > 0) part++;
      else if (r == 0) zero++;
      else if (e == EDOM) neg_unset++;
      else neg_set++;
      if (r <= 0 && shown < 6) {
        printf("WRINPROG 10 #%d: writev(8 x 4096) -> %d errno %d %s%s\n", it, r, e, e == EDOM ? "EDOM" : ename(e),
               r < 0 && e == EDOM ? "  <- -1 WITHOUT setting errno" : "");
        shown++;
      }
      (void) read(cs, sink, it % 3 ? 2048 : 24576);
    }
    printf("WRINPROG 10 summary x1500: full %d partial %d zero %d -1+errno %d -1+errno-unchanged %d\n",
           pos, part, zero, neg_set, neg_unset);
    close(cs); close(as);
  }

  close(ls);
  printf("WRINPROG done; EINPROGRESS=%d EAGAIN=%d EWOULDBLOCK=%d\n", EINPROGRESS, EAGAIN, EWOULDBLOCK);
  return 0;
}
