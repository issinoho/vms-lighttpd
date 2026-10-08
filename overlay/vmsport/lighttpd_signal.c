/* lighttpd_signal.c - send a POSIX signal to a lighttpd process on OpenVMS.

   Usage:  LIGHTTPD_SIGNAL <pid> TERM|INT|HUP|USR1
     TERM  graceful shutdown (finish requests in progress, then exit)
     INT   immediate shutdown
     HUP   reopen log files (after renaming them: log rotation)
     USR1  graceful restart of the configuration is not supported on VMS
           (lighttpd would fork); accepted but lighttpd treats it as TERM

   <pid> is the VMS process id in hex, as SHOW SYSTEM prints it.  DCL has no
   way to send a C RTL signal; the C RTL's kill() does, to a process that has
   the privilege or the same UIC.  Exit status: success, or the errno text. */
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv)
{
  long pid;
  int sig;
  char *end;
  if (argc != 3) {
    fprintf(stderr, "usage: lighttpd_signal <pid-in-hex> TERM|INT|HUP|USR1\n");
    return EXIT_FAILURE;
  }
  pid = strtol(argv[1], &end, 16);
  if (*end || pid <= 0) {
    fprintf(stderr, "lighttpd_signal: bad pid %s\n", argv[1]);
    return EXIT_FAILURE;
  }
  if (strcmp(argv[2], "TERM") == 0 || strcmp(argv[2], "term") == 0) sig = SIGTERM;
  else if (strcmp(argv[2], "INT") == 0 || strcmp(argv[2], "int") == 0) sig = SIGINT;
  else if (strcmp(argv[2], "HUP") == 0 || strcmp(argv[2], "hup") == 0) sig = SIGHUP;
  else if (strcmp(argv[2], "USR1") == 0 || strcmp(argv[2], "usr1") == 0) sig = SIGUSR1;
  else {
    fprintf(stderr, "lighttpd_signal: unknown signal %s\n", argv[2]);
    return EXIT_FAILURE;
  }
  if (kill((pid_t) pid, sig) != 0) {
    fprintf(stderr, "lighttpd_signal: kill(%lX, %s): %s\n", pid, argv[2], strerror(errno));
    return EXIT_FAILURE;
  }
  return EXIT_SUCCESS;
}
