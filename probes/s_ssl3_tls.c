/* s_ssl3_tls.c - what mod_openssl needs from VSI's SSL3 (OpenSSL 3.0) when
   called from VSI C code (32-bit pointers, linked against SSL3$LIBSSL_SHR32
   and SSL3$LIBCRYPTO_SHR32, as vms-curl does): an in-process TLS handshake
   between a server and a client over a socketpair, with a freshly made EC
   key and self-signed certificate, ALPN "h2", then a resumed session. */
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <unistd.h>
#include <openssl/opensslv.h>
#include <openssl/crypto.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>
#include <openssl/rand.h>

static void say(const char *what, int ok, const char *detail)
{
  printf("TLS %-38s %s %s\n", what, ok ? "yes" : "NO ", detail ? detail : "");
  fflush(stdout);
}

static void errs(void)
{
  unsigned long e;
  char b[256];
  while ((e = ERR_get_error()) != 0) {
    ERR_error_string_n(e, b, sizeof b);
    printf("TLS   error %s\n", b);
  }
}

static const unsigned char alpn_wire[] = "\x02h2\x08http/1.1";

static int alpn_select(SSL *s, const unsigned char **out, unsigned char *outlen,
                       const unsigned char *in, unsigned int inlen, void *arg)
{
  (void) s; (void) arg;
  if (SSL_select_next_proto((unsigned char **) out, outlen, alpn_wire, sizeof alpn_wire - 1,
                            in, inlen) == OPENSSL_NPN_NEGOTIATED)
    return SSL_TLSEXT_ERR_OK;
  return SSL_TLSEXT_ERR_NOACK;
}

/* Drive both ends of a non-blocking handshake until both finish. */
static int handshake(SSL *srv, SSL *cli)
{
  int i, sd = 0, cd = 0, r;
  for (i = 0; i < 1000 && !(sd && cd); i++) {
    if (!cd) {
      r = SSL_do_handshake(cli);
      if (r == 1) cd = 1;
      else if (SSL_get_error(cli, r) != SSL_ERROR_WANT_READ && SSL_get_error(cli, r) != SSL_ERROR_WANT_WRITE) return 0;
    }
    if (!sd) {
      r = SSL_do_handshake(srv);
      if (r == 1) sd = 1;
      else if (SSL_get_error(srv, r) != SSL_ERROR_WANT_READ && SSL_get_error(srv, r) != SSL_ERROR_WANT_WRITE) return 0;
    }
  }
  return sd && cd;
}

static void pump(SSL *a, SSL *b)  /* let post-handshake messages (tickets) through */
{
  char buf[64];
  int i;
  for (i = 0; i < 10; i++) { SSL_read(a, buf, sizeof buf); SSL_read(b, buf, sizeof buf); }
}

int main(void)
{
  EVP_PKEY *pk;
  X509 *x;
  X509_NAME *nm;
  SSL_CTX *sctx, *cctx;
  SSL *srv, *cli;
  SSL_SESSION *sess = NULL;
  int sv[2], ok;
  char d[200], buf[64];
  const unsigned char *ap;
  unsigned int aplen;

  printf("TLS header %s; library %s\n", OPENSSL_VERSION_TEXT, OpenSSL_version(OPENSSL_VERSION));
  printf("TLS sizeof(long)=%u sizeof(void *)=%u sizeof(size_t)=%u\n", (unsigned) sizeof(long),
         (unsigned) sizeof(void *), (unsigned) sizeof(size_t));

  pk = EVP_EC_gen("P-256");
  say("EVP_EC_gen P-256", pk != NULL, NULL);
  if (!pk) { errs(); return 1; }
  x = X509_new();
  X509_set_version(x, 2);
  ASN1_INTEGER_set(X509_get_serialNumber(x), 1);
  X509_gmtime_adj(X509_getm_notBefore(x), 0);
  X509_gmtime_adj(X509_getm_notAfter(x), 86400L);
  X509_set_pubkey(x, pk);
  nm = X509_get_subject_name(x);
  X509_NAME_add_entry_by_txt(nm, "CN", MBSTRING_ASC, (const unsigned char *) "localhost", -1, -1, 0);
  X509_set_issuer_name(x, nm);
  ok = X509_sign(x, pk, EVP_sha256()) > 0;
  say("self-signed certificate", ok, NULL);
  if (!ok) { errs(); return 1; }

  sctx = SSL_CTX_new(TLS_server_method());
  cctx = SSL_CTX_new(TLS_client_method());
  ok = SSL_CTX_use_certificate(sctx, x) == 1 && SSL_CTX_use_PrivateKey(sctx, pk) == 1 &&
       SSL_CTX_check_private_key(sctx) == 1;
  say("server cert + key", ok, NULL);
  SSL_CTX_set_min_proto_version(sctx, TLS1_2_VERSION);
  SSL_CTX_set_alpn_select_cb(sctx, alpn_select, NULL);
  SSL_CTX_set_session_cache_mode(cctx, SSL_SESS_CACHE_CLIENT);
  {
    uint64_t o = SSL_CTX_set_options(sctx, SSL_OP_NO_RENEGOTIATION | SSL_OP_CIPHER_SERVER_PREFERENCE);
    snprintf(d, sizeof d, "%#llx", (unsigned long long) o);
    say("SSL_CTX_set_options (uint64_t)", (o & SSL_OP_NO_RENEGOTIATION) != 0, d);
  }
  ok = SSL_CTX_set_ciphersuites(sctx, "TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256") == 1 &&
       SSL_CTX_set_cipher_list(sctx, "ECDHE+AESGCM:ECDHE+CHACHA20") == 1;
  say("cipher configuration", ok, NULL);

  socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
  fcntl(sv[0], F_SETFL, O_NONBLOCK);
  fcntl(sv[1], F_SETFL, O_NONBLOCK);
  srv = SSL_new(sctx); SSL_set_fd(srv, sv[0]); SSL_set_accept_state(srv);
  cli = SSL_new(cctx); SSL_set_fd(cli, sv[1]); SSL_set_connect_state(cli);
  SSL_set_alpn_protos(cli, alpn_wire, sizeof alpn_wire - 1);
  SSL_set_tlsext_host_name(cli, "localhost");
  ok = handshake(srv, cli);
  SSL_get0_alpn_selected(srv, &ap, &aplen);
  snprintf(d, sizeof d, "%s %s alpn=%.*s", SSL_get_version(srv), SSL_get_cipher(srv), (int) aplen,
           aplen ? (const char *) ap : "");
  say("TLS handshake (socketpair, non-blocking)", ok, d);
  if (!ok) { errs(); return 1; }
  say("ALPN selected h2", aplen == 2 && memcmp(ap, "h2", 2) == 0, NULL);
  {
    const char *sni = SSL_get_servername(srv, TLSEXT_NAMETYPE_host_name);
    say("SNI seen by server", sni && strcmp(sni, "localhost") == 0, sni);
  }
  SSL_write(cli, "ping", 4);
  memset(buf, 0, sizeof buf);
  {
    int i, n = -1;
    for (i = 0; i < 100 && n <= 0; i++) n = SSL_read(srv, buf, sizeof buf);
    say("application data", n == 4 && memcmp(buf, "ping", 4) == 0, NULL);
  }
  pump(cli, srv);
  sess = SSL_get1_session(cli);
  say("client has a resumable session", sess && SSL_SESSION_is_resumable(sess), NULL);
  SSL_shutdown(cli); SSL_shutdown(srv);
  SSL_free(cli); SSL_free(srv);
  close(sv[0]); close(sv[1]);

  /* resumption with the ticket */
  socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
  fcntl(sv[0], F_SETFL, O_NONBLOCK);
  fcntl(sv[1], F_SETFL, O_NONBLOCK);
  srv = SSL_new(sctx); SSL_set_fd(srv, sv[0]); SSL_set_accept_state(srv);
  cli = SSL_new(cctx); SSL_set_fd(cli, sv[1]); SSL_set_connect_state(cli);
  if (sess) SSL_set_session(cli, sess);
  ok = handshake(srv, cli);
  say("second handshake resumed", ok && SSL_session_reused(cli), NULL);
  if (!ok) errs();

  /* TLS 1.2 only client still works (older browsers, monitoring) */
  SSL_free(cli); SSL_free(srv);
  close(sv[0]); close(sv[1]);
  socketpair(AF_UNIX, SOCK_STREAM, 0, sv);
  fcntl(sv[0], F_SETFL, O_NONBLOCK);
  fcntl(sv[1], F_SETFL, O_NONBLOCK);
  SSL_CTX_set_max_proto_version(cctx, TLS1_2_VERSION);
  srv = SSL_new(sctx); SSL_set_fd(srv, sv[0]); SSL_set_accept_state(srv);
  cli = SSL_new(cctx); SSL_set_fd(cli, sv[1]); SSL_set_connect_state(cli);
  ok = handshake(srv, cli);
  snprintf(d, sizeof d, "%s %s", SSL_get_version(srv), SSL_get_cipher(srv));
  say("TLS 1.2 handshake", ok, d);
  if (!ok) errs();

  {
    unsigned char r[16];
    say("RAND_bytes", RAND_bytes(r, sizeof r) == 1, NULL);
  }
  printf("S_SSL3_TLS DONE\n");
  return 0;
}
