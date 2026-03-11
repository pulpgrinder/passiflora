/*
 * passiflora.c — A minimal HTTP server that serves files from an
 * embedded ZIP archive.  The ZIP data is compiled in as a C array
 * via #include "generated/zipdata.h".  The server has no filesystem access
 * whatsoever — all content comes from the embedded archive.
 *
 * Supports ZIP compression methods 0 (stored) and 8 (deflate).
 * The deflate decompressor is a self-contained pure-C implementation
 * of RFC 1951 with no external dependencies.
 *
 * Build:
 *   ./nixscripts/mkzipfile.sh content_dir    # generates zipdata.c
 *   cc -O2 -o passiflora passiflora.c
 *
 * Usage:
 *   ./passiflora [port]           # default port: 8080
 *
 * Dependencies: POSIX (sockets, pthreads, signal).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <errno.h>
#include <ctype.h>
#include <stdint.h>
#include <signal.h>
#include <pthread.h>

/* ---- Platform socket abstraction ---- */
#ifdef _WIN32
  #ifndef WIN32_LEAN_AND_MEAN
  #define WIN32_LEAN_AND_MEAN
  #endif
  #include <winsock2.h>
  #include <ws2tcpip.h>
  #include <windows.h>
  #include <shellapi.h>
  #define sock_read(fd,buf,len)   recv((fd),(char*)(buf),(int)(len),0)
  #define sock_write(fd,buf,len)  send((fd),(const char*)(buf),(int)(len),0)
  #define sock_close(fd)          closesocket(fd)
  #define sock_errno()            WSAGetLastError()
  #define SOCK_EINTR              WSAEINTR
  static inline void sock_perror(const char *msg) {
      fprintf(stderr, "%s: Winsock error %d\n", msg, WSAGetLastError());
  }
#else
  #include <unistd.h>
  #include <pwd.h>
  #include <sys/types.h>
  #include <sys/socket.h>
  #include <sys/time.h>
  #include <netinet/in.h>
  #include <arpa/inet.h>
  #define sock_read(fd,buf,len)   read(fd,buf,len)
  #define sock_write(fd,buf,len)  write(fd,buf,len)
  #define sock_close(fd)          close(fd)
  #define sock_errno()            errno
  #define SOCK_EINTR              EINTR
  #define sock_perror(msg)        perror(msg)
#endif

/* ---- macOS: NSWorkspace for opening external URLs ---- */
#if defined(__APPLE__) && defined(__MACH__)
  #include <TargetConditionals.h>
  #if TARGET_OS_IPHONE
    #import <UIKit/UIKit.h>
  #else
    #import <Cocoa/Cocoa.h>
  #endif
#endif

/* ---- Android logging: route fprintf(stderr,...) to logcat ---- */
#ifdef __ANDROID__
  #include <android/log.h>
  #define LOG_TAG "passiflora"
  #define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
  #define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
  #define LOGI(...) fprintf(stderr, __VA_ARGS__)
  #define LOGE(...) fprintf(stderr, __VA_ARGS__)
#endif

/* ------------------------------------------------------------------ */
/*  Embedded ZIP filesystem                                            */
/* ------------------------------------------------------------------ */
#include "generated/zipdata.h"
#include "zipzip.h"

/* Provided by UI.c */
extern void ui_open(int port);

/* ------------------------------------------------------------------ */
/*  Configuration                                                      */
/* ------------------------------------------------------------------ */
#define DEFAULT_PORT       8080
#define BACKLOG            128
#define MAX_HEADER_SIZE    (64 * 1024)
#define MAX_CONNECTIONS    64
#define READ_TIMEOUT_SECS  30
#define WRITE_TIMEOUT_SECS 30

/* Connection limiter */
static int             active_connections = 0;
static pthread_mutex_t conn_lock  = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  conn_cond  = PTHREAD_COND_INITIALIZER;

/* ------------------------------------------------------------------ */
/*  MIME type helper                                                   */
/* ------------------------------------------------------------------ */
static const char *mime_for_path(const char *path)
{
    const char *dot = strrchr(path, '.');
    if (!dot) return "application/octet-stream";
    dot++;
    if (strcasecmp(dot, "html") == 0 || strcasecmp(dot, "htm") == 0)
        return "text/html; charset=utf-8";
    if (strcasecmp(dot, "css") == 0)
        return "text/css; charset=utf-8";
    if (strcasecmp(dot, "js") == 0)
        return "application/javascript; charset=utf-8";
    if (strcasecmp(dot, "json") == 0)
        return "application/json; charset=utf-8";
    if (strcasecmp(dot, "xml") == 0)
        return "application/xml; charset=utf-8";
    if (strcasecmp(dot, "svg") == 0)
        return "image/svg+xml";
    if (strcasecmp(dot, "png") == 0)
        return "image/png";
    if (strcasecmp(dot, "jpg") == 0 || strcasecmp(dot, "jpeg") == 0)
        return "image/jpeg";
    if (strcasecmp(dot, "gif") == 0)
        return "image/gif";
    if (strcasecmp(dot, "ico") == 0)
        return "image/x-icon";
    if (strcasecmp(dot, "woff") == 0)
        return "font/woff";
    if (strcasecmp(dot, "woff2") == 0)
        return "font/woff2";
    if (strcasecmp(dot, "ttf") == 0)
        return "font/ttf";
    if (strcasecmp(dot, "otf") == 0)
        return "font/otf";
    if (strcasecmp(dot, "wasm") == 0)
        return "application/wasm";
    if (strcasecmp(dot, "pdf") == 0)
        return "application/pdf";
    if (strcasecmp(dot, "txt") == 0)
        return "text/plain; charset=utf-8";
    if (strcasecmp(dot, "md") == 0)
        return "text/markdown; charset=utf-8";
    if (strcasecmp(dot, "mp3") == 0)
        return "audio/mpeg";
    if (strcasecmp(dot, "mp4") == 0)
        return "video/mp4";
    if (strcasecmp(dot, "webm") == 0)
        return "video/webm";
    if (strcasecmp(dot, "webp") == 0)
        return "image/webp";
    return "application/octet-stream";
}

/* ------------------------------------------------------------------ */
/*  Send helpers                                                       */
/* ------------------------------------------------------------------ */
static int send_all(int fd, const void *buf, size_t len)
{
    const unsigned char *p = buf;
    while (len > 0) {
        ssize_t n = sock_write(fd, p, len);
        if (n <= 0) return -1;
        p   += n;
        len -= n;
    }
    return 0;
}

static void send_response(int fd, int code, const char *status,
                           const char *content_type,
                           const unsigned char *body, size_t body_len)
{
    char hdr[1024];
    int hlen = snprintf(hdr, sizeof hdr,
        "HTTP/1.1 %d %s\r\n"
        "Content-Type: %s\r\n"
        "Content-Length: %zu\r\n"
        "X-Content-Type-Options: nosniff\r\n"
        "X-Frame-Options: DENY\r\n"
        "Content-Security-Policy: default-src 'self' 'unsafe-inline'\r\n"
        "Referrer-Policy: no-referrer\r\n"
        "Connection: close\r\n"
        "\r\n",
        code, status, content_type, body_len);
    if (hlen > 0 && (size_t)hlen < sizeof hdr)
        send_all(fd, hdr, hlen);
    if (body && body_len)
        send_all(fd, body, body_len);
}

static void send_text(int fd, int code, const char *status, const char *msg)
{
    send_response(fd, code, status, "text/plain; charset=utf-8",
                  (const unsigned char *)msg, strlen(msg));
}

/* ================================================================== */
/*  POSIX bridge — file I/O accessible from JavaScript                */
/* ================================================================== */

/* Forward declaration — url_decode is defined further below */
static int url_decode(char *s);

#define MAX_POSIX_READ     (16 * 1024 * 1024)
#define MAX_FGETS_LINE     65536
#define MAX_FILE_HANDLES   64

/* ---- File handle table ---- */
static FILE            *file_handles[MAX_FILE_HANDLES];
static pthread_mutex_t  fh_lock = PTHREAD_MUTEX_INITIALIZER;

static int fh_alloc(FILE *f)
{
    pthread_mutex_lock(&fh_lock);
    for (int i = 1; i < MAX_FILE_HANDLES; i++) {
        if (!file_handles[i]) {
            file_handles[i] = f;
            pthread_mutex_unlock(&fh_lock);
            return i;
        }
    }
    pthread_mutex_unlock(&fh_lock);
    return -1;
}

static FILE *fh_get(int h)
{
    if (h < 1 || h >= MAX_FILE_HANDLES) return NULL;
    pthread_mutex_lock(&fh_lock);
    FILE *f = file_handles[h];
    pthread_mutex_unlock(&fh_lock);
    return f;
}

/* Atomically remove and return a handle (for fclose) */
static FILE *fh_take(int h)
{
    if (h < 1 || h >= MAX_FILE_HANDLES) return NULL;
    pthread_mutex_lock(&fh_lock);
    FILE *f = file_handles[h];
    file_handles[h] = NULL;
    pthread_mutex_unlock(&fh_lock);
    return f;
}

/* ---- Base64 encode/decode ---- */
static const char b64_table[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static char *b64_encode(const unsigned char *data, size_t len, size_t *out_len)
{
    size_t olen = 4 * ((len + 2) / 3);
    char *out = malloc(olen + 1);
    if (!out) return NULL;
    size_t j = 0;
    for (size_t i = 0; i < len; ) {
        uint32_t a = i < len ? data[i++] : 0;
        uint32_t b = i < len ? data[i++] : 0;
        uint32_t c = i < len ? data[i++] : 0;
        uint32_t triple = (a << 16) | (b << 8) | c;
        out[j++] = b64_table[(triple >> 18) & 0x3F];
        out[j++] = b64_table[(triple >> 12) & 0x3F];
        out[j++] = b64_table[(triple >> 6) & 0x3F];
        out[j++] = b64_table[triple & 0x3F];
    }
    /* Pad */
    size_t mod = len % 3;
    if (mod == 1) { out[olen - 1] = '='; out[olen - 2] = '='; }
    else if (mod == 2) { out[olen - 1] = '='; }
    out[olen] = '\0';
    if (out_len) *out_len = olen;
    return out;
}

static int b64_val(unsigned char c)
{
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

static unsigned char *b64_decode(const char *data, size_t len, size_t *out_len)
{
    if (len % 4 != 0) return NULL;
    size_t olen = len / 4 * 3;
    if (len > 0 && data[len - 1] == '=') olen--;
    if (len > 1 && data[len - 2] == '=') olen--;
    unsigned char *out = malloc(olen + 1);
    if (!out) return NULL;
    size_t j = 0;
    for (size_t i = 0; i < len; i += 4) {
        int a = b64_val(data[i]);
        int b = b64_val(data[i + 1]);
        int c = data[i + 2] == '=' ? 0 : b64_val(data[i + 2]);
        int d = data[i + 3] == '=' ? 0 : b64_val(data[i + 3]);
        if (a < 0 || b < 0 || c < 0 || d < 0) { free(out); return NULL; }
        uint32_t triple = (a << 18) | (b << 12) | (c << 6) | d;
        if (j < olen) out[j++] = (triple >> 16) & 0xFF;
        if (j < olen) out[j++] = (triple >> 8) & 0xFF;
        if (j < olen) out[j++] = triple & 0xFF;
    }
    out[olen] = '\0';
    if (out_len) *out_len = olen;
    return out;
}

/* ---- Form-body parsing (application/x-www-form-urlencoded) ---- */
static int form_get_str(const char *body, const char *key,
                        char *out, size_t out_sz)
{
    if (!body || !key) return -1;
    size_t klen = strlen(key);
    const char *p = body;
    while (*p) {
        if (strncmp(p, key, klen) == 0 && p[klen] == '=') {
            p += klen + 1;
            const char *end = strchr(p, '&');
            size_t vlen = end ? (size_t)(end - p) : strlen(p);
            if (vlen >= out_sz) vlen = out_sz - 1;
            memcpy(out, p, vlen);
            out[vlen] = '\0';
            if (url_decode(out) < 0) return -1;
            return 0;
        }
        const char *amp = strchr(p, '&');
        if (!amp) break;
        p = amp + 1;
    }
    return -1;
}

static int form_get_int(const char *body, const char *key, int *val)
{
    char buf[64];
    if (form_get_str(body, key, buf, sizeof buf) < 0) return -1;
    *val = atoi(buf);
    return 0;
}

static int form_get_long(const char *body, const char *key, long *val)
{
    char buf[64];
    if (form_get_str(body, key, buf, sizeof buf) < 0) return -1;
    *val = atol(buf);
    return 0;
}

/* Get the raw (still-encoded) value of a form parameter.
 * Needed for base64 data where we do our own decoding. */
static int form_get_raw(const char *body, const char *key,
                        const char **start, size_t *len)
{
    if (!body || !key) return -1;
    size_t klen = strlen(key);
    const char *p = body;
    while (*p) {
        if (strncmp(p, key, klen) == 0 && p[klen] == '=') {
            p += klen + 1;
            const char *end = strchr(p, '&');
            *start = p;
            *len = end ? (size_t)(end - p) : strlen(p);
            return 0;
        }
        const char *amp = strchr(p, '&');
        if (!amp) break;
        p = amp + 1;
    }
    return -1;
}

/* ---- JSON result builders (return malloc'd string, caller frees) ---- */

static char *json_error(const char *msg)
{
    char esc[512];
    size_t j = 0;
    for (size_t i = 0; msg[i] && j < sizeof(esc) - 6; i++) {
        unsigned char c = (unsigned char)msg[i];
        if (c == '"')       { esc[j++] = '\\'; esc[j++] = '"'; }
        else if (c == '\\') { esc[j++] = '\\'; esc[j++] = '\\'; }
        else if (c == '\n') { esc[j++] = '\\'; esc[j++] = 'n'; }
        else if (c == '\r') { esc[j++] = '\\'; esc[j++] = 'r'; }
        else if (c < 0x20)  { j += snprintf(esc + j, sizeof(esc) - j,
                                             "\\u%04x", c); }
        else                { esc[j++] = c; }
    }
    esc[j] = '\0';
    char *buf = malloc(1024);
    if (!buf) return NULL;
    snprintf(buf, 1024, "{\"ok\":false,\"error\":\"%s\"}", esc);
    return buf;
}

static char *json_ok_void(void)
{
    return strdup("{\"ok\":true}");
}

static char *json_ok_int(long val)
{
    char *buf = malloc(128);
    if (!buf) return NULL;
    snprintf(buf, 128, "{\"ok\":true,\"result\":%ld}", val);
    return buf;
}

static char *json_ok_bool(int val)
{
    return strdup(val ? "{\"ok\":true,\"result\":true}"
                      : "{\"ok\":true,\"result\":false}");
}

static char *json_ok_null(void)
{
    return strdup("{\"ok\":true,\"result\":null}");
}

static char *json_ok_str(const char *val)
{
    if (!val) return json_ok_null();
    size_t slen = strlen(val);
    size_t bufsz = slen * 6 + 64;
    char *buf = malloc(bufsz);
    if (!buf) return json_error("Out of memory");
    size_t pos = 0;
    pos += snprintf(buf, bufsz, "{\"ok\":true,\"result\":\"");
    for (size_t i = 0; i < slen && pos < bufsz - 10; i++) {
        unsigned char c = (unsigned char)val[i];
        if (c == '"')       { buf[pos++] = '\\'; buf[pos++] = '"'; }
        else if (c == '\\') { buf[pos++] = '\\'; buf[pos++] = '\\'; }
        else if (c == '\n') { buf[pos++] = '\\'; buf[pos++] = 'n'; }
        else if (c == '\r') { buf[pos++] = '\\'; buf[pos++] = 'r'; }
        else if (c == '\t') { buf[pos++] = '\\'; buf[pos++] = 't'; }
        else if (c < 0x20)  { pos += snprintf(buf + pos, bufsz - pos,
                                               "\\u%04x", c); }
        else                { buf[pos++] = c; }
    }
    pos += snprintf(buf + pos, bufsz - pos, "\"}");
    return buf;
}

static char *json_ok_b64(const unsigned char *data, size_t len)
{
    size_t b64_len;
    char *b64 = b64_encode(data, len, &b64_len);
    if (!b64) return json_error("Out of memory");
    size_t bufsz = b64_len + 64;
    char *buf = malloc(bufsz);
    if (!buf) { free(b64); return json_error("Out of memory"); }
    int pre = snprintf(buf, bufsz, "{\"ok\":true,\"result\":\"");
    memcpy(buf + pre, b64, b64_len);
    snprintf(buf + pre + b64_len, bufsz - pre - b64_len, "\"}");
    free(b64);
    return buf;
}

/* ---- POSIX dispatcher (called from native UI bridge) ---- */
/*  params: URL-encoded string "func=fopen&path=...&mode=..."          */
/*  Returns malloc'd JSON string. Caller must free().                  */
char *passiflora_posix_call(const char *params)
{
    /* Make a mutable copy so form_get_str can url_decode in place */
    size_t plen = params ? strlen(params) : 0;
    char *body = malloc(plen + 1);
    if (!body) return json_error("Out of memory");
    memcpy(body, params ? params : "", plen + 1);

    char func_buf[64];
    if (form_get_str(body, "func", func_buf, sizeof func_buf) < 0) {
        free(body);
        return json_error("Missing 'func' parameter");
    }
    const char *func = func_buf;

    char path_buf[2048], path_buf2[2048], mode_buf[16];
    char str_buf[MAX_FGETS_LINE];
    int handle;
    long lval;
    char *result;

    /* ---- fopen ---- */
    if (strcmp(func, "fopen") == 0) {
        if (form_get_str(body, "path", path_buf, sizeof path_buf) < 0) {
            free(body); return json_error("Missing 'path' parameter");
        }
        if (form_get_str(body, "mode", mode_buf, sizeof mode_buf) < 0)
            snprintf(mode_buf, sizeof mode_buf, "r");
        if (strstr(path_buf, "..")) {
            free(body); return json_error("Path traversal not allowed");
        }
        FILE *f = fopen(path_buf, mode_buf);
        if (!f) { result = json_error(strerror(errno)); free(body); return result; }
        int h = fh_alloc(f);
        if (h < 0) { fclose(f); free(body); return json_error("Too many open files"); }
        free(body); return json_ok_int(h);
    }

    /* ---- fclose ---- */
    if (strcmp(func, "fclose") == 0) {
        if (form_get_int(body, "handle", &handle) < 0) {
            free(body); return json_error("Missing 'handle' parameter");
        }
        FILE *f = fh_take(handle);
        if (!f) { free(body); return json_error("Invalid handle"); }
        fclose(f);
        free(body); return json_ok_void();
    }

    /* ---- fread ---- */
    if (strcmp(func, "fread") == 0) {
        int size = 0;
        if (form_get_int(body, "handle", &handle) < 0 ||
            form_get_int(body, "size", &size) < 0) {
            free(body); return json_error("Missing 'handle' or 'size' parameter");
        }
        if (size <= 0 || size > MAX_POSIX_READ) {
            free(body); return json_error("Invalid size");
        }
        FILE *f = fh_get(handle);
        if (!f) { free(body); return json_error("Invalid handle"); }
        unsigned char *buf = malloc(size);
        if (!buf) { free(body); return json_error("Out of memory"); }
        size_t nread = fread(buf, 1, size, f);
        if (nread == 0) { free(buf); free(body); return json_ok_null(); }
        result = json_ok_b64(buf, nread);
        free(buf); free(body); return result;
    }

    /* ---- fwrite ---- */
    if (strcmp(func, "fwrite") == 0) {
        if (form_get_int(body, "handle", &handle) < 0) {
            free(body); return json_error("Missing 'handle' parameter");
        }
        const char *b64_start; size_t b64_len;
        if (form_get_raw(body, "data", &b64_start, &b64_len) < 0) {
            free(body); return json_error("Missing 'data' parameter");
        }
        size_t dec_len;
        unsigned char *dec = b64_decode(b64_start, b64_len, &dec_len);
        if (!dec) { free(body); return json_error("Invalid base64 data"); }
        FILE *f = fh_get(handle);
        if (!f) { free(dec); free(body); return json_error("Invalid handle"); }
        size_t written = fwrite(dec, 1, dec_len, f);
        free(dec); free(body); return json_ok_int((long)written);
    }

    /* ---- fgets ---- */
    if (strcmp(func, "fgets") == 0) {
        if (form_get_int(body, "handle", &handle) < 0) {
            free(body); return json_error("Missing 'handle' parameter");
        }
        FILE *f = fh_get(handle);
        if (!f) { free(body); return json_error("Invalid handle"); }
        char *r = fgets(str_buf, sizeof str_buf, f);
        free(body);
        return r ? json_ok_str(str_buf) : json_ok_null();
    }

    /* ---- fputs ---- */
    if (strcmp(func, "fputs") == 0) {
        if (form_get_int(body, "handle", &handle) < 0) {
            free(body); return json_error("Missing 'handle' parameter");
        }
        if (form_get_str(body, "str", str_buf, sizeof str_buf) < 0) {
            free(body); return json_error("Missing 'str' parameter");
        }
        FILE *f = fh_get(handle);
        if (!f) { free(body); return json_error("Invalid handle"); }
        int rc = fputs(str_buf, f);
        free(body);
        return rc == EOF ? json_error("Write error") : json_ok_void();
    }

    /* ---- fseek ---- */
    if (strcmp(func, "fseek") == 0) {
        int whence = 0;
        if (form_get_int(body, "handle", &handle) < 0 ||
            form_get_long(body, "offset", &lval) < 0) {
            free(body); return json_error("Missing 'handle' or 'offset' parameter");
        }
        form_get_int(body, "whence", &whence);
        if (whence < 0 || whence > 2) {
            free(body); return json_error("Invalid whence (must be 0, 1, or 2)");
        }
        FILE *f = fh_get(handle);
        if (!f) { free(body); return json_error("Invalid handle"); }
        if (fseek(f, lval, whence) != 0) {
            result = json_error(strerror(errno)); free(body); return result;
        }
        free(body); return json_ok_void();
    }

    /* ---- ftell ---- */
    if (strcmp(func, "ftell") == 0) {
        if (form_get_int(body, "handle", &handle) < 0) {
            free(body); return json_error("Missing 'handle' parameter");
        }
        FILE *f = fh_get(handle);
        if (!f) { free(body); return json_error("Invalid handle"); }
        long pos = ftell(f);
        free(body);
        return pos < 0 ? json_error(strerror(errno)) : json_ok_int(pos);
    }

    /* ---- feof ---- */
    if (strcmp(func, "feof") == 0) {
        if (form_get_int(body, "handle", &handle) < 0) {
            free(body); return json_error("Missing 'handle' parameter");
        }
        FILE *f = fh_get(handle);
        if (!f) { free(body); return json_error("Invalid handle"); }
        result = json_ok_bool(feof(f));
        free(body); return result;
    }

    /* ---- fflush ---- */
    if (strcmp(func, "fflush") == 0) {
        if (form_get_int(body, "handle", &handle) < 0) {
            free(body); return json_error("Missing 'handle' parameter");
        }
        FILE *f = fh_get(handle);
        if (!f) { free(body); return json_error("Invalid handle"); }
        if (fflush(f) != 0) {
            result = json_error(strerror(errno)); free(body); return result;
        }
        free(body); return json_ok_void();
    }

    /* ---- remove ---- */
    if (strcmp(func, "remove") == 0) {
        if (form_get_str(body, "path", path_buf, sizeof path_buf) < 0) {
            free(body); return json_error("Missing 'path' parameter");
        }
        if (strstr(path_buf, "..")) {
            free(body); return json_error("Path traversal not allowed");
        }
        if (remove(path_buf) != 0) {
            result = json_error(strerror(errno)); free(body); return result;
        }
        free(body); return json_ok_void();
    }

    /* ---- rename ---- */
    if (strcmp(func, "rename") == 0) {
        if (form_get_str(body, "oldpath", path_buf, sizeof path_buf) < 0 ||
            form_get_str(body, "newpath", path_buf2, sizeof path_buf2) < 0) {
            free(body); return json_error("Missing 'oldpath' or 'newpath' parameter");
        }
        if (strstr(path_buf, "..") || strstr(path_buf2, "..")) {
            free(body); return json_error("Path traversal not allowed");
        }
        if (rename(path_buf, path_buf2) != 0) {
            result = json_error(strerror(errno)); free(body); return result;
        }
        free(body); return json_ok_void();
    }

    /* ---- getUsername ---- */
    if (strcmp(func, "getUsername") == 0) {
        const char *name = NULL;
#ifdef _WIN32
        name = getenv("USERNAME");
#else
        struct passwd *pw = getpwuid(getuid());
        if (pw) name = pw->pw_name;
#endif
        if (!name) name = getenv("USER");
        free(body);
        return name ? json_ok_str(name) : json_ok_null();
    }

    /* ---- getHomeFolder ---- */
    if (strcmp(func, "getHomeFolder") == 0) {
        const char *home = NULL;
#ifdef _WIN32
        home = getenv("USERPROFILE");
#elif defined(__APPLE__) && defined(__MACH__) && TARGET_OS_IPHONE
        @autoreleasepool {
            NSString *docs = [NSSearchPathForDirectoriesInDomains(
                NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            if (docs) {
                char *cdir = strdup([docs UTF8String]);
                free(body);
                result = json_ok_str(cdir);
                free(cdir);
                return result;
            }
        }
#else
        struct passwd *pw = getpwuid(getuid());
        if (pw) home = pw->pw_dir;
#endif
        if (!home) home = getenv("HOME");
        free(body);
        return home ? json_ok_str(home) : json_ok_null();
    }

    free(body);
    return json_error("Unknown POSIX function");
}

/* ------------------------------------------------------------------ */
/*  URL-decode in place.  Returns -1 if a null byte is encountered.   */
/* ------------------------------------------------------------------ */
static int url_decode(char *s)
{
    char *out = s;
    while (*s) {
        if (s[0] == '%' && isxdigit(s[1]) && isxdigit(s[2])) {
            char hex[3] = { s[1], s[2], 0 };
            char ch = (char)strtol(hex, NULL, 16);
            if (ch == '\0') return -1;
            *out++ = ch;
            s += 3;
        } else {
            *out++ = *s++;
        }
    }
    *out = '\0';
    return 0;
}

/* ------------------------------------------------------------------ */
/*  Resolve a URL path to a ZIP filename.                              */
/*  Strips leading /, strips query string, appends index.html for      */
/*  trailing-slash paths.  Rejects path traversal.                     */
/* ------------------------------------------------------------------ */
static int resolve_path(const char *url_path, char *out, size_t out_sz)
{
    const char *p = url_path;
    while (*p == '/') p++;

    snprintf(out, out_sz, "%s", p);

    /* Strip query string */
    char *q = strchr(out, '?');
    if (q) *q = '\0';

    /* Trailing slash or empty → index.html */
    size_t len = strlen(out);
    if (len == 0) {
        snprintf(out, out_sz, "index.html");
    } else if (out[len - 1] == '/') {
        snprintf(out + len, out_sz - len, "index.html");
    }

    /* Reject path traversal */
    if (strstr(out, ".."))
        return -1;

    return 0;
}

/* ------------------------------------------------------------------ */
/*  Open a URL in the system's default browser                         */
/* ------------------------------------------------------------------ */
static void open_url_in_browser(const char *url)
{
#if defined(__APPLE__) && defined(__MACH__) && TARGET_OS_IPHONE
    @autoreleasepool {
        NSURL *nsurl = [NSURL URLWithString:
            [NSString stringWithUTF8String:url]];
        if (nsurl)
            [[UIApplication sharedApplication] openURL:nsurl
                options:@{} completionHandler:nil];
    }
#elif defined(__APPLE__) && defined(__MACH__)
    @autoreleasepool {
        NSURL *nsurl = [NSURL URLWithString:
            [NSString stringWithUTF8String:url]];
        if (nsurl)
            [[NSWorkspace sharedWorkspace] openURL:nsurl];
    }
#elif defined(_WIN32)
    ShellExecuteA(NULL, "open", url, NULL, NULL, SW_SHOWNORMAL);
#elif defined(__ANDROID__)
    /* Android: handled on the Java side; no-op here */
    (void)url;
#else
    /* Linux / other: use xdg-open */
    pid_t pid = fork();
    if (pid == 0) {
        execl("/usr/bin/xdg-open", "xdg-open", url, (char *)NULL);
        _exit(127);
    }
#endif
}

/* ------------------------------------------------------------------ */
/*  Request handler                                                    */
/* ------------------------------------------------------------------ */
static void handle_request(int fd)
{
    /* Read headers */
    size_t cap = 4096, used = 0;
    char *hdr = malloc(cap);
    if (!hdr) return;

    char *header_end = NULL;
    while (!header_end) {
        if (used + 1 >= cap) {
            cap *= 2;
            if (cap > MAX_HEADER_SIZE) {
                send_text(fd, 431, "Request Header Fields Too Large",
                          "Headers too large\n");
                free(hdr);
                return;
            }
            char *tmp = realloc(hdr, cap);
            if (!tmp) { free(hdr); return; }
            hdr = tmp;
        }
        ssize_t r = sock_read(fd, hdr + used, cap - used - 1);
        if (r <= 0) { free(hdr); return; }
        used += r;
        hdr[used] = '\0';
        header_end = strstr(hdr, "\r\n\r\n");
    }

    /* Parse request line */
    char method[16] = {0}, path[2048] = {0};
    if (sscanf(hdr, "%15s %2047s", method, path) < 2) {
        send_text(fd, 400, "Bad Request", "Malformed request\n");
        free(hdr);
        return;
    }

    if (url_decode(path) < 0) {
        send_text(fd, 400, "Bad Request", "Bad URL\n");
        free(hdr);
        return;
    }

    /* Sanitise path for logging: replace control chars */
    {
        char safe[2048];
        size_t i;
        for (i = 0; path[i] && i < sizeof(safe) - 1; i++)
            safe[i] = (unsigned char)path[i] < 0x20 || path[i] == 0x7f
                      ? '?' : path[i];
        safe[i] = '\0';
        LOGI("passiflora: %s %s\n", method, safe);
    }

    /* Only GET and HEAD are supported */
    if (strcasecmp(method, "GET") != 0 && strcasecmp(method, "HEAD") != 0) {
        send_text(fd, 405, "Method Not Allowed", "Only GET is supported\n");
        free(hdr);
        return;
    }

    /* ---- Internal API: open URL in external browser ---- */
    if (strncmp(path, "/__passiflora/openexternal?", 27) == 0) {
        const char *qs = path + 27;
        /* Extract url= parameter */
        if (strncmp(qs, "url=", 4) == 0) {
            char target[2048];
            snprintf(target, sizeof target, "%s", qs + 4);
            /* Only allow http:// and https:// URLs */
            if (strncmp(target, "http://", 7) == 0 ||
                strncmp(target, "https://", 8) == 0) {
                open_url_in_browser(target);
                send_text(fd, 200, "OK", "ok\n");
            } else {
                send_text(fd, 400, "Bad Request",
                          "Only http/https URLs are allowed\n");
            }
        } else {
            send_text(fd, 400, "Bad Request", "Missing url= parameter\n");
        }
        free(hdr);
        return;
    }

    /* Resolve path to a ZIP filename */
    char filename[2048];
    if (resolve_path(path, filename, sizeof filename) < 0) {
        send_text(fd, 400, "Bad Request", "Invalid path\n");
        free(hdr);
        return;
    }

    const char *mime = mime_for_path(filename);

    if (strcasecmp(method, "HEAD") == 0) {
        /* HEAD — look up size from ZIP headers without decompressing */
        size_t file_size = zip_find_size(zipdata, zipdata_len, filename);
        if (file_size == (size_t)-1) {
            send_text(fd, 404, "Not Found", "404 — file not found\n");
            free(hdr);
            return;
        }
        send_response(fd, 200, "OK", mime, NULL, file_size);
        free(hdr);
        return;
    }

    /* GET — decompress and serve */
    size_t data_len;
    unsigned char *data = zip_find(zipdata, zipdata_len,
                                   filename, &data_len);
    if (!data) {
        send_text(fd, 404, "Not Found", "404 — file not found\n");
        free(hdr);
        return;
    }

    send_response(fd, 200, "OK", mime, data, data_len);

    free(data);
    free(hdr);
}

/* ------------------------------------------------------------------ */
/*  Per-connection wrapper                                             */
/* ------------------------------------------------------------------ */
static void *handle_connection(void *arg)
{
    int fd = (int)(intptr_t)arg;

#ifdef _WIN32
    DWORD rcv_ms = READ_TIMEOUT_SECS * 1000;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO,
               (const char *)&rcv_ms, sizeof rcv_ms);
    DWORD snd_ms = WRITE_TIMEOUT_SECS * 1000;
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO,
               (const char *)&snd_ms, sizeof snd_ms);
#else
    struct timeval tv = { .tv_sec = READ_TIMEOUT_SECS, .tv_usec = 0 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);

    struct timeval wtv = { .tv_sec = WRITE_TIMEOUT_SECS, .tv_usec = 0 };
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &wtv, sizeof wtv);
#endif

    handle_request(fd);
    sock_close(fd);

    pthread_mutex_lock(&conn_lock);
    active_connections--;
    pthread_cond_signal(&conn_cond);
    pthread_mutex_unlock(&conn_lock);

    return NULL;
}

/* ------------------------------------------------------------------ */
/*  Server loop (runs on a background thread when UI is enabled)       */
/* ------------------------------------------------------------------ */
static void *server_loop(void *arg)
{
    int server_fd = (int)(intptr_t)arg;

    for (;;) {
        struct sockaddr_in client;
        socklen_t clen = sizeof client;
        int client_fd = accept(server_fd, (struct sockaddr *)&client, &clen);
        if (client_fd < 0) {
            if (sock_errno() == SOCK_EINTR) continue;
            sock_perror("accept");
            continue;
        }

        pthread_mutex_lock(&conn_lock);
        while (active_connections >= MAX_CONNECTIONS)
            pthread_cond_wait(&conn_cond, &conn_lock);
        active_connections++;
        pthread_mutex_unlock(&conn_lock);

        pthread_t tid;
        pthread_attr_t attr;
        pthread_attr_init(&attr);
        pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
        if (pthread_create(&tid, &attr, handle_connection,
                           (void *)(intptr_t)client_fd) != 0) {
            perror("pthread_create");
            sock_close(client_fd);
            pthread_mutex_lock(&conn_lock);
            active_connections--;
            pthread_cond_signal(&conn_cond);
            pthread_mutex_unlock(&conn_lock);
        }
        pthread_attr_destroy(&attr);
    }

    return NULL;
}

/* ------------------------------------------------------------------ */
/*  Main (not used on Android — Java is the entry point)               */
/* ------------------------------------------------------------------ */
#if !defined(__ANDROID__)
int main(int argc, char **argv)
{
#ifdef SIGPIPE
    signal(SIGPIPE, SIG_IGN);
#endif
#ifdef _WIN32
    { WSADATA wsa; WSAStartup(MAKEWORD(2,2), &wsa); }
#endif

    int port = 0;  /* 0 = let the OS pick a free port */
    int headless = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--headless") == 0) {
            headless = 1;
        } else {
            port = atoi(argv[i]);
            if (port < 1 || port > 65535) {
                fprintf(stderr,
                        "passiflora: invalid port '%s' (must be 1-65535)\n",
                        argv[i]);
                return 1;
            }
        }
    }

    LOGI("passiflora: embedded archive contains %zu bytes\n",
         (size_t)zipdata_len);

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) { sock_perror("socket"); return 1; }

    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR,
               (const char *)&opt, sizeof opt);

    struct sockaddr_in addr = {
        .sin_family      = AF_INET,
        .sin_addr.s_addr = htonl(INADDR_LOOPBACK),
        .sin_port        = htons(port),
    };

    if (bind(server_fd, (struct sockaddr *)&addr, sizeof addr) < 0) {
        sock_perror("bind");
        return 1;
    }

    /* If port was 0, read back the actual port the OS assigned */
    if (port == 0) {
        struct sockaddr_in bound;
        socklen_t blen = sizeof bound;
        if (getsockname(server_fd, (struct sockaddr *)&bound, &blen) == 0)
            port = ntohs(bound.sin_port);
    }

    if (listen(server_fd, BACKLOG) < 0) {
        sock_perror("listen");
        return 1;
    }

    LOGI("passiflora: listening on http://127.0.0.1:%d/\n", port);

    if (headless) {
        /* No UI — run server loop on the main thread */
        server_loop((void *)(intptr_t)server_fd);
    } else {
        /* Start server on a background thread, UI on the main thread */
        pthread_t srv_tid;
        if (pthread_create(&srv_tid, NULL, server_loop,
                           (void *)(intptr_t)server_fd) != 0) {
            perror("pthread_create");
            return 1;
        }
        pthread_detach(srv_tid);

        ui_open(port);  /* runs event loop, does not return */
    }

    sock_close(server_fd);
    return 0;
}
#else /* __ANDROID__ */
/* ------------------------------------------------------------------ */
/*  Android JNI — start server, return port                            */
/* ------------------------------------------------------------------ */
#include <jni.h>

JNIEXPORT jint JNICALL
Java_com_example_zipserve_MainActivity_startServer(JNIEnv *env, jclass cls)
{
    (void)env; (void)cls;

    /* Ignore SIGPIPE — Android delivers it when the WebView closes a
       connection and the server thread writes to the dead socket.
       Without this the default disposition (process termination) fires
       and the app crashes with "keeps stopping". */
#ifdef SIGPIPE
    signal(SIGPIPE, SIG_IGN);
#endif

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) {
        LOGE("passiflora: socket() failed: %s\n", strerror(errno));
        return -1;
    }

    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR,
               (const char *)&opt, sizeof opt);

    struct sockaddr_in addr = {
        .sin_family      = AF_INET,
        .sin_addr.s_addr = htonl(INADDR_LOOPBACK),
        .sin_port        = htons(0),
    };

    if (bind(server_fd, (struct sockaddr *)&addr, sizeof addr) < 0) {
        LOGE("passiflora: bind() failed: %s\n", strerror(errno));
        sock_close(server_fd);
        return -1;
    }

    struct sockaddr_in bound;
    socklen_t blen = sizeof bound;
    int port = 0;
    if (getsockname(server_fd, (struct sockaddr *)&bound, &blen) == 0)
        port = ntohs(bound.sin_port);

    if (listen(server_fd, BACKLOG) < 0) {
        LOGE("passiflora: listen() failed: %s\n", strerror(errno));
        sock_close(server_fd);
        return -1;
    }

    LOGI("passiflora: listening on http://127.0.0.1:%d/\n", port);

    pthread_t tid;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    if (pthread_create(&tid, &attr, server_loop,
                       (void *)(intptr_t)server_fd) != 0) {
        sock_close(server_fd);
        pthread_attr_destroy(&attr);
        return -1;
    }
    pthread_attr_destroy(&attr);

    return port;
}

JNIEXPORT jstring JNICALL
Java_com_example_zipserve_MainActivity_nativePosixCall(
    JNIEnv *env, jclass cls, jstring params)
{
    (void)cls;
    const char *p = (*env)->GetStringUTFChars(env, params, NULL);
    char *result = passiflora_posix_call(p);
    (*env)->ReleaseStringUTFChars(env, params, p);
    jstring jresult = (*env)->NewStringUTF(env, result ? result : "{}");
    free(result);
    return jresult;
}
#endif /* __ANDROID__ */
