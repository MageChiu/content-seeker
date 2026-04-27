/// YouTube 流提取器实现
/// 使用 YouTube 页面抓取获取流地址
/// 对 signatureCipher 加密流通过 QuickJS 解密

#include "youtube_plugin.h"
#include "../../utils/json_utils.h"
#include <stdexcept>
#include <algorithm>

namespace seeker {

bool YouTubePlugin::can_handle(const std::string& url) const {
    return url.find("youtube.com") != std::string::npos ||
           url.find("youtu.be") != std::string::npos;
}

std::string YouTubePlugin::extract_video_id(const std::string& url) const {
    // youtu.be/VIDEO_ID
    auto pos = url.find("youtu.be/");
    if (pos != std::string::npos) {
        pos += 9;
        size_t end = pos;
        while (end < url.size() && url[end] != '?' && url[end] != '&' && url[end] != '#' && url[end] != '/')
            ++end;
        return url.substr(pos, end - pos);
    }

    // youtube.com/watch?v=VIDEO_ID
    pos = url.find("v=");
    if (pos != std::string::npos) {
        pos += 2;
        size_t end = pos;
        while (end < url.size() && url[end] != '&' && url[end] != '#')
            ++end;
        return url.substr(pos, end - pos);
    }

    // youtube.com/embed/VIDEO_ID
    pos = url.find("/embed/");
    if (pos != std::string::npos) {
        pos += 7;
        size_t end = pos;
        while (end < url.size() && url[end] != '?' && url[end] != '&' && url[end] != '#' && url[end] != '/')
            ++end;
        return url.substr(pos, end - pos);
    }

    // youtube.com/shorts/VIDEO_ID
    pos = url.find("/shorts/");
    if (pos != std::string::npos) {
        pos += 8;
        size_t end = pos;
        while (end < url.size() && url[end] != '?' && url[end] != '&' && url[end] != '#' && url[end] != '/')
            ++end;
        return url.substr(pos, end - pos);
    }

    return "";
}

std::string YouTubePlugin::extract_player_url(const std::string& page_html) {
    // 提取 player.js URL，格式如: /s/player/XXXXX/player_ias.vflset/en_US/base.js
    std::string marker = "/s/player/";
    auto pos = page_html.find(marker);
    if (pos == std::string::npos) return "";

    // 向前找引号
    size_t start = pos;
    while (start > 0 && page_html[start - 1] != '"' && page_html[start - 1] != '\'')
        --start;

    // 向后找 .js 结尾
    size_t end = page_html.find(".js", pos);
    if (end == std::string::npos) return "";
    end += 3; // 包含 ".js"

    std::string path = page_html.substr(start, end - start);
    // 确保是完整 URL
    if (path.find("http") != 0) {
        path = "https://www.youtube.com" + path;
    }
    return path;
}

std::string YouTubePlugin::fetch_player_response(const std::string& video_id) {
    std::string page_url = "https://www.youtube.com/watch?v=" + video_id;
    std::map<std::string, std::string> headers = {
        {"Accept-Language", "en-US,en;q=0.9"},
        {"Accept", "text/html,application/xhtml+xml"},
    };

    auto resp = http_.get(page_url, headers);
    if (!resp.ok()) {
        throw std::runtime_error("YouTube 页面请求失败: HTTP " + std::to_string(resp.status_code));
    }

    // 从页面中提取 ytInitialPlayerResponse
    std::string marker = "var ytInitialPlayerResponse = ";
    auto marker_pos = resp.body.find(marker);
    if (marker_pos == std::string::npos) {
        marker = "ytInitialPlayerResponse = ";
        marker_pos = resp.body.find(marker);
    }
    if (marker_pos == std::string::npos) {
        throw std::runtime_error("无法在 YouTube 页面中找到 player response");
    }

    size_t json_start = marker_pos + marker.size();
    if (json_start >= resp.body.size() || resp.body[json_start] != '{') {
        throw std::runtime_error("YouTube player response 格式异常");
    }

    // 找到 JSON 对象的结束位置
    int depth = 0;
    bool in_string = false;
    size_t json_end = json_start;
    for (size_t i = json_start; i < resp.body.size(); ++i) {
        if (resp.body[i] == '\\' && in_string) { ++i; continue; }
        if (resp.body[i] == '"') { in_string = !in_string; continue; }
        if (in_string) continue;
        if (resp.body[i] == '{') ++depth;
        else if (resp.body[i] == '}') {
            --depth;
            if (depth == 0) { json_end = i; break; }
        }
    }

    // 同时保存页面用于提取 player URL
    // 利用 player_url_ 临时存储（通过 extract 方法传递）
    // 这里直接把 player_url 也提取出来存在 response 前面
    std::string player_url = extract_player_url(resp.body);
    std::string player_response = resp.body.substr(json_start, json_end - json_start + 1);

    // 在结果中嵌入 player_url 供后续使用
    // 插入到 JSON 顶层: {"_playerUrl":"...", ...原始内容...}
    if (!player_url.empty() && player_response.size() > 1) {
        player_response = "{\"_playerUrl\":\"" + json::escape(player_url) + "\"," +
                         player_response.substr(1);
    }

    return player_response;
}

std::string YouTubePlugin::resolve_format_url(const std::string& obj, const std::string& player_url) {
    // 优先使用直接 URL
    std::string url = json::get_string(obj, "url");
    if (!url.empty()) return url;

    // 处理 signatureCipher
    std::string sig_cipher = json::get_string(obj, "signatureCipher");
    if (sig_cipher.empty()) return "";

    // 需要 player_url 来下载解密函数
    if (player_url.empty()) return "";

    // 使用 cipher 解密
    return cipher_.decrypt(sig_cipher, player_url);
}

std::string YouTubePlugin::pick_best_format(const std::string& formats_json, const std::string& player_url) {
    size_t pos = 0;
    if (pos < formats_json.size() && formats_json[pos] == '[') pos++;

    std::string best_url;
    int best_height = 0;
    int best_bitrate = 0;

    while (pos < formats_json.size() && formats_json[pos] != ']') {
        while (pos < formats_json.size() && (formats_json[pos] == ' ' || formats_json[pos] == '\n' ||
               formats_json[pos] == '\r' || formats_json[pos] == '\t' || formats_json[pos] == ','))
            ++pos;

        if (pos < formats_json.size() && formats_json[pos] == '{') {
            size_t obj_end = pos + 1;
            int depth = 1;
            bool in_str = false;
            while (obj_end < formats_json.size() && depth > 0) {
                if (formats_json[obj_end] == '\\' && in_str) { obj_end += 2; continue; }
                if (formats_json[obj_end] == '"') in_str = !in_str;
                else if (!in_str) {
                    if (formats_json[obj_end] == '{') ++depth;
                    else if (formats_json[obj_end] == '}') --depth;
                }
                ++obj_end;
            }
            std::string obj = formats_json.substr(pos, obj_end - pos);

            // 尝试解析 URL（支持 cipher 解密）
            std::string resolved_url = resolve_format_url(obj, player_url);
            if (!resolved_url.empty()) {
                int height = json::get_int(obj, "height", 0);
                int bitrate = json::get_int(obj, "bitrate", 0);
                int score = height * 100000 + bitrate / 1000;
                if (score > best_height * 100000 + best_bitrate / 1000) {
                    best_url = resolved_url;
                    best_height = height;
                    best_bitrate = bitrate;
                }
            }
            pos = obj_end;
        } else {
            ++pos;
        }
    }
    return best_url;
}

std::string YouTubePlugin::extract(const std::string& url, const std::string& options_json) {
    (void)options_json;

    std::string video_id = extract_video_id(url);
    if (video_id.empty()) {
        throw std::runtime_error("无法从 URL 中提取 YouTube video ID");
    }

    std::string player_response = fetch_player_response(video_id);
    if (player_response.empty()) {
        throw std::runtime_error("无法获取 YouTube player response");
    }

    // 提取内嵌的 player URL
    std::string player_url = json::get_string(player_response, "_playerUrl");

    // 提取标题
    std::string title = json::get_string(player_response, "title");
    if (title.empty()) {
        std::string video_details = json::get_nested(player_response, "videoDetails");
        if (!video_details.empty()) {
            title = json::get_string(video_details, "title");
        }
    }

    // 获取 streamingData
    std::string streaming_data = json::get_nested(player_response, "streamingData");
    if (streaming_data.empty()) {
        throw std::runtime_error("YouTube streamingData 为空，视频可能受限");
    }

    // 优先从 formats (含音视频合一) 中选择
    size_t formats_start = 0, formats_end = 0;
    if (json::find_array(streaming_data, "formats", formats_start, formats_end)) {
        std::string formats_arr = streaming_data.substr(formats_start, formats_end - formats_start + 1);
        std::string best_url = pick_best_format(formats_arr, player_url);
        if (!best_url.empty()) {
            std::map<std::string, std::string> headers = {
                {"Accept", "*/*"},
                {"Accept-Language", "en-US,en;q=0.9"},
                {"Origin", "https://www.youtube.com"},
                {"Referer", "https://www.youtube.com/"},
            };
            return json::build_stream_result(
                best_url, title, "combined", "video/mp4", headers
            );
        }
    }

    // 尝试 adaptiveFormats（分离流）
    size_t adaptive_start = 0, adaptive_end = 0;
    if (json::find_array(streaming_data, "adaptiveFormats", adaptive_start, adaptive_end)) {
        std::string adaptive_arr = streaming_data.substr(adaptive_start, adaptive_end - adaptive_start + 1);

        std::string best_video;
        std::string best_audio;
        int best_video_score = -1;
        int best_audio_bitrate = -1;

        size_t pos = 1; // 跳过 '['
        while (pos < adaptive_arr.size() && adaptive_arr[pos] != ']') {
            while (pos < adaptive_arr.size() && (adaptive_arr[pos] == ' ' || adaptive_arr[pos] == '\n' ||
                   adaptive_arr[pos] == '\r' || adaptive_arr[pos] == '\t' || adaptive_arr[pos] == ','))
                ++pos;

            if (pos < adaptive_arr.size() && adaptive_arr[pos] == '{') {
                size_t obj_end = pos + 1;
                int depth = 1;
                bool in_str = false;
                while (obj_end < adaptive_arr.size() && depth > 0) {
                    if (adaptive_arr[obj_end] == '\\' && in_str) { obj_end += 2; continue; }
                    if (adaptive_arr[obj_end] == '"') in_str = !in_str;
                    else if (!in_str) {
                        if (adaptive_arr[obj_end] == '{') ++depth;
                        else if (adaptive_arr[obj_end] == '}') --depth;
                    }
                    ++obj_end;
                }
                std::string obj = adaptive_arr.substr(pos, obj_end - pos);
                std::string mime = json::get_string(obj, "mimeType");

                // 解析 URL（支持 cipher）
                std::string fmt_url = resolve_format_url(obj, player_url);

                if (!fmt_url.empty()) {
                    int height = json::get_int(obj, "height", 0);
                    int bitrate = json::get_int(obj, "bitrate", 0);

                    if (mime.find("video/") != std::string::npos) {
                        int score = height * 100000 + bitrate / 1000;
                        if (score > best_video_score) {
                            best_video_score = score;
                            best_video = fmt_url;
                        }
                    } else if (mime.find("audio/") != std::string::npos) {
                        if (bitrate > best_audio_bitrate) {
                            best_audio_bitrate = bitrate;
                            best_audio = fmt_url;
                        }
                    }
                }
                pos = obj_end;
            } else {
                ++pos;
            }
        }

        if (!best_video.empty() && !best_audio.empty()) {
            std::map<std::string, std::string> headers = {
                {"Accept", "*/*"},
                {"Origin", "https://www.youtube.com"},
                {"Referer", "https://www.youtube.com/"},
            };
            return json::build_stream_result(
                best_video, title, "adaptive_hd", "video/mp4",
                headers, best_audio
            );
        }

        if (!best_video.empty()) {
            std::map<std::string, std::string> headers = {
                {"Accept", "*/*"},
                {"Origin", "https://www.youtube.com"},
                {"Referer", "https://www.youtube.com/"},
            };
            return json::build_stream_result(
                best_video, title, "adaptive_video_only", "video/mp4", headers
            );
        }
    }

    // HLS 回退
    std::string hls_url = json::get_string(streaming_data, "hlsManifestUrl");
    if (!hls_url.empty()) {
        return json::build_stream_result(
            hls_url, title, "hls", "application/x-mpegURL", {}
        );
    }

    throw std::runtime_error("YouTube 无法获取可播放的流地址 (可能需要解密或视频受地区限制)");
}

} // namespace seeker
