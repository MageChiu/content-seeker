#include "transfer_manager.h"

#include "../../include/seeker/seeker.h"
#include "../utils/http_client.h"

#include <filesystem>
#include <fstream>

namespace seeker {

void TransferManager::configure(CacheStore* cache_store, AssetCatalog* asset_catalog) {
    cache_store_ = cache_store;
    asset_catalog_ = asset_catalog;
}

int32_t TransferManager::start_download(int32_t download_id, const DownloadPlanData& plan) {
    if (cache_store_ == nullptr || asset_catalog_ == nullptr) {
        return SEEKER_ERROR_NOT_INIT;
    }

    DownloadPlanData materialized = plan;
    materialized.save_path = resolve_target_path(plan);
    std::filesystem::create_directories(std::filesystem::path(materialized.save_path).parent_path());

    TransferJobRecord job;
    job.download_id = download_id;
    job.media_id = plan.media_id;
    job.target_path = materialized.save_path;
    job.status = "running";
    {
        std::lock_guard<std::mutex> lock(mutex_);
        jobs_[download_id] = job;
    }

    const int started = asset_catalog_->start_download(download_id, materialized);
    if (started < 0) {
        mark_job_status(download_id, "failed");
        return started;
    }

    run_download(download_id, materialized);
    return download_id;
}

int TransferManager::pause_download(int32_t download_id) {
    if (asset_catalog_ == nullptr) return SEEKER_ERROR_NOT_INIT;
    mark_job_status(download_id, "paused");
    return asset_catalog_->pause_download(download_id);
}

int TransferManager::resume_download(int32_t download_id) {
    if (asset_catalog_ == nullptr) return SEEKER_ERROR_NOT_INIT;
    mark_job_status(download_id, "running");
    return asset_catalog_->resume_download(download_id);
}

int TransferManager::cancel_download(int32_t download_id) {
    if (asset_catalog_ == nullptr) return SEEKER_ERROR_NOT_INIT;
    mark_job_status(download_id, "canceled");
    return asset_catalog_->cancel_download(download_id);
}

int TransferManager::run_download(int32_t download_id, const DownloadPlanData& plan) {
    HttpClient client;
    const HttpResponse response = client.get(plan.primary_url, plan.headers);
    if (!response.ok()) {
        const std::string error_message =
            response.body.empty()
                ? ("request failed with status " + std::to_string(response.status_code))
                : response.body;
        mark_job_status(download_id, "failed");
        return asset_catalog_->fail_download(download_id, error_message);
    }

    const int64_t total_bytes = static_cast<int64_t>(response.body.size());
    const int write_result = write_response_body(plan.save_path, response.body);
    if (write_result != SEEKER_OK) {
        std::error_code remove_error;
        std::filesystem::remove(plan.save_path, remove_error);
        mark_job_status(download_id, "failed");
        return asset_catalog_->fail_download(download_id, "failed to write download to disk");
    }

    const int progress_result = asset_catalog_->update_download_progress(
        download_id,
        total_bytes,
        total_bytes
    );
    if (progress_result != SEEKER_OK) {
        mark_job_status(download_id, "failed");
        return progress_result;
    }

    mark_job_status(download_id, "completed");
    return asset_catalog_->complete_download(download_id, total_bytes);
}

int TransferManager::write_response_body(const std::string& target_path, const std::string& body) const {
    std::ofstream output(target_path, std::ios::binary | std::ios::trunc);
    if (!output.is_open()) {
        return SEEKER_ERROR_INVALID;
    }

    output.write(body.data(), static_cast<std::streamsize>(body.size()));
    output.flush();
    if (!output.good()) {
        return SEEKER_ERROR_INVALID;
    }
    return SEEKER_OK;
}

void TransferManager::mark_job_status(int32_t download_id, const std::string& status) {
    std::lock_guard<std::mutex> lock(mutex_);
    const auto it = jobs_.find(download_id);
    if (it == jobs_.end()) {
        return;
    }
    it->second.status = status;
}

std::string TransferManager::resolve_target_path(const DownloadPlanData& plan) const {
    if (cache_store_ == nullptr) {
        return plan.save_path;
    }
    const std::string source = plan.source_id.empty() ? "runtime" : plan.source_id;
    return cache_store_->offline_root() + "/" + source + "/" + plan.filename;
}

} // namespace seeker
