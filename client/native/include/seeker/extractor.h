#ifndef SEEKER_EXTRACTOR_H
#define SEEKER_EXTRACTOR_H

#include "seeker.h"

#ifdef __cplusplus
extern "C" {
#endif

/// 流提取结果回调
/// @param request_id 请求 ID
/// @param result_json 结果 JSON（成功时非 NULL）
/// @param error 错误信息（失败时非 NULL）
typedef void (*seeker_extract_callback)(
    int32_t request_id,
    const char* result_json,
    const char* error
);

/// 异步提取流地址
/// @param url 内容页 URL
/// @param options_json 选项 JSON，可为 NULL
/// @param callback 结果回调
/// @return 请求 ID (>0)，或错误码 (<0)
SEEKER_API int32_t seeker_extract_stream(
    const char* url,
    const char* options_json,
    seeker_extract_callback callback
);

/// 同步提取流地址（阻塞调用，适合从 Dart Isolate 调用）
/// @param url 内容页 URL
/// @param options_json 选项 JSON，可为 NULL
/// @return 结果 JSON 字符串（调用者需用 seeker_free_string 释放），失败返回 NULL
SEEKER_API char* seeker_extract_stream_sync(
    const char* url,
    const char* options_json
);

/// 释放 seeker 分配的字符串
SEEKER_API void seeker_free_string(char* str);

/// 取消正在进行的提取请求
/// @param request_id 由 seeker_extract_stream 返回的请求 ID
SEEKER_API void seeker_cancel_extract(int32_t request_id);

/// 获取支持的站点列表
/// @return JSON 数组字符串，调用者不需要释放
SEEKER_API const char* seeker_get_supported_sites(void);

#ifdef __cplusplus
}
#endif

#endif // SEEKER_EXTRACTOR_H
