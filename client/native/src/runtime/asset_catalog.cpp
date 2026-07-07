#include "asset_catalog.h"

#include "../utils/json_utils.h"
#include "../../include/seeker/seeker.h"

#include <chrono>
#include <ctime>
#include <fstream>
#include <iomanip>
#include <sstream>

namespace seeker {

namespace {

std::string status_to_asset_completeness(const std::string& status) {
    return status == "completed" ? "full" : "partial";
}

std::string status_to_storage_kind(const std::string& status) {
    return status == "completed" ? "offline" : "cache";
}

} // namespace

void AssetCatalog::configure(CacheStore* cache_store) {
    std::lock_guard<std::mutex> lock(mutex_);
    cache_store_ = cache_store;
    load_from_disk();
}

int32_t AssetCatalog::start_download(int32_t download_id, const DownloadPlanData& plan) {
    std::lock_guard<std::mutex> lock(mutex_);
    const std::string timestamp = now_iso8601();
    std::string asset_id;

    const auto existing_asset_it = asset_id_by_media_id_.find(plan.media_id);
    if (existing_asset_it != asset_id_by_media_id_.end()) {
        asset_id = existing_asset_it->second;
        auto& existing_asset = assets_by_id_[asset_id];
        existing_asset.updated_at = timestamp;
        existing_asset.storage_kind = "cache";
        existing_asset.completeness = "partial";
        existing_asset.primary_file_path = plan.save_path;
        existing_asset.mime_type = plan.mime_type;
    } else {
        asset_id = "asset-" + std::to_string(download_id);
        RuntimeAssetRecord asset;
        asset.asset_id = asset_id;
        asset.media_id = plan.media_id;
        asset.source_id = plan.source_id;
        asset.title = plan.title;
        asset.storage_kind = "cache";
        asset.completeness = "partial";
        asset.primary_file_path = plan.save_path;
        asset.mime_type = plan.mime_type;
        asset.created_at = timestamp;
        asset.updated_at = timestamp;
        assets_by_id_.emplace(asset_id, asset);
        asset_id_by_media_id_[plan.media_id] = asset_id;
    }

    RuntimeDownloadRecord record;
    record.download_id = download_id;
    record.task_id = "runtime-download-" + std::to_string(download_id);
    record.asset_id = asset_id;
    record.media_id = plan.media_id;
    record.source_id = plan.source_id;
    record.filename = plan.filename;
    record.save_path = plan.save_path;
    record.primary_url = plan.primary_url;
    record.status = "running";
    record.supports_resume = plan.supports_resume;
    record.created_at = timestamp;
    record.updated_at = timestamp;
    downloads_[download_id] = record;
    persist_to_disk();
    return download_id;
}

int AssetCatalog::pause_download(int32_t download_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = downloads_.find(download_id);
    if (it == downloads_.end()) return SEEKER_ERROR_INVALID;
    it->second.status = "paused";
    it->second.updated_at = now_iso8601();
    persist_to_disk();
    return SEEKER_OK;
}

int AssetCatalog::resume_download(int32_t download_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = downloads_.find(download_id);
    if (it == downloads_.end()) return SEEKER_ERROR_INVALID;
    it->second.status = "running";
    it->second.updated_at = now_iso8601();
    persist_to_disk();
    return SEEKER_OK;
}

int AssetCatalog::cancel_download(int32_t download_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = downloads_.find(download_id);
    if (it == downloads_.end()) return SEEKER_ERROR_INVALID;
    it->second.status = "canceled";
    it->second.updated_at = now_iso8601();

    const auto asset_it = assets_by_id_.find(it->second.asset_id);
    if (asset_it != assets_by_id_.end()) {
        asset_it->second.storage_kind = status_to_storage_kind(it->second.status);
        asset_it->second.completeness = status_to_asset_completeness(it->second.status);
        asset_it->second.updated_at = it->second.updated_at;
    }
    persist_to_disk();
    return SEEKER_OK;
}

int AssetCatalog::complete_download(int32_t download_id, int64_t bytes_total) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = downloads_.find(download_id);
    if (it == downloads_.end()) return SEEKER_ERROR_INVALID;

    it->second.status = "completed";
    it->second.bytes_downloaded = bytes_total;
    it->second.total_bytes = bytes_total;
    it->second.last_error.clear();
    it->second.updated_at = now_iso8601();

    const auto asset_it = assets_by_id_.find(it->second.asset_id);
    if (asset_it != assets_by_id_.end()) {
        asset_it->second.storage_kind = "offline";
        asset_it->second.completeness = "full";
        asset_it->second.bytes_total = bytes_total;
        asset_it->second.bytes_ready = bytes_total;
        asset_it->second.updated_at = it->second.updated_at;
    }
    persist_to_disk();
    return SEEKER_OK;
}

int AssetCatalog::fail_download(int32_t download_id, const std::string& error_message) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = downloads_.find(download_id);
    if (it == downloads_.end()) return SEEKER_ERROR_INVALID;

    it->second.status = "failed";
    it->second.last_error = error_message;
    it->second.updated_at = now_iso8601();

    const auto asset_it = assets_by_id_.find(it->second.asset_id);
    if (asset_it != assets_by_id_.end()) {
        asset_it->second.storage_kind = "cache";
        asset_it->second.completeness = "partial";
        asset_it->second.bytes_total = it->second.total_bytes;
        asset_it->second.bytes_ready = it->second.bytes_downloaded;
        asset_it->second.updated_at = it->second.updated_at;
    }
    persist_to_disk();
    return SEEKER_OK;
}

int AssetCatalog::update_download_progress(int32_t download_id, int64_t bytes_downloaded, int64_t total_bytes) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = downloads_.find(download_id);
    if (it == downloads_.end()) return SEEKER_ERROR_INVALID;

    it->second.bytes_downloaded = bytes_downloaded;
    it->second.total_bytes = total_bytes;
    it->second.updated_at = now_iso8601();

    const auto asset_it = assets_by_id_.find(it->second.asset_id);
    if (asset_it != assets_by_id_.end()) {
        asset_it->second.bytes_total = total_bytes;
        asset_it->second.bytes_ready = bytes_downloaded;
        asset_it->second.updated_at = it->second.updated_at;
    }
    persist_to_disk();
    return SEEKER_OK;
}

std::string AssetCatalog::query_asset_json(const std::string& media_id) const {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto id_it = asset_id_by_media_id_.find(media_id);
    if (id_it == asset_id_by_media_id_.end()) {
        std::ostringstream ss;
        ss << "{";
        ss << "\"found\":false";
        ss << ",\"mediaId\":\"" << json::escape(media_id) << "\"";
        ss << "}";
        return ss.str();
    }

    const auto asset_it = assets_by_id_.find(id_it->second);
    if (asset_it == assets_by_id_.end()) {
        std::ostringstream ss;
        ss << "{";
        ss << "\"found\":false";
        ss << ",\"mediaId\":\"" << json::escape(media_id) << "\"";
        ss << "}";
        return ss.str();
    }

    std::ostringstream ss;
    ss << "{";
    ss << "\"found\":true";
    ss << ",\"asset\":" << build_asset_json(asset_it->second);
    ss << "}";
    return ss.str();
}

std::string AssetCatalog::list_assets_json(const std::string& filter_json) const {
    std::lock_guard<std::mutex> lock(mutex_);
    const std::string storage_kind_filter = json::get_string(filter_json, "storageKind");
    std::ostringstream ss;
    ss << "{";
    ss << "\"items\":[";
    bool first = true;
    for (const auto& [asset_id, asset] : assets_by_id_) {
        if (!storage_kind_filter.empty() && asset.storage_kind != storage_kind_filter) {
            continue;
        }
        if (!first) ss << ",";
        first = false;
        ss << build_asset_json(asset);
    }
    ss << "]";
    ss << "}";
    return ss.str();
}

std::string AssetCatalog::list_downloads_json(const std::string& filter_json) const {
    std::lock_guard<std::mutex> lock(mutex_);
    const std::string status_filter = json::get_string(filter_json, "status");
    std::ostringstream ss;
    ss << "{";
    ss << "\"items\":[";
    bool first = true;
    for (const auto& [download_id, download] : downloads_) {
        if (!status_filter.empty() && download.status != status_filter) {
            continue;
        }
        if (!first) ss << ",";
        first = false;
        ss << build_download_json(download);
    }
    ss << "]";
    ss << "}";
    return ss.str();
}

int AssetCatalog::evict_asset(const std::string& asset_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto it = assets_by_id_.find(asset_id);
    if (it == assets_by_id_.end()) return SEEKER_ERROR_INVALID;
    asset_id_by_media_id_.erase(it->second.media_id);
    assets_by_id_.erase(it);
    persist_to_disk();
    return SEEKER_OK;
}

void AssetCatalog::load_from_disk() {
    assets_by_id_.clear();
    asset_id_by_media_id_.clear();
    downloads_.clear();
    if (cache_store_ == nullptr) return;

    {
        std::ifstream input(cache_store_->assets_metadata_path());
        std::string line;
        while (std::getline(input, line)) {
            if (line.empty()) continue;
            const RuntimeAssetRecord asset = parse_asset_record(line);
            if (asset.asset_id.empty() || asset.media_id.empty()) continue;
            assets_by_id_[asset.asset_id] = asset;
            asset_id_by_media_id_[asset.media_id] = asset.asset_id;
        }
    }

    {
        std::ifstream input(cache_store_->downloads_metadata_path());
        std::string line;
        while (std::getline(input, line)) {
            if (line.empty()) continue;
            const RuntimeDownloadRecord download = parse_download_record(line);
            if (download.download_id <= 0) continue;
            downloads_[download.download_id] = download;
        }
    }
}

void AssetCatalog::persist_to_disk() const {
    if (cache_store_ == nullptr) return;

    {
        std::ofstream output(cache_store_->assets_metadata_path(), std::ios::trunc);
        for (const auto& [asset_id, asset] : assets_by_id_) {
            output << build_asset_json(asset) << "\n";
        }
    }

    {
        std::ofstream output(cache_store_->downloads_metadata_path(), std::ios::trunc);
        for (const auto& [download_id, download] : downloads_) {
            output << build_download_json(download) << "\n";
        }
    }
}

std::string AssetCatalog::now_iso8601() const {
    using namespace std::chrono;
    const auto now = system_clock::now();
    const std::time_t now_time = system_clock::to_time_t(now);
    std::tm tm{};
#if defined(_WIN32)
    gmtime_s(&tm, &now_time);
#else
    gmtime_r(&now_time, &tm);
#endif
    std::ostringstream ss;
    ss << std::put_time(&tm, "%Y-%m-%dT%H:%M:%SZ");
    return ss.str();
}

std::string AssetCatalog::build_asset_json(const RuntimeAssetRecord& asset) const {
    std::ostringstream ss;
    ss << "{";
    ss << "\"assetId\":\"" << json::escape(asset.asset_id) << "\"";
    ss << ",\"mediaId\":\"" << json::escape(asset.media_id) << "\"";
    ss << ",\"sourceId\":\"" << json::escape(asset.source_id) << "\"";
    ss << ",\"title\":\"" << json::escape(asset.title) << "\"";
    ss << ",\"storageKind\":\"" << json::escape(asset.storage_kind) << "\"";
    ss << ",\"completeness\":\"" << json::escape(asset.completeness) << "\"";
    ss << ",\"manifestPath\":\"" << json::escape(asset.manifest_path) << "\"";
    ss << ",\"primaryFilePath\":\"" << json::escape(asset.primary_file_path) << "\"";
    ss << ",\"auxiliaryFiles\":[]";
    ss << ",\"mimeType\":\"" << json::escape(asset.mime_type) << "\"";
    ss << ",\"bytesTotal\":" << asset.bytes_total;
    ss << ",\"bytesReady\":" << asset.bytes_ready;
    ss << ",\"createdAt\":\"" << json::escape(asset.created_at) << "\"";
    ss << ",\"updatedAt\":\"" << json::escape(asset.updated_at) << "\"";
    ss << "}";
    return ss.str();
}

std::string AssetCatalog::build_download_json(const RuntimeDownloadRecord& download) const {
    std::ostringstream ss;
    ss << "{";
    ss << "\"downloadId\":" << download.download_id;
    ss << ",\"taskId\":\"" << json::escape(download.task_id) << "\"";
    ss << ",\"assetId\":\"" << json::escape(download.asset_id) << "\"";
    ss << ",\"mediaId\":\"" << json::escape(download.media_id) << "\"";
    ss << ",\"sourceId\":\"" << json::escape(download.source_id) << "\"";
    ss << ",\"filename\":\"" << json::escape(download.filename) << "\"";
    ss << ",\"savePath\":\"" << json::escape(download.save_path) << "\"";
    ss << ",\"primaryUrl\":\"" << json::escape(download.primary_url) << "\"";
    ss << ",\"status\":\"" << json::escape(download.status) << "\"";
    ss << ",\"supportsResume\":" << (download.supports_resume ? "true" : "false");
    ss << ",\"bytesDownloaded\":" << download.bytes_downloaded;
    ss << ",\"totalBytes\":" << download.total_bytes;
    ss << ",\"createdAt\":\"" << json::escape(download.created_at) << "\"";
    ss << ",\"updatedAt\":\"" << json::escape(download.updated_at) << "\"";
    ss << ",\"lastError\":\"" << json::escape(download.last_error) << "\"";
    ss << "}";
    return ss.str();
}

RuntimeAssetRecord AssetCatalog::parse_asset_record(const std::string& line) const {
    RuntimeAssetRecord asset;
    asset.asset_id = json::get_string(line, "assetId");
    asset.media_id = json::get_string(line, "mediaId");
    asset.source_id = json::get_string(line, "sourceId");
    asset.title = json::get_string(line, "title");
    asset.storage_kind = json::get_string(line, "storageKind");
    asset.completeness = json::get_string(line, "completeness");
    asset.manifest_path = json::get_string(line, "manifestPath");
    asset.primary_file_path = json::get_string(line, "primaryFilePath");
    asset.mime_type = json::get_string(line, "mimeType");
    asset.bytes_total = json::get_int64(line, "bytesTotal");
    asset.bytes_ready = json::get_int64(line, "bytesReady");
    asset.created_at = json::get_string(line, "createdAt");
    asset.updated_at = json::get_string(line, "updatedAt");
    return asset;
}

RuntimeDownloadRecord AssetCatalog::parse_download_record(const std::string& line) const {
    RuntimeDownloadRecord download;
    download.download_id = json::get_int(line, "downloadId");
    download.task_id = json::get_string(line, "taskId");
    download.asset_id = json::get_string(line, "assetId");
    download.media_id = json::get_string(line, "mediaId");
    download.source_id = json::get_string(line, "sourceId");
    download.filename = json::get_string(line, "filename");
    download.save_path = json::get_string(line, "savePath");
    download.primary_url = json::get_string(line, "primaryUrl");
    download.status = json::get_string(line, "status");
    download.supports_resume = json::get_string(line, "supportsResume") != "false";
    download.bytes_downloaded = json::get_int64(line, "bytesDownloaded");
    download.total_bytes = json::get_int64(line, "totalBytes");
    download.created_at = json::get_string(line, "createdAt");
    download.updated_at = json::get_string(line, "updatedAt");
    download.last_error = json::get_string(line, "lastError");
    return download;
}

} // namespace seeker
