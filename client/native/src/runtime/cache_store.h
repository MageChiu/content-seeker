#ifndef SEEKER_CACHE_STORE_H
#define SEEKER_CACHE_STORE_H

#include <string>

namespace seeker {

class CacheStore {
public:
    CacheStore() = default;

    void configure(
        const std::string& storage_root,
        const std::string& cache_root_override = "",
        const std::string& recording_root_override = ""
    );

    const std::string& storage_root() const { return storage_root_; }
    const std::string& metadata_root() const { return metadata_root_; }
    const std::string& cache_root() const { return cache_root_; }
    const std::string& offline_root() const { return offline_root_; }
    const std::string& recording_root() const { return recording_root_; }

    std::string assets_metadata_path() const;
    std::string downloads_metadata_path() const;

private:
    std::string storage_root_;
    std::string metadata_root_;
    std::string cache_root_;
    std::string offline_root_;
    std::string recording_root_;
};

} // namespace seeker

#endif // SEEKER_CACHE_STORE_H
