/// 非 Apple 平台的 HTTP 客户端桩实现
/// Windows/Linux/Android 后续补充真实实现

#include "http_client.h"

#if !defined(__APPLE__)

namespace seeker {

HttpResponse HttpClient::get(
    const std::string& url,
    const std::map<std::string, std::string>& headers
) {
    (void)url;
    (void)headers;
    HttpResponse response;
    response.status_code = -1;
    response.body = "{\"error\": \"HTTP client not implemented on this platform\"}";
    return response;
}

std::string HttpClient::resolve_redirect(const std::string& url) {
    return url; // 未实现，原样返回
}

} // namespace seeker

#endif // !__APPLE__
