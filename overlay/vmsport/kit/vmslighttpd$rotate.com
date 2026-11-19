$! VMSLIGHTTPD$ROTATE.COM - daily rotation of the lighttpd logs (batch job)
$!
$! Usage:
$!   @VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$ROTATE SCHEDULE   queue the job for the
$!                        next vmslighttpd_rotate_time unless it is queued
$!                        already (VMSLIGHTTPD$BOOT does this at each START)
$!   As the batch job (no parameter): it queues its next run first, so that a
$!   failed rotation does not end the schedule, then runs
$!   VMSLIGHTTPD$CONTROL ROTATE.
$!
$! Site settings (SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM, docs/DECISIONS.md D16):
$!   vmslighttpd_rotate_time   time of day, e.g. "00:05" (the default); ""
$!                             turns scheduled rotation off
$!   vmslighttpd_batch_queue   batch queue (default SYS$BATCH)
$!   vmslighttpd_keep_logs     versions kept of each log (default 7)
$!
$! The job runs as the service account and needs no privilege: the account
$! owns the logs, and the server it sends SIGHUP to runs under its UIC.  Run
$! by another user (e.g. SYSTEM), SCHEDULE submits with /USER=<account>,
$! which needs CMKRNL.
$!
$ set noon
$ say = "write sys$output"
$ @SYS$MANAGER:VMSLIGHTTPD$CONFIG.COM
$ logs = vmslighttpd_data - "]" + ".LOGS]"
$ jobname = "VMSLIGHTTPD_ROTATE"
$ rtime = "00:05"
$ if f$type(vmslighttpd_rotate_time) .nes. "" then rtime = f$edit(vmslighttpd_rotate_time, "TRIM")
$ queue = "SYS$BATCH"
$ if f$type(vmslighttpd_batch_queue) .nes. "" then queue = f$edit(vmslighttpd_batch_queue, "TRIM,UPCASE")
$ keep = 7
$ if f$type(vmslighttpd_keep_logs) .nes. "" then keep = f$integer(vmslighttpd_keep_logs)
$ if rtime .eqs. ""
$ then
$   say "VMSLIGHTTPD$ROTATE: vmslighttpd_rotate_time is empty; no scheduled rotation"
$   exit 1
$ endif
$ gosub schedule
$ if f$edit(p1, "UPCASE,TRIM") .eqs. "SCHEDULE" then exit 1
$ @VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$CONTROL ROTATE
$ purge/nolog/keep='keep' 'logs'ROTATE.LOG
$ exit 1
$!
$! queue the next run, unless a VMSLIGHTTPD_ROTATE job (other than this one)
$! is queued already.  DISPLAY_JOB without ALL_JOBS returns only the caller's
$! own jobs, so every queue is looked at, generic ones included.
$schedule:
$ self = 0
$ if f$mode() .eqs. "BATCH" then self = f$getqui("DISPLAY_JOB", "ENTRY_NUMBER", , "THIS_JOB")
$ found = 0
$ x = f$getqui("CANCEL_OPERATION")
$q_loop:
$ q = f$getqui("DISPLAY_QUEUE", "QUEUE_NAME", "*", "WILDCARD")
$ if q .eqs. "" then goto q_done
$j_loop:
$ j = f$getqui("DISPLAY_JOB", "JOB_NAME", , "")
$ if j .eqs. "" then goto q_loop
$ e = f$getqui("DISPLAY_JOB", "ENTRY_NUMBER", , "FREEZE_CONTEXT")
$ if j .eqs. jobname .and. e .ne. self
$ then
$   found = e
$   x = f$getqui("CANCEL_OPERATION")
$   goto q_done
$ endif
$ goto j_loop
$q_done:
$ if found .ne. 0
$ then
$   say "VMSLIGHTTPD$ROTATE: already queued (entry ", found, ")"
$   return
$ endif
$! today at rtime, or tomorrow if that has passed (or is now)
$ after = "TODAY+" + rtime
$! (an invalid time leaves t unassigned: %DCL-W-IVATIME)
$ t = ""
$ t = f$cvtime(after)
$ if t .eqs. ""
$ then
$   say "VMSLIGHTTPD$ROTATE: vmslighttpd_rotate_time """, rtime, """ is not a time of day (hh:mm)"
$   exit 44
$ endif
$ if t .les. f$cvtime() then after = "TOMORROW+" + rtime
$ user = ""
$ if f$edit(f$getjpi("", "USERNAME"), "TRIM") .nes. f$edit(vmslighttpd_account, "UPCASE") then -
     user = "/USER=" + vmslighttpd_account
$ submit 'user' /noprint/name='jobname'/queue='queue'/after="''after'" -
      /log_file='logs'ROTATE.LOG VMSLIGHTTPD$ROOT:[COM]VMSLIGHTTPD$ROTATE.COM
$ if .not. $status then exit $status
$ say "VMSLIGHTTPD$ROTATE: next rotation ", f$cvtime(after, "ABSOLUTE"), " on ", queue
$ return
