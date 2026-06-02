/// Bilibili 流提取器实现
/// 通过 Bilibili Web API 获取 DASH/MP4 播放地址

#include "bilibili_plugin.h"
#include "../../utils/json_utils.h"
#include <stdexcept>
#include <cstdio>  // fprintf for debug

namespace seeker {

const std::map<std::string, std::string>& BilibiliPlugin::bilibili_headers() {
    static const std::map<std::string, std::string> headers = {
        {"User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"},
        {"Referer", "https://www.bilibili.com"},
        {"Origin", "https://www.bilibili.com"},
        {"Accept", "application/json, text/plain, */*"},
        {"Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8"},
    };
    return headers;
}

const std::map<std::string, std::string>& BilibiliPlugin::playback_headers() {
    static const std::map<std::string, std::string> headers = {
        {"User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"},
        {"Referer", "https://www.bilibili.com"},
        {"Origin", "https://www.bilibili.com"},
        {"Accept", "*/*"},
        {"Range", "bytes=0-"},
    };
    return headers;
}

bool BilibiliPlugin::can_handle(const std::string& url) const {
    return url.find("bilibili.com") != std::string::npos ||
           url.find("b23.tv") != std::string::npos;
}

std::string BilibiliPlugin::resolve_short_url(const std::string& url) {
    // b23.tv 短链接需要解析重定向
    if (url.find("b23.tv") != std::string::npos) {
        std::string resolved = http_.resolve_redirect(url);
        if (!resolved.empty() && resolved != url) {
            return resolved;
        }
    }
    return url;
}

std::string BilibiliPlugin::extract_bvid(const std::string& url) const {
    // 匹配 /video/BVxxxxxx 格式
    auto pos = url.find("/video/BV");
    if (pos == std::string::npos) {
        pos = url.find("/video/bv");
    }
    if (pos == std::string::npos) return "";

    pos += 7; // 跳过 "/video/"
    size_t end = pos;
    while (end < url.size() && url[end] != '/' && url[end] != '?' && url[end] != '#') {
        ++end;
    }
    return url.substr(pos, end - pos);
}

std::string BilibiliPlugin::fetch_view(const std::string& bvid) {
    // 使用 wbi 签名
    std::map<std::string, std::string> params = {{"bvid", bvid}};
    std::string signed_qs = wbi_.sign(params);
    std::string api_url = "https://api.bilibili.com/x/web-interface/view?" + signed_qs;
    auto resp = http_.get(api_url, bilibili_headers());
    if (!resp.ok()) {
        throw std::runtime_error("Bilibili view API 请求失败: HTTP " + std::to_string(resp.status_code));
    }
    return resp.body;
}

std::string BilibiliPlugin::fetch_dash_playurl(const std::string& bvid, int64_t cid) {
    // 尝试多个质量级别
    std::vector<std::string> qn_list = {"112", "80", "64"};
    for (const auto& qn : qn_list) {
        std::map<std::string, std::string> params = {
            {"bvid", bvid},
            {"cid", std::to_string(cid)},
            {"qn", qn},
            {"fnval", "16"},
            {"fourk", "1"}
        };
        std::string signed_qs = wbi_.sign(params);
        std::string api_url = "https://api.bilibili.com/x/player/playurl?" + signed_qs;
        auto resp = http_.get(api_url, bilibili_headers());
        if (resp.ok()) {
            int code = json::get_int(resp.body, "code", -1);
            if (code == 0) {
                // 检查 dash 数据是否存在
                std::string data = json::get_nested(resp.body, "data");
                if (!data.empty()) {
                    size_t dash_start, dash_end;
                    if (json::find_object(data, "dash", dash_start, dash_end)) {
                        return resp.body;
                    }
                }
            }
        }
    }
    return "";
}

std::string BilibiliPlugin::fetch_mp4_playurl(const std::string& bvid, int64_t cid) {
    std::vector<std::string> qn_list = {"80", "64", "32"};
    for (const auto& qn : qn_list) {
        std::map<std::string, std::string> params = {
            {"bvid", bvid},
            {"cid", std::to_string(cid)},
            {"qn", qn},
            {"fnval", "1"},
            {"platform", "html5"},
            {"high_quality", "1"},
            {"try_look", "1"}
        };
        std::string signed_qs = wbi_.sign(params);
        std::string api_url = "https://api.bilibili.com/x/player/playurl?" + signed_qs;
        auto resp = http_.get(api_url, bilibili_headers());
        if (resp.ok()) {
            int code = json::get_int(resp.body, "code", -1);
            if (code == 0) return resp.body;
        }
    }
    return "";
}

std::string BilibiliPlugin::pick_best_video(const std::string& video_array) {
    // 在数组中遍历对象，选 bandwidth 最大的
    size_t pos = 0;
    if (pos < video_array.size() && video_array[pos] == '[') pos++;

    std::string best_url;
    int best_score = -1;

    while (pos < video_array.size() && video_array[pos] != ']') {
        // 跳过空白和逗号
        while (pos < video_array.size() && (video_array[pos] == ' ' || video_array[pos] == '\n' ||
               video_array[pos] == '\r' || video_array[pos] == '\t' || video_array[pos] == ','))
            ++pos;

        if (pos < video_array.size() && video_array[pos] == '{') {
            size_t obj_end = pos + 1;
            int depth = 1;
            bool in_str = false;
            while (obj_end < video_array.size() && depth > 0) {
                if (video_array[obj_end] == '\\' && in_str) { obj_end += 2; continue; }
                if (video_array[obj_end] == '"') in_str = !in_str;
                else if (!in_str) {
                    if (video_array[obj_end] == '{') ++depth;
                    else if (video_array[obj_end] == '}') --depth;
                }
                ++obj_end;
            }
            std::string obj = video_array.substr(pos, obj_end - pos);

            int id = json::get_int(obj, "id", 0);
            int bandwidth = json::get_int(obj, "bandwidth", 0);
            int score = id * 100000 + bandwidth / 1000;

            if (score > best_score) {
                best_score = score;
                std::string base_url = json::get_string(obj, "baseUrl");
                if (base_url.empty()) base_url = json::get_string(obj, "base_url");
                if (!base_url.empty()) best_url = base_url;
            }
            pos = obj_end;
        } else {
            ++pos;
        }
    }
    return best_url;
}

std::string BilibiliPlugin::pick_best_audio(const std::string& audio_array) {
    size_t pos = 0;
    if (pos < audio_array.size() && audio_array[pos] == '[') pos++;

    std::string best_url;
    int best_bandwidth = -1;

    while (pos < audio_array.size() && audio_array[pos] != ']') {
        while (pos < audio_array.size() && (audio_array[pos] == ' ' || audio_array[pos] == '\n' ||
               audio_array[pos] == '\r' || audio_array[pos] == '\t' || audio_array[pos] == ','))
            ++pos;

        if (pos < audio_array.size() && audio_array[pos] == '{') {
            size_t obj_end = pos + 1;
            int depth = 1;
            bool in_str = false;
            while (obj_end < audio_array.size() && depth > 0) {
                if (audio_array[obj_end] == '\\' && in_str) { obj_end += 2; continue; }
                if (audio_array[obj_end] == '"') in_str = !in_str;
                else if (!in_str) {
                    if (audio_array[obj_end] == '{') ++depth;
                    else if (audio_array[obj_end] == '}') --depth;
                }
                ++obj_end;
            }
            std::string obj = audio_array.substr(pos, obj_end - pos);

            int bandwidth = json::get_int(obj, "bandwidth", 0);
            if (bandwidth > best_bandwidth) {
                best_bandwidth = bandwidth;
                std::string base_url = json::get_string(obj, "baseUrl");
                if (base_url.empty()) base_url = json::get_string(obj, "base_url");
                if (!base_url.empty()) best_url = base_url;
            }
            pos = obj_end;
        } else {
            ++pos;
        }
    }
    return best_url;
}

std::string BilibiliPlugin::extract(const std::string& url, const std::string& options_json) {
    (void)options_json;

    // 解析短链接（b23.tv → bilibili.com）
    std::string resolved_url = resolve_short_url(url);
    fprintf(stderr, "[bilibili] url='%s' -> resolved='%s'\n", url.c_str(), resolved_url.c_str());

    // 提取 BV 号
    std::string bvid = extract_bvid(resolved_url);
    if (bvid.empty()) {
        throw std::runtime_error("无法从 URL 中提取 Bilibili BV 号: " + resolved_url);
    }
    fprintf(stderr, "[bilibili] bvid='%s'\n", bvid.c_str());

    // 获取视频信息
    std::string view_resp = fetch_view(bvid);
    int code = json::get_int(view_resp, "code", -1);
    fprintf(stderr, "[bilibili] view API code=%d, resp.size=%zu\n", code, view_resp.size());
    if (code != 0) {
        throw std::runtime_error("Bilibili view API 返回错误: code=" + std::to_string(code));
    }

    std::string data = json::get_nested(view_resp, "data");
    if (data.empty()) {
        throw std::runtime_error("Bilibili view API 返回数据为空");
    }

    std::string title = json::get_string(data, "title");
    
    // 使用深度感知的解析函数，只在 data 对象的顶层查找 cid
    int64_t cid = json::get_top_level_int64(data, "cid", 0);
    fprintf(stderr, "[bilibili] top_level cid=%lld, data.size=%zu\n", (long long)cid, data.size());
    
    if (cid == 0) {
        // 回退：使用全局搜索的 get_int64
        cid = json::get_int64(data, "cid", 0);
        fprintf(stderr, "[bilibili] fallback get_int64 cid=%lld\n", (long long)cid);
    }
    
    if (cid == 0) {
        // 尝试从 pages 数组获取第一个 cid
        size_t pages_start, pages_end;
        if (json::find_array(data, "pages", pages_start, pages_end)) {
            std::string pages = data.substr(pages_start, pages_end - pages_start + 1);
            fprintf(stderr, "[bilibili] pages array size=%zu, first 200 chars: %.200s\n", 
                    pages.size(), pages.c_str());
            std::vector<std::string> cids = json::get_array_field(pages, "cid");
            fprintf(stderr, "[bilibili] pages cid count=%zu\n", cids.size());
            if (!cids.empty() && !cids[0].empty()) {
                fprintf(stderr, "[bilibili] pages[0].cid = '%s'\n", cids[0].c_str());
                try { cid = std::stoll(cids[0]); } catch (...) {}
            }
        } else {
            fprintf(stderr, "[bilibili] pages array NOT found in data\n");
        }
    }
    if (cid == 0) {
        // 最后尝试：直接在原始 view_resp 中搜索 "cid":\d+ 模式
        // 原始响应中 data.cid 应该存在
        cid = json::get_int64(view_resp, "cid", 0);
        fprintf(stderr, "[bilibili] last resort from view_resp cid=%lld\n", (long long)cid);
    }
    if (cid == 0) {
        // 输出 data 的前 500 字符用于诊断
        std::string data_preview = data.substr(0, std::min(data.size(), (size_t)500));
        throw std::runtime_error("无法获取 Bilibili cid, title=" + title + 
            ", data_preview=" + data_preview);
    }
    fprintf(stderr, "[bilibili] final cid=%lld, title=%s\n", (long long)cid, title.c_str());

    // 优先尝试 DASH
    std::string dash_resp = fetch_dash_playurl(bvid, cid);
    if (!dash_resp.empty()) {
        std::string resp_data = json::get_nested(dash_resp, "data");
        std::string dash = json::get_nested(resp_data, "dash");

        if (!dash.empty()) {
            size_t video_start = 0, video_end = 0, audio_start = 0, audio_end = 0;
            if (json::find_array(dash, "video", video_start, video_end) &&
                json::find_array(dash, "audio", audio_start, audio_end)) {

                std::string video_array = dash.substr(video_start, video_end - video_start + 1);
                std::string audio_array = dash.substr(audio_start, audio_end - audio_start + 1);

                std::string video_url = pick_best_video(video_array);
                std::string audio_url = pick_best_audio(audio_array);

                if (!video_url.empty() && !audio_url.empty()) {
                    return json::build_stream_result(
                        video_url, title, "dash_hd", "video/mp4",
                        playback_headers(), audio_url
                    );
                }
            }
        }
    }

    // 回退到直链 MP4
    std::string mp4_resp = fetch_mp4_playurl(bvid, cid);
    if (!mp4_resp.empty()) {
        std::string mp4_data = json::get_nested(mp4_resp, "data");
        // 获取 durl 数组中第一个元素的 url
        size_t durl_start, durl_end;
        if (json::find_array(mp4_data, "durl", durl_start, durl_end)) {
            std::string durl_array = mp4_data.substr(durl_start, durl_end - durl_start + 1);
            std::vector<std::string> urls = json::get_array_field(durl_array, "url");
            if (!urls.empty() && !urls[0].empty()) {
                int quality = json::get_int(mp4_data, "quality", 0);
                std::string quality_label = "mp4_" + std::to_string(quality);
                return json::build_stream_result(
                    urls[0], title, quality_label, "video/mp4",
                    playback_headers()
                );
            }
        }
    }

    throw std::runtime_error("Bilibili 无法获取可播放的流地址: bvid=" + bvid);
}

} // namespace seeker
