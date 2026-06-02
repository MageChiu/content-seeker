// Apple 平台音视频合并实现（AVFoundation）
// 用 AVMutableComposition + AVAssetExportSession 实现 pass-through 合并
// 不依赖 ffmpeg，沙箱完全友好
//
// 这里覆盖通用的 fMP4 实现：当系统能力可用时优先用，
// 失败时（极少见）会回退到 muxer_fmp4.cpp 中的 seeker_mux_av_to_mp4_fmp4

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#include "seeker/muxer.h"
#include <cstdlib>
#include <cstring>
#include <string>

// 来自 muxer_fmp4.cpp 的跨平台后备实现
extern "C" SEEKER_API char* seeker_mux_av_to_mp4_fmp4(
    const char* video_path,
    const char* audio_path,
    const char* output_path
);

namespace {
char* make_result_json(const std::string& json) {
    return strdup(json.c_str());
}

std::string escape_json(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 8);
    for (char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default: out += c;
        }
    }
    return out;
}
} // namespace

extern "C" SEEKER_API char* seeker_mux_av_to_mp4(
    const char* video_path,
    const char* audio_path,
    const char* output_path
) {
    if (!video_path || !output_path) {
        return make_result_json("{\"error\":\"invalid arguments\"}");
    }

    @autoreleasepool {
        NSString* videoNs = [NSString stringWithUTF8String:video_path];
        NSString* outputNs = [NSString stringWithUTF8String:output_path];
        NSString* audioNs = audio_path
            ? [NSString stringWithUTF8String:audio_path]
            : nil;

        NSURL* videoUrl = [NSURL fileURLWithPath:videoNs];
        NSURL* outputUrl = [NSURL fileURLWithPath:outputNs];

        // 删除可能已存在的输出文件
        [[NSFileManager defaultManager] removeItemAtURL:outputUrl error:nil];

        AVURLAsset* videoAsset = [AVURLAsset URLAssetWithURL:videoUrl options:nil];
        if (videoAsset == nil) {
            return make_result_json("{\"error\":\"failed to open video asset\"}");
        }

        AVMutableComposition* composition = [AVMutableComposition composition];

        // 添加视频轨
        NSArray<AVAssetTrack*>* videoTracks =
            [videoAsset tracksWithMediaType:AVMediaTypeVideo];
        AVAssetTrack* srcVideoTrack = videoTracks.count > 0 ? videoTracks[0] : nil;
        if (srcVideoTrack == nil) {
            // 没有视频轨，可能视频文件本身就是仅音频或损坏，
            // 直接尝试把它当作完整 audio 复制
            srcVideoTrack = nil;
        }

        if (srcVideoTrack != nil) {
            AVMutableCompositionTrack* dstVideoTrack =
                [composition addMutableTrackWithMediaType:AVMediaTypeVideo
                                          preferredTrackID:kCMPersistentTrackID_Invalid];
            NSError* err = nil;
            CMTimeRange range = CMTimeRangeMake(kCMTimeZero, videoAsset.duration);
            [dstVideoTrack insertTimeRange:range
                                   ofTrack:srcVideoTrack
                                    atTime:kCMTimeZero
                                     error:&err];
            if (err != nil) {
                std::string msg = "failed to insert video track: ";
                msg += [err.localizedDescription UTF8String];
                std::string out = "{\"error\":\"" + escape_json(msg) + "\"}";
                return make_result_json(out);
            }
            dstVideoTrack.preferredTransform = srcVideoTrack.preferredTransform;
        }

        // 视频文件里可能自带音轨（普通 mp4），优先用它
        bool audioInserted = false;
        NSArray<AVAssetTrack*>* videoFileAudioTracks =
            [videoAsset tracksWithMediaType:AVMediaTypeAudio];
        if (videoFileAudioTracks.count > 0) {
            AVAssetTrack* srcAudio = videoFileAudioTracks[0];
            AVMutableCompositionTrack* dstAudio =
                [composition addMutableTrackWithMediaType:AVMediaTypeAudio
                                          preferredTrackID:kCMPersistentTrackID_Invalid];
            NSError* err = nil;
            CMTimeRange range = CMTimeRangeMake(kCMTimeZero, videoAsset.duration);
            [dstAudio insertTimeRange:range ofTrack:srcAudio atTime:kCMTimeZero error:&err];
            if (err == nil) {
                audioInserted = true;
            }
        }

        // 否则使用单独的 audio 文件（DASH 场景）
        if (!audioInserted && audioNs != nil) {
            NSURL* audioUrl = [NSURL fileURLWithPath:audioNs];
            AVURLAsset* audioAsset = [AVURLAsset URLAssetWithURL:audioUrl options:nil];
            NSArray<AVAssetTrack*>* audioTracks =
                [audioAsset tracksWithMediaType:AVMediaTypeAudio];
            if (audioTracks.count > 0) {
                AVAssetTrack* srcAudio = audioTracks[0];
                AVMutableCompositionTrack* dstAudio =
                    [composition addMutableTrackWithMediaType:AVMediaTypeAudio
                                              preferredTrackID:kCMPersistentTrackID_Invalid];
                NSError* err = nil;
                CMTimeRange range = CMTimeRangeMake(kCMTimeZero, audioAsset.duration);
                [dstAudio insertTimeRange:range ofTrack:srcAudio atTime:kCMTimeZero error:&err];
                if (err != nil) {
                    std::string msg = "failed to insert audio track: ";
                    msg += [err.localizedDescription UTF8String];
                    std::string out = "{\"error\":\"" + escape_json(msg) + "\"}";
                    return make_result_json(out);
                }
            }
        }

        // 导出为 mp4 (pass-through)
        AVAssetExportSession* exporter =
            [[AVAssetExportSession alloc] initWithAsset:composition
                                             presetName:AVAssetExportPresetPassthrough];
        if (exporter == nil) {
            return make_result_json("{\"error\":\"failed to create exporter\"}");
        }
        exporter.outputURL = outputUrl;
        exporter.outputFileType = AVFileTypeMPEG4;
        exporter.shouldOptimizeForNetworkUse = YES;

        // 同步等待完成
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        __block AVAssetExportSessionStatus status = AVAssetExportSessionStatusUnknown;
        __block NSError* exportError = nil;
        [exporter exportAsynchronouslyWithCompletionHandler:^{
            status = exporter.status;
            exportError = exporter.error;
            dispatch_semaphore_signal(sema);
        }];
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

        if (status != AVAssetExportSessionStatusCompleted) {
            std::string msg = "AVAssetExportSession failed";
            if (exportError != nil) {
                msg += ": ";
                msg += [exportError.localizedDescription UTF8String];
            }
            // 回退到跨平台 fMP4 muxer
            char* fallback = seeker_mux_av_to_mp4_fmp4(
                video_path, audio_path, output_path);
            if (fallback != nullptr) {
                return fallback;
            }
            std::string out = "{\"error\":\"" + escape_json(msg) + "\"}";
            return make_result_json(out);
        }

        std::string ok = "{\"ok\":true,\"output\":\"";
        ok += escape_json(output_path);
        ok += "\"}";
        return make_result_json(ok);
    }
}
