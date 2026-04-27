#ifndef SEEKER_PLAYER_H
#define SEEKER_PLAYER_H

#include "seeker.h"

#ifdef __cplusplus
extern "C" {
#endif

/// 播放器事件回调
/// @param player_id 播放器实例 ID
/// @param event_json 事件 JSON
typedef void (*seeker_player_event_callback)(
    int32_t player_id,
    const char* event_json
);

/// 创建播放器实例
/// @param callback 事件回调
/// @return 播放器 ID (>0)，或错误码 (<0)
SEEKER_API int32_t seeker_player_create(seeker_player_event_callback callback);

/// 打开流进行播放
/// @param player_id 播放器 ID
/// @param stream_json 流描述 JSON（由 extractor 输出）
/// @return SEEKER_OK 或错误码
SEEKER_API int seeker_player_open(int32_t player_id, const char* stream_json);

/// 开始播放
SEEKER_API int seeker_player_play(int32_t player_id);

/// 暂停播放
SEEKER_API int seeker_player_pause(int32_t player_id);

/// 跳转到指定位置
/// @param position_seconds 目标位置（秒）
SEEKER_API int seeker_player_seek(int32_t player_id, double position_seconds);

/// 设置播放速率
/// @param rate 播放倍速 (0.25 - 4.0)
SEEKER_API int seeker_player_set_rate(int32_t player_id, double rate);

/// 销毁播放器实例
SEEKER_API void seeker_player_destroy(int32_t player_id);

#ifdef __cplusplus
}
#endif

#endif // SEEKER_PLAYER_H
