#include "download_planner.h"

#include "../utils/json_utils.h"

#include <sstream>

namespace seeker {

std::string DownloadPlanner::build_plan_json(
    int32_t runtime_id,
    const std::string& resolved_media_json,
    const std::string& options_json
) const {
    const std::string media_id = json::get_string(resolved_media_json, "mediaId");
    const std::string source_id = json::get_string(resolved_media_json, "sourceId");
    const std::string title = json::get_string(resolved_media_json, "title");
    const std::string kind = json::get_string(resolved_media_json, "kind");
    const std::string primary_url = json::get_string(resolved_media_json, "primaryUrl");
    const std::string mime_type = json::get_string(resolved_media_json, "mimeType");
    const std::map<std::string, std::string> headers =
        json::get_object_string_map(resolved_media_json, "headers");
    const std::string filename = derive_filename(title, primary_url, options_json, mime_type);
    const std::string save_path = (source_id.empty() ? "runtime" : source_id) + "/" + filename;

    std::ostringstream ss;
    ss << "{";
    ss << "\"ok\":true";
    ss << ",\"runtimeId\":" << runtime_id;
    ss << ",\"mediaId\":\"" << json::escape(media_id) << "\"";
    ss << ",\"sourceId\":\"" << json::escape(source_id) << "\"";
    ss << ",\"title\":\"" << json::escape(title) << "\"";
    ss << ",\"kind\":\"" << json::escape(kind) << "\"";
    ss << ",\"primaryUrl\":\"" << json::escape(primary_url) << "\"";
    ss << ",\"mimeType\":\"" << json::escape(mime_type) << "\"";
    ss << ",\"filename\":\"" << json::escape(filename) << "\"";
    ss << ",\"savePath\":\"" << json::escape(save_path) << "\"";
    ss << ",\"headers\":" << json::build_object(headers);
    ss << ",\"reuseCache\":true";
    ss << ",\"supportsResume\":true";
    ss << ",\"segments\":[]";
    ss << "}";
    return ss.str();
}

DownloadPlanData DownloadPlanner::parse_plan_json(const std::string& download_plan_json) const {
    DownloadPlanData plan;
    plan.media_id = json::get_string(download_plan_json, "mediaId");
    plan.source_id = json::get_string(download_plan_json, "sourceId");
    plan.title = json::get_string(download_plan_json, "title");
    plan.kind = json::get_string(download_plan_json, "kind");
    plan.primary_url = json::get_string(download_plan_json, "primaryUrl");
    plan.filename = json::get_string(download_plan_json, "filename");
    plan.save_path = json::get_string(download_plan_json, "savePath");
    plan.mime_type = json::get_string(download_plan_json, "mimeType");
    plan.headers = json::get_object_string_map(download_plan_json, "headers");
    plan.reuse_cache = json::get_string(download_plan_json, "reuseCache") != "false";
    plan.supports_resume = json::get_string(download_plan_json, "supportsResume") != "false";
    return plan;
}

std::string DownloadPlanner::derive_filename(
    const std::string& title,
    const std::string& primary_url,
    const std::string& options_json,
    const std::string& mime_type
) const {
    const std::string explicit_filename = json::get_string(options_json, "filename");
    if (!explicit_filename.empty()) {
        return explicit_filename;
    }

    const std::string base = sanitize_filename(title.empty() ? "media" : title);
    const std::string extension = derive_extension(primary_url, mime_type);
    if (extension.empty()) {
        return base;
    }
    return base + "." + extension;
}

std::string DownloadPlanner::derive_extension(
    const std::string& primary_url,
    const std::string& mime_type
) const {
    const auto dot = primary_url.find_last_of('.');
    const auto slash = primary_url.find_last_of('/');
    if (dot != std::string::npos && (slash == std::string::npos || dot > slash)) {
        std::string ext = primary_url.substr(dot + 1);
        const auto q = ext.find_first_of("?#");
        if (q != std::string::npos) {
            ext = ext.substr(0, q);
        }
        if (!ext.empty() && ext.size() <= 8) {
            return ext;
        }
    }

    if (mime_type == "application/x-mpegURL") return "m3u8";
    if (mime_type == "application/dash+xml") return "mpd";
    if (mime_type == "video/mp4") return "mp4";
    if (mime_type == "video/webm") return "webm";
    if (mime_type == "audio/mpeg") return "mp3";
    if (mime_type == "audio/mp4") return "m4a";
    if (mime_type == "audio/flac") return "flac";
    return "";
}

std::string DownloadPlanner::sanitize_filename(const std::string& input) const {
    std::string out;
    out.reserve(input.size());
    for (char ch : input) {
        switch (ch) {
            case '\\':
            case '/':
            case ':':
            case '*':
            case '?':
            case '"':
            case '<':
            case '>':
            case '|':
                out.push_back('_');
                break;
            default:
                out.push_back(ch);
                break;
        }
    }
    return out.empty() ? "media" : out;
}

} // namespace seeker
