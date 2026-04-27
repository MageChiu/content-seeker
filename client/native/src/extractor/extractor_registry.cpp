#include "extractor_registry.h"

namespace seeker {

ExtractorRegistry& ExtractorRegistry::instance() {
    static ExtractorRegistry registry;
    return registry;
}

void ExtractorRegistry::register_plugin(std::unique_ptr<ExtractorPlugin> plugin) {
    plugins_.push_back(std::move(plugin));
}

ExtractorPlugin* ExtractorRegistry::find_plugin(const std::string& url) const {
    for (const auto& plugin : plugins_) {
        if (plugin->can_handle(url)) {
            return plugin.get();
        }
    }
    return nullptr;
}

std::vector<std::string> ExtractorRegistry::get_plugin_names() const {
    std::vector<std::string> names;
    names.reserve(plugins_.size());
    for (const auto& plugin : plugins_) {
        names.push_back(plugin->name());
    }
    return names;
}

} // namespace seeker
