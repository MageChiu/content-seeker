#ifndef SEEKER_CALLBACK_DISPATCHER_H
#define SEEKER_CALLBACK_DISPATCHER_H

#include <functional>
#include <mutex>
#include <unordered_map>
#include <atomic>

namespace seeker {

/// 回调分发器，管理异步操作的回调注册和触发
class CallbackDispatcher {
public:
    using Callback = std::function<void(const char* result_json, const char* error)>;

    static CallbackDispatcher& instance();

    /// 注册回调，返回唯一请求 ID
    int32_t register_callback(Callback cb);

    /// 触发回调并移除
    void dispatch(int32_t request_id, const char* result_json, const char* error);

    /// 取消并移除回调
    void cancel(int32_t request_id);

private:
    CallbackDispatcher() = default;

    std::mutex mutex_;
    std::unordered_map<int32_t, Callback> callbacks_;
    std::atomic<int32_t> next_id_{1};
};

} // namespace seeker

#endif // SEEKER_CALLBACK_DISPATCHER_H
