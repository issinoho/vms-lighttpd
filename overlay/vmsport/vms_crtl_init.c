/* vms_crtl_init.c - C RTL features lighttpd needs, set in the image before
   main() through LIB$INITIALIZE, so the server does not depend on DECC$
   logical names in whatever process runs it.  (Same technique as
   vms-mariadb's vms/vms_crtl_init.c.)

   - EFS_CHARSET, EFS_CASE_PRESERVE: ODS-5 names with dots, mixed case.
   - FILENAME_UNIX_REPORT, FILENAME_UNIX_NO_VERSION: getcwd/realpath and
     friends report UNIX paths without ;version, as lighttpd compares and
     logs paths.
   - READDIR_DROPDOTNOTYPE: "README." is listed as "README" (mod_dirlisting).
   - POSIX_SEEK_STREAM_FILE: lseek past EOF on stream files as POSIX.
   - ARGV_PARSE_STYLE: keep the case of command line arguments (-D, -f).
   - FILE_SHARING: logs can be read while the server writes them. */
#include <stdio.h>
#include <unixlib.h>

static void set_features(void)
{
  static const char *const names[] = {
    "DECC$EFS_CHARSET", "DECC$EFS_CASE_PRESERVE", "DECC$FILENAME_UNIX_REPORT",
    "DECC$FILENAME_UNIX_NO_VERSION", "DECC$READDIR_DROPDOTNOTYPE",
    "DECC$POSIX_SEEK_STREAM_FILE", "DECC$ARGV_PARSE_STYLE", "DECC$FILE_SHARING", NULL
  };
  int i;
  for (i = 0; names[i]; i++) {
    int idx = decc$feature_get_index(names[i]);
    if (idx >= 0) decc$feature_set_value(idx, 1, 1);
  }
}

#pragma extern_model save
#pragma extern_model strict_refdef "LIB$INITIALIZE" nopic, con, rel, gbl, noshr, noexe, nowrt, novec, long
extern void (*const vms_lib_init)(void) = set_features;
#pragma extern_model restore
int LIB$INITIALIZE(void);
int (*vms_lib_init_ref)(void) = LIB$INITIALIZE;
