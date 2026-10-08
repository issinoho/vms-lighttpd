/* vms_privs.c - give up privileges once lighttpd's listeners are bound.

   VMS TCP/IP lets only processes with SYSPRV, OPER or BYPASS bind ports below
   1024 (probes/r_bindpriv.c).  The kit installs LIGHTTPD.EXE with
   /PRIVILEGED=OPER and the service account has only TMPMBX and NETMBX
   (docs/DECISIONS.md D12).  Right after network_init(), server.c calls this
   (patch 0014).

   Privileges granted by an installed image are in the *current* privilege
   mask while the image runs; $SETPRV with prmflg=1 changes only the
   permanent mask and left OPER enabled (install check, 2026-10-08).  So both
   masks are changed, and the result is checked with $GETJPI: if anything but
   TMPMBX and NETMBX is still enabled, the caller stops the server.

   As on Unix after setuid(), this limits mistakes rather than a determined
   attacker: a process can re-enable privileges its account or its installed
   image grants by calling $SETPRV itself.

   Returns 0, or a VMS condition value (SS$_ABORT if privileges remain);
   *cur receives the current privilege mask either way. */
#include <jpidef.h>
#include <prvdef.h>
#include <ssdef.h>
#include <starlet.h>

unsigned int vms_drop_privileges(unsigned int cur[2])
{
  unsigned int all[2]  = { 0xFFFFFFFFu, 0xFFFFFFFFu };
  unsigned int keep[2] = { PRV$M_TMPMBX | PRV$M_NETMBX, 0 };
  unsigned short len = 0;
  struct { unsigned short buflen, code; void *buf; unsigned short *retlen; } items[2];
  unsigned int st, iosb[2];
  int prm;

  for (prm = 0; prm <= 1; prm++) {             /* 0: current (image), 1: permanent */
    st = sys$setprv(0, (void *) all, (char) prm, 0);
    if (!(st & 1)) return st;
    st = sys$setprv(1, (void *) keep, (char) prm, 0);
    if (!(st & 1) && st != SS$_NOTALLPRIV) return st;
  }

  cur[0] = cur[1] = 0;
  items[0].buflen = 8; items[0].code = JPI$_CURPRIV; items[0].buf = cur; items[0].retlen = &len;
  items[1].buflen = 0; items[1].code = 0; items[1].buf = 0; items[1].retlen = 0;
  st = sys$getjpiw(0, 0, 0, items, iosb, 0, 0);
  if (st & 1) st = iosb[0];
  if (!(st & 1)) return st;
  if ((cur[0] & ~keep[0]) || cur[1]) return SS$_ABORT;
  return 0;
}
