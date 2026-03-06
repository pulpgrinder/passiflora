/*
 * zipzip.h — Pure-C ZIP filesystem and DEFLATE decompressor.
 *
 * Provides zip_find() and zip_find_size() for looking up files in a
 * ZIP archive stored as a byte array.  Supports compression methods
 * 0 (stored) and 8 (deflate).  The deflate decompressor is a
 * self-contained implementation of RFC 1951 with no external
 * dependencies.
 *
 * This file is #included by passiflora.c — all functions are static.
 */

#ifndef MAX_DECOMP_SIZE
#define MAX_DECOMP_SIZE (64 * 1024 * 1024)  /* 64 MB per file */
#endif

/* ------------------------------------------------------------------ */
/*  Little-endian readers                                              */
/* ------------------------------------------------------------------ */
static uint16_t read_le16(const unsigned char *p)
{
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t read_le32(const unsigned char *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

/* ------------------------------------------------------------------ */
/*  Pure-C DEFLATE decompressor (RFC 1951)                             */
/*                                                                     */
/*  Supports block types 0 (stored), 1 (fixed Huffman), and           */
/*  2 (dynamic Huffman).  No external dependencies.                    */
/* ------------------------------------------------------------------ */

#define DEFLATE_MAX_BITS   15
#define DEFLATE_MAX_LITS  288
#define DEFLATE_MAX_DISTS  32
#define DEFLATE_MAX_CODES 319

typedef struct {
    const unsigned char *src;
    size_t src_len;
    size_t byte_pos;
    unsigned int bit_buf;
    int bit_cnt;
} deflate_bits_t;

static void deflate_bits_init(deflate_bits_t *b,
                              const unsigned char *src, size_t len)
{
    b->src      = src;
    b->src_len  = len;
    b->byte_pos = 0;
    b->bit_buf  = 0;
    b->bit_cnt  = 0;
}

static unsigned int deflate_bits_read(deflate_bits_t *b, int n)
{
    while (b->bit_cnt < n) {
        if (b->byte_pos >= b->src_len) return 0;
        b->bit_buf |= (unsigned int)b->src[b->byte_pos++] << b->bit_cnt;
        b->bit_cnt += 8;
    }
    unsigned int val = b->bit_buf & ((1u << n) - 1);
    b->bit_buf >>= n;
    b->bit_cnt -= n;
    return val;
}

static void deflate_bits_align(deflate_bits_t *b)
{
    b->bit_buf = 0;
    b->bit_cnt = 0;
}

typedef struct {
    uint16_t counts[DEFLATE_MAX_BITS + 1];
    uint16_t symbols[DEFLATE_MAX_CODES];
} deflate_huff_t;

static int deflate_build_huff(deflate_huff_t *h,
                              const uint16_t *lengths, int num)
{
    int i;
    memset(h->counts, 0, sizeof h->counts);
    for (i = 0; i < num; i++)
        h->counts[lengths[i]]++;

    uint16_t offsets[DEFLATE_MAX_BITS + 1];
    offsets[0] = 0;
    for (i = 1; i <= DEFLATE_MAX_BITS; i++)
        offsets[i] = offsets[i - 1] + h->counts[i - 1];

    for (i = 0; i < num; i++)
        if (lengths[i])
            h->symbols[offsets[lengths[i]]++] = (uint16_t)i;
    return 0;
}

static int deflate_decode_sym(deflate_bits_t *b, const deflate_huff_t *h)
{
    int code = 0, first = 0, index = h->counts[0];
    for (int len = 1; len <= DEFLATE_MAX_BITS; len++) {
        code |= (int)deflate_bits_read(b, 1);
        int count = h->counts[len];
        if (code < first + count)
            return h->symbols[index + (code - first)];
        index += count;
        first = (first + count) << 1;
        code <<= 1;
    }
    return -1;
}

static void deflate_build_fixed(deflate_huff_t *lit, deflate_huff_t *dist)
{
    uint16_t lengths[DEFLATE_MAX_LITS];
    int i;
    for (i =   0; i <= 143; i++) lengths[i] = 8;
    for (i = 144; i <= 255; i++) lengths[i] = 9;
    for (i = 256; i <= 279; i++) lengths[i] = 7;
    for (i = 280; i <= 287; i++) lengths[i] = 8;
    deflate_build_huff(lit, lengths, 288);

    for (i = 0; i < 32; i++) lengths[i] = 5;
    deflate_build_huff(dist, lengths, 32);
}

static const uint16_t deflate_len_base[29] = {
    3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,
    35,43,51,59,67,83,99,115,131,163,195,227,258
};
static const uint16_t deflate_len_extra[29] = {
    0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,
    3,3,3,3,4,4,4,4,5,5,5,5,0
};

static const uint16_t deflate_dist_base[30] = {
    1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,
    257,385,513,769,1025,1537,2049,3073,4097,6145,
    8193,12289,16385,24577
};
static const uint16_t deflate_dist_extra[30] = {
    0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,
    7,7,8,8,9,9,10,10,11,11,12,12,13,13
};

static const int deflate_cl_order[19] = {
    16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15
};

static size_t deflate_inflate(const unsigned char *src, size_t src_len,
                              unsigned char *out_buf, size_t out_cap)
{
    deflate_bits_t bits;
    deflate_bits_init(&bits, src, src_len);

    size_t out_pos = 0;
    int bfinal;

    do {
        bfinal = (int)deflate_bits_read(&bits, 1);
        int btype = (int)deflate_bits_read(&bits, 2);

        if (btype == 0) {
            deflate_bits_align(&bits);
            if (bits.byte_pos + 4 > bits.src_len) return (size_t)-1;
            uint16_t len  = bits.src[bits.byte_pos] |
                            ((uint16_t)bits.src[bits.byte_pos + 1] << 8);
            uint16_t nlen = bits.src[bits.byte_pos + 2] |
                            ((uint16_t)bits.src[bits.byte_pos + 3] << 8);
            bits.byte_pos += 4;
            if ((uint16_t)~nlen != len) return (size_t)-1;
            if (bits.byte_pos + len > bits.src_len) return (size_t)-1;
            if (out_pos + len > out_cap) return (size_t)-1;
            memcpy(out_buf + out_pos, bits.src + bits.byte_pos, len);
            bits.byte_pos += len;
            out_pos += len;
        } else if (btype == 1 || btype == 2) {
            deflate_huff_t lit_huff, dist_huff;

            if (btype == 1) {
                deflate_build_fixed(&lit_huff, &dist_huff);
            } else {
                int hlit  = (int)deflate_bits_read(&bits, 5) + 257;
                int hdist = (int)deflate_bits_read(&bits, 5) + 1;
                int hclen = (int)deflate_bits_read(&bits, 4) + 4;

                uint16_t cl_lengths[19];
                memset(cl_lengths, 0, sizeof cl_lengths);
                for (int i = 0; i < hclen; i++)
                    cl_lengths[deflate_cl_order[i]] =
                        (uint16_t)deflate_bits_read(&bits, 3);

                deflate_huff_t cl_huff;
                deflate_build_huff(&cl_huff, cl_lengths, 19);

                uint16_t all_lengths[DEFLATE_MAX_CODES];
                int total = hlit + hdist;
                int idx = 0;
                while (idx < total) {
                    int sym = deflate_decode_sym(&bits, &cl_huff);
                    if (sym < 0) return (size_t)-1;
                    if (sym < 16) {
                        all_lengths[idx++] = (uint16_t)sym;
                    } else if (sym == 16) {
                        if (idx == 0) return (size_t)-1;
                        int rep = (int)deflate_bits_read(&bits, 2) + 3;
                        uint16_t prev = all_lengths[idx - 1];
                        while (rep-- > 0 && idx < total)
                            all_lengths[idx++] = prev;
                    } else if (sym == 17) {
                        int rep = (int)deflate_bits_read(&bits, 3) + 3;
                        while (rep-- > 0 && idx < total)
                            all_lengths[idx++] = 0;
                    } else if (sym == 18) {
                        int rep = (int)deflate_bits_read(&bits, 7) + 11;
                        while (rep-- > 0 && idx < total)
                            all_lengths[idx++] = 0;
                    } else {
                        return (size_t)-1;
                    }
                }

                deflate_build_huff(&lit_huff, all_lengths, hlit);
                deflate_build_huff(&dist_huff, all_lengths + hlit, hdist);
            }

            for (;;) {
                int sym = deflate_decode_sym(&bits, &lit_huff);
                if (sym < 0) return (size_t)-1;
                if (sym < 256) {
                    if (out_pos >= out_cap) return (size_t)-1;
                    out_buf[out_pos++] = (unsigned char)sym;
                } else if (sym == 256) {
                    break;
                } else {
                    int li = sym - 257;
                    if (li < 0 || li >= 29) return (size_t)-1;
                    unsigned int length = deflate_len_base[li] +
                        deflate_bits_read(&bits, deflate_len_extra[li]);

                    int di = deflate_decode_sym(&bits, &dist_huff);
                    if (di < 0 || di >= 30) return (size_t)-1;
                    unsigned int distance = deflate_dist_base[di] +
                        deflate_bits_read(&bits, deflate_dist_extra[di]);

                    if (distance > out_pos) return (size_t)-1;
                    if (out_pos + length > out_cap) return (size_t)-1;

                    size_t from = out_pos - distance;
                    for (unsigned int j = 0; j < length; j++)
                        out_buf[out_pos++] = out_buf[from + j];
                }
            }
        } else {
            return (size_t)-1;
        }
    } while (!bfinal);

    return out_pos;
}

/* ------------------------------------------------------------------ */
/*  Slash-insensitive path compare: treats '\' and '/' as equal.       */
/*  Handles zips created by PowerShell Compress-Archive (backslashes). */
/* ------------------------------------------------------------------ */
static int zip_path_eq(const unsigned char *a, const char *b, size_t len)
{
    for (size_t i = 0; i < len; i++) {
        char ca = (char)a[i], cb = b[i];
        if (ca == '\\') ca = '/';
        if (cb == '\\') cb = '/';
        if (ca != cb) return 0;
    }
    return 1;
}

/* ------------------------------------------------------------------ */
/*  ZIP filesystem lookup                                              */
/*                                                                     */
/*  Walks the local file headers in a ZIP byte array looking for a     */
/*  matching filename.  On match, decompresses (or copies) the data   */
/*  and returns a malloc'd buffer.  Returns NULL if not found.         */
/* ------------------------------------------------------------------ */
static unsigned char *zip_find(const unsigned char *zip, size_t zip_len,
                               const char *filename,
                               size_t *out_len)
{
    size_t pos = 0;
    size_t fname_len = strlen(filename);

    while (pos + 30 <= zip_len) {
        uint32_t sig = read_le32(zip + pos);
        if (sig != 0x04034b50)
            break;

        uint16_t compression = read_le16(zip + pos + 8);
        uint32_t comp_size   = read_le32(zip + pos + 18);
        uint32_t uncomp_size = read_le32(zip + pos + 22);
        uint16_t name_len    = read_le16(zip + pos + 26);
        uint16_t extra_len   = read_le16(zip + pos + 28);

        pos += 30;

        if (pos + name_len + extra_len > zip_len)
            return NULL;

        /* Check if this entry matches the requested filename */
        int match = (name_len == fname_len &&
                     zip_path_eq(zip + pos, filename, fname_len));

        pos += name_len + extra_len;

        if (pos + comp_size > zip_len)
            return NULL;

        if (match) {
            if (compression == 0) {
                /* Stored */
                if (comp_size > MAX_DECOMP_SIZE)
                    return NULL;
                unsigned char *data = malloc(comp_size ? comp_size : 1);
                if (!data) return NULL;
                if (comp_size) memcpy(data, zip + pos, comp_size);
                *out_len = comp_size;
                return data;
            } else if (compression == 8) {
                /* Deflate */
                if (uncomp_size > MAX_DECOMP_SIZE)
                    return NULL;
                unsigned char *data = malloc(uncomp_size ? uncomp_size : 1);
                if (!data) return NULL;
                if (uncomp_size == 0) {
                    *out_len = 0;
                    return data;
                }
                size_t got = deflate_inflate(zip + pos, comp_size,
                                             data, uncomp_size);
                if (got == (size_t)-1) {
                    free(data);
                    return NULL;
                }
                *out_len = got;
                return data;
            }
            /* Unsupported compression — treat as not found */
            return NULL;
        }

        pos += comp_size;
    }

    return NULL;  /* not found */
}

/* ------------------------------------------------------------------ */
/*  ZIP size-only lookup (for HEAD requests — no decompression)        */
/* ------------------------------------------------------------------ */
static size_t zip_find_size(const unsigned char *zip, size_t zip_len,
                            const char *filename)
{
    size_t pos = 0;
    size_t fname_len = strlen(filename);

    while (pos + 30 <= zip_len) {
        uint32_t sig = read_le32(zip + pos);
        if (sig != 0x04034b50)
            break;

        uint16_t compression = read_le16(zip + pos + 8);
        uint32_t comp_size   = read_le32(zip + pos + 18);
        uint32_t uncomp_size = read_le32(zip + pos + 22);
        uint16_t name_len    = read_le16(zip + pos + 26);
        uint16_t extra_len   = read_le16(zip + pos + 28);

        pos += 30;

        if (pos + name_len + extra_len > zip_len)
            return (size_t)-1;

        int match = (name_len == fname_len &&
                     zip_path_eq(zip + pos, filename, fname_len));

        pos += name_len + extra_len;

        if (pos + comp_size > zip_len)
            return (size_t)-1;

        if (match) {
            if (compression == 0) return comp_size;
            if (compression == 8) return uncomp_size;
            return (size_t)-1;
        }

        pos += comp_size;
    }

    return (size_t)-1;  /* not found */
}
