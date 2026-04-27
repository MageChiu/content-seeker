#ifndef SEEKER_BILIBILI_PLUGIN_H
#define SEEKER_BILIBILI_PLUGIN_H

#include "../extractor_registry.h"
#include "../../utils/http_client.h"
#include "../../utils/wbi_sign.h"
#include <string>
#include <cstdint>

namespace seeker {

/// Bilibili 视频流提取器
/// 支持 DASH 和直链 MP4 两种模式
class BilibiliPlugin : public ExtractorPlugin {
public:
    BilibiliPlugin() : wbi_(http_) {}

    const char* name() const override { return "bilibili"; }
    bool can_handle(const std::string& url) const override;
    std::string extract(const std::string& url, const std::string& options_json) override;

private:
    HttpClient http_;
    WbiSigner wbi_;

    /// 从 URL 中提取 BV 号
    std::string extract_bvid(const std::string& url) const;

    /// 解析短链接（b23.tv 等）为完整 URL
    std::string resolve_short_url(const std::string& url);

    /// 获取视频基本信息（含 cid）
    std::string fetch_view(const std::string& bvid);

    /// 获取 DASH 播放地址
    std::string fetch_dash_playurl(const std::string& bvid, int64_t cid);

    /// 获取直链 MP4 播放地址
    std::string fetch_mp4_playurl(const std::string& bvid, int64_t cid);

    /// 从 DASH 数据中选出最佳视频轨
    std::string pick_best_video(const std::string& video_array);

    /// 从 DASH 数据中选出最佳音频轨
    std::string pick_best_audio(const std::string& audio_array);

    /// 标准请求头
    static const std::map<std::string, std::string>& bilibili_headers();

    /// 播放时需要的 headers
    static const std::map<std::string, std::string>& playback_headers();
};

} // namespace seeker

#endif // SEEKER_BILIBILI_PLUGIN_H
