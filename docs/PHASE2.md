# Phase 2: static HTTP, HTTPS, soak

Test server: `tools/serve.sh <node> setup|start|stop|log` (a batch job running
`vmsport/tests/p2server.com`, config from `vmsport/tests/p2setup.com`), checks:
`tools/test_http.sh <node>`, load: `tools/soak.sh <node> [min] [workers]`.

## Results

| Check | x86 | IA64 |
|---|---|---|
| test_http.sh (24 checks) | 24/24 (2026-10-08) | 24/24 (2026-10-08; the 2 MB transfers time out if run while another node is loaded over the same network) |
| 2 MB transfer | 40-127 KB/s | ~100 KB/s |
| soak, 60 min, 8 workers | 21,231 requests; server memory flat (9,512 KB, 1,189 pages from minute 6 to the end), page faults flat after warm-up, no errors logged; 151 client timeouts (30 s) on responses the server completed, from the slow TCP (D10) | not run (same code; x86 is the target) |

Per check: GET/HEAD, Content-Type, Content-Length for Stream_LF, a variable-record file
served by its converted bytes (0008), 404, path traversal refused, directory listing,
If-Modified-Since/If-None-Match → 304, three Range cases, 2 MB transfer with data check,
keep-alive reuse, POST to a static file; HTTPS GET, TLS 1.3, TLS 1.2 refused by default
(lighttpd 1.4.85's minimum is TLS 1.3) and accepted on a listener with
`ssl.openssl.ssl-conf-cmd = ("MinProtocol" => "TLSv1.2")`, TLS 1.1 refused, HTTP/2 via
ALPN, 2 MB over HTTPS h2, TLS 1.3 ticket resumption, TLS 1.2 resumption.

Throughput is limited by the nodes' TCP/IP (~50-130 KB/s per connection, D10), not lighttpd.

## Notes

- `lighttpd -V` prints its feature list (poll, writev/write, mmap, IPv6, zlib, OpenSSL, PCRE)
  when its output goes to a file; through vms.sh's `/OUTPUT=` capture only the first line
  arrives (write() then printf() to a captured SYS$OUTPUT). Not a lighttpd problem.
- The `invalid request-line` 400s in the error log come from the TLS tests, which send a
  bare newline after the handshake.
- Test paths for rooted disks (`DKA800:[USERS.][IAIN...]`) need the `.][` join turned into
  a `.` before the UNIX path is built (`p2setup.com`).
