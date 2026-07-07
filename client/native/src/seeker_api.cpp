/// libseeker 对外 C API 实现
/// 此文件是 dart:ffi 的直接调用入口

#include "seeker/seeker.h"
#include "seeker/extractor.h"
#include "seeker/player.h"
#include "core/seeker_context.h"
#include "core/thread_pool.h"
#include "core/callback_dispatcher.h"
#include "runtime/runtime_manager.h"
#include "extractor/extractor_registry.h"
#include "extractor/plugins/bilibili_plugin.h"
#include "extractor/plugins/youtube_plugin.h"
#include "utils/json_utils.h"

#include <string>
#include <memory>
#include <atomic>
#include <cstring>
#include <cstdlib>

static const char* SEEKER_VERSION = "0.3.0";

static char* seeker_strdup(const char* str) {
    if (!str) {
        return nullptr;
    }

#if defined(_WIN32)
    return _strdup(str);
#else
    return strdup(str);
#endif
}

// 全局线程池（在 init 时创建）
static std::unique_ptr<seeker::ThreadPool> g_thread_pool;

// 注册所有内置提取器插件
static void register_builtin_plugins() {
    auto& registry = seeker::ExtractorRegistry::instance();
    registry.register_plugin(std::make_unique<seeker::BilibiliPlugin>());
    registry.register_plugin(std::make_unique<seeker::YouTubePlugin>());
}

// ===== 生命周期 =====

int seeker_init(const char* config_json) {
    auto& ctx = seeker::SeekerContext::instance();
    std::string config = config_json ? config_json : "{}";

    if (!ctx.init(config)) {
        return SEEKER_ERROR_INVALID;
    }

    // 创建线程池
    if (!g_thread_pool) {
        g_thread_pool = std::make_unique<seeker::ThreadPool>(4);
    }

    // 注册内置插件
    register_builtin_plugins();

    return SEEKER_OK;
}

void seeker_destroy(void) {
    if (g_thread_pool) {
        g_thread_pool->shutdown();
        g_thread_pool.reset();
    }
    seeker::SeekerContext::instance().destroy();
}

const char* seeker_version(void) {
    return SEEKER_VERSION;
}

int seeker_is_initialized(void) {
    return seeker::SeekerContext::instance().is_initialized() ? 1 : 0;
}

// ===== 流提取 =====

int32_t seeker_extract_stream(
    const char* url,
    const char* options_json,
    seeker_extract_callback callback
) {
    if (!seeker::SeekerContext::instance().is_initialized()) {
        return SEEKER_ERROR_NOT_INIT;
    }
    if (!url || !callback) {
        return SEEKER_ERROR_INVALID;
    }

    std::string url_str(url);
    std::string options = options_json ? options_json : "{}";

    // 生成请求 ID
    static std::atomic<int32_t> s_next_id{1};
    int32_t request_id = s_next_id.fetch_add(1);

    // 异步执行提取
    g_thread_pool->submit([url_str, options, request_id, callback]() {
        auto* plugin = seeker::ExtractorRegistry::instance().find_plugin(url_str);
        if (!plugin) {
            // 使用 strdup 分配持久内存，确保回调跨线程安全
            char* err = seeker_strdup("no suitable extractor plugin found");
            callback(request_id, nullptr, err);
            free(err);
            return;
        }

        try {
            std::string result = plugin->extract(url_str, options);
            char* result_copy = seeker_strdup(result.c_str());
            callback(request_id, result_copy, nullptr);
            free(result_copy);
        } catch (const std::exception& e) {
            char* err = seeker_strdup(e.what());
            callback(request_id, nullptr, err);
            free(err);
        }
    });

    return request_id;
}

void seeker_cancel_extract(int32_t request_id) {
    seeker::CallbackDispatcher::instance().cancel(request_id);
}

char* seeker_extract_stream_sync(
    const char* url,
    const char* options_json
) {
    if (!seeker::SeekerContext::instance().is_initialized()) {
        // 返回错误 JSON 而非 nullptr，便于调试
        return seeker_strdup("{\"error\":\"libseeker not initialized\"}");
    }
    if (!url) {
        return seeker_strdup("{\"error\":\"url is null\"}");
    }

    std::string url_str(url);
    std::string options = options_json ? options_json : "{}";

    auto* plugin = seeker::ExtractorRegistry::instance().find_plugin(url_str);
    if (!plugin) {
        return seeker_strdup("{\"error\":\"no suitable extractor plugin found\"}");
    }

    try {
        std::string result = plugin->extract(url_str, options);
        return seeker_strdup(result.c_str());
    } catch (const std::exception& e) {
        std::string err = "{\"error\":\"" + seeker::json::escape(e.what()) + "\"}";
        return seeker_strdup(err.c_str());
    }
}

void seeker_free_string(char* str) {
    if (str) {
        free(str);
    }
}

const char* seeker_get_supported_sites(void) {
    static std::string sites_cache;
    auto names = seeker::ExtractorRegistry::instance().get_plugin_names();
    sites_cache = "[";
    for (size_t i = 0; i < names.size(); ++i) {
        if (i > 0) sites_cache += ",";
        sites_cache += "\"" + names[i] + "\"";
    }
    sites_cache += "]";
    return sites_cache.c_str();
}

// ===== Runtime / 播放控制 =====

int32_t seeker_runtime_create(const char* config_json) {
    if (!seeker::SeekerContext::instance().is_initialized()) {
        return SEEKER_ERROR_NOT_INIT;
    }
    return seeker::RuntimeManager::instance().create_runtime(
        config_json ? config_json : "{}"
    );
}

void seeker_runtime_destroy(int32_t runtime_id) {
    seeker::RuntimeManager::instance().destroy_runtime(runtime_id);
}

int32_t seeker_session_create(
    int32_t runtime_id,
    seeker_runtime_event_callback callback
) {
    if (!seeker::SeekerContext::instance().is_initialized()) {
        return SEEKER_ERROR_NOT_INIT;
    }
    return seeker::RuntimeManager::instance().create_session(runtime_id, callback);
}

int seeker_session_dispose(int32_t runtime_id, int32_t session_id) {
    return seeker::RuntimeManager::instance().dispose_session(runtime_id, session_id);
}

char* seeker_resolve_media(
    int32_t runtime_id,
    const char* request_json
) {
    if (!seeker::SeekerContext::instance().is_initialized()) {
        return seeker_strdup("{\"error\":\"libseeker not initialized\"}");
    }
    if (!request_json) {
        return seeker_strdup("{\"error\":\"request_json is null\"}");
    }
    const std::string result = seeker::RuntimeManager::instance().resolve_media(
        runtime_id,
        request_json
    );
    return seeker_strdup(result.c_str());
}

int seeker_session_open(
    int32_t runtime_id,
    int32_t session_id,
    const char* resolved_media_json
) {
    if (!resolved_media_json) return SEEKER_ERROR_INVALID;
    return seeker::RuntimeManager::instance().session_open(
        runtime_id,
        session_id,
        resolved_media_json
    );
}

int seeker_session_play(int32_t runtime_id, int32_t session_id) {
    return seeker::RuntimeManager::instance().session_play(runtime_id, session_id);
}

int seeker_session_pause(int32_t runtime_id, int32_t session_id) {
    return seeker::RuntimeManager::instance().session_pause(runtime_id, session_id);
}

int seeker_session_seek(
    int32_t runtime_id,
    int32_t session_id,
    int64_t position_ms
) {
    return seeker::RuntimeManager::instance().session_seek(
        runtime_id,
        session_id,
        position_ms
    );
}

int seeker_session_set_rate(
    int32_t runtime_id,
    int32_t session_id,
    double rate
) {
    return seeker::RuntimeManager::instance().session_set_rate(
        runtime_id,
        session_id,
        rate
    );
}

int seeker_session_set_volume(
    int32_t runtime_id,
    int32_t session_id,
    double volume
) {
    return seeker::RuntimeManager::instance().session_set_volume(
        runtime_id,
        session_id,
        volume
    );
}

int seeker_session_select_track(
    int32_t runtime_id,
    int32_t session_id,
    const char* track_id
) {
    if (!track_id) return SEEKER_ERROR_INVALID;
    return seeker::RuntimeManager::instance().session_select_track(
        runtime_id,
        session_id,
        track_id
    );
}

int seeker_session_select_variant(
    int32_t runtime_id,
    int32_t session_id,
    const char* variant_id
) {
    if (!variant_id) return SEEKER_ERROR_INVALID;
    return seeker::RuntimeManager::instance().session_select_variant(
        runtime_id,
        session_id,
        variant_id
    );
}

char* seeker_build_download_plan(
    int32_t runtime_id,
    const char* resolved_media_json,
    const char* options_json
) {
    if (!resolved_media_json) {
        return seeker_strdup("{\"error\":\"resolved_media_json is null\"}");
    }
    const std::string result = seeker::RuntimeManager::instance().build_download_plan(
        runtime_id,
        resolved_media_json,
        options_json ? options_json : "{}"
    );
    return seeker_strdup(result.c_str());
}

int32_t seeker_download_start(
    int32_t runtime_id,
    const char* download_plan_json
) {
    if (!download_plan_json) return SEEKER_ERROR_INVALID;
    return seeker::RuntimeManager::instance().download_start(runtime_id, download_plan_json);
}

int seeker_download_pause(int32_t runtime_id, int32_t download_id) {
    return seeker::RuntimeManager::instance().download_pause(runtime_id, download_id);
}

int seeker_download_resume(int32_t runtime_id, int32_t download_id) {
    return seeker::RuntimeManager::instance().download_resume(runtime_id, download_id);
}

int seeker_download_cancel(int32_t runtime_id, int32_t download_id) {
    return seeker::RuntimeManager::instance().download_cancel(runtime_id, download_id);
}

char* seeker_query_asset(
    int32_t runtime_id,
    const char* media_id
) {
    if (!media_id) return seeker_strdup("{\"error\":\"media_id is null\"}");
    const std::string result = seeker::RuntimeManager::instance().query_asset(
        runtime_id,
        media_id
    );
    return seeker_strdup(result.c_str());
}

char* seeker_list_assets(
    int32_t runtime_id,
    const char* filter_json
) {
    const std::string result = seeker::RuntimeManager::instance().list_assets(
        runtime_id,
        filter_json ? filter_json : "{}"
    );
    return seeker_strdup(result.c_str());
}

char* seeker_list_downloads(
    int32_t runtime_id,
    const char* filter_json
) {
    const std::string result = seeker::RuntimeManager::instance().list_downloads(
        runtime_id,
        filter_json ? filter_json : "{}"
    );
    return seeker_strdup(result.c_str());
}

int seeker_evict_asset(
    int32_t runtime_id,
    const char* asset_id
) {
    if (!asset_id) return SEEKER_ERROR_INVALID;
    return seeker::RuntimeManager::instance().evict_asset(runtime_id, asset_id);
}
