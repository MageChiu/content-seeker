// 跨平台默认 muxer 实现：直接转发到 fMP4 muxer
// Apple 平台不编译此文件（由 muxer_apple.mm 提供 seeker_mux_av_to_mp4）

#include "seeker/muxer.h"

extern "C" char* seeker_mux_av_to_mp4_fmp4(
    const char* video_path,
    const char* audio_path,
    const char* output_path
);

extern "C" SEEKER_API char* seeker_mux_av_to_mp4(
    const char* video_path,
    const char* audio_path,
    const char* output_path
) {
    return seeker_mux_av_to_mp4_fmp4(video_path, audio_path, output_path);
}
