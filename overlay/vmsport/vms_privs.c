/* vms_privs.c - give up privileges once lighttpd's listeners are bound.

   VMS TCP/IP lets only processes with SYSPRV, OPER or BYPASS bind ports below
   1024 (probes/r_bindpriv.c).  The kit installs LIGHTTPD.EXE with
   /PRIVILEGED=OPER and the service account has only TMPMBX and NETMBX
   (docs/DECISIONS.md D12).  Right after network_init(), server.c calls this
   (patch 0014): every privilege is disabled for the rest of the process's
   life, then TMPMBX and NETMBX are enabled again.

   As on Unix after setuid(), this limits mistakes rather than a determined
   attacker: a process can re-enable privileges it is authorized for, or that
   its installed image grants, by calling $SETPRV itself.

   Returns 0, or the failing VMS condition value. */
#include <prvdef.h>
#include <ssdef.h>
#include <starlet.h>

unsigned int vms_drop_privileges(void)
{
  unsigned int all[2]  = { 0xFFFFFFFFu, 0xFFFFFFFFu };
  unsigned int keep[2] = { PRV$M_TMPMBX | PRV$M_NETMBX, 0 };
  unsigned int st;

  st = sys$setprv(0, (void *) all, 1, 0);        /* disable all, permanently */
  if (!(st & 1)) return st;
  st = sys$setprv(1, (void *) keep, 1, 0);       /* TMPMBX, NETMBX back on */
  if (!(st & 1) && st != SS$_NOTALLPRIV) return st;
  return 0;
}
