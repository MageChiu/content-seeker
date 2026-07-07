#include "backend_adapter.h"

#include "../../include/seeker/seeker.h"

namespace seeker {

namespace {

class StubMpvBackendSession final : public PlayerBackendSession {
public:
    explicit StubMpvBackendSession(int32_t session_id) : session_id_(session_id) {}

    int open(const std::string& resolved_media_json) override {
        (void)resolved_media_json;
        state_.status = "ready";
        state_.position_ms = 0;
        return SEEKER_OK;
    }

    int play() override {
        state_.status = "playing";
        return SEEKER_OK;
    }

    int pause() override {
        state_.status = "paused";
        return SEEKER_OK;
    }

    int seek(int64_t position_ms) override {
        state_.position_ms = position_ms;
        return SEEKER_OK;
    }

    int set_rate(double rate) override {
        state_.rate = rate;
        return SEEKER_OK;
    }

    int set_volume(double volume) override {
        state_.volume = volume;
        return SEEKER_OK;
    }

    int select_track(const std::string& track_id) override {
        (void)track_id;
        return SEEKER_OK;
    }

    int select_variant(const std::string& variant_id) override {
        (void)variant_id;
        return SEEKER_OK;
    }

    BackendPlaybackState snapshot() const override {
        return state_;
    }

private:
    int32_t session_id_ = 0;
    BackendPlaybackState state_;
};

class MpvBackendAdapter final : public BackendAdapter {
public:
    std::unique_ptr<PlayerBackendSession> create_session(int32_t session_id) override {
        return std::make_unique<StubMpvBackendSession>(session_id);
    }
};

} // namespace

std::unique_ptr<BackendAdapter> create_mpv_backend_adapter() {
    return std::make_unique<MpvBackendAdapter>();
}

} // namespace seeker
