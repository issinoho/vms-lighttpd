/* r_nodelay.c - is TCP_NODELAY on a listening socket inherited by accept()?
   lighttpd sets it on the listener and, if getsockopt() on the first
   accepted socket says it is set, never sets it on accepted sockets again
   (network.c network_accept_tcp_nagle_disable).  Phase 2 downloads looked
   like Nagle + delayed ACK (~100 ms per 16 KB write).  Report what
   getsockopt() says on the listener and the accepted socket, raw. */
#include <errno.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static void show(const char *what, int fd)
{
  int opt = -12345;
  socklen_t len = sizeof opt;
  int r = getsockopt(fd, IPPROTO_TCP, TCP_NODELAY, (char *) &opt, &len);
  printf("NODELAY %-36s getsockopt=%d opt=%d (%#x) len=%u %s\n", what, r, opt, opt,
         (unsigned) len, r ? strerror(errno) : "");
}

int main(void)
{
  struct sockaddr_in sa;
  socklen_t len = sizeof sa;
  int ls, cs, as, one = 1;
  printf("NODELAY TCP_NODELAY = %d\n", TCP_NODELAY);
  ls = socket(AF_INET, SOCK_STREAM, 0);
  memset(&sa, 0, sizeof sa);
  sa.sin_family = AF_INET; sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  bind(ls, (struct sockaddr *) &sa, sizeof sa);
  show("listener before set", ls);
  printf("NODELAY setsockopt(listener, 1) = %d\n",
         setsockopt(ls, IPPROTO_TCP, TCP_NODELAY, (char *) &one, sizeof one));
  show("listener after set", ls);
  listen(ls, 5);
  show("listener after listen()", ls);
  getsockname(ls, (struct sockaddr *) &sa, &len);
  cs = socket(AF_INET, SOCK_STREAM, 0);
  connect(cs, (struct sockaddr *) &sa, sizeof sa);
  as = accept(ls, NULL, NULL);
  show("accepted socket (inherited?)", as);
  printf("NODELAY setsockopt(accepted, 1) = %d\n",
         setsockopt(as, IPPROTO_TCP, TCP_NODELAY, (char *) &one, sizeof one));
  show("accepted socket after set", as);
  show("client socket (never set)", cs);
  printf("R_NODELAY DONE\n");
  return 0;
}
