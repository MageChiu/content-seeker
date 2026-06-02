/// YouTube 签名解密实现
/// 解析 player.js 中的签名函数并通过 QuickJS 执行

#include "youtube_cipher.h"
#include <regex>
#include <sstream>

namespace seeker {

std::string YouTubeCipher::url_decode(const std::string& encoded) {
    std::string result;
    result.reserve(encoded.size());
    for (size_t i = 0; i < encoded.size(); ++i) {
        if (encoded[i] == '%' && i + 2 < encoded.size()) {
            int hi = 0, lo = 0;
            char c1 = encoded[i + 1], c2 = encoded[i + 2];
            if (c1 >= '0' && c1 <= '9') hi = c1 - '0';
            else if (c1 >= 'a' && c1 <= 'f') hi = c1 - 'a' + 10;
            else if (c1 >= 'A' && c1 <= 'F') hi = c1 - 'A' + 10;
            if (c2 >= '0' && c2 <= '9') lo = c2 - '0';
            else if (c2 >= 'a' && c2 <= 'f') lo = c2 - 'a' + 10;
            else if (c2 >= 'A' && c2 <= 'F') lo = c2 - 'A' + 10;
            result += static_cast<char>((hi << 4) | lo);
            i += 2;
        } else if (encoded[i] == '+') {
            result += ' ';
        } else {
            result += encoded[i];
        }
    }
    return result;
}

bool YouTubeCipher::parse_cipher(const std::string& cipher,
                                  std::string& sig, std::string& sp, std::string& url) {
    // cipher 格式: s=xxx&sp=sig&url=xxx (URL encoded)
    std::istringstream ss(cipher);
    std::string pair;
    while (std::getline(ss, pair, '&')) {
        auto eq = pair.find('=');
        if (eq == std::string::npos) continue;
        std::string key = pair.substr(0, eq);
        std::string value = url_decode(pair.substr(eq + 1));
        if (key == "s") sig = value;
        else if (key == "sp") sp = value;
        else if (key == "url") url = value;
    }
    return !sig.empty() && !url.empty();
}

std::string YouTubeCipher::find_decrypt_func_name(const std::string& player_js) {
    // YouTube player.js 中签名函数的特征模式
    // 常见模式:
    //   a.set("alr","yes");a.set(b,encodeURIComponent(XX(c)));
    //   a.set(b,XX(c))   其中 XX 是解密函数名
    // 另一种: \b[cs]\s*&&\s*[adf]\.set\([^,]+\s*,\s*encodeURIComponent\(([a-zA-Z0-9$]+)\(
    static const std::regex patterns[] = {
        std::regex(R"(\b[cs]\s*&&\s*[adf]\.set\([^,]+\s*,\s*encodeURIComponent\(([a-zA-Z0-9$]+)\()"),
        std::regex(R"(\bm=([a-zA-Z0-9$]{2,})\(decodeURIComponent\(h\.s\)\))"),
        std::regex(R"(\bc\s*&&\s*d\.set\([^,]+\s*,\s*(?:encodeURIComponent\s*\()([a-zA-Z0-9$]+)\()"),
        std::regex(R"(\bc\s*&&\s*[a-z]\.set\([^,]+\s*,\s*([a-zA-Z0-9$]+)\()"),
        std::regex(R"(\bc\s*&&\s*[a-z]\.set\([^,]+\s*,\s*encodeURIComponent\(([a-zA-Z0-9$]+)\()"),
    };

    for (const auto& pattern : patterns) {
        std::smatch match;
        if (std::regex_search(player_js, match, pattern)) {
            return match[1].str();
        }
    }
    return "";
}

std::string YouTubeCipher::extract_decrypt_function(const std::string& player_js) {
    std::string func_name = find_decrypt_func_name(player_js);
    if (func_name.empty()) return "";

    cached_decrypt_func_name_ = func_name;

    // 提取函数定义: var XX=function(a){...};  或  function XX(a){...}
    // 模式 1: var funcName=function(a){a=a.split("");...;return a.join("")};
    std::string pattern1 = "var " + func_name + "=function(";
    std::string pattern2 = func_name + "=function(";
    std::string pattern3 = "function " + func_name + "(";

    size_t func_start = std::string::npos;
    for (const auto& pat : {pattern1, pattern2, pattern3}) {
        func_start = player_js.find(pat);
        if (func_start != std::string::npos) break;
    }
    if (func_start == std::string::npos) return "";

    // 找到函数体（匹配花括号）
    size_t brace_start = player_js.find('{', func_start);
    if (brace_start == std::string::npos) return "";

    int depth = 0;
    size_t func_end = brace_start;
    for (size_t i = brace_start; i < player_js.size(); ++i) {
        if (player_js[i] == '{') ++depth;
        else if (player_js[i] == '}') {
            --depth;
            if (depth == 0) { func_end = i; break; }
        }
    }

    std::string func_body = player_js.substr(func_start, func_end - func_start + 1);

    // 提取辅助对象（通常是包含 splice/reverse/swap 操作的对象）
    // 模式: 函数体内调用了某个对象的方法，如 XY.ab(a,3)
    std::regex helper_call(R"(([a-zA-Z0-9$]+)\.([a-zA-Z0-9$]+)\()");
    std::smatch helper_match;
    std::string helper_obj_name;
    std::string search_body = func_body;
    if (std::regex_search(search_body, helper_match, helper_call)) {
        helper_obj_name = helper_match[1].str();
    }

    std::string helper_code;
    if (!helper_obj_name.empty()) {
        // 提取辅助对象: var XX={ab:function(a){...}, cd:function(a,b){...}};
        std::string obj_pattern = "var " + helper_obj_name + "={";
        size_t obj_start = player_js.find(obj_pattern);
        if (obj_start != std::string::npos) {
            size_t obj_brace = player_js.find('{', obj_start + 4 + helper_obj_name.size());
            if (obj_brace != std::string::npos) {
                int obj_depth = 0;
                size_t obj_end = obj_brace;
                for (size_t i = obj_brace; i < player_js.size(); ++i) {
                    if (player_js[i] == '{') ++obj_depth;
                    else if (player_js[i] == '}') {
                        --obj_depth;
                        if (obj_depth == 0) { obj_end = i; break; }
                    }
                }
                helper_code = player_js.substr(obj_start, obj_end - obj_start + 1) + ";";
            }
        }
    }

    return helper_code + "\n" + func_body + ";";
}

bool YouTubeCipher::ensure_cipher_loaded(const std::string& player_url) {
    // 检查缓存
    if (cached_engine_ && cached_player_url_ == player_url) {
        return cached_engine_->is_valid();
    }

    // 下载 player.js
    auto resp = http_.get(player_url);
    if (!resp.ok() || resp.body.empty()) {
        return false;
    }

    // 提取解密函数
    std::string js_code = extract_decrypt_function(resp.body);
    if (js_code.empty()) {
        return false;
    }

    // 创建 JS 引擎并加载
    cached_engine_ = std::make_unique<JsEngine>();
    if (!cached_engine_->is_valid()) {
        cached_engine_.reset();
        return false;
    }

    if (!cached_engine_->exec(js_code)) {
        cached_engine_.reset();
        return false;
    }

    cached_player_url_ = player_url;
    return true;
}

std::string YouTubeCipher::decrypt_signature(const std::string& scrambled_sig,
                                              const std::string& player_url) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!ensure_cipher_loaded(player_url)) {
        return "";
    }

    return cached_engine_->call(cached_decrypt_func_name_, scrambled_sig);
}

std::string YouTubeCipher::decrypt(const std::string& signature_cipher,
                                    const std::string& player_url) {
    std::string sig, sp, url;
    if (!parse_cipher(signature_cipher, sig, sp, url)) {
        return "";
    }

    if (sp.empty()) sp = "sig";

    std::string decrypted = decrypt_signature(sig, player_url);
    if (decrypted.empty() || decrypted.find("ERROR:") == 0) {
        return "";
    }

    // 将解密后的签名追加到 URL
    char separator = (url.find('?') != std::string::npos) ? '&' : '?';
    return url + separator + sp + "=" + decrypted;
}

} // namespace seeker
