#ifndef SEEKER_YOUTUBE_PLUGIN_H
#define SEEKER_YOUTUBE_PLUGIN_H

#include "../extractor_registry.h"
#include "../../utils/http_client.h"
#include "youtube_cipher.h"
#include <string>

namespace seeker {

/// YouTube 视频流提取器
/// 通过抓取页面获取 player response，提取 streaming data
/// 对加密流使用 QuickJS 执行签名解密
class YouTubePlugin : public ExtractorPlugin {
public:
    const char* name() const override { return "youtube"; }
    bool can_handle(const std::string& url) const override;
    std::string extract(const std::string& url, const std::string& options_json) override;

private:
    HttpClient http_;
    YouTubeCipher cipher_;

    /// 从 URL 中提取 video ID
    std::string extract_video_id(const std::string& url) const;

    /// 通过页面抓取获取视频信息
    std::string fetch_player_response(const std::string& video_id);

    /// 从页面中提取 player.js URL
    std::string extract_player_url(const std::string& page_html);

    /// 从 streaming formats 中选出最佳带音频的视频流
    /// 支持 signatureCipher 解密
    std::string pick_best_format(const std::string& formats_json, const std::string& player_url);

    /// 解析单个格式对象，处理 cipher 解密
    std::string resolve_format_url(const std::string& obj, const std::string& player_url);
};

} // namespace seeker

#endif // SEEKER_YOUTUBE_PLUGIN_H
