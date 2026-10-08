/* r_bindpriv.c <port> - can this process bind a TCP port (e.g. < 1024)?
   VMS TCP/IP restricts ports below 1024 to privileged processes; the service
   account should have only TMPMBX and NETMBX.  Binds 0.0.0.0:<port>, listens,
   reports, and exits at once. */
#include <errno.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

int main(int argc, char **argv)
{
  int port = argc > 1 ? atoi(argv[1]) : 981, one = 1, s, r;
  struct sockaddr_in sa;
  s = socket(AF_INET, SOCK_STREAM, 0);
  setsockopt(s, SOL_SOCKET, SO_REUSEADDR, (char *) &one, sizeof one);
  memset(&sa, 0, sizeof sa);
  sa.sin_family = AF_INET;
  sa.sin_port = htons(port);
  sa.sin_addr.s_addr = htonl(INADDR_ANY);
  r = bind(s, (struct sockaddr *) &sa, sizeof sa);
  if (r == 0) r = listen(s, 5);
  printf("BINDPRIV port %d: %s\n", port, r == 0 ? "bound" : strerror(errno));
  close(s);
  return 0;
}
