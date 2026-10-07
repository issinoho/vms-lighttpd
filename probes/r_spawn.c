/* r_spawn.c - can lighttpd start child processes (mod_cgi, piped logs,
   fastcgi.server "bin-path")?  The CRTL has no fork() or posix_spawn(); the
   VMS way is vfork() + exec*(), with the child's standard streams chosen by
   decc$set_child_standard_streams() between the two, since anything else done
   "in the child" (dup2, close) really happens in the parent.

   Run with no arguments: the parent re-executes its own image as
   "r_spawn child <mode> [fd]" for each mode. */
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static void say(const char *what, int ok, const char *detail)
{
  printf("SPAWN %-38s %s %s\n", what, ok ? "yes" : "NO ", detail ? detail : "");
  fflush(stdout);
}

static char errbuf[200];
static const char *err(void)
{
  snprintf(errbuf, sizeof errbuf, "errno=%d (%s)", errno, strerror(errno));
  return errbuf;
}

static char *self;

/* --- child side ------------------------------------------------------- */

static int child(int argc, char **argv)
{
  const char *mode = argc > 2 ? argv[2] : "";
  if (strcmp(mode, "stdout") == 0) {
    /* stdout is whatever the parent passed (pipe or socket) */
    const char *msg = "hello from child\n";
    write(1, msg, strlen(msg));
    return 0;
  }
  if (strcmp(mode, "env") == 0) {
    const char *v = getenv("LTPROBE_VAR");
    printf("%s\n", v ? v : "(unset)");
    return 0;
  }
  if (strcmp(mode, "fdarg") == 0 && argc > 3) {
    /* fastcgi bin-path style: a listening socket inherited by number */
    int fd = atoi(argv[3]);
    struct sockaddr_in sa;
    socklen_t len = sizeof sa;
    int r = getsockname(fd, (struct sockaddr *) &sa, &len);
    printf("child getsockname(fd %d) %s\n", fd, r == 0 ? "ok" : strerror(errno));
    return 0;
  }
  if (strcmp(mode, "stdin_listen") == 0) {
    /* FCGI_LISTENSOCK_FILENO: the listening socket as fd 0 */
    struct sockaddr_in sa;
    socklen_t len = sizeof sa;
    int r = getsockname(0, (struct sockaddr *) &sa, &len);
    printf("child getsockname(0) %s\n", r == 0 ? "ok" : strerror(errno));
    return 0;
  }
  if (strcmp(mode, "nop") == 0) return 0;
  return 2;
}

/* --- parent side ------------------------------------------------------ */

/* Start self as "child <mode> [arg]" with child stdin/stdout set to in/out
   (-1 = inherit).  Returns the pid or -1. */
static pid_t spawn(const char *mode, const char *arg, int in, int out, char **envp)
{
  char *av[5];
  pid_t pid;
  av[0] = self; av[1] = "child"; av[2] = (char *) mode; av[3] = (char *) arg; av[4] = NULL;
  pid = vfork();
  if (pid == 0) {
    decc$set_child_standard_streams(in, out, -1);
    if (envp) execve(self, av, envp); else execv(self, av);
    _exit(127);  /* exec failed: under vfork this returns -1 from vfork */
  }
  return pid;
}

static int read_all(int fd, char *buf, int max)
{
  int n = 0, r;
  struct pollfd p;
  while (n < max - 1) {
    p.fd = fd; p.events = POLLIN; p.revents = 0;
    if (poll(&p, 1, 5000) <= 0) break;
    r = (int) read(fd, buf + n, max - 1 - n);
    if (r <= 0) break;
    n += r;
  }
  buf[n] = 0;
  return n;
}

static int listener(struct sockaddr_in *sa)
{
  int ls = socket(AF_INET, SOCK_STREAM, 0);
  socklen_t len = sizeof *sa;
  memset(sa, 0, sizeof *sa);
  sa->sin_family = AF_INET;
  sa->sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  bind(ls, (struct sockaddr *) sa, sizeof *sa);
  listen(ls, 5);
  getsockname(ls, (struct sockaddr *) sa, &len);
  return ls;
}

int main(int argc, char **argv)
{
  char buf[256], d[200];
  int st, r;
  pid_t pid;

  if (argc > 1 && strcmp(argv[1], "child") == 0) return child(argc, argv);
  self = argv[0];
  printf("SPAWN self = %s\n", self);

  /* 1. child stdout -> pipe (mod_cgi on most systems; piped access logs) */
  {
    int p[2];
    r = pipe(p);
    pid = spawn("stdout", NULL, -1, p[1], NULL);
    say("vfork+execv returns a pid", pid > 0, pid > 0 ? NULL : err());
    close(p[1]);
    read_all(p[0], buf, sizeof buf);
    close(p[0]);
    r = pid > 0 ? (int) waitpid(pid, &st, 0) : -1;
    say("child stdout -> pipe", strstr(buf, "hello from child") != NULL, buf[0] ? buf : "(nothing)");
    snprintf(d, sizeof d, "waitpid=%d status=%#x exited=%d code=%d", r, st, WIFEXITED(st), WEXITSTATUS(st));
    say("waitpid", r == pid, d);
  }

  /* 2. child stdout -> socketpair end (lighttpd's Windows mod_cgi choice) */
  {
    int sv[2];
    buf[0] = 0;
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) == 0) {
      pid = spawn("stdout", NULL, -1, sv[1], NULL);
      close(sv[1]);
      read_all(sv[0], buf, sizeof buf);
      close(sv[0]);
      if (pid > 0) waitpid(pid, &st, 0);
    }
    say("child stdout -> socketpair", strstr(buf, "hello from child") != NULL, buf[0] ? buf : "(nothing)");
  }

  /* 3. child stdout -> connected TCP socket */
  {
    struct sockaddr_in sa;
    int ls = listener(&sa), cs = socket(AF_INET, SOCK_STREAM, 0), as;
    connect(cs, (struct sockaddr *) &sa, sizeof sa);
    as = accept(ls, NULL, NULL);
    buf[0] = 0;
    pid = spawn("stdout", NULL, -1, as, NULL);
    close(as);
    read_all(cs, buf, sizeof buf);
    if (pid > 0) waitpid(pid, &st, 0);
    say("child stdout -> TCP socket", strstr(buf, "hello from child") != NULL, buf[0] ? buf : "(nothing)");
    close(cs); close(ls);
  }

  /* 4. explicit environment via execve (CGI variables) */
  {
    int p[2];
    char *env[3];
    env[0] = "LTPROBE_VAR=from-execve"; env[1] = "PATH=/bin"; env[2] = NULL;
    pipe(p);
    pid = spawn("env", NULL, -1, p[1], env);
    close(p[1]);
    read_all(p[0], buf, sizeof buf);
    close(p[0]);
    if (pid > 0) waitpid(pid, &st, 0);
    say("execve envp reaches child", strstr(buf, "from-execve") != NULL, buf);
  }

  /* 5. listening socket inherited by fd number (fastcgi bin-path) */
  {
    struct sockaddr_in sa;
    int ls = listener(&sa), p[2];
    char num[16];
    snprintf(num, sizeof num, "%d", ls);
    pipe(p);
    pid = spawn("fdarg", num, -1, p[1], NULL);
    close(p[1]);
    read_all(p[0], buf, sizeof buf);
    close(p[0]);
    if (pid > 0) waitpid(pid, &st, 0);
    say("socket fd inherited by number", strstr(buf, " ok") != NULL, buf);
    close(ls);
  }

  /* 6. listening socket as the child's stdin (FCGI_LISTENSOCK_FILENO) */
  {
    struct sockaddr_in sa;
    int ls = listener(&sa), p[2];
    pipe(p);
    pid = spawn("stdin_listen", NULL, ls, p[1], NULL);
    close(p[1]);
    read_all(p[0], buf, sizeof buf);
    close(p[0]);
    if (pid > 0) waitpid(pid, &st, 0);
    say("listening socket as child stdin", strstr(buf, " ok") != NULL, buf);
    close(ls);
  }

  /* 7. cost of a spawn (CGI per request): 10 children, run one at a time */
  {
    struct timeval t0, t1;
    int i, ok = 0;
    gettimeofday(&t0, NULL);
    for (i = 0; i < 10; i++) {
      pid = spawn("nop", NULL, -1, -1, NULL);
      if (pid > 0 && waitpid(pid, &st, 0) == pid) ok++;
    }
    gettimeofday(&t1, NULL);
    snprintf(d, sizeof d, "%d/10 ok, %.1f ms per spawn+exit", ok,
             ((t1.tv_sec - t0.tv_sec) * 1000.0 + (t1.tv_usec - t0.tv_usec) / 1000.0) / 10);
    say("spawn cost", ok == 10, d);
  }

  printf("R_SPAWN DONE\n");
  return 0;
}
