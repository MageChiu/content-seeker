#ifndef SEEKER_ASSET_CATALOG_H
#define SEEKER_ASSET_CATALOG_H

#include "cache_store.h"
#include "download_planner.h"

#include <cstdint>
#include <mutex>
#include <string>
#include <unordered_map>

namespace seeker {

struct RuntimeAssetRecord {
    std::string asset_id;
    std::string media_id;
    std::string source_id;
    std::string title;
    std::string storage_kind = "cache";
    std::string completeness = "partial";
    std::string manifest_path;
    std::string primary_file_path;
    std::string mime_type;
    int64_t bytes_total = 0;
    int64_t bytes_ready = 0;
    std::string created_at;
    std::string updated_at;
};

struct RuntimeDownloadRecord {
    int32_t download_id = 0;
    std::string task_id;
    std::string asset_id;
    std::string media_id;
    std::string source_id;
    std::string filename;
    std::string save_path;
    std::string primary_url;
    std::string status = "queued";
    bool supports_resume = true;
    int64_t bytes_downloaded = 0;
    int64_t total_bytes = 0;
    std::string created_at;
    std::string updated_at;
    std::string last_error;
};

class AssetCatalog {
public:
    void configure(CacheStore* cache_store);
    int32_t start_download(int32_t download_id, const DownloadPlanData& plan);
    int pause_download(int32_t download_id);
    int resume_download(int32_t download_id);
    int cancel_download(int32_t download_id);
    int complete_download(int32_t download_id, int64_t bytes_total);
    int fail_download(int32_t download_id, const std::string& error_message);
    int update_download_progress(int32_t download_id, int64_t bytes_downloaded, int64_t total_bytes);

    std::string query_asset_json(const std::string& media_id) const;
    std::string list_assets_json(const std::string& filter_json) const;
    std::string list_downloads_json(const std::string& filter_json) const;
    int evict_asset(const std::string& asset_id);

private:
    void load_from_disk();
    void persist_to_disk() const;
    std::string now_iso8601() const;
    std::string build_asset_json(const RuntimeAssetRecord& asset) const;
    std::string build_download_json(const RuntimeDownloadRecord& download) const;
    RuntimeAssetRecord parse_asset_record(const std::string& line) const;
    RuntimeDownloadRecord parse_download_record(const std::string& line) const;

    CacheStore* cache_store_ = nullptr;
    mutable std::mutex mutex_;
    std::unordered_map<std::string, RuntimeAssetRecord> assets_by_id_;
    std::unordered_map<std::string, std::string> asset_id_by_media_id_;
    std::unordered_map<int32_t, RuntimeDownloadRecord> downloads_;
};

} // namespace seeker

#endif // SEEKER_ASSET_CATALOG_H
