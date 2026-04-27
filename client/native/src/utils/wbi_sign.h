#ifndef SEEKER_WBI_SIGN_H
#define SEEKER_WBI_SIGN_H

#include <string>
#include <map>
#include "http_client.h"

namespace seeker {

class WbiSigner {
public:
    explicit WbiSigner(HttpClient& http);

    /// 对参数进行 wbi 签名，返回签名后的完整 query string
    std::string sign(const std::map<std::string, std::string>& params);

    /// 强制刷新 wbi keys
    void refresh_keys();

private:
    HttpClient& http_;
    std::string mixin_key_;
    int64_t keys_fetched_at_ = 0;

    void ensure_keys();
    std::string fetch_mixin_key();
    static std::string generate_mixin_key(const std::string& raw_key);
    static std::string md5(const std::string& input);
    static std::string url_encode(const std::string& value);
    static std::string filter_value(const std::string& value);
};

} // namespace seeker

#endif
