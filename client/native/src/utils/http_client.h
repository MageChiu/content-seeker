#ifndef SEEKER_HTTP_CLIENT_H
#define SEEKER_HTTP_CLIENT_H

#include <map>
#include <string>

namespace seeker {

/// HTTP 响应
struct HttpResponse {
    int status_code = 0;
    std::string body;

    bool ok() const { return status_code >= 200 && status_code < 300; }
};

/// 跨平台 HTTP 客户端
/// Apple 平台使用 NSURLSession (Objective-C++)
/// 其他平台暂返回错误，后续补充
class HttpClient {
public:
    HttpClient() = default;

    /// 执行同步 GET 请求（自动跟随重定向）
    HttpResponse get(
        const std::string& url,
        const std::map<std::string, std::string>& headers = {}
    );

    /// 解析重定向，返回最终 URL（不下载 body）
    /// 用于短链接解析（如 b23.tv → bilibili.com）
    std::string resolve_redirect(const std::string& url);

    void set_user_agent(const std::string& ua) { user_agent_ = ua; }
    const std::string& user_agent() const { return user_agent_; }

private:
    std::string user_agent_ = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36";
};

} // namespace seeker

#endif // SEEKER_HTTP_CLIENT_H
