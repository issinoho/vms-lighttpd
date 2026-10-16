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

## TLS scan (testssl.sh 3.2.4, x86, 2026-10-16)

Both HTTPS listeners of the test server, rebuilt from clean that day (logs in
`out/testssl-x86-1844[34].{log,json}`): 18443 (lighttpd's default, TLS 1.3 only) and 18444
(`MinProtocol` TLSv1.2, as the kit template's commented-out line offers).

| | 18443 | 18444 |
|---|---|---|
| protocols | TLS 1.3 only | TLS 1.2, 1.3; SSLv2/3, TLS 1.0/1.1 not offered |
| ciphers | AEAD with forward secrecy only; no NULL/export/RC4/3DES/CBC | same |
| curves | X25519, X448, P-256, P-384 | same |
| vulnerabilities (Heartbleed ... RC4, 17 checks) | none | none |
| ALPN | h2, http/1.1 | h2, http/1.1 |
| client simulations | modern clients connect; IE 11, Android 7-8, Apple Mail 16, Java 7, OpenSSL 1.0.2 do not (no TLS 1.2) | all but IE 8 and Java 7 |
| HIGH/CRITICAL | certificate only | certificate only |

All HIGH and CRITICAL findings are about the throwaway 30-day self-signed test certificate
(self-signed chain, no SAN, name mismatch, no CRL/OCSP, expiry < 30 days), and they cap
the grade at T. None is about lighttpd or OpenSSL. A CA-issued certificate removes them;
that check is done on the live service, not here. Lower findings: no HSTS and no security
headers (MEDIUM/LOW; set with `setenv.add-response-header` per site), and no post-quantum
KEMs (LOW; SSL3 is OpenSSL 3.0, and ML-KEM needs 3.5).

## Notes

- `lighttpd -V` prints its feature list (poll, writev/write, mmap, IPv6, zlib, OpenSSL, PCRE)
  when its output goes to a file; through vms.sh's `/OUTPUT=` capture only the first line
  arrives (write() then printf() to a captured SYS$OUTPUT). Not a lighttpd problem.
- The `invalid request-line` 400s in the error log come from the TLS tests, which send a
  bare newline after the handshake.
- Test paths for rooted disks (`DKA800:[USERS.][IAIN...]`) need the `.][` join turned into
  a `.` before the UNIX path is built (`p2setup.com`).
