#ifndef SEEKER_PLAYER_H
#define SEEKER_PLAYER_H

#include "seeker.h"

#ifdef __cplusplus
extern "C" {
#endif

/// Runtime 会话事件回调
/// @param runtime_id runtime 实例 ID
/// @param session_id 会话 ID
/// @param event_json 事件 JSON
typedef void (*seeker_runtime_event_callback)(
    int32_t runtime_id,
    int32_t session_id,
    const char* event_json
);

/// 创建 runtime 实例
SEEKER_API int32_t seeker_runtime_create(const char* config_json);

/// 销毁 runtime 实例
SEEKER_API void seeker_runtime_destroy(int32_t runtime_id);

/// 创建播放会话
SEEKER_API int32_t seeker_session_create(
    int32_t runtime_id,
    seeker_runtime_event_callback callback
);

/// 销毁播放会话
SEEKER_API int seeker_session_dispose(int32_t runtime_id, int32_t session_id);

/// 解析媒体请求，返回 ResolvedMediaGraph JSON
SEEKER_API char* seeker_resolve_media(
    int32_t runtime_id,
    const char* request_json
);

/// 打开已解析媒体
SEEKER_API int seeker_session_open(
    int32_t runtime_id,
    int32_t session_id,
    const char* resolved_media_json
);

/// 开始播放
SEEKER_API int seeker_session_play(int32_t runtime_id, int32_t session_id);

/// 暂停播放
SEEKER_API int seeker_session_pause(int32_t runtime_id, int32_t session_id);

/// 跳转位置
SEEKER_API int seeker_session_seek(
    int32_t runtime_id,
    int32_t session_id,
    int64_t position_ms
);

/// 设置倍速
SEEKER_API int seeker_session_set_rate(
    int32_t runtime_id,
    int32_t session_id,
    double rate
);

/// 设置音量
SEEKER_API int seeker_session_set_volume(
    int32_t runtime_id,
    int32_t session_id,
    double volume
);

/// 选择轨道
SEEKER_API int seeker_session_select_track(
    int32_t runtime_id,
    int32_t session_id,
    const char* track_id
);

/// 选择码率变体
SEEKER_API int seeker_session_select_variant(
    int32_t runtime_id,
    int32_t session_id,
    const char* variant_id
);

/// 构建下载计划
SEEKER_API char* seeker_build_download_plan(
    int32_t runtime_id,
    const char* resolved_media_json,
    const char* options_json
);

/// 启动下载任务
SEEKER_API int32_t seeker_download_start(
    int32_t runtime_id,
    const char* download_plan_json
);

/// 暂停下载任务
SEEKER_API int seeker_download_pause(int32_t runtime_id, int32_t download_id);

/// 恢复下载任务
SEEKER_API int seeker_download_resume(int32_t runtime_id, int32_t download_id);

/// 取消下载任务
SEEKER_API int seeker_download_cancel(int32_t runtime_id, int32_t download_id);

/// 查询单个资产
SEEKER_API char* seeker_query_asset(
    int32_t runtime_id,
    const char* media_id
);

/// 列出资产
SEEKER_API char* seeker_list_assets(
    int32_t runtime_id,
    const char* filter_json
);

/// 列出下载任务
SEEKER_API char* seeker_list_downloads(
    int32_t runtime_id,
    const char* filter_json
);

/// 删除资产
SEEKER_API int seeker_evict_asset(
    int32_t runtime_id,
    const char* asset_id
);

#ifdef __cplusplus
}
#endif

#endif // SEEKER_PLAYER_H
