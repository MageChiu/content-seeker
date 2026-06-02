#ifndef SEEKER_EXTRACTOR_REGISTRY_H
#define SEEKER_EXTRACTOR_REGISTRY_H

#include <memory>
#include <string>
#include <vector>

namespace seeker {

/// 站点提取器插件接口
class ExtractorPlugin {
public:
    virtual ~ExtractorPlugin() = default;

    /// 插件名称
    virtual const char* name() const = 0;

    /// 判断是否能处理该 URL
    virtual bool can_handle(const std::string& url) const = 0;

    /// 执行提取（同步，由线程池调用）
    /// @return 结果 JSON 字符串
    virtual std::string extract(const std::string& url, const std::string& options_json) = 0;
};

/// 提取器注册中心
class ExtractorRegistry {
public:
    static ExtractorRegistry& instance();

    /// 注册插件
    void register_plugin(std::unique_ptr<ExtractorPlugin> plugin);

    /// 根据 URL 查找能处理的插件
    ExtractorPlugin* find_plugin(const std::string& url) const;

    /// 获取所有已注册插件的名称列表
    std::vector<std::string> get_plugin_names() const;

private:
    ExtractorRegistry() = default;
    std::vector<std::unique_ptr<ExtractorPlugin>> plugins_;
};

} // namespace seeker

#endif // SEEKER_EXTRACTOR_REGISTRY_H
