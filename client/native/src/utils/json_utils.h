#ifndef SEEKER_JSON_UTILS_H
#define SEEKER_JSON_UTILS_H

#include <string>
#include <vector>
#include <map>
#include <cstdint>

namespace seeker {
namespace json {

/// 从 JSON 字符串中提取指定 key 对应的字符串值
/// 仅支持简单的顶层 key 查找，不处理嵌套
std::string get_string(const std::string& json, const std::string& key);

/// 从 JSON 字符串中提取指定 key 对应的整数值
int get_int(const std::string& json, const std::string& key, int default_val = 0);

/// 从 JSON 字符串中提取指定 key 对应的 64 位整数值
int64_t get_int64(const std::string& json, const std::string& key, int64_t default_val = 0);

/// 从 JSON 对象中提取顶层（depth=1）指定 key 的 int64 值
/// 不会匹配嵌套对象/数组中同名的 key
int64_t get_top_level_int64(const std::string& json, const std::string& key, int64_t default_val = 0);

/// 从 JSON 对象字符串中提取指定路径的值（支持 "data.dash.video" 形式）
std::string get_nested(const std::string& json, const std::string& path);

/// 提取 JSON 数组中每个对象的指定字段
std::vector<std::string> get_array_field(const std::string& json_array, const std::string& field);

/// 构建简单的 JSON 对象字符串
std::string build_object(const std::map<std::string, std::string>& fields);

/// 构建流提取结果的标准 JSON
std::string build_stream_result(
    const std::string& url,
    const std::string& title,
    const std::string& quality,
    const std::string& mime_type,
    const std::map<std::string, std::string>& headers,
    const std::string& audio_url = ""
);

/// JSON 字符串转义
std::string escape(const std::string& s);

/// 查找 JSON 数组的起始和结束位置
bool find_array(const std::string& json, const std::string& key, size_t& start, size_t& end);

/// 查找 JSON 对象的起始和结束位置
bool find_object(const std::string& json, const std::string& key, size_t& start, size_t& end);

} // namespace json
} // namespace seeker

#endif // SEEKER_JSON_UTILS_H
