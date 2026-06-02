#include "callback_dispatcher.h"

namespace seeker {

CallbackDispatcher& CallbackDispatcher::instance() {
    static CallbackDispatcher dispatcher;
    return dispatcher;
}

int32_t CallbackDispatcher::register_callback(Callback cb) {
    int32_t id = next_id_.fetch_add(1);
    std::lock_guard<std::mutex> lock(mutex_);
    callbacks_[id] = std::move(cb);
    return id;
}

void CallbackDispatcher::dispatch(int32_t request_id, const char* result_json, const char* error) {
    Callback cb;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = callbacks_.find(request_id);
        if (it == callbacks_.end()) return;
        cb = std::move(it->second);
        callbacks_.erase(it);
    }
    if (cb) {
        cb(result_json, error);
    }
}

void CallbackDispatcher::cancel(int32_t request_id) {
    std::lock_guard<std::mutex> lock(mutex_);
    callbacks_.erase(request_id);
}

} // namespace seeker
