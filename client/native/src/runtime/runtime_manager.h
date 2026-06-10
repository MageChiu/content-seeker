#ifndef SEEKER_RUNTIME_MANAGER_H
#define SEEKER_RUNTIME_MANAGER_H

#include "../../include/seeker/player.h"
#include "asset_catalog.h"
#include "cache_store.h"
#include "download_planner.h"
#include "transfer_manager.h"
#include "../player/backend_adapter.h"

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <memory>
#include <unordered_map>

namespace seeker {

struct RuntimeSession {
    int32_t session_id = 0;
    seeker_runtime_event_callback callback = nullptr;
    std::string last_media_json;
    std::string status = "idle";
    int64_t position_ms = 0;
    double rate = 1.0;
    double volume = 100.0;
    std::unique_ptr<PlayerBackendSession> backend_session;
};

struct RuntimeInstance {
    int32_t runtime_id = 0;
    std::string config_json;
    std::atomic<int32_t> next_session_id{1};
    std::atomic<int32_t> next_download_id{1};
    std::unordered_map<int32_t, RuntimeSession> sessions;
    CacheStore cache_store;
    AssetCatalog asset_catalog;
    TransferManager transfer_manager;
    std::unique_ptr<BackendAdapter> backend_adapter;
};

class RuntimeManager {
public:
    static RuntimeManager& instance();

    int32_t create_runtime(const std::string& config_json);
    void destroy_runtime(int32_t runtime_id);

    int32_t create_session(int32_t runtime_id, seeker_runtime_event_callback callback);
    int dispose_session(int32_t runtime_id, int32_t session_id);

    std::string resolve_media(int32_t runtime_id, const std::string& request_json) const;
    int session_open(int32_t runtime_id, int32_t session_id, const std::string& resolved_media_json);
    int session_play(int32_t runtime_id, int32_t session_id);
    int session_pause(int32_t runtime_id, int32_t session_id);
    int session_seek(int32_t runtime_id, int32_t session_id, int64_t position_ms);
    int session_set_rate(int32_t runtime_id, int32_t session_id, double rate);
    int session_set_volume(int32_t runtime_id, int32_t session_id, double volume);
    int session_select_track(int32_t runtime_id, int32_t session_id, const std::string& track_id);
    int session_select_variant(int32_t runtime_id, int32_t session_id, const std::string& variant_id);

    std::string build_download_plan(
        int32_t runtime_id,
        const std::string& resolved_media_json,
        const std::string& options_json
    ) const;
    int32_t download_start(int32_t runtime_id, const std::string& download_plan_json);
    int download_pause(int32_t runtime_id, int32_t download_id);
    int download_resume(int32_t runtime_id, int32_t download_id);
    int download_cancel(int32_t runtime_id, int32_t download_id);

    std::string query_asset(int32_t runtime_id, const std::string& media_id) const;
    std::string list_assets(int32_t runtime_id, const std::string& filter_json) const;
    std::string list_downloads(int32_t runtime_id, const std::string& filter_json) const;
    int evict_asset(int32_t runtime_id, const std::string& asset_id);

private:
    RuntimeManager() = default;

    RuntimeInstance* find_runtime_locked(int32_t runtime_id);
    const RuntimeInstance* find_runtime_locked(int32_t runtime_id) const;
    RuntimeSession* find_session_locked(int32_t runtime_id, int32_t session_id);
    void dispatch_session_event_locked(
        RuntimeInstance& runtime,
        RuntimeSession& session,
        const std::string& event_json
    );

    DownloadPlanner download_planner_;
    mutable std::mutex mutex_;
    std::atomic<int32_t> next_runtime_id_{1};
    std::unordered_map<int32_t, std::unique_ptr<RuntimeInstance>> runtimes_;
};

} // namespace seeker

#endif // SEEKER_RUNTIME_MANAGER_H
