#ifndef SEEKER_MUXER_H
#define SEEKER_MUXER_H

#include "seeker.h"

#ifdef __cplusplus
extern "C" {
#endif

/// 把 DASH 分轨（仅视频 + 仅音频）合并为完整 MP4
/// - 不重编码，pass-through
/// - macOS/iOS 使用 AVAssetExportSession（沙箱友好）
/// - 其他平台未实现，返回错误
///
/// @param video_path 视频分轨绝对路径
/// @param audio_path 音频分轨绝对路径，可为 NULL（此时仅复制视频）
/// @param output_path 输出 mp4 绝对路径
/// @return 结果 JSON（调用方用 seeker_free_string 释放）：
///   成功 {"ok":true,"output":"..."}；失败 {"error":"..."}
SEEKER_API char* seeker_mux_av_to_mp4(
    const char* video_path,
    const char* audio_path,
    const char* output_path
);

#ifdef __cplusplus
}
#endif

#endif // SEEKER_MUXER_H
