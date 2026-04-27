#include "wbi_sign.h"
#include "json_utils.h"
#include <algorithm>
#include <cstring>
#include <ctime>
#include <sstream>
#include <iomanip>
#include <cstdint>

namespace seeker {

// ============================================================
// MD5 Implementation (RFC 1321)
// ============================================================
namespace {

struct MD5Context {
    uint32_t state[4];
    uint64_t count;
    uint8_t buffer[64];
};

static const uint32_t S[64] = {
    7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,  7, 12, 17, 22,
    5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,  5,  9, 14, 20,
    4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,  4, 11, 16, 23,
    6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21,  6, 10, 15, 21
};

static const uint32_t K[64] = {
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
};

inline uint32_t left_rotate(uint32_t x, uint32_t c) {
    return (x << c) | (x >> (32 - c));
}

void md5_init(MD5Context& ctx) {
    ctx.state[0] = 0x67452301;
    ctx.state[1] = 0xefcdab89;
    ctx.state[2] = 0x98badcfe;
    ctx.state[3] = 0x10325476;
    ctx.count = 0;
    std::memset(ctx.buffer, 0, 64);
}

void md5_transform(MD5Context& ctx, const uint8_t block[64]) {
    uint32_t M[16];
    for (int i = 0; i < 16; ++i) {
        M[i] = static_cast<uint32_t>(block[i * 4])
             | (static_cast<uint32_t>(block[i * 4 + 1]) << 8)
             | (static_cast<uint32_t>(block[i * 4 + 2]) << 16)
             | (static_cast<uint32_t>(block[i * 4 + 3]) << 24);
    }

    uint32_t a = ctx.state[0];
    uint32_t b = ctx.state[1];
    uint32_t c = ctx.state[2];
    uint32_t d = ctx.state[3];

    for (int i = 0; i < 64; ++i) {
        uint32_t f, g;
        if (i < 16) {
            f = (b & c) | ((~b) & d);
            g = static_cast<uint32_t>(i);
        } else if (i < 32) {
            f = (d & b) | ((~d) & c);
            g = static_cast<uint32_t>((5 * i + 1) % 16);
        } else if (i < 48) {
            f = b ^ c ^ d;
            g = static_cast<uint32_t>((3 * i + 5) % 16);
        } else {
            f = c ^ (b | (~d));
            g = static_cast<uint32_t>((7 * i) % 16);
        }

        uint32_t temp = d;
        d = c;
        c = b;
        b = b + left_rotate(a + f + K[i] + M[g], S[i]);
        a = temp;
    }

    ctx.state[0] += a;
    ctx.state[1] += b;
    ctx.state[2] += c;
    ctx.state[3] += d;
}

void md5_update(MD5Context& ctx, const uint8_t* data, size_t len) {
    size_t index = static_cast<size_t>(ctx.count % 64);
    ctx.count += len;

    size_t i = 0;
    if (index) {
        size_t part_len = 64 - index;
        if (len >= part_len) {
            std::memcpy(ctx.buffer + index, data, part_len);
            md5_transform(ctx, ctx.buffer);
            i = part_len;
        } else {
            std::memcpy(ctx.buffer + index, data, len);
            return;
        }
    }

    for (; i + 64 <= len; i += 64) {
        md5_transform(ctx, data + i);
    }

    if (i < len) {
        std::memcpy(ctx.buffer, data + i, len - i);
    }
}

void md5_final(MD5Context& ctx, uint8_t digest[16]) {
    uint64_t bits = ctx.count * 8;
    size_t index = static_cast<size_t>(ctx.count % 64);

    // Padding
    uint8_t padding[64];
    std::memset(padding, 0, 64);
    padding[0] = 0x80;

    size_t pad_len = (index < 56) ? (56 - index) : (120 - index);
    md5_update(ctx, padding, pad_len);

    // Append length in bits as 64-bit little-endian
    uint8_t bits_buf[8];
    for (int i = 0; i < 8; ++i) {
        bits_buf[i] = static_cast<uint8_t>((bits >> (i * 8)) & 0xff);
    }
    md5_update(ctx, bits_buf, 8);

    // Output digest
    for (int i = 0; i < 4; ++i) {
        digest[i * 4]     = static_cast<uint8_t>(ctx.state[i] & 0xff);
        digest[i * 4 + 1] = static_cast<uint8_t>((ctx.state[i] >> 8) & 0xff);
        digest[i * 4 + 2] = static_cast<uint8_t>((ctx.state[i] >> 16) & 0xff);
        digest[i * 4 + 3] = static_cast<uint8_t>((ctx.state[i] >> 24) & 0xff);
    }
}

// mixin_key_enc_tab
static const int MIXIN_KEY_ENC_TAB[64] = {
    46, 47, 18,  2, 53,  8, 23, 32, 15, 50, 10, 31, 58,  3, 45, 35,
    27, 43,  5, 49, 33,  9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
    37, 48,  7, 16, 24, 55, 40, 61, 26, 17,  0,  1, 60, 51, 30,  4,
    22, 25, 54, 21, 56, 59,  6, 63, 57, 62, 11, 36, 20, 34, 44, 52
};

static const char HEX_CHARS[] = "0123456789abcdef";

// Characters that should not be URL-encoded (unreserved characters per RFC 3986)
bool is_unreserved(char c) {
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
           (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~';
}

} // anonymous namespace

// ============================================================
// WbiSigner implementation
// ============================================================

static const int64_t CACHE_DURATION_SEC = 30 * 60; // 30 minutes

WbiSigner::WbiSigner(HttpClient& http) : http_(http) {}

std::string WbiSigner::sign(const std::map<std::string, std::string>& params) {
    ensure_keys();

    // Add wts (current timestamp)
    int64_t wts = static_cast<int64_t>(std::time(nullptr));
    std::map<std::string, std::string> sorted_params = params;
    sorted_params["wts"] = std::to_string(wts);

    // Build query string (params are already sorted by std::map)
    std::string query;
    for (auto it = sorted_params.begin(); it != sorted_params.end(); ++it) {
        if (it != sorted_params.begin()) {
            query += '&';
        }
        query += url_encode(it->first) + '=' + url_encode(filter_value(it->second));
    }

    // Append mixin_key and compute MD5
    std::string to_hash = query + mixin_key_;
    std::string w_rid = md5(to_hash);

    // Append w_rid and wts to the query string
    query += "&w_rid=" + w_rid;

    return query;
}

void WbiSigner::refresh_keys() {
    mixin_key_ = fetch_mixin_key();
    keys_fetched_at_ = static_cast<int64_t>(std::time(nullptr));
}

void WbiSigner::ensure_keys() {
    int64_t now = static_cast<int64_t>(std::time(nullptr));
    if (mixin_key_.empty() || (now - keys_fetched_at_) > CACHE_DURATION_SEC) {
        refresh_keys();
    }
}

std::string WbiSigner::fetch_mixin_key() {
    std::map<std::string, std::string> headers;
    headers["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36";
    headers["Referer"] = "https://www.bilibili.com/";
    headers["Origin"] = "https://www.bilibili.com";

    HttpResponse resp = http_.get("https://api.bilibili.com/x/web-interface/nav", headers);
    if (!resp.ok()) {
        return "";
    }

    // Extract img_url and sub_url using json utilities
    std::string img_url = json::get_nested(resp.body, "data.wbi_img.img_url");
    std::string sub_url = json::get_nested(resp.body, "data.wbi_img.sub_url");

    if (img_url.empty() || sub_url.empty()) {
        return "";
    }

    // Extract filename without extension from URL path
    // e.g. "https://i0.hdslb.com/bfs/wbi/xxxx.png" -> "xxxx"
    auto extract_key = [](const std::string& url) -> std::string {
        size_t last_slash = url.rfind('/');
        if (last_slash == std::string::npos) return "";
        std::string filename = url.substr(last_slash + 1);
        size_t dot = filename.rfind('.');
        if (dot != std::string::npos) {
            filename = filename.substr(0, dot);
        }
        return filename;
    };

    std::string img_key = extract_key(img_url);
    std::string sub_key = extract_key(sub_url);
    std::string raw_key = img_key + sub_key;

    return generate_mixin_key(raw_key);
}

std::string WbiSigner::generate_mixin_key(const std::string& raw_key) {
    std::string result;
    result.reserve(32);
    for (int i = 0; i < 32; ++i) {
        int idx = MIXIN_KEY_ENC_TAB[i];
        if (idx < static_cast<int>(raw_key.size())) {
            result += raw_key[static_cast<size_t>(idx)];
        }
    }
    return result;
}

std::string WbiSigner::md5(const std::string& input) {
    MD5Context ctx;
    md5_init(ctx);
    md5_update(ctx, reinterpret_cast<const uint8_t*>(input.data()), input.size());

    uint8_t digest[16];
    md5_final(ctx, digest);

    std::string result;
    result.reserve(32);
    for (int i = 0; i < 16; ++i) {
        result += HEX_CHARS[(digest[i] >> 4) & 0x0f];
        result += HEX_CHARS[digest[i] & 0x0f];
    }
    return result;
}

std::string WbiSigner::url_encode(const std::string& value) {
    std::string result;
    result.reserve(value.size() * 3);
    for (unsigned char c : value) {
        if (is_unreserved(static_cast<char>(c))) {
            result += static_cast<char>(c);
        } else {
            result += '%';
            result += HEX_CHARS[(c >> 4) & 0x0f];
            result += HEX_CHARS[c & 0x0f];
        }
    }
    return result;
}

std::string WbiSigner::filter_value(const std::string& value) {
    std::string result;
    result.reserve(value.size());
    for (char c : value) {
        if (c != '!' && c != '\'' && c != '(' && c != ')' && c != '*') {
            result += c;
        }
    }
    return result;
}

} // namespace seeker
