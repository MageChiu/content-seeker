#ifndef SEEKER_SEEKER_H
#define SEEKER_SEEKER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// 平台导出宏
#if defined(_WIN32)
  #ifdef SEEKER_BUILDING_DLL
    #define SEEKER_API __declspec(dllexport)
  #else
    #define SEEKER_API __declspec(dllimport)
  #endif
#else
  #define SEEKER_API __attribute__((visibility("default")))
#endif

// 错误码
#define SEEKER_OK              0
#define SEEKER_ERROR_INVALID   -1
#define SEEKER_ERROR_NOT_INIT  -2
#define SEEKER_ERROR_NETWORK   -3
#define SEEKER_ERROR_PARSE     -4
#define SEEKER_ERROR_CANCELLED -5

/// 初始化 libseeker
/// @param config_json 配置 JSON 字符串，可为 NULL 使用默认配置
/// @return SEEKER_OK 成功，其他为错误码
SEEKER_API int seeker_init(const char* config_json);

/// 销毁 libseeker，释放所有资源
SEEKER_API void seeker_destroy(void);

/// 获取库版本号
/// @return 版本字符串，如 "0.1.0"
SEEKER_API const char* seeker_version(void);

/// 检查是否已初始化
/// @return 1 已初始化，0 未初始化
SEEKER_API int seeker_is_initialized(void);

#ifdef __cplusplus
}
#endif

#endif // SEEKER_SEEKER_H
