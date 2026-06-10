#include "cache_store.h"

#include <filesystem>

namespace seeker {

void CacheStore::configure(
    const std::string& storage_root,
    const std::string& cache_root_override,
    const std::string& recording_root_override
) {
    storage_root_ = storage_root.empty() ? "seeker_runtime" : storage_root;
    metadata_root_ = storage_root_ + "/metadata";
    cache_root_ = cache_root_override.empty() ? (storage_root_ + "/cache") : cache_root_override;
    offline_root_ = storage_root_ + "/offline";
    recording_root_ = recording_root_override.empty()
        ? (storage_root_ + "/recordings")
        : recording_root_override;

    std::error_code ec;
    std::filesystem::create_directories(metadata_root_, ec);
    std::filesystem::create_directories(cache_root_, ec);
    std::filesystem::create_directories(offline_root_, ec);
    std::filesystem::create_directories(recording_root_, ec);
}

std::string CacheStore::assets_metadata_path() const {
    return metadata_root_ + "/assets.ndjson";
}

std::string CacheStore::downloads_metadata_path() const {
    return metadata_root_ + "/downloads.ndjson";
}

} // namespace seeker
