/* vms_in6addr.c - in6addr_any and in6addr_loopback for OpenVMS.

   <netinet/in6.h> declares them, but neither DECC$SHR nor the TCP/IP
   images define them: lighttpd's sock_addr.c failed to link
   (%ILINK-W-USEUNDEF), and probes/r_net2.c crashed reading in6addr_any.
   Define them here, as RFC 3493 specifies. */
#include <sys/types.h>
#include <netinet/in.h>

const struct in6_addr in6addr_any = { { { 0, 0, 0, 0, 0, 0, 0, 0,
                                          0, 0, 0, 0, 0, 0, 0, 0 } } };
const struct in6_addr in6addr_loopback = { { { 0, 0, 0, 0, 0, 0, 0, 0,
                                               0, 0, 0, 0, 0, 0, 0, 1 } } };
