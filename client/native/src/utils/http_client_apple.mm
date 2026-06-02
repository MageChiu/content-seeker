/// Apple 平台 HTTP 客户端实现
/// 使用 NSURLSession 进行同步 HTTP 请求

#include "http_client.h"

#if defined(__APPLE__)

#import <Foundation/Foundation.h>

namespace seeker {

HttpResponse HttpClient::get(
    const std::string& url,
    const std::map<std::string, std::string>& headers
) {
    HttpResponse response;

    @autoreleasepool {
        NSString* urlStr = [NSString stringWithUTF8String:url.c_str()];
        NSURL* nsUrl = [NSURL URLWithString:urlStr];
        if (!nsUrl) {
            response.status_code = -1;
            return response;
        }

        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:nsUrl];
        [request setHTTPMethod:@"GET"];
        [request setTimeoutInterval:15.0];

        // 设置 User-Agent
        [request setValue:[NSString stringWithUTF8String:user_agent_.c_str()]
            forHTTPHeaderField:@"User-Agent"];

        // 设置自定义 headers
        for (const auto& [key, value] : headers) {
            [request setValue:[NSString stringWithUTF8String:value.c_str()]
                forHTTPHeaderField:[NSString stringWithUTF8String:key.c_str()]];
        }

        // 同步请求（使用信号量）
        __block NSData* responseData = nil;
        __block NSHTTPURLResponse* httpResponse = nil;
        __block NSError* requestError = nil;

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);

        NSURLSessionDataTask* task = [[NSURLSession sharedSession]
            dataTaskWithRequest:request
            completionHandler:^(NSData* data, NSURLResponse* resp, NSError* err) {
                responseData = data;
                httpResponse = (NSHTTPURLResponse*)resp;
                requestError = err;
                dispatch_semaphore_signal(sem);
            }];
        [task resume];

        // 等待最多 30 秒
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));

        if (requestError || !httpResponse) {
            response.status_code = -1;
            return response;
        }

        response.status_code = (int)httpResponse.statusCode;
        if (responseData && responseData.length > 0) {
            response.body = std::string((const char*)responseData.bytes, responseData.length);
        }
    }

    return response;
}

std::string HttpClient::resolve_redirect(const std::string& url) {
    @autoreleasepool {
        NSString* urlStr = [NSString stringWithUTF8String:url.c_str()];
        NSURL* nsUrl = [NSURL URLWithString:urlStr];
        if (!nsUrl) return url;

        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:nsUrl];
        [request setHTTPMethod:@"HEAD"];
        [request setTimeoutInterval:10.0];
        [request setValue:[NSString stringWithUTF8String:user_agent_.c_str()]
            forHTTPHeaderField:@"User-Agent"];

        __block NSURL* finalUrl = nil;
        __block NSError* requestError = nil;

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);

        // NSURLSession 默认跟随重定向，最终 response.URL 就是目标 URL
        NSURLSessionDataTask* task = [[NSURLSession sharedSession]
            dataTaskWithRequest:request
            completionHandler:^(NSData* data, NSURLResponse* resp, NSError* err) {
                (void)data;
                finalUrl = resp.URL;
                requestError = err;
                dispatch_semaphore_signal(sem);
            }];
        [task resume];

        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC));

        if (!requestError && finalUrl) {
            return std::string([finalUrl.absoluteString UTF8String]);
        }
    }
    return url; // 解析失败则返回原 URL
}

} // namespace seeker

#endif // __APPLE__
