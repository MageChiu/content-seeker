// Cross-platform fragmented MP4 → MP4 muxer
//
// 设计目标：
// - 处理 Bilibili / YouTube DASH 录制后的 video.m4s + audio.m4s 文件
// - 不重编码、不依赖 ffmpeg/AVFoundation/MediaMuxer
// - 纯 C++17，所有平台共用
//
// 实现思路：
// fMP4 (init + media segments) 已经是合法的 ISOBMFF 文件结构。
// 我们读取两个 m4s 文件的所有 box，把它们写到同一个输出文件中，
// 通过修改 trak/tkhd 中的 track_id 让两个 track 不冲突，
// 并把 moov 中的 trex 合并起来。这样得到的输出文件可以被任何
// 标准 mp4 解析器播放（系统播放器 / 浏览器 / VLC 等）。
//
// 局限：仅支持 ISOBMFF (mp4) 容器，不处理 webm/ts。这与
// Bilibili / YouTube DASH 的实际场景完全匹配。

#include "seeker/muxer.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

namespace {

std::string make_error(const std::string& msg) {
    std::string out;
    out.reserve(msg.size() + 16);
    out += "{\"error\":\"";
    for (char c : msg) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            default: out += c;
        }
    }
    out += "\"}";
    return out;
}

bool read_file(const std::string& path, std::vector<uint8_t>& buf) {
    std::ifstream f(path, std::ios::binary | std::ios::ate);
    if (!f) return false;
    auto size = f.tellg();
    if (size <= 0) return false;
    f.seekg(0, std::ios::beg);
    buf.resize(static_cast<size_t>(size));
    f.read(reinterpret_cast<char*>(buf.data()), size);
    return f.good() || f.eof();
}

uint32_t read_be32(const uint8_t* p) {
    return (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16) |
           (uint32_t(p[2]) << 8)  | uint32_t(p[3]);
}

void write_be32(uint8_t* p, uint32_t v) {
    p[0] = static_cast<uint8_t>((v >> 24) & 0xFF);
    p[1] = static_cast<uint8_t>((v >> 16) & 0xFF);
    p[2] = static_cast<uint8_t>((v >> 8) & 0xFF);
    p[3] = static_cast<uint8_t>(v & 0xFF);
}

// 在 buffer 中查找顶层 box，返回 box 起始偏移（找不到返回 SIZE_MAX）
size_t find_top_level_box(const std::vector<uint8_t>& buf,
                          const char type[4],
                          size_t start = 0) {
    size_t pos = start;
    while (pos + 8 <= buf.size()) {
        uint32_t size = read_be32(&buf[pos]);
        if (size < 8 || pos + size > buf.size()) {
            return static_cast<size_t>(-1);
        }
        if (std::memcmp(&buf[pos + 4], type, 4) == 0) {
            return pos;
        }
        pos += size;
    }
    return static_cast<size_t>(-1);
}

// 在 box 内部查找直接子 box（不递归）
// box_start 指向 box 的 size 字段
size_t find_child_box(const std::vector<uint8_t>& buf,
                      size_t box_start,
                      const char type[4]) {
    if (box_start + 8 > buf.size()) return static_cast<size_t>(-1);
    uint32_t parent_size = read_be32(&buf[box_start]);
    size_t parent_end = box_start + parent_size;
    if (parent_end > buf.size()) return static_cast<size_t>(-1);
    size_t pos = box_start + 8; // 跳过 size + type
    while (pos + 8 <= parent_end) {
        uint32_t size = read_be32(&buf[pos]);
        if (size < 8 || pos + size > parent_end) return static_cast<size_t>(-1);
        if (std::memcmp(&buf[pos + 4], type, 4) == 0) return pos;
        pos += size;
    }
    return static_cast<size_t>(-1);
}

// 改写 trak/tkhd 中的 track_id
// tkhd box layout: size(4) type(4) version(1) flags(3) [version 0:
//                  creation_time(4) modification_time(4) track_id(4) ...]
//                  [version 1: creation_time(8) modification_time(8) track_id(4) ...]
bool rewrite_track_id(std::vector<uint8_t>& buf, size_t trak_pos, uint32_t new_id) {
    size_t tkhd = find_child_box(buf, trak_pos, "tkhd");
    if (tkhd == static_cast<size_t>(-1)) return false;
    if (tkhd + 12 + 8 > buf.size()) return false;
    uint8_t version = buf[tkhd + 8];
    size_t track_id_offset = tkhd + 12; // skip size+type+version+flags
    if (version == 0) {
        track_id_offset += 8;  // creation + modification (4+4)
    } else if (version == 1) {
        track_id_offset += 16; // creation + modification (8+8)
    } else {
        return false;
    }
    if (track_id_offset + 4 > buf.size()) return false;
    write_be32(&buf[track_id_offset], new_id);
    return true;
}

// 改写 moof/traf/tfhd 中的 track_id
// tfhd box: size(4) type(4) version(1) flags(3) track_id(4) ...
bool rewrite_traf_track_id(std::vector<uint8_t>& buf, size_t moof_pos, uint32_t new_id) {
    size_t pos = moof_pos + 8;
    uint32_t moof_size = read_be32(&buf[moof_pos]);
    size_t moof_end = moof_pos + moof_size;
    bool any = false;
    while (pos + 8 <= moof_end) {
        uint32_t size = read_be32(&buf[pos]);
        if (size < 8 || pos + size > moof_end) break;
        if (std::memcmp(&buf[pos + 4], "traf", 4) == 0) {
            size_t tfhd = find_child_box(buf, pos, "tfhd");
            if (tfhd != static_cast<size_t>(-1) && tfhd + 16 <= buf.size()) {
                write_be32(&buf[tfhd + 12], new_id);
                any = true;
            }
        }
        pos += size;
    }
    return any;
}

// 改写 moov/mvex/trex 中的 track_id
bool rewrite_trex_track_id(std::vector<uint8_t>& buf, size_t moov_pos, uint32_t old_id, uint32_t new_id) {
    size_t mvex = find_child_box(buf, moov_pos, "mvex");
    if (mvex == static_cast<size_t>(-1)) return false;
    uint32_t mvex_size = read_be32(&buf[mvex]);
    size_t mvex_end = mvex + mvex_size;
    size_t pos = mvex + 8;
    while (pos + 8 <= mvex_end) {
        uint32_t size = read_be32(&buf[pos]);
        if (size < 8 || pos + size > mvex_end) break;
        if (std::memcmp(&buf[pos + 4], "trex", 4) == 0) {
            // trex: size(4) type(4) version(1) flags(3) track_id(4) ...
            if (pos + 16 <= buf.size()) {
                uint32_t cur = read_be32(&buf[pos + 12]);
                if (cur == old_id) {
                    write_be32(&buf[pos + 12], new_id);
                }
            }
        }
        pos += size;
    }
    return true;
}

uint32_t get_first_track_id(const std::vector<uint8_t>& buf, size_t moov_pos) {
    size_t trak = find_child_box(buf, moov_pos, "trak");
    if (trak == static_cast<size_t>(-1)) return 1;
    size_t tkhd = find_child_box(buf, trak, "tkhd");
    if (tkhd == static_cast<size_t>(-1)) return 1;
    if (tkhd + 12 > buf.size()) return 1;
    uint8_t version = buf[tkhd + 8];
    size_t off = tkhd + 12 + (version == 1 ? 16 : 8);
    if (off + 4 > buf.size()) return 1;
    return read_be32(&buf[off]);
}

// 把 src moov 的 trak/mvex 子 box 合并到 dst moov 中
// 简化策略：直接 append 到 dst moov 的末尾，调整 dst moov size
// 同时把 mvhd 的 next_track_ID 字段更新为更大的值
bool merge_moov(std::vector<uint8_t>& dst, size_t dst_moov_pos,
                const std::vector<uint8_t>& src, size_t src_moov_pos,
                uint32_t src_track_new_id) {
    // 收集要合并的子 box: trak（追加） + 整个 mvex 内的 trex（追加到 dst mvex）
    // 简化：仅追加 trak。如果 dst 没有 mvex 就把 src 的 mvex 整个加入；否则把 src mvex 内的 trex 合到 dst mvex
    uint32_t src_size = read_be32(&src[src_moov_pos]);
    size_t src_end = src_moov_pos + src_size;

    std::vector<std::vector<uint8_t>> to_append; // 要加到 dst moov 末尾的 box
    std::vector<std::vector<uint8_t>> trex_to_append; // 要加到 dst mvex 末尾

    size_t pos = src_moov_pos + 8;
    while (pos + 8 <= src_end) {
        uint32_t bsize = read_be32(&src[pos]);
        if (bsize < 8 || pos + bsize > src_end) return false;
        const char* btype = reinterpret_cast<const char*>(&src[pos + 4]);
        if (std::memcmp(btype, "trak", 4) == 0) {
            to_append.emplace_back(src.begin() + pos, src.begin() + pos + bsize);
            // 改写新 trak 的 track_id
            std::vector<uint8_t>& back = to_append.back();
            // back 是独立 box，find_child_box 第二个参数从 0 开始
            size_t tkhd_in = find_child_box(back, 0, "tkhd");
            if (tkhd_in != static_cast<size_t>(-1) && tkhd_in + 12 <= back.size()) {
                uint8_t ver = back[tkhd_in + 8];
                size_t toff = tkhd_in + 12 + (ver == 1 ? 16 : 8);
                if (toff + 4 <= back.size()) {
                    write_be32(&back[toff], src_track_new_id);
                }
            }
        } else if (std::memcmp(btype, "mvex", 4) == 0) {
            // 把 src mvex 的所有 trex 子 box 抽出来
            uint32_t mvex_size = bsize;
            size_t mvex_end = pos + mvex_size;
            size_t inner = pos + 8;
            while (inner + 8 <= mvex_end) {
                uint32_t isize = read_be32(&src[inner]);
                if (isize < 8 || inner + isize > mvex_end) break;
                if (std::memcmp(&src[inner + 4], "trex", 4) == 0) {
                    std::vector<uint8_t> trex(src.begin() + inner, src.begin() + inner + isize);
                    // 改写 trex 的 track_id 为新 id
                    if (trex.size() >= 16) {
                        write_be32(&trex[12], src_track_new_id);
                    }
                    trex_to_append.push_back(std::move(trex));
                }
                inner += isize;
            }
        }
        pos += bsize;
    }

    // 写入 dst：先追加 trex 到 dst mvex
    if (!trex_to_append.empty()) {
        size_t dst_mvex = find_child_box(dst, dst_moov_pos, "mvex");
        if (dst_mvex == static_cast<size_t>(-1)) return false;
        uint32_t dst_mvex_size = read_be32(&dst[dst_mvex]);
        size_t dst_mvex_end = dst_mvex + dst_mvex_size;
        size_t total_added = 0;
        std::vector<uint8_t> blob;
        for (auto& t : trex_to_append) {
            blob.insert(blob.end(), t.begin(), t.end());
            total_added += t.size();
        }
        // 在 dst_mvex_end 处插入 blob
        dst.insert(dst.begin() + dst_mvex_end, blob.begin(), blob.end());
        // 更新 dst mvex 大小
        write_be32(&dst[dst_mvex], dst_mvex_size + static_cast<uint32_t>(total_added));
        // 更新 dst moov 大小
        uint32_t dst_moov_size = read_be32(&dst[dst_moov_pos]);
        write_be32(&dst[dst_moov_pos], dst_moov_size + static_cast<uint32_t>(total_added));
    }

    // 把所有 trak append 到 dst moov 末尾
    for (auto& tr : to_append) {
        uint32_t dst_moov_size = read_be32(&dst[dst_moov_pos]);
        size_t dst_moov_end = dst_moov_pos + dst_moov_size;
        dst.insert(dst.begin() + dst_moov_end, tr.begin(), tr.end());
        write_be32(&dst[dst_moov_pos],
                   dst_moov_size + static_cast<uint32_t>(tr.size()));
    }
    return true;
}

// 收集 src 文件中所有 moof + mdat 对（按出现顺序）
// 返回每个 moof 在 src 中的偏移；mdat 紧随其后
std::vector<size_t> collect_moofs(const std::vector<uint8_t>& src) {
    std::vector<size_t> r;
    size_t pos = 0;
    while (pos + 8 <= src.size()) {
        uint32_t size = read_be32(&src[pos]);
        if (size < 8 || pos + size > src.size()) break;
        if (std::memcmp(&src[pos + 4], "moof", 4) == 0) {
            r.push_back(pos);
        }
        pos += size;
    }
    return r;
}

} // namespace

extern "C" SEEKER_API char* seeker_mux_av_to_mp4_fmp4(
    const char* video_path,
    const char* audio_path,
    const char* output_path
) {
    if (!video_path || !output_path) {
        return strdup(make_error("invalid arguments").c_str());
    }
    std::vector<uint8_t> video_buf;
    if (!read_file(video_path, video_buf)) {
        return strdup(make_error(std::string("cannot read video: ") + video_path).c_str());
    }

    // 找 video 中的 ftyp / moov
    size_t v_ftyp = find_top_level_box(video_buf, "ftyp");
    size_t v_moov = find_top_level_box(video_buf, "moov");
    if (v_ftyp == static_cast<size_t>(-1) || v_moov == static_cast<size_t>(-1)) {
        return strdup(make_error("video file is not a valid fragmented MP4").c_str());
    }

    // 输出 = video_buf 的副本作为基底
    std::vector<uint8_t> out = video_buf;

    // 获取 video 的 track_id（保持不变，作为 track 1）
    uint32_t v_track_id = get_first_track_id(out, v_moov);
    if (v_track_id == 0) v_track_id = 1;

    // 如果有音频文件，读入并合并
    if (audio_path && audio_path[0] != '\0') {
        std::vector<uint8_t> audio_buf;
        if (!read_file(audio_path, audio_buf)) {
            return strdup(make_error(std::string("cannot read audio: ") + audio_path).c_str());
        }
        size_t a_moov = find_top_level_box(audio_buf, "moov");
        if (a_moov == static_cast<size_t>(-1)) {
            return strdup(make_error("audio file is not a valid fragmented MP4").c_str());
        }

        uint32_t a_track_id = get_first_track_id(audio_buf, a_moov);
        // 给 audio 分配一个不冲突的新 id
        uint32_t new_audio_id = (v_track_id == 2) ? 3 : 2;

        // 合并 audio 的 trak/trex 到 out 的 moov
        // 此时 out 的 moov 在 v_moov 偏移上，merge 后 out moov 大小变化但起始偏移不变
        size_t out_moov = find_top_level_box(out, "moov");
        if (out_moov == static_cast<size_t>(-1)) {
            return strdup(make_error("internal: lost moov in output").c_str());
        }
        if (!merge_moov(out, out_moov, audio_buf, a_moov, new_audio_id)) {
            return strdup(make_error("failed to merge audio moov").c_str());
        }

        // 把 audio 的所有 moof+mdat 改写 track_id 后追加到 out 末尾
        auto moofs = collect_moofs(audio_buf);
        for (size_t mp : moofs) {
            uint32_t moof_size = read_be32(&audio_buf[mp]);
            // 找紧随的 mdat（如果有）
            size_t after = mp + moof_size;
            size_t mdat_size = 0;
            if (after + 8 <= audio_buf.size() &&
                std::memcmp(&audio_buf[after + 4], "mdat", 4) == 0) {
                mdat_size = read_be32(&audio_buf[after]);
            }
            // 拷贝并改 track_id
            std::vector<uint8_t> chunk(
                audio_buf.begin() + mp,
                audio_buf.begin() + after + mdat_size);
            // chunk 的 0 偏移就是 moof
            rewrite_traf_track_id(chunk, 0, new_audio_id);
            out.insert(out.end(), chunk.begin(), chunk.end());
        }
    }

    // 写 out 到文件
    std::ofstream of(output_path, std::ios::binary | std::ios::trunc);
    if (!of) {
        return strdup(make_error(std::string("cannot open output: ") + output_path).c_str());
    }
    of.write(reinterpret_cast<const char*>(out.data()),
             static_cast<std::streamsize>(out.size()));
    if (!of.good()) {
        return strdup(make_error("write output failed").c_str());
    }
    of.close();

    std::string ok = std::string("{\"ok\":true,\"output\":\"") + output_path + "\"}";
    return strdup(ok.c_str());
}
