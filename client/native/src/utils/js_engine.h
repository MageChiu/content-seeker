#ifndef SEEKER_JS_ENGINE_H
#define SEEKER_JS_ENGINE_H

#include <string>
#include <memory>

namespace seeker {

/// 轻量级 JavaScript 执行引擎（基于 QuickJS）
/// 用于执行 YouTube signature cipher 解密等场景
class JsEngine {
public:
    JsEngine();
    ~JsEngine();

    /// 执行 JavaScript 代码，返回结果字符串
    /// @param code 要执行的 JS 代码
    /// @return 执行结果的字符串表示
    std::string eval(const std::string& code);

    /// 执行 JS 代码，不关心返回值
    bool exec(const std::string& code);

    /// 调用已定义的函数
    /// @param func_name 函数名
    /// @param arg 单个字符串参数
    /// @return 函数返回值的字符串表示
    std::string call(const std::string& func_name, const std::string& arg);

    /// 是否初始化成功
    bool is_valid() const;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace seeker

#endif // SEEKER_JS_ENGINE_H
