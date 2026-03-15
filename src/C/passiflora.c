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
  #include <shlobj.h>
  #define sock_read(fd,buf,len)       recv((fd),(char*)(buf),(int)(len),0)
  #define sock_write(fd,buf,len)      send((fd),(const char*)(buf),(int)(len),0)
  #define sock_close(fd)              closesocket(fd)
  #define sock_errno()                WSAGetLastError()
  #define SOCK_EINTR                  WSAEINTR
  static inline void sock_perror(const char *msg) {
      fprintf(stderr, "%s: Winsock error %d\n", msg, WSAGetLastError());
  }
#else
  #include <unistd.h>
  #include <pwd.h>
  #include <sys/types.h>
  #include <sys/stat.h>
  #include <sys/socket.h>
  #include <sys/time.h>
  #include <netinet/in.h>
  #include <arpa/inet.h>
  #define sock_read(fd,buf,len)   read(fd,buf,len)
  #define sock_write(fd,buf,len)  write(fd,buf,len)
  #define sock_close(fd)              close(fd)
  #define sock_errno()                errno
  #define SOCK_EINTR                  EINTR
  #define sock_perror(msg)            perror(msg)
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
extern void passiflora_eval_js(const char *js);

/* Global server port — readable from UI.c for auto-debug */
int g_server_port = 0;

#ifdef PERM_REMOTEDEBUGGING
/* Maximum POST body for debug endpoint */
#define MAX_DEBUG_BODY  (256 * 1024)

/* Debug result buffer — written by webview JS, read by external debugger */
static char *debug_result_buf = NULL;
static pthread_mutex_t debug_result_lock = PTHREAD_MUTEX_INITIALIZER;

/* Return the local LAN IPv4 address (or "127.0.0.1" as fallback).
 * Uses the UDP-connect trick: connect a UDP socket to an external
 * address (no data sent), then read back the local address.          */
static char g_ip_buf[64];
#ifndef _WIN32
static pthread_once_t g_ip_once = PTHREAD_ONCE_INIT;
#endif

static void get_local_ip_init(void)
{
#ifdef _WIN32
    SOCKET s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s == INVALID_SOCKET) { snprintf(g_ip_buf, sizeof g_ip_buf, "127.0.0.1"); return; }
#else
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s < 0) { snprintf(g_ip_buf, sizeof g_ip_buf, "127.0.0.1"); return; }
#endif

    struct sockaddr_in dst;
    memset(&dst, 0, sizeof dst);
    dst.sin_family = AF_INET;
    dst.sin_port = htons(53);
    /* 8.8.8.8 — used only for routing lookup, no data is sent */
    dst.sin_addr.s_addr = htonl(0x08080808u);

    if (connect(s, (struct sockaddr *)&dst, sizeof dst) < 0) {
        sock_close(s);
        snprintf(g_ip_buf, sizeof g_ip_buf, "127.0.0.1");
        return;
    }

    struct sockaddr_in local;
    socklen_t len = sizeof local;
    if (getsockname(s, (struct sockaddr *)&local, &len) < 0) {
        sock_close(s);
        snprintf(g_ip_buf, sizeof g_ip_buf, "127.0.0.1");
        return;
    }
    sock_close(s);

    inet_ntop(AF_INET, &local.sin_addr, g_ip_buf, sizeof g_ip_buf);
}

const char *get_local_ip(void)
{
#ifdef _WIN32
    static INIT_ONCE win_once = INIT_ONCE_STATIC_INIT;
    InitOnceExecuteOnce(&win_once,
        (PINIT_ONCE_FN)(void *)get_local_ip_init, NULL, NULL);
#else
    pthread_once(&g_ip_once, get_local_ip_init);
#endif
    return g_ip_buf;
}

/* Called from UI.c after page finishes loading to auto-start debug */
void passiflora_auto_debug(int port)
{
    const char *ip = get_local_ip();
    char js[256];
    snprintf(js, sizeof js,
        "PassifloraIO._autoDebug('%s',%d)", ip, port);
    passiflora_eval_js(js);
}
#endif /* PERM_REMOTEDEBUGGING */

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
    if (strcasecmp(dot, "m4a") == 0)
        return "audio/mp4";
    if (strcasecmp(dot, "mov") == 0)
        return "video/quicktime";
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
    char hdr[2048];
    int hlen = snprintf(hdr, sizeof hdr,
        "HTTP/1.1 %d %s\r\n"
        "Content-Type: %s\r\n"
        "Content-Length: %zu\r\n"
        "X-Content-Type-Options: nosniff\r\n"
        "X-Frame-Options: DENY\r\n"
#ifdef PERM_REMOTEDEBUGGING
        "Content-Security-Policy: default-src 'self' 'unsafe-inline' 'unsafe-eval'; media-src 'self' mediastream: blob:\r\n"
#else
        "Content-Security-Policy: default-src 'self' 'unsafe-inline'; media-src 'self' mediastream: blob:\r\n"
#endif
        "Permissions-Policy: camera=(self), microphone=(self), geolocation=(self)\r\n"
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

/* Close all open file handles (cleanup on page navigation/reload) */
static int fh_close_all(void)
{
    int closed = 0;
    pthread_mutex_lock(&fh_lock);
    for (int i = 1; i < MAX_FILE_HANDLES; i++) {
        if (file_handles[i]) {
            fclose(file_handles[i]);
            file_handles[i] = NULL;
            closed++;
        }
    }
    pthread_mutex_unlock(&fh_lock);
    return closed;
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
/* These are non-static so UI.c media functions can use them. */

char *json_error(const char *msg)
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

char *json_ok_void(void)
{
    return strdup("{\"ok\":true}");
}

char *json_ok_int(long val)
{
    char *buf = malloc(128);
    if (!buf) return NULL;
    snprintf(buf, 128, "{\"ok\":true,\"result\":%ld}", val);
    return buf;
}

char *json_ok_bool(int val)
{
    return strdup(val ? "{\"ok\":true,\"result\":true}"
                      : "{\"ok\":true,\"result\":false}");
}

char *json_ok_null(void)
{
    return strdup("{\"ok\":true,\"result\":null}");
}

char *json_ok_str(const char *val)
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

char *json_ok_b64(const unsigned char *data, size_t len)
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

/* Return a pre-formed JSON value (array, object, etc.) as the result.
 * WARNING: json_val is embedded without escaping — only pass trusted data. */
char *json_ok_raw(const char *json_val)
{
    if (!json_val) return json_ok_null();
    size_t vlen = strlen(json_val);
    size_t bufsz = vlen + 32;
    char *buf = malloc(bufsz);
    if (!buf) return json_error("Out of memory");
    snprintf(buf, bufsz, "{\"ok\":true,\"result\":%s}", json_val);
    return buf;
}

/* ---- POSIX dispatcher (called from native UI bridge) ---- */
/*  params: URL-encoded string "func=fopen&path=...&mode=..."          */
/*  Returns malloc'd JSON string. Caller must free().                  */

/* ------------------------------------------------------------------ */
/*  App documents directory — platform-specific                        */
/*  Returns a static path to "~/Documents/PROGNAME" or equivalent.     */
/*  Creates the directory on first call if it does not exist.          */
/* ------------------------------------------------------------------ */
static const char *getDocumentsDirectory(void)
{
    static char doc_dir[2048] = "";
    if (doc_dir[0]) return doc_dir;

#ifdef _WIN32
    char my_docs[MAX_PATH];
    if (SUCCEEDED(SHGetFolderPathA(NULL, CSIDL_MYDOCUMENTS, NULL, 0, my_docs))) {
        snprintf(doc_dir, sizeof doc_dir, "%s\\%s", my_docs, PROGNAME_STR);
    } else {
        const char *profile = getenv("USERPROFILE");
        if (profile)
            snprintf(doc_dir, sizeof doc_dir, "%s\\Documents\\%s",
                     profile, PROGNAME_STR);
    }
    if (doc_dir[0]) CreateDirectoryA(doc_dir, NULL);
#elif defined(__APPLE__) && defined(__MACH__) && TARGET_OS_IPHONE
    @autoreleasepool {
        NSString *docs = [NSSearchPathForDirectoriesInDomains(
            NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        if (docs)
            snprintf(doc_dir, sizeof doc_dir, "%s/%s",
                     [docs UTF8String], PROGNAME_STR);
    }
    if (doc_dir[0]) mkdir(doc_dir, 0755);
#elif defined(__ANDROID__)
    extern const char *android_files_dir;
    const char *base = android_files_dir;
    if (!base) base = getenv("HOME");
    if (base)
        snprintf(doc_dir, sizeof doc_dir, "%s/%s", base, PROGNAME_STR);
    if (doc_dir[0]) mkdir(doc_dir, 0755);
#else
    /* macOS, Linux — use ~/Documents/ */
    const char *dd_home = getenv("HOME");
    if (!dd_home) {
        struct passwd *pw = getpwuid(getuid());
        if (pw) dd_home = pw->pw_dir;
    }
    if (dd_home) {
        char parent[1024];
        snprintf(parent, sizeof parent, "%s/Documents", dd_home);
        mkdir(parent, 0755);
        snprintf(doc_dir, sizeof doc_dir, "%s/%s", parent, PROGNAME_STR);
    }
    if (doc_dir[0]) mkdir(doc_dir, 0755);
#endif

    /* Canonicalize the stored path so symlink comparisons work */
#ifndef _WIN32
    if (doc_dir[0]) {
        char *rp = realpath(doc_dir, NULL);
        if (rp) {
            snprintf(doc_dir, sizeof doc_dir, "%s", rp);
            free(rp);
        }
    }
#endif

    return doc_dir[0] ? doc_dir : NULL;
}

#ifndef PERM_UNRESTRICTEDFILESYSTEMACCESS
/* ------------------------------------------------------------------ */
/*  Sandbox check — ensure a path resolves inside the documents dir    */
/* ------------------------------------------------------------------ */
static int path_in_sandbox(const char *path)
{
    const char *sandbox = getDocumentsDirectory();
    if (!sandbox) return 0;

#ifdef _WIN32
    char resolved[2048], resolved_sb[2048];
    if (!_fullpath(resolved, path, sizeof resolved))
        return 0;
    if (!_fullpath(resolved_sb, sandbox, sizeof resolved_sb))
        return 0;
    size_t slen = strlen(resolved_sb);
    return (_strnicmp(resolved, resolved_sb, slen) == 0 &&
            (resolved[slen] == '\\' || resolved[slen] == '/' ||
             resolved[slen] == '\0'));
#else
    /* Canonicalize the sandbox path to resolve symlinks */
    char *real_sandbox = realpath(sandbox, NULL);
    if (!real_sandbox) return 0;
    size_t slen = strlen(real_sandbox);

    /* Try realpath for existing paths */
    char *resolved = realpath(path, NULL);
    if (resolved) {
        int ok = (strncmp(resolved, real_sandbox, slen) == 0 &&
                  (resolved[slen] == '/' || resolved[slen] == '\0'));
        free(resolved);
        free(real_sandbox);
        return ok;
    }
    /* For new files, resolve the parent directory */
    char pathcopy[2048];
    snprintf(pathcopy, sizeof pathcopy, "%s", path);
    char *last_slash = strrchr(pathcopy, '/');
    if (last_slash && last_slash != pathcopy) {
        *last_slash = '\0';
        resolved = realpath(pathcopy, NULL);
        if (resolved) {
            int ok = (strncmp(resolved, real_sandbox, slen) == 0 &&
                      (resolved[slen] == '/' || resolved[slen] == '\0'));
            free(resolved);
            free(real_sandbox);
            return ok;
        }
    }
    free(real_sandbox);
    return 0;
#endif
}
#endif

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

    char *result = NULL;

    {
    char path_buf[2048], path_buf2[2048], mode_buf[16];
    char str_buf[MAX_FGETS_LINE];
    int handle;
    long lval;
    /* ---- fopen ---- */
    if (strcmp(func, "fopen") == 0) {
        if (form_get_str(body, "path", path_buf, sizeof path_buf) < 0) {
            free(body); return json_error("Missing 'path' parameter");
        }
        if (form_get_str(body, "mode", mode_buf, sizeof mode_buf) < 0)
            snprintf(mode_buf, sizeof mode_buf, "r");
        /* Whitelist valid fopen modes */
        {
            static const char *valid_modes[] = {
                "r","w","a","rb","wb","ab","r+","w+","a+",
                "rb+","wb+","ab+","r+b","w+b","a+b", NULL
            };
            int mode_ok = 0;
            for (int i = 0; valid_modes[i]; i++) {
                if (strcmp(mode_buf, valid_modes[i]) == 0) { mode_ok = 1; break; }
            }
            if (!mode_ok) { free(body); return json_error("Invalid file mode"); }
        }
#ifndef PERM_UNRESTRICTEDFILESYSTEMACCESS
        if (strstr(path_buf, "..") || !path_in_sandbox(path_buf)) {
            free(body); return json_error("Access denied: path outside app folder");
        }
#endif
        FILE *f = fopen(path_buf, mode_buf);
        if (!f) { result = json_error("File open failed"); free(body); return result; }
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
            result = json_error("Seek failed"); free(body); return result;
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
        return pos < 0 ? json_error("Tell failed") : json_ok_int(pos);
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
            result = json_error("Flush failed"); free(body); return result;
        }
        free(body); return json_ok_void();
    }

    /* ---- remove ---- */
    if (strcmp(func, "remove") == 0) {
        if (form_get_str(body, "path", path_buf, sizeof path_buf) < 0) {
            free(body); return json_error("Missing 'path' parameter");
        }
#ifndef PERM_UNRESTRICTEDFILESYSTEMACCESS
        if (strstr(path_buf, "..") || !path_in_sandbox(path_buf)) {
            free(body); return json_error("Access denied: path outside app folder");
        }
#endif
        if (remove(path_buf) != 0) {
            result = json_error("Remove failed"); free(body); return result;
        }
        free(body); return json_ok_void();
    }

    /* ---- rename ---- */
    if (strcmp(func, "rename") == 0) {
        if (form_get_str(body, "oldpath", path_buf, sizeof path_buf) < 0 ||
            form_get_str(body, "newpath", path_buf2, sizeof path_buf2) < 0) {
            free(body); return json_error("Missing 'oldpath' or 'newpath' parameter");
        }
#ifndef PERM_UNRESTRICTEDFILESYSTEMACCESS
        if (strstr(path_buf, "..") || strstr(path_buf2, "..") ||
            !path_in_sandbox(path_buf) || !path_in_sandbox(path_buf2)) {
            free(body); return json_error("Access denied: path outside app folder");
        }
#endif
        if (rename(path_buf, path_buf2) != 0) {
            result = json_error("Rename failed"); free(body); return result;
        }
        free(body); return json_ok_void();
    }
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
        const char *dir = getDocumentsDirectory();
        free(body);
        return dir ? json_ok_str(dir) : json_ok_null();
    }

    /* ---- startRecording (Linux GStreamer) ---- */
#if defined(__linux__) && !defined(__ANDROID__)
    if (strcmp(func, "startRecording") == 0) {
        extern char *gst_start_recording(const char *path, int has_video, int has_audio);
        char rec_path[2048], rec_video[8], rec_audio[8];
        if (form_get_str(body, "path", rec_path, sizeof rec_path) < 0) {
            free(body); return json_error("path required");
        }
#ifndef PERM_UNRESTRICTEDFILESYSTEMACCESS
        if (strstr(rec_path, "..") || !path_in_sandbox(rec_path)) {
            free(body); return json_error("Access denied: path outside app folder");
        }
#endif
        if (form_get_str(body, "video", rec_video, sizeof rec_video) < 0)
            rec_video[0] = '0', rec_video[1] = '\0';
        if (form_get_str(body, "audio", rec_audio, sizeof rec_audio) < 0)
            rec_audio[0] = '0', rec_audio[1] = '\0';
        int has_video = strcmp(rec_video, "1") == 0;
        int has_audio = strcmp(rec_audio, "1") == 0;
        if (!has_video && !has_audio) { free(body); return json_error("video or audio required"); }
        char *err = gst_start_recording(rec_path, has_video, has_audio);
        free(body);
        if (err) { char *r = json_error(err); free(err); return r; }
        return json_ok_str("recording");
    }

    if (strcmp(func, "stopRecording") == 0) {
        extern char *gst_stop_recording(void);
        char *err = gst_stop_recording();
        free(body);
        if (err) { char *r = json_error(err); free(err); return r; }
        return json_ok_str("stopped");
    }

    if (strcmp(func, "hasNativeRecording") == 0) {
        free(body);
        return json_ok_str("true");
    }
#endif

    /* ---- closeAllFileHandles ---- */
    if (strcmp(func, "closeAllFileHandles") == 0) {
        int closed = fh_close_all();
        free(body);
        return json_ok_int(closed);
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

    /* Only GET, HEAD, POST, and OPTIONS are supported */
    int is_post = (strcasecmp(method, "POST") == 0);
    int is_options = (strcasecmp(method, "OPTIONS") == 0);
    if (strcasecmp(method, "GET") != 0 && strcasecmp(method, "HEAD") != 0
        && !is_post && !is_options) {
        send_text(fd, 405, "Method Not Allowed",
                  "Method not supported\n");
        free(hdr);
        return;
    }

    /* ---- CORS preflight for debug endpoints ---- */
#ifdef PERM_REMOTEDEBUGGING
    if (is_options && (strcmp(path, "/__passiflora/debug") == 0
                       || strcmp(path, "/__passiflora/debug_result") == 0)) {
        const char *resp =
            "HTTP/1.1 204 No Content\r\n"
            "Access-Control-Allow-Origin: *\r\n"
            "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            "Access-Control-Allow-Headers: Content-Type\r\n"
            "Access-Control-Max-Age: 86400\r\n"
            "Content-Length: 0\r\n"
            "Connection: close\r\n"
            "\r\n";
        send_all(fd, resp, strlen(resp));
        free(hdr);
        return;
    }
#endif /* PERM_REMOTEDEBUGGING */

    /* Reject OPTIONS on all other paths */
    if (is_options) {
        send_text(fd, 405, "Method Not Allowed", "OPTIONS not supported here\n");
        free(hdr);
        return;
    }

#ifdef PERM_REMOTEDEBUGGING
    /* ---- Internal API: debug — relay POST body to webview ---- */
    if (strcmp(path, "/__passiflora/debug") == 0) {
        if (!is_post) {
            send_text(fd, 405, "Method Not Allowed", "POST required\n");
            free(hdr);
            return;
        }
        /* Find Content-Length */
        size_t content_length = 0;
        {
            const char *cl = header_end; /* scan headers */
            for (const char *p = hdr; p < header_end; ) {
                (void)cl;
                if (strncasecmp(p, "Content-Length:", 15) == 0) {
                    content_length = (size_t)strtoul(p + 15, NULL, 10);
                    break;
                }
                const char *nl = strstr(p, "\r\n");
                if (!nl) break;
                p = nl + 2;
            }
        }
        if (content_length == 0 || content_length > MAX_DEBUG_BODY) {
            send_text(fd, 400, "Bad Request", "Invalid Content-Length\n");
            free(hdr);
            return;
        }
        /* Read the POST body — some may already be in hdr past header_end */
        char *body = malloc(content_length + 1);
        if (!body) { free(hdr); return; }
        size_t body_already = used - (size_t)(header_end + 4 - hdr);
        if (body_already > content_length) body_already = content_length;
        if (body_already > 0)
            memcpy(body, header_end + 4, body_already);
        size_t body_read = body_already;
        while (body_read < content_length) {
            ssize_t r = sock_read(fd, body + body_read,
                                  content_length - body_read);
            if (r <= 0) { free(body); free(hdr); return; }
            body_read += r;
        }
        body[content_length] = '\0';

        /* JSON-escape the body for safe embedding in JS string */
        size_t esc_cap = content_length * 2 + 1;
        char *escaped = malloc(esc_cap);
        if (!escaped) { free(body); free(hdr); return; }
        size_t j = 0;
        for (size_t i = 0; i < content_length && j < esc_cap - 2; i++) {
            unsigned char ch = (unsigned char)body[i];
            if (ch == '\\')     { escaped[j++] = '\\'; escaped[j++] = '\\'; }
            else if (ch == '\'') { escaped[j++] = '\\'; escaped[j++] = '\''; }
            else if (ch == '\n') { escaped[j++] = '\\'; escaped[j++] = 'n'; }
            else if (ch == '\r') { escaped[j++] = '\\'; escaped[j++] = 'r'; }
            else if (ch == '\t') { escaped[j++] = '\\'; escaped[j++] = 't'; }
            else if (ch < 0x20)  { /* skip control chars */ }
            else                 { escaped[j++] = (char)ch; }
        }
        escaped[j] = '\0';
        free(body);

        /* Build JS call: PassifloraIO._debugExec('...escaped...') */
        size_t js_len = j + 64;
        char *js = malloc(js_len);
        if (!js) { free(escaped); free(hdr); return; }
        snprintf(js, js_len, "PassifloraIO._debugExec('%s')", escaped);
        free(escaped);

        passiflora_eval_js(js);
        free(js);

        /* Send CORS-friendly JSON response */
        const char *resp_hdrs =
            "HTTP/1.1 200 OK\r\n"
            "Content-Type: application/json; charset=utf-8\r\n"
            "Access-Control-Allow-Origin: *\r\n"
            "Access-Control-Allow-Methods: POST, OPTIONS\r\n"
            "Access-Control-Allow-Headers: Content-Type\r\n"
            "Connection: close\r\n";
        const char *resp_body = "{\"ok\":true}\n";
        char resp[512];
        int rlen = snprintf(resp, sizeof resp,
            "%sContent-Length: %zu\r\n\r\n%s",
            resp_hdrs, strlen(resp_body), resp_body);
        if (rlen > 0) send_all(fd, resp, (size_t)rlen);
        free(hdr);
        return;
    }

    /* ---- Internal API: debug_result — webview stores result, debugger retrieves ---- */
    if (strcmp(path, "/__passiflora/debug_result") == 0) {
        int is_get = (strcasecmp(method, "GET") == 0);
        const char *cors =
            "Access-Control-Allow-Origin: *\r\n"
            "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            "Access-Control-Allow-Headers: Content-Type\r\n";
        if (is_post) {
            /* Webview POSTs the execution result */
            size_t cl2 = 0;
            for (const char *p = hdr; p < header_end; ) {
                if (strncasecmp(p, "Content-Length:", 15) == 0) {
                    cl2 = (size_t)strtoul(p + 15, NULL, 10);
                    break;
                }
                const char *nl = strstr(p, "\r\n");
                if (!nl) break;
                p = nl + 2;
            }
            if (cl2 == 0 || cl2 > MAX_DEBUG_BODY) {
                send_text(fd, 400, "Bad Request", "Invalid Content-Length\n");
                free(hdr); return;
            }
            char *body2 = malloc(cl2 + 1);
            if (!body2) { free(hdr); return; }
            size_t ba2 = used - (size_t)(header_end + 4 - hdr);
            if (ba2 > cl2) ba2 = cl2;
            if (ba2 > 0) memcpy(body2, header_end + 4, ba2);
            size_t br2 = ba2;
            while (br2 < cl2) {
                ssize_t r = sock_read(fd, body2 + br2, cl2 - br2);
                if (r <= 0) { free(body2); free(hdr); return; }
                br2 += r;
            }
            body2[cl2] = '\0';
            pthread_mutex_lock(&debug_result_lock);
            /* Reject if a result is already pending (not yet retrieved) */
            if (debug_result_buf) {
                pthread_mutex_unlock(&debug_result_lock);
                free(body2);
                send_text(fd, 429, "Too Many Requests",
                          "Previous result not yet retrieved\n");
                free(hdr); return;
            }
            debug_result_buf = body2;
            pthread_mutex_unlock(&debug_result_lock);
            char resp[512];
            const char *rb = "{\"ok\":true}\n";
            int rlen = snprintf(resp, sizeof resp,
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n%s"
                "Connection: close\r\nContent-Length: %zu\r\n\r\n%s",
                cors, strlen(rb), rb);
            if (rlen > 0) send_all(fd, resp, (size_t)rlen);
        } else if (is_get) {
            /* Debugger polls for result */
            pthread_mutex_lock(&debug_result_lock);
            char *result = debug_result_buf;
            debug_result_buf = NULL;
            pthread_mutex_unlock(&debug_result_lock);
            if (result) {
                char resp[512];
                int rlen = snprintf(resp, sizeof resp,
                    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n%s"
                    "Connection: close\r\nContent-Length: %zu\r\n\r\n",
                    cors, strlen(result));
                if (rlen > 0) {
                    send_all(fd, resp, (size_t)rlen);
                    send_all(fd, result, strlen(result));
                }
                free(result);
            } else {
                char resp[256];
                int rlen = snprintf(resp, sizeof resp,
                    "HTTP/1.1 204 No Content\r\n%s"
                    "Connection: close\r\n\r\n", cors);
                if (rlen > 0) send_all(fd, resp, (size_t)rlen);
            }
        } else {
            send_text(fd, 405, "Method Not Allowed", "GET or POST required\n");
        }
        free(hdr);
        return;
    }

    /* GET on /__passiflora/debug — not allowed */
    if (strcmp(path, "/__passiflora/debug") == 0
        && strcasecmp(method, "GET") == 0) {
        send_text(fd, 405, "Method Not Allowed", "POST required\n");
        free(hdr);
        return;
    }
#endif /* PERM_REMOTEDEBUGGING */

    /* POST is only valid for /__passiflora/debug endpoints (handled above) */
    if (is_post) {
        send_text(fd, 405, "Method Not Allowed",
                  "POST not supported on this path\n");
        free(hdr);
        return;
    }

#ifdef PERM_REMOTEDEBUGGING
    /* ---- Internal API: embedded debugger page ---- */
    if (strcmp(path, "/debug") == 0 || strcmp(path, "/debug/") == 0) {
        static const char debugger_html[] =
            "<!DOCTYPE html>\n"
            "<html lang=\"en\"><head><meta charset=\"UTF-8\">\n"
            "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n"
            "<title>Passiflora Debugger</title>\n"
            "<style>\n"
            "body{font-family:system-ui,sans-serif;max-width:700px;margin:2em auto;padding:0 1em}\n"
            "label{display:block;margin-top:1em;font-weight:bold}\n"
            "input,textarea{width:100%;box-sizing:border-box;font:14px monospace;padding:6px}\n"
            "textarea{min-height:120px}\n"
            "button{margin-top:1em;padding:8px 20px;font-size:14px;cursor:pointer}\n"
            "#status{margin-top:1em;padding:10px;background:#f0f0f0;border-radius:4px;"
            "font:monospace;white-space:pre-wrap;min-height:2em}\n"
            ".error{color:#c00}.ok{color:#060}\n"
            "</style></head><body>\n"
            "<h1>Passiflora Debugger</h1>\n"
            "<p>Enter the passphrase and JavaScript to execute on this device.</p>\n"
            "<label for=\"key\">Passphrase</label>\n"
            "<input type=\"password\" id=\"key\" placeholder=\"Enter the passphrase you set in the app\">\n"
            "<label for=\"code\">JavaScript</label>\n"
            "<textarea id=\"code\" placeholder=\"document.title\"></textarea>\n"
            "<button onclick=\"sendDebug()\">Execute</button>\n"
            "<div id=\"status\"></div>\n"
            "<script>\n"
            "var _nonce=0;\n"
            "function s2b(s){var b=[];for(var i=0;i<s.length;i++){var c=s.charCodeAt(i);\n"
            "  if(c<128)b.push(c);else if(c<2048){b.push(192|(c>>6),128|(c&63));}\n"
            "  else{b.push(224|(c>>12),128|((c>>6)&63),128|(c&63));}}return b;}\n"
            "function sha256(b){\n"
            "  var K=[0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,\n"
            "    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,\n"
            "    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,\n"
            "    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,\n"
            "    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,\n"
            "    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,\n"
            "    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,\n"
            "    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];\n"
            "  function rr(x,n){return(x>>>n)|(x<<(32-n));}\n"
            "  b=b.slice();var bl=b.length*8;b.push(128);\n"
            "  while(b.length%64!==56)b.push(0);\n"
            "  for(var s=56;s>=0;s-=8)b.push((bl/Math.pow(2,s))&255);\n"
            "  var H=[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];\n"
            "  for(var o=0;o<b.length;o+=64){var W=[];\n"
            "    for(var t=0;t<16;t++)W[t]=(b[o+t*4]<<24)|(b[o+t*4+1]<<16)|(b[o+t*4+2]<<8)|b[o+t*4+3];\n"
            "    for(var t=16;t<64;t++){var s0=rr(W[t-15],7)^rr(W[t-15],18)^(W[t-15]>>>3);\n"
            "      var s1=rr(W[t-2],17)^rr(W[t-2],19)^(W[t-2]>>>10);W[t]=(W[t-16]+s0+W[t-7]+s1)|0;}\n"
            "    var a=H[0],B=H[1],c=H[2],d=H[3],e=H[4],f=H[5],g=H[6],h=H[7];\n"
            "    for(var t=0;t<64;t++){var S1=rr(e,6)^rr(e,11)^rr(e,25),ch=(e&f)^(~e&g),t1=(h+S1+ch+K[t]+W[t])|0;\n"
            "      var S0=rr(a,2)^rr(a,13)^rr(a,22),mj=(a&B)^(a&c)^(B&c),t2=(S0+mj)|0;\n"
            "      h=g;g=f;f=e;e=(d+t1)|0;d=c;c=B;B=a;a=(t1+t2)|0;}\n"
            "    H[0]=(H[0]+a)|0;H[1]=(H[1]+B)|0;H[2]=(H[2]+c)|0;H[3]=(H[3]+d)|0;\n"
            "    H[4]=(H[4]+e)|0;H[5]=(H[5]+f)|0;H[6]=(H[6]+g)|0;H[7]=(H[7]+h)|0;}\n"
            "  var out=[];for(var i=0;i<8;i++){var v=H[i]>>>0;out.push((v>>24)&255,(v>>16)&255,(v>>8)&255,v&255);}\n"
            "  return out;}\n"
            "function hmac(key,msg){\n"
            "  var kb=s2b(key);if(kb.length>64)kb=sha256(kb);\n"
            "  while(kb.length<64)kb.push(0);\n"
            "  var ip=[],op=[];for(var i=0;i<64;i++){ip.push(kb[i]^0x36);op.push(kb[i]^0x5c);}\n"
            "  var inner=sha256(ip.concat(s2b(msg)));\n"
            "  var outer=sha256(op.concat(inner));\n"
            "  var hex='';for(var i=0;i<outer.length;i++)hex+=('0'+outer[i].toString(16)).slice(-2);\n"
            "  return hex;}\n"
            "function sendDebug(){\n"
            "  var s=document.getElementById('status'),k=document.getElementById('key').value,\n"
            "      c=document.getElementById('code').value;\n"
            "  if(!k||!c){s.innerHTML='<span class=\"error\">Passphrase and code required.</span>';return;}\n"
            "  _nonce=Date.now()*1000+Math.floor(Math.random()*1000);\n"
            "  var h=hmac(k,_nonce+':'+c);\n"
            "  s.textContent='Sending...';\n"
            "  fetch('/__passiflora/debug',{method:'POST',\n"
            "    headers:{'Content-Type':'application/json'},\n"
            "    body:JSON.stringify({javascript:c,signature:h,nonce:_nonce})})\n"
            "  .then(function(r){\n"
            "    if(r.ok){\n"
            "      s.innerHTML='<span class=\"ok\">Sent — waiting for result...</span>';\n"
            "      var att=0,mx=20,iv=setInterval(function(){\n"
            "        att++;fetch('/__passiflora/debug_result').then(function(rr){\n"
            "          if(rr.status===200){clearInterval(iv);rr.json().then(function(j){var p=[];\n"
            "            if(j.output)p.push(j.output);if(j.error)p.push('ERROR: '+j.error);\n"
            "            s.innerHTML='<span class=\"ok\">Result:</span>\\n'+esc(p.join('\\n'));});}\n"
            "          else if(att>=mx){clearInterval(iv);\n"
            "            s.innerHTML='<span class=\"ok\">Sent OK</span>\\n(no result within timeout)';}\n"
            "        }).catch(function(e){if(att>=mx){clearInterval(iv);\n"
            "          s.innerHTML='<span class=\"ok\">Sent OK</span>\\n('+esc(e.message)+')';}});\n"
            "      },250);\n"
            "    }else{r.text().then(function(b){\n"
            "      s.innerHTML='<span class=\"error\">HTTP '+r.status+'</span>\\n'+esc(b);});}\n"
            "  }).catch(function(e){s.innerHTML='<span class=\"error\">Error: '+esc(e.message)+'</span>';});\n"
            "}\n"
            "function esc(t){var d=document.createElement('div');d.textContent=t;return d.innerHTML;}\n"
            "</script></body></html>\n";
        send_response(fd, 200, "OK", "text/html; charset=utf-8",
                      (const unsigned char *)debugger_html,
                      strlen(debugger_html));
        free(hdr);
        return;
    }
#endif /* PERM_REMOTEDEBUGGING */

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
#ifdef PERM_REMOTEDEBUGGING
        .sin_addr.s_addr = htonl(INADDR_ANY),
#else
        .sin_addr.s_addr = htonl(INADDR_LOOPBACK),
#endif
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

    g_server_port = port;

#ifdef PERM_REMOTEDEBUGGING
    LOGI("passiflora: listening on http://0.0.0.0:%d/\n", port);
#else
    LOGI("passiflora: listening on http://127.0.0.1:%d/\n", port);
#endif

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

/* App-private files directory, set from Java before startServer() */
const char *android_files_dir = NULL;

JNIEXPORT void JNICALL
Java_com_example_zipserve_MainActivity_nativeSetFilesDir(
    JNIEnv *env, jclass cls, jstring path)
{
    (void)cls;
    const char *p = (*env)->GetStringUTFChars(env, path, NULL);
    android_files_dir = strdup(p);
    (*env)->ReleaseStringUTFChars(env, path, p);
}

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
#ifdef PERM_REMOTEDEBUGGING
        .sin_addr.s_addr = htonl(INADDR_ANY),
#else
        .sin_addr.s_addr = htonl(INADDR_LOOPBACK),
#endif
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

    g_server_port = port;

#ifdef PERM_REMOTEDEBUGGING
    LOGI("passiflora: listening on http://0.0.0.0:%d/\n", port);
#else
    LOGI("passiflora: listening on http://127.0.0.1:%d/\n", port);
#endif

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
