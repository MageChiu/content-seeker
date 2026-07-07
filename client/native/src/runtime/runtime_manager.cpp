#include "runtime_manager.h"

#include "../extractor/extractor_registry.h"
#include "../utils/json_utils.h"

#include <sstream>

namespace seeker {

namespace {

std::string build_basic_event(
    const std::string& type,
    const std::string& status,
    int64_t position_ms = 0,
    const std::string& extra_json = ""
) {
    std::ostringstream ss;
    ss << "{";
    ss << "\"type\":\"" << json::escape(type) << "\"";
    ss << ",\"status\":\"" << json::escape(status) << "\"";
    ss << ",\"positionMs\":" << position_ms;
    if (!extra_json.empty()) {
        ss << "," << extra_json;
    }
    ss << "}";
    return ss.str();
}

bool is_network_url(const std::string& url) {
    return url.rfind("http://", 0) == 0 ||
           url.rfind("https://", 0) == 0 ||
           url.rfind("rtmp://", 0) == 0 ||
           url.rfind("rtsp://", 0) == 0 ||
           url.rfind("rtp://", 0) == 0;
}

bool is_direct_media_url(const std::string& url) {
    return url.find(".m3u8") != std::string::npos ||
           url.find(".mpd") != std::string::npos ||
           url.find(".mp4") != std::string::npos ||
           url.find(".webm") != std::string::npos ||
           url.find(".mp3") != std::string::npos ||
           url.find(".m4a") != std::string::npos ||
           url.find(".aac") != std::string::npos ||
           url.find(".wav") != std::string::npos ||
           url.find(".flac") != std::string::npos;
}

std::string classify_media_kind(const std::string& url) {
    if (url.find(".m3u8") != std::string::npos) return "hls";
    if (url.find(".mpd") != std::string::npos) return "dash";
    if (url.rfind("rtmp://", 0) == 0 || url.rfind("rtsp://", 0) == 0) return "live";
    return "progressive";
}

std::string guess_mime_type(const std::string& url) {
    if (url.find(".m3u8") != std::string::npos) return "application/x-mpegURL";
    if (url.find(".mpd") != std::string::npos) return "application/dash+xml";
    if (url.find(".mp4") != std::string::npos) return "video/mp4";
    if (url.find(".webm") != std::string::npos) return "video/webm";
    if (url.find(".mp3") != std::string::npos) return "audio/mpeg";
    if (url.find(".m4a") != std::string::npos) return "audio/mp4";
    if (url.find(".aac") != std::string::npos) return "audio/aac";
    if (url.find(".wav") != std::string::npos) return "audio/wav";
    if (url.find(".flac") != std::string::npos) return "audio/flac";
    return "";
}

std::string default_title_for(const std::string& url) {
    if (url.empty()) return "Untitled Media";
    const auto slash = url.find_last_of('/');
    if (slash == std::string::npos || slash + 1 >= url.size()) {
        return "Untitled Media";
    }
    return url.substr(slash + 1);
}

std::string build_headers_json(const std::map<std::string, std::string>& headers) {
    return json::build_object(headers);
}

std::string build_media_graph_json(
    int32_t runtime_id,
    const std::string& media_id,
    const std::string& source_id,
    const std::string& title,
    const std::string& input_url,
    const std::string& primary_url,
    const std::string& kind,
    const std::string& mime_type,
    const std::map<std::string, std::string>& headers,
    const std::string& secondary_audio_url,
    const std::string& display_label,
    const std::string& resolver_kind
) {
    std::ostringstream ss;
    ss << "{";
    ss << "\"ok\":true";
    ss << ",\"runtimeId\":" << runtime_id;
    ss << ",\"mediaId\":\"" << json::escape(media_id) << "\"";
    ss << ",\"sourceId\":\"" << json::escape(source_id) << "\"";
    ss << ",\"title\":\"" << json::escape(title) << "\"";
    ss << ",\"kind\":\"" << json::escape(kind) << "\"";
    ss << ",\"primaryUrl\":\"" << json::escape(primary_url) << "\"";
    ss << ",\"inputUrl\":\"" << json::escape(input_url) << "\"";
    ss << ",\"displayLabel\":\"" << json::escape(display_label) << "\"";
    ss << ",\"resolverKind\":\"" << json::escape(resolver_kind) << "\"";
    if (!mime_type.empty()) {
        ss << ",\"mimeType\":\"" << json::escape(mime_type) << "\"";
    }
    if (!secondary_audio_url.empty()) {
        ss << ",\"secondaryAudioUrl\":\"" << json::escape(secondary_audio_url) << "\"";
    }
    ss << ",\"tracks\":[";
    ss << "{\"id\":\"primary\",\"kind\":\"primary\",\"url\":\"" << json::escape(primary_url) << "\"";
    if (!mime_type.empty()) {
        ss << ",\"mimeType\":\"" << json::escape(mime_type) << "\"";
    }
    ss << "}";
    if (!secondary_audio_url.empty()) {
        ss << ",{\"id\":\"audio-secondary\",\"kind\":\"audio\",\"url\":\""
           << json::escape(secondary_audio_url) << "\"}";
    }
    ss << "]";
    ss << ",\"variants\":[]";
    ss << ",\"fallbacks\":[";
    ss << "{\"label\":\"original\",\"url\":\"" << json::escape(input_url) << "\"}";
    ss << "]";
    ss << ",\"auth\":{\"headers\":" << build_headers_json(headers) << ",\"cookies\":{}}";
    ss << ",\"downloadProfile\":{\"mode\":\"runtime-managed\",\"supported\":true}";
    ss << ",\"cacheProfile\":{\"mode\":\"shared\",\"supported\":true}";
    ss << "}";
    return ss.str();
}

} // namespace

RuntimeManager& RuntimeManager::instance() {
    static RuntimeManager manager;
    return manager;
}

int32_t RuntimeManager::create_runtime(const std::string& config_json) {
    std::lock_guard<std::mutex> lock(mutex_);
    const int32_t runtime_id = next_runtime_id_.fetch_add(1);
    auto runtime = std::make_unique<RuntimeInstance>();
    runtime->runtime_id = runtime_id;
    runtime->config_json = config_json;
    const std::string storage_root = json::get_string(config_json, "storageRoot");
    const std::string cache_root = json::get_string(config_json, "cacheDir");
    const std::string recording_root = json::get_string(config_json, "recordingDir");
    runtime->cache_store.configure(
        storage_root.empty() ? ("seeker_runtime/runtime_" + std::to_string(runtime_id)) : storage_root,
        cache_root,
        recording_root
    );
    runtime->asset_catalog.configure(&runtime->cache_store);
    runtime->transfer_manager.configure(&runtime->cache_store, &runtime->asset_catalog);
    runtime->backend_adapter = create_mpv_backend_adapter();
    runtimes_.emplace(runtime_id, std::move(runtime));
    return runtime_id;
}

void RuntimeManager::destroy_runtime(int32_t runtime_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    runtimes_.erase(runtime_id);
}

int32_t RuntimeManager::create_session(
    int32_t runtime_id,
    seeker_runtime_event_callback callback
) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* runtime = find_runtime_locked(runtime_id);
    if (!runtime || !callback) return SEEKER_ERROR_INVALID;

    const int32_t session_id = runtime->next_session_id.fetch_add(1);
    RuntimeSession session;
    session.session_id = session_id;
    session.callback = callback;
    if (runtime->backend_adapter) {
        session.backend_session = runtime->backend_adapter->create_session(session_id);
    }
    runtime->sessions.emplace(session_id, std::move(session));

    auto* created = find_session_locked(runtime_id, session_id);
    if (created != nullptr) {
        dispatch_session_event_locked(
            *runtime,
            *created,
            build_basic_event("session.created", "idle")
        );
    }
    return session_id;
}

int RuntimeManager::dispose_session(int32_t runtime_id, int32_t session_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* runtime = find_runtime_locked(runtime_id);
    if (!runtime) return SEEKER_ERROR_INVALID;
    const auto it = runtime->sessions.find(session_id);
    if (it == runtime->sessions.end()) return SEEKER_ERROR_INVALID;
    runtime->sessions.erase(it);
    return SEEKER_OK;
}

std::string RuntimeManager::resolve_media(
    int32_t runtime_id,
    const std::string& request_json
) const {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto* runtime = find_runtime_locked(runtime_id);
    if (!runtime) {
        return "{\"error\":\"runtime not found\"}";
    }

    const std::string primary_url = json::get_string(request_json, "url");
    if (primary_url.empty()) {
        return "{\"error\":\"request.url is required\"}";
    }
    const std::string source_id = json::get_string(request_json, "sourceId");
    const std::string title = json::get_string(request_json, "title");
    const std::string media_id = json::get_string(request_json, "mediaId");
    const std::string resolved_media_id =
        media_id.empty() ? ("runtime-media-" + std::to_string(runtime_id)) : media_id;
    const std::string resolved_title =
        title.empty() ? default_title_for(primary_url) : title;

    if (is_direct_media_url(primary_url)) {
        return build_media_graph_json(
            runtime_id,
            resolved_media_id,
            source_id,
            resolved_title,
            primary_url,
            primary_url,
            classify_media_kind(primary_url),
            guess_mime_type(primary_url),
            {},
            "",
            "Direct Stream",
            "direct"
        );
    }

    if (auto* plugin = ExtractorRegistry::instance().find_plugin(primary_url)) {
        try {
            const std::string extracted = plugin->extract(primary_url, "{}");
            if (!json::get_string(extracted, "error").empty()) {
                return extracted;
            }
            const std::string extracted_primary = json::get_string(extracted, "url");
            if (!extracted_primary.empty()) {
                const std::string extracted_title = json::get_string(extracted, "title");
                const std::string extracted_mime = json::get_string(extracted, "mimeType");
                const std::string extracted_audio = json::get_string(extracted, "audioUrl");
                const auto headers = json::get_object_string_map(extracted, "headers");
                return build_media_graph_json(
                    runtime_id,
                    resolved_media_id,
                    source_id.empty() ? plugin->name() : source_id,
                    extracted_title.empty() ? resolved_title : extracted_title,
                    primary_url,
                    extracted_primary,
                    classify_media_kind(extracted_primary),
                    extracted_mime.empty() ? guess_mime_type(extracted_primary) : extracted_mime,
                    headers,
                    extracted_audio,
                    std::string("Extractor: ") + plugin->name(),
                    "extractor"
                );
            }
        } catch (const std::exception& e) {
            std::ostringstream error;
            error << "{\"error\":\"resolver extract failed: "
                  << json::escape(e.what()) << "\"}";
            return error.str();
        }
    }

    if (is_network_url(primary_url)) {
        return build_media_graph_json(
            runtime_id,
            resolved_media_id,
            source_id,
            resolved_title,
            primary_url,
            primary_url,
            classify_media_kind(primary_url),
            guess_mime_type(primary_url),
            {},
            "",
            "Runtime Network Fallback",
            "network-fallback"
        );
    }

    return build_media_graph_json(
        runtime_id,
        resolved_media_id,
        source_id,
        resolved_title,
        primary_url,
        primary_url,
        "progressive",
        guess_mime_type(primary_url),
        {},
        "",
        "Runtime Local Fallback",
        "local-fallback"
    );
}

int RuntimeManager::session_open(
    int32_t runtime_id,
    int32_t session_id,
    const std::string& resolved_media_json
) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* session = find_session_locked(runtime_id, session_id);
    auto* runtime = find_runtime_locked(runtime_id);
    if (!session || !runtime) return SEEKER_ERROR_INVALID;

    session->last_media_json = resolved_media_json;
    if (session->backend_session == nullptr) return SEEKER_ERROR_NOT_INIT;
    const int result = session->backend_session->open(resolved_media_json);
    if (result != SEEKER_OK) return result;
    const BackendPlaybackState state = session->backend_session->snapshot();
    session->status = state.status;
    session->position_ms = state.position_ms;
    session->rate = state.rate;
    session->volume = state.volume;
    dispatch_session_event_locked(
        *runtime,
        *session,
        build_basic_event("session.ready", session->status)
    );
    return SEEKER_OK;
}

int RuntimeManager::session_play(int32_t runtime_id, int32_t session_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* session = find_session_locked(runtime_id, session_id);
    auto* runtime = find_runtime_locked(runtime_id);
    if (!session || !runtime) return SEEKER_ERROR_INVALID;
    if (session->backend_session == nullptr) return SEEKER_ERROR_NOT_INIT;
    const int result = session->backend_session->play();
    if (result != SEEKER_OK) return result;
    const BackendPlaybackState state = session->backend_session->snapshot();
    session->status = state.status;
    session->position_ms = state.position_ms;
    dispatch_session_event_locked(
        *runtime,
        *session,
        build_basic_event("session.playing", session->status, session->position_ms)
    );
    return SEEKER_OK;
}

int RuntimeManager::session_pause(int32_t runtime_id, int32_t session_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* session = find_session_locked(runtime_id, session_id);
    auto* runtime = find_runtime_locked(runtime_id);
    if (!session || !runtime) return SEEKER_ERROR_INVALID;
    if (session->backend_session == nullptr) return SEEKER_ERROR_NOT_INIT;
    const int result = session->backend_session->pause();
    if (result != SEEKER_OK) return result;
    const BackendPlaybackState state = session->backend_session->snapshot();
    session->status = state.status;
    session->position_ms = state.position_ms;
    dispatch_session_event_locked(
        *runtime,
        *session,
        build_basic_event("session.paused", session->status, session->position_ms)
    );
    return SEEKER_OK;
}

int RuntimeManager::session_seek(
    int32_t runtime_id,
    int32_t session_id,
    int64_t position_ms
) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* session = find_session_locked(runtime_id, session_id);
    auto* runtime = find_runtime_locked(runtime_id);
    if (!session || !runtime) return SEEKER_ERROR_INVALID;
    if (session->backend_session == nullptr) return SEEKER_ERROR_NOT_INIT;
    const int result = session->backend_session->seek(position_ms);
    if (result != SEEKER_OK) return result;
    const BackendPlaybackState state = session->backend_session->snapshot();
    session->status = state.status;
    session->position_ms = state.position_ms;
    dispatch_session_event_locked(
        *runtime,
        *session,
        build_basic_event("session.seeked", session->status, session->position_ms)
    );
    return SEEKER_OK;
}

int RuntimeManager::session_set_rate(
    int32_t runtime_id,
    int32_t session_id,
    double rate
) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* session = find_session_locked(runtime_id, session_id);
    auto* runtime = find_runtime_locked(runtime_id);
    if (!session || !runtime) return SEEKER_ERROR_INVALID;
    if (session->backend_session == nullptr) return SEEKER_ERROR_NOT_INIT;
    const int result = session->backend_session->set_rate(rate);
    if (result != SEEKER_OK) return result;
    const BackendPlaybackState state = session->backend_session->snapshot();
    session->rate = state.rate;
    dispatch_session_event_locked(
        *runtime,
        *session,
        build_basic_event("session.rateChanged", session->status, session->position_ms,
                          "\"rate\":" + std::to_string(rate))
    );
    return SEEKER_OK;
}

int RuntimeManager::session_set_volume(
    int32_t runtime_id,
    int32_t session_id,
    double volume
) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* session = find_session_locked(runtime_id, session_id);
    auto* runtime = find_runtime_locked(runtime_id);
    if (!session || !runtime) return SEEKER_ERROR_INVALID;
    if (session->backend_session == nullptr) return SEEKER_ERROR_NOT_INIT;
    const int result = session->backend_session->set_volume(volume);
    if (result != SEEKER_OK) return result;
    const BackendPlaybackState state = session->backend_session->snapshot();
    session->volume = state.volume;
    dispatch_session_event_locked(
        *runtime,
        *session,
        build_basic_event("session.volumeChanged", session->status, session->position_ms,
                          "\"volume\":" + std::to_string(volume))
    );
    return SEEKER_OK;
}

int RuntimeManager::session_select_track(
    int32_t runtime_id,
    int32_t session_id,
    const std::string& track_id
) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* session = find_session_locked(runtime_id, session_id);
    auto* runtime = find_runtime_locked(runtime_id);
    if (!session || !runtime) return SEEKER_ERROR_INVALID;
    if (session->backend_session == nullptr) return SEEKER_ERROR_NOT_INIT;
    const int result = session->backend_session->select_track(track_id);
    if (result != SEEKER_OK) return result;
    dispatch_session_event_locked(
        *runtime,
        *session,
        build_basic_event("session.trackSelected", session->status, session->position_ms,
                          "\"trackId\":\"" + json::escape(track_id) + "\"")
    );
    return SEEKER_OK;
}

int RuntimeManager::session_select_variant(
    int32_t runtime_id,
    int32_t session_id,
    const std::string& variant_id
) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* session = find_session_locked(runtime_id, session_id);
    auto* runtime = find_runtime_locked(runtime_id);
    if (!session || !runtime) return SEEKER_ERROR_INVALID;
    if (session->backend_session == nullptr) return SEEKER_ERROR_NOT_INIT;
    const int result = session->backend_session->select_variant(variant_id);
    if (result != SEEKER_OK) return result;
    dispatch_session_event_locked(
        *runtime,
        *session,
        build_basic_event("session.variantSelected", session->status, session->position_ms,
                          "\"variantId\":\"" + json::escape(variant_id) + "\"")
    );
    return SEEKER_OK;
}

std::string RuntimeManager::build_download_plan(
    int32_t runtime_id,
    const std::string& resolved_media_json,
    const std::string& options_json
) const {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto* runtime = find_runtime_locked(runtime_id);
    if (!runtime) {
        return "{\"error\":\"runtime not found\"}";
    }
    return download_planner_.build_plan_json(runtime_id, resolved_media_json, options_json);
}

int32_t RuntimeManager::download_start(
    int32_t runtime_id,
    const std::string& download_plan_json
) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* runtime = find_runtime_locked(runtime_id);
    if (!runtime) return SEEKER_ERROR_INVALID;
    const int32_t download_id = runtime->next_download_id.fetch_add(1);
    const DownloadPlanData plan = download_planner_.parse_plan_json(download_plan_json);
    if (plan.media_id.empty() || plan.primary_url.empty()) {
        return SEEKER_ERROR_INVALID;
    }
    return runtime->transfer_manager.start_download(download_id, plan);
}

int RuntimeManager::download_pause(int32_t runtime_id, int32_t download_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* runtime = find_runtime_locked(runtime_id);
    if (!runtime || download_id <= 0) return SEEKER_ERROR_INVALID;
    return runtime->transfer_manager.pause_download(download_id);
}

int RuntimeManager::download_resume(int32_t runtime_id, int32_t download_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* runtime = find_runtime_locked(runtime_id);
    if (!runtime || download_id <= 0) return SEEKER_ERROR_INVALID;
    return runtime->transfer_manager.resume_download(download_id);
}

int RuntimeManager::download_cancel(int32_t runtime_id, int32_t download_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* runtime = find_runtime_locked(runtime_id);
    if (!runtime || download_id <= 0) return SEEKER_ERROR_INVALID;
    return runtime->transfer_manager.cancel_download(download_id);
}

std::string RuntimeManager::query_asset(
    int32_t runtime_id,
    const std::string& media_id
) const {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto* runtime = find_runtime_locked(runtime_id);
    if (!runtime) {
        return "{\"error\":\"runtime not found\"}";
    }
    return runtime->asset_catalog.query_asset_json(media_id);
}

std::string RuntimeManager::list_assets(
    int32_t runtime_id,
    const std::string& filter_json
) const {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto* runtime = find_runtime_locked(runtime_id);
    if (!runtime) {
        return "{\"error\":\"runtime not found\"}";
    }
    return runtime->asset_catalog.list_assets_json(filter_json);
}

std::string RuntimeManager::list_downloads(
    int32_t runtime_id,
    const std::string& filter_json
) const {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto* runtime = find_runtime_locked(runtime_id);
    if (!runtime) {
        return "{\"error\":\"runtime not found\"}";
    }
    return runtime->asset_catalog.list_downloads_json(filter_json);
}

int RuntimeManager::evict_asset(int32_t runtime_id, const std::string& asset_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto* runtime = find_runtime_locked(runtime_id);
    if (!runtime || asset_id.empty()) return SEEKER_ERROR_INVALID;
    return runtime->asset_catalog.evict_asset(asset_id);
}

RuntimeInstance* RuntimeManager::find_runtime_locked(int32_t runtime_id) {
    const auto it = runtimes_.find(runtime_id);
    if (it == runtimes_.end()) return nullptr;
    return it->second.get();
}

const RuntimeInstance* RuntimeManager::find_runtime_locked(int32_t runtime_id) const {
    const auto it = runtimes_.find(runtime_id);
    if (it == runtimes_.end()) return nullptr;
    return it->second.get();
}

RuntimeSession* RuntimeManager::find_session_locked(int32_t runtime_id, int32_t session_id) {
    auto* runtime = find_runtime_locked(runtime_id);
    if (!runtime) return nullptr;
    const auto it = runtime->sessions.find(session_id);
    if (it == runtime->sessions.end()) return nullptr;
    return &it->second;
}

void RuntimeManager::dispatch_session_event_locked(
    RuntimeInstance& runtime,
    RuntimeSession& session,
    const std::string& event_json
) {
    if (session.callback == nullptr) return;
    session.callback(runtime.runtime_id, session.session_id, event_json.c_str());
}

} // namespace seeker
