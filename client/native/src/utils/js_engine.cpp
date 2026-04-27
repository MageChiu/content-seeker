/// JavaScript 引擎实现
/// 当 QuickJS 可用时使用真实引擎，否则提供桩实现
/// QuickJS 将作为 git submodule 引入到 third_party/quickjs/

#include "js_engine.h"

#if __has_include("quickjs.h")
// ===== QuickJS 真实实现 =====
#include "quickjs.h"
#include <cstring>

namespace seeker {

struct JsEngine::Impl {
    JSRuntime* rt = nullptr;
    JSContext* ctx = nullptr;

    Impl() {
        rt = JS_NewRuntime();
        if (rt) {
            // 限制内存使用（防止恶意 JS 占用过多资源）
            JS_SetMemoryLimit(rt, 64 * 1024 * 1024); // 64MB
            JS_SetMaxStackSize(rt, 1024 * 1024);      // 1MB stack
            ctx = JS_NewContext(rt);
        }
    }

    ~Impl() {
        if (ctx) JS_FreeContext(ctx);
        if (rt) JS_FreeRuntime(rt);
    }

    bool is_valid() const { return ctx != nullptr; }

    std::string eval(const std::string& code) {
        if (!ctx) return "";
        JSValue val = JS_Eval(ctx, code.c_str(), code.size(), "<eval>", JS_EVAL_TYPE_GLOBAL);
        std::string result = js_value_to_string(val);
        JS_FreeValue(ctx, val);
        return result;
    }

    bool exec(const std::string& code) {
        if (!ctx) return false;
        JSValue val = JS_Eval(ctx, code.c_str(), code.size(), "<exec>", JS_EVAL_TYPE_GLOBAL);
        bool ok = !JS_IsException(val);
        JS_FreeValue(ctx, val);
        return ok;
    }

    std::string call(const std::string& func_name, const std::string& arg) {
        if (!ctx) return "";
        // 通过 eval 调用函数
        std::string code = func_name + "(\"" + escape_js_string(arg) + "\")";
        return eval(code);
    }

private:
    std::string js_value_to_string(JSValue val) {
        if (JS_IsException(val)) {
            JSValue exc = JS_GetException(ctx);
            const char* str = JS_ToCString(ctx, exc);
            std::string result = str ? std::string("ERROR: ") + str : "ERROR: unknown";
            JS_FreeCString(ctx, str);
            JS_FreeValue(ctx, exc);
            return result;
        }
        const char* str = JS_ToCString(ctx, val);
        std::string result = str ? str : "";
        JS_FreeCString(ctx, str);
        return result;
    }

    static std::string escape_js_string(const std::string& s) {
        std::string result;
        result.reserve(s.size());
        for (char c : s) {
            switch (c) {
                case '"': result += "\\\""; break;
                case '\\': result += "\\\\"; break;
                case '\n': result += "\\n"; break;
                case '\r': result += "\\r"; break;
                default: result += c; break;
            }
        }
        return result;
    }
};

} // namespace seeker

#else
// ===== 无 QuickJS 时的桩实现 =====

namespace seeker {

struct JsEngine::Impl {
    bool is_valid() const { return false; }
    std::string eval(const std::string&) { return ""; }
    bool exec(const std::string&) { return false; }
    std::string call(const std::string&, const std::string&) { return ""; }
};

} // namespace seeker

#endif // QuickJS available

namespace seeker {

JsEngine::JsEngine() : impl_(std::make_unique<Impl>()) {}
JsEngine::~JsEngine() = default;

std::string JsEngine::eval(const std::string& code) {
    return impl_->eval(code);
}

bool JsEngine::exec(const std::string& code) {
    return impl_->exec(code);
}

std::string JsEngine::call(const std::string& func_name, const std::string& arg) {
    return impl_->call(func_name, arg);
}

bool JsEngine::is_valid() const {
    return impl_->is_valid();
}

} // namespace seeker
