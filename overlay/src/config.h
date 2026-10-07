/* config.h - lighttpd configuration for OpenVMS (IA64, x86-64) with VSI C.
 *
 * Hand-maintained (docs/DECISIONS.md D3) in place of the one CMake would make
 * from src/config.h.cmake.  Each HAVE_ follows the Phase 0 probes
 * (docs/PHASE0.md, docs/probes-<node>.txt), which agree on both nodes except
 * where noted.  Things deliberately left undefined are listed at the end.
 */
#ifndef LIGHTTPD_VMS_CONFIG_H
#define LIGHTTPD_VMS_CONFIG_H

#include "vms_version.h"   /* LIGHTTPD_VERSION_ID, PACKAGE_VERSION: written by tools/prepare.sh */
#define PACKAGE_NAME "lighttpd"
#define LIBRARY_DIR "/vmslighttpd$root/lib"   /* unused: modules are linked in */

#ifndef LIGHTTPD_STATIC
#define LIGHTTPD_STATIC 1
#endif

/* headers (H_ probes) */
#define HAVE_DLFCN_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_MALLOC_H 1
#define HAVE_POLL_H 1
/* HAVE_PWD_H left undefined: pwd.h exists, but server.c then calls
   setgroups()/initgroups(), which the CRTL lacks, to drop root.  On VMS the
   server runs under its own account (DCL), not by changing user itself. */
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRINGS_H 1
#define HAVE_SYS_MMAN_H 1
#define HAVE_SYS_POLL_H 1
#define HAVE_SYS_RESOURCE_H 1      /* present, but no getrlimit/RLIMIT_NOFILE */
#define HAVE_SYS_TYPES_H 1
#define HAVE_SYS_UIO_H 1
#define HAVE_SYS_UN_H 1
#define HAVE_SYS_WAIT_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_UNISTD_H 1
/* no getopt.h, syslog.h, sys/select.h (select() is in socket.h/time.h),
   sys/loadavg.h, sys/sendfile.h, sys/epoll.h, sys/event.h, port.h, crypt.h */

/* networking (r_net, r_net2) */
#define HAVE_IPV6 1
#define HAVE_SOCKLEN_T 1

/* sizes: VSI C is ILP32; _LARGEFILE gives a 64-bit off_t */
#define SIZEOF_LONG 4
#define SIZEOF_OFF_T 8

/* libraries */
#define HAVE_OPENSSL_SSL_H 1       /* VSI SSL3 (OPENSSL -> SSL3$INCLUDE:) */
#define HAVE_LIBSSL 1
#define HAVE_PCRE2_H 1             /* vms-pcre2, PCRE2$ROOT */
#define HAVE_PCRE 1
#define HAVE_ZLIB_H 1              /* vms-zlib, ZLIB$ROOT */
#define HAVE_LIBZ 1

/* functions (F_ and G_ probes: links and declared) */
#define HAVE_CLOCK_GETTIME 1
#define HAVE_GETUID 1
#define HAVE_GMTIME_R 1
#define HAVE_INET_ATON 1
#define HAVE_INET_PTON 1
#define HAVE_JRAND48 1
#define HAVE_LOCALTIME_R 1
#define HAVE_LSTAT 1
#define HAVE_MKOSTEMP 1
#define HAVE_MMAP 1                /* right for stream-LF/UDF files only (r_files) */
#define HAVE_POLL 1
#define HAVE_PREAD 1
#define HAVE_PWRITE 1
#define HAVE_SELECT 1
#define HAVE_SIGACTION 1
#define HAVE_SIGNAL 1
#define HAVE_SRANDOM 1
#define HAVE_STRERROR_R 1
#define HAVE_WRITEV 1

/* Deliberately undefined:
 *   HAVE_FORK, HAVE_POSIX_SPAWN    no fork/posix_spawn in the CRTL (vfork+exec only)
 *   HAVE_GETRLIMIT                 not in the CRTL; the fd limit is FILLM
 *   HAVE_CHROOT                    not in the CRTL
 *   HAVE_TIMEGM                    not in the CRTL; lighttpd has its own fallback
 *   HAVE_PIPE2, HAVE_SENDFILE, HAVE_SPLICE, HAVE_COPY_FILE_RANGE,
 *   HAVE_PREADV, HAVE_PWRITEV, HAVE_MADVISE, HAVE_MEMPCPY  not in the CRTL
 *   HAVE_GETENTROPY, HAVE_GETRANDOM, HAVE_ARC4RANDOM_BUF  not in the CRTL; OpenSSL RAND
 *   HAVE_EXPLICIT_BZERO, HAVE_MEMSET_S ...  not in the CRTL; lighttpd's fallback
 *   HAVE_CRYPT                     crypt() links but there is no crypt.h, and
 *                                  mod_authn_file is not built
 *   HAVE_STRUCT_TM_GMTOFF          not verified
 *   HAVE_WEAK_SYMBOLS              not with VSI C
 */

#endif
