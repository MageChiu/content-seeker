#ifndef SEEKER_YOUTUBE_CIPHER_H
#define SEEKER_YOUTUBE_CIPHER_H

#include <string>
#include <mutex>
#include "../../utils/js_engine.h"
#include "../../utils/http_client.h"

namespace seeker {

/// YouTube 签名解密器
/// 下载 YouTube player.js，提取解密函数，通过 QuickJS 执行解密
class YouTubeCipher {
public:
    YouTubeCipher() = default;

    /// 解密 signatureCipher 字符串，返回可播放的 URL
    /// @param signature_cipher URL 编码的 cipher 字符串 (s=...&sp=...&url=...)
    /// @param player_url player.js 的完整 URL
    /// @return 解密后的完整流 URL，失败返回空字符串
    std::string decrypt(const std::string& signature_cipher, const std::string& player_url);

    /// 解密单个签名
    /// @param scrambled_sig 加扰后的签名
    /// @param player_url player.js URL
    /// @return 解密后的签名
    std::string decrypt_signature(const std::string& scrambled_sig, const std::string& player_url);

private:
    HttpClient http_;
    std::mutex mutex_;

    // 缓存：player_url -> 已加载的解密函数
    std::string cached_player_url_;
    std::string cached_decrypt_func_name_;
    std::unique_ptr<JsEngine> cached_engine_;

    /// 确保指定 player 的解密函数已加载到 JS 引擎中
    bool ensure_cipher_loaded(const std::string& player_url);

    /// 从 player.js 源码中提取解密函数代码
    std::string extract_decrypt_function(const std::string& player_js);

    /// 提取解密函数名
    std::string find_decrypt_func_name(const std::string& player_js);

    /// URL 解码
    static std::string url_decode(const std::string& encoded);

    /// 从 cipher 字符串中解析参数
    static bool parse_cipher(const std::string& cipher,
                             std::string& sig, std::string& sp, std::string& url);
};

} // namespace seeker

#endif // SEEKER_YOUTUBE_CIPHER_H
