/// libseeker 对外 C API 实现
/// 此文件是 dart:ffi 的直接调用入口

#include "seeker/seeker.h"
#include "seeker/extractor.h"
#include "seeker/player.h"
#include "core/seeker_context.h"
#include "core/thread_pool.h"
#include "core/callback_dispatcher.h"
#include "extractor/extractor_registry.h"
#include "extractor/plugins/bilibili_plugin.h"
#include "extractor/plugins/youtube_plugin.h"
#include "utils/json_utils.h"

#include <string>
#include <memory>
#include <atomic>
#include <cstring>
#include <cstdlib>

static const char* SEEKER_VERSION = "0.2.0";

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

// ===== 播放控制 (Phase 4 实现，当前提供桩) =====

int32_t seeker_player_create(seeker_player_event_callback callback) {
    (void)callback;
    return SEEKER_ERROR_NOT_INIT; // 暂未实现
}

int seeker_player_open(int32_t player_id, const char* stream_json) {
    (void)player_id; (void)stream_json;
    return SEEKER_ERROR_NOT_INIT;
}

int seeker_player_play(int32_t player_id) {
    (void)player_id;
    return SEEKER_ERROR_NOT_INIT;
}

int seeker_player_pause(int32_t player_id) {
    (void)player_id;
    return SEEKER_ERROR_NOT_INIT;
}

int seeker_player_seek(int32_t player_id, double position_seconds) {
    (void)player_id; (void)position_seconds;
    return SEEKER_ERROR_NOT_INIT;
}

int seeker_player_set_rate(int32_t player_id, double rate) {
    (void)player_id; (void)rate;
    return SEEKER_ERROR_NOT_INIT;
}

void seeker_player_destroy(int32_t player_id) {
    (void)player_id;
}
