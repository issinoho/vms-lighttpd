# Phase 2: static HTTP, HTTPS, soak

Test server: `tools/serve.sh <node> setup|start|stop|log` (a batch job running
`vmsport/tests/p2server.com`, config from `vmsport/tests/p2setup.com`), checks:
`tools/test_http.sh <node>`, load: `tools/soak.sh <node> [min] [workers]`.

## Results

| Check | x86 | IA64 |
|---|---|---|
| test_http.sh (24 checks) | 24/24 (2026-10-08) | see below |
| soak | see below | |

Per check: GET/HEAD, Content-Type, Content-Length for Stream_LF, a variable-record file
served by its converted bytes (0008), 404, path traversal refused, directory listing,
If-Modified-Since/If-None-Match → 304, three Range cases, 2 MB transfer with data check,
keep-alive reuse, POST to a static file; HTTPS GET, TLS 1.3, TLS 1.2 refused by default
(lighttpd 1.4.85's minimum is TLS 1.3) and accepted on a listener with
`ssl.openssl.ssl-conf-cmd = ("MinProtocol" => "TLSv1.2")`, TLS 1.1 refused, HTTP/2 via
ALPN, 2 MB over HTTPS h2, TLS 1.3 ticket resumption, TLS 1.2 resumption.

Throughput is limited by the nodes' TCP/IP (~50-130 KB/s per connection, D10), not lighttpd.
