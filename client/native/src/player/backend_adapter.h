#ifndef SEEKER_BACKEND_ADAPTER_H
#define SEEKER_BACKEND_ADAPTER_H

#include <cstdint>
#include <memory>
#include <string>

namespace seeker {

struct BackendPlaybackState {
    std::string status = "idle";
    int64_t position_ms = 0;
    double rate = 1.0;
    double volume = 100.0;
};

class PlayerBackendSession {
public:
    virtual ~PlayerBackendSession() = default;

    virtual int open(const std::string& resolved_media_json) = 0;
    virtual int play() = 0;
    virtual int pause() = 0;
    virtual int seek(int64_t position_ms) = 0;
    virtual int set_rate(double rate) = 0;
    virtual int set_volume(double volume) = 0;
    virtual int select_track(const std::string& track_id) = 0;
    virtual int select_variant(const std::string& variant_id) = 0;
    virtual BackendPlaybackState snapshot() const = 0;
};

class BackendAdapter {
public:
    virtual ~BackendAdapter() = default;
    virtual std::unique_ptr<PlayerBackendSession> create_session(int32_t session_id) = 0;
};

std::unique_ptr<BackendAdapter> create_mpv_backend_adapter();

} // namespace seeker

#endif // SEEKER_BACKEND_ADAPTER_H
