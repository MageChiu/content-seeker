#ifndef SEEKER_TRANSFER_MANAGER_H
#define SEEKER_TRANSFER_MANAGER_H

#include "asset_catalog.h"
#include "cache_store.h"
#include "download_planner.h"

#include <cstdint>
#include <mutex>
#include <string>
#include <unordered_map>

namespace seeker {

struct TransferJobRecord {
    int32_t download_id = 0;
    std::string media_id;
    std::string target_path;
    std::string status = "queued";
};

class TransferManager {
public:
    void configure(CacheStore* cache_store, AssetCatalog* asset_catalog);

    int32_t start_download(int32_t download_id, const DownloadPlanData& plan);
    int pause_download(int32_t download_id);
    int resume_download(int32_t download_id);
    int cancel_download(int32_t download_id);

private:
    int run_download(int32_t download_id, const DownloadPlanData& plan);
    int write_response_body(const std::string& target_path, const std::string& body) const;
    void mark_job_status(int32_t download_id, const std::string& status);
    std::string resolve_target_path(const DownloadPlanData& plan) const;

    CacheStore* cache_store_ = nullptr;
    AssetCatalog* asset_catalog_ = nullptr;
    mutable std::mutex mutex_;
    std::unordered_map<int32_t, TransferJobRecord> jobs_;
};

} // namespace seeker

#endif // SEEKER_TRANSFER_MANAGER_H
