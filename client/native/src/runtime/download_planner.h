#ifndef SEEKER_DOWNLOAD_PLANNER_H
#define SEEKER_DOWNLOAD_PLANNER_H

#include <map>
#include <string>

namespace seeker {

struct DownloadPlanData {
    std::string media_id;
    std::string source_id;
    std::string title;
    std::string kind;
    std::string primary_url;
    std::string filename;
    std::string save_path;
    std::string mime_type;
    std::map<std::string, std::string> headers;
    bool reuse_cache = true;
    bool supports_resume = true;
};

class DownloadPlanner {
public:
    std::string build_plan_json(
        int32_t runtime_id,
        const std::string& resolved_media_json,
        const std::string& options_json
    ) const;

    DownloadPlanData parse_plan_json(const std::string& download_plan_json) const;

private:
    std::string derive_filename(
        const std::string& title,
        const std::string& primary_url,
        const std::string& options_json,
        const std::string& mime_type
    ) const;
    std::string derive_extension(
        const std::string& primary_url,
        const std::string& mime_type
    ) const;
    std::string sanitize_filename(const std::string& input) const;
};

} // namespace seeker

#endif // SEEKER_DOWNLOAD_PLANNER_H
