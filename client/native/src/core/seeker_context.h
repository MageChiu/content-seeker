#ifndef SEEKER_CONTEXT_H
#define SEEKER_CONTEXT_H

#include <atomic>
#include <memory>
#include <string>

namespace seeker {

/// 全局上下文，管理 libseeker 的生命周期和共享状态
class SeekerContext {
public:
    static SeekerContext& instance();

    bool init(const std::string& config_json);
    void destroy();
    bool is_initialized() const;

    // 禁止拷贝
    SeekerContext(const SeekerContext&) = delete;
    SeekerContext& operator=(const SeekerContext&) = delete;

private:
    SeekerContext() = default;
    ~SeekerContext() = default;

    std::atomic<bool> initialized_{false};
};

} // namespace seeker

#endif // SEEKER_CONTEXT_H
