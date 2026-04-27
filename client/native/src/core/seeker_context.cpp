#include "seeker_context.h"

namespace seeker {

SeekerContext& SeekerContext::instance() {
    static SeekerContext ctx;
    return ctx;
}

bool SeekerContext::init(const std::string& config_json) {
    if (initialized_.load()) {
        return true; // 已初始化，幂等操作
    }

    // TODO: 解析 config_json，初始化线程池、HTTP 客户端等
    initialized_.store(true);
    return true;
}

void SeekerContext::destroy() {
    if (!initialized_.load()) {
        return;
    }

    // TODO: 停止线程池、释放资源
    initialized_.store(false);
}

bool SeekerContext::is_initialized() const {
    return initialized_.load();
}

} // namespace seeker
