/// 简易 JSON 工具实现
/// 不依赖第三方库，仅处理已知结构的 API 响应

#include "json_utils.h"
#include <sstream>
#include <algorithm>

namespace seeker {
namespace json {

// 跳过空白字符
static size_t skip_ws(const std::string& s, size_t pos) {
    while (pos < s.size() && (s[pos] == ' ' || s[pos] == '\t' || s[pos] == '\n' || s[pos] == '\r'))
        ++pos;
    return pos;
}

// 查找匹配的闭合字符（处理嵌套）
static size_t find_matching(const std::string& s, size_t start, char open, char close) {
    int depth = 1;
    bool in_string = false;
    for (size_t i = start + 1; i < s.size(); ++i) {
        if (s[i] == '\\' && in_string) { ++i; continue; }
        if (s[i] == '"') { in_string = !in_string; continue; }
        if (in_string) continue;
        if (s[i] == open) ++depth;
        else if (s[i] == close) { --depth; if (depth == 0) return i; }
    }
    return std::string::npos;
}

// 提取引号内的字符串值
static std::string extract_string_value(const std::string& s, size_t pos) {
    pos = skip_ws(s, pos);
    if (pos >= s.size() || s[pos] != '"') return "";
    ++pos;
    std::string result;
    while (pos < s.size() && s[pos] != '"') {
        if (s[pos] == '\\' && pos + 1 < s.size()) {
            ++pos;
            switch (s[pos]) {
                case '"': result += '"'; break;
                case '\\': result += '\\'; break;
                case '/': result += '/'; break;
                case 'n': result += '\n'; break;
                case 't': result += '\t'; break;
                case 'r': result += '\r'; break;
                case 'b': result += '\b'; break;
                case 'f': result += '\f'; break;
                case 'u': {
                    // Unicode 转义 \uXXXX
                    if (pos + 4 < s.size()) {
                        unsigned int code = 0;
                        bool valid = true;
                        for (int k = 1; k <= 4; ++k) {
                            char hc = s[pos + k];
                            code <<= 4;
                            if (hc >= '0' && hc <= '9') code |= (hc - '0');
                            else if (hc >= 'a' && hc <= 'f') code |= (hc - 'a' + 10);
                            else if (hc >= 'A' && hc <= 'F') code |= (hc - 'A' + 10);
                            else { valid = false; break; }
                        }
                        if (valid) {
                            // 转 UTF-8
                            if (code < 0x80) {
                                result += static_cast<char>(code);
                            } else if (code < 0x800) {
                                result += static_cast<char>(0xC0 | (code >> 6));
                                result += static_cast<char>(0x80 | (code & 0x3F));
                            } else {
                                // 注意：未处理 surrogate pair（Bilibili API 中
                                // 一般不会出现 BMP 之外的字符）
                                result += static_cast<char>(0xE0 | (code >> 12));
                                result += static_cast<char>(0x80 | ((code >> 6) & 0x3F));
                                result += static_cast<char>(0x80 | (code & 0x3F));
                            }
                            pos += 4; // 跳过 4 个 hex 字符
                        } else {
                            result += s[pos];
                        }
                    } else {
                        result += s[pos];
                    }
                    break;
                }
                default: result += s[pos]; break;
            }
        } else {
            result += s[pos];
        }
        ++pos;
    }
    return result;
}

// 提取数值（整数或浮点数字面量）
static std::string extract_number(const std::string& s, size_t pos) {
    pos = skip_ws(s, pos);
    std::string result;
    while (pos < s.size() && (s[pos] == '-' || s[pos] == '+' || s[pos] == '.' ||
           (s[pos] >= '0' && s[pos] <= '9') || s[pos] == 'e' || s[pos] == 'E')) {
        result += s[pos++];
    }
    return result;
}

// 在 JSON 中查找 key 对应的值起始位置
static size_t find_key_value(const std::string& json, const std::string& key) {
    std::string search = "\"" + key + "\"";
    size_t pos = 0;
    while (true) {
        pos = json.find(search, pos);
        if (pos == std::string::npos) return std::string::npos;
        // 确保下一个非空白字符是冒号
        size_t after_key = skip_ws(json, pos + search.size());
        if (after_key < json.size() && json[after_key] == ':') {
            return skip_ws(json, after_key + 1);
        }
        pos += search.size();
    }
}

std::string get_string(const std::string& json, const std::string& key) {
    size_t pos = find_key_value(json, key);
    if (pos == std::string::npos) return "";
    if (json[pos] == '"') return extract_string_value(json, pos);
    // 对于数值，也返回字符串形式
    return extract_number(json, pos);
}

int get_int(const std::string& json, const std::string& key, int default_val) {
    size_t pos = find_key_value(json, key);
    if (pos == std::string::npos) return default_val;
    std::string num = extract_number(json, pos);
    if (num.empty()) return default_val;
    try { return std::stoi(num); } catch (...) { return default_val; }
}

int64_t get_int64(const std::string& json, const std::string& key, int64_t default_val) {
    size_t pos = find_key_value(json, key);
    if (pos == std::string::npos) return default_val;
    std::string num = extract_number(json, pos);
    if (num.empty()) return default_val;
    try { return std::stoll(num); } catch (...) { return default_val; }
}

int64_t get_top_level_int64(const std::string& json, const std::string& key, int64_t default_val) {
    // 只在 JSON 对象的第一层查找 key（深度=1，即紧跟在最外层 {} 内）
    // 不会匹配嵌套在 子对象/数组 中同名的 key
    std::string search = "\"" + key + "\"";
    int depth = 0;
    bool in_string = false;

    for (size_t i = 0; i < json.size(); ++i) {
        char c = json[i];
        if (in_string) {
            if (c == '\\') { ++i; continue; } // skip escaped char
            if (c == '"') in_string = false;
            continue;
        }
        if (c == '"') {
            // 只在 depth==1 时检查是否为目标 key
            if (depth == 1 && json.compare(i, search.size(), search) == 0) {
                size_t after_key = skip_ws(json, i + search.size());
                if (after_key < json.size() && json[after_key] == ':') {
                    size_t val_pos = skip_ws(json, after_key + 1);
                    // 处理 null
                    if (val_pos + 3 < json.size() &&
                        json.compare(val_pos, 4, "null") == 0) {
                        return default_val;
                    }
                    std::string num = extract_number(json, val_pos);
                    if (num.empty()) return default_val;
                    try { return std::stoll(num); } catch (...) { return default_val; }
                }
            }
            in_string = true;
            continue;
        }
        if (c == '{' || c == '[') ++depth;
        else if (c == '}' || c == ']') --depth;
    }
    return default_val;
}

std::string get_nested(const std::string& json, const std::string& path) {
    // 按 '.' 分割路径
    std::string current = json;
    size_t start = 0;
    while (start < path.size()) {
        size_t dot = path.find('.', start);
        std::string key = (dot == std::string::npos) ? path.substr(start) : path.substr(start, dot - start);
        start = (dot == std::string::npos) ? path.size() : dot + 1;

        size_t pos = find_key_value(current, key);
        if (pos == std::string::npos) return "";

        if (current[pos] == '{') {
            size_t end = find_matching(current, pos, '{', '}');
            if (end == std::string::npos) return "";
            current = current.substr(pos, end - pos + 1);
        } else if (current[pos] == '[') {
            size_t end = find_matching(current, pos, '[', ']');
            if (end == std::string::npos) return "";
            current = current.substr(pos, end - pos + 1);
        } else if (current[pos] == '"') {
            return extract_string_value(current, pos);
        } else {
            return extract_number(current, pos);
        }
    }
    return current;
}

bool find_array(const std::string& json, const std::string& key, size_t& start, size_t& end) {
    size_t pos = find_key_value(json, key);
    if (pos == std::string::npos || json[pos] != '[') return false;
    start = pos;
    end = find_matching(json, pos, '[', ']');
    return end != std::string::npos;
}

bool find_object(const std::string& json, const std::string& key, size_t& start, size_t& end) {
    size_t pos = find_key_value(json, key);
    if (pos == std::string::npos || json[pos] != '{') return false;
    start = pos;
    end = find_matching(json, pos, '{', '}');
    return end != std::string::npos;
}

std::vector<std::string> get_array_field(const std::string& json_array, const std::string& field) {
    std::vector<std::string> results;
    // 遍历数组中的每个对象
    size_t pos = skip_ws(json_array, 0);
    if (pos >= json_array.size() || json_array[pos] != '[') return results;
    pos = skip_ws(json_array, pos + 1);

    while (pos < json_array.size() && json_array[pos] != ']') {
        if (json_array[pos] == '{') {
            size_t obj_end = find_matching(json_array, pos, '{', '}');
            if (obj_end == std::string::npos) break;
            std::string obj = json_array.substr(pos, obj_end - pos + 1);
            results.push_back(get_string(obj, field));
            pos = skip_ws(json_array, obj_end + 1);
            if (pos < json_array.size() && json_array[pos] == ',')
                pos = skip_ws(json_array, pos + 1);
        } else {
            ++pos;
        }
    }
    return results;
}

std::map<std::string, std::string> get_object_string_map(
    const std::string& json,
    const std::string& key
) {
    std::map<std::string, std::string> result;
    size_t start = 0;
    size_t end = 0;
    if (!find_object(json, key, start, end)) {
      return result;
    }

    const std::string object = json.substr(start, end - start + 1);
    size_t pos = skip_ws(object, 0);
    if (pos >= object.size() || object[pos] != '{') return result;
    pos = skip_ws(object, pos + 1);

    while (pos < object.size() && object[pos] != '}') {
        if (object[pos] != '"') {
            ++pos;
            continue;
        }
        const size_t key_start = pos;
        const std::string field_key = extract_string_value(object, key_start);
        if (field_key.empty()) {
            ++pos;
            continue;
        }
        pos = object.find(':', key_start);
        if (pos == std::string::npos) break;
        pos = skip_ws(object, pos + 1);
        std::string field_value;
        if (pos < object.size() && object[pos] == '"') {
            field_value = extract_string_value(object, pos);
            pos = object.find('"', pos + 1);
            while (pos != std::string::npos && pos + 1 < object.size() && object[pos - 1] == '\\') {
                pos = object.find('"', pos + 1);
            }
            if (pos == std::string::npos) break;
            ++pos;
        } else {
            field_value = extract_number(object, pos);
            pos += field_value.size();
        }
        result[field_key] = field_value;
        pos = skip_ws(object, pos);
        if (pos < object.size() && object[pos] == ',') {
            pos = skip_ws(object, pos + 1);
        }
    }
    return result;
}

std::string escape(const std::string& s) {
    std::string result;
    result.reserve(s.size() + 16);
    for (char c : s) {
        switch (c) {
            case '"': result += "\\\""; break;
            case '\\': result += "\\\\"; break;
            case '\n': result += "\\n"; break;
            case '\r': result += "\\r"; break;
            case '\t': result += "\\t"; break;
            default: result += c; break;
        }
    }
    return result;
}

std::string build_object(const std::map<std::string, std::string>& fields) {
    std::ostringstream ss;
    ss << "{";
    bool first = true;
    for (const auto& [key, value] : fields) {
        if (!first) ss << ",";
        first = false;
        ss << "\"" << escape(key) << "\":\"" << escape(value) << "\"";
    }
    ss << "}";
    return ss.str();
}

std::string build_stream_result(
    const std::string& url,
    const std::string& title,
    const std::string& quality,
    const std::string& mime_type,
    const std::map<std::string, std::string>& headers,
    const std::string& audio_url
) {
    std::ostringstream ss;
    ss << "{";
    ss << "\"url\":\"" << escape(url) << "\"";
    ss << ",\"title\":\"" << escape(title) << "\"";
    ss << ",\"quality\":\"" << escape(quality) << "\"";
    ss << ",\"mimeType\":\"" << escape(mime_type) << "\"";
    if (!audio_url.empty()) {
        ss << ",\"audioUrl\":\"" << escape(audio_url) << "\"";
    }
    ss << ",\"headers\":{";
    bool first = true;
    for (const auto& [key, value] : headers) {
        if (!first) ss << ",";
        first = false;
        ss << "\"" << escape(key) << "\":\"" << escape(value) << "\"";
    }
    ss << "}";
    ss << "}";
    return ss.str();
}

} // namespace json
} // namespace seeker
