#!/usr/bin/env bash
# Content Seeker 客户端构建脚本
# 用法: ./scripts/build.sh [选项]
#
# 选项:
#   -p, --platform <platform>   目标平台: macos, ios, android, windows, linux (默认: macos)
#   -m, --mode <mode>           构建模式: debug, release, profile (默认: debug)
#   -r, --run                   构建后立即运行
#   -c, --clean                 构建前执行 clean
#   -v, --verbose               显示详细输出
#   -h, --help                  显示帮助信息
#
# 示例:
#   ./scripts/build.sh -p macos -m debug -r
#   ./scripts/build.sh --platform android --mode release
#   ./scripts/build.sh -p ios -m profile -v

set -euo pipefail

# 默认值
PLATFORM="macos"
MODE="debug"
RUN=false
CLEAN=false
VERBOSE=false

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
    sed -n '2,16p' "$0" | sed 's/^# \?//'
    exit 0
}

# 解析参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--platform)
            PLATFORM="${2:-}"
            shift 2
            ;;
        -m|--mode)
            MODE="${2:-}"
            shift 2
            ;;
        -r|--run)
            RUN=true
            shift
            ;;
        -c|--clean)
            CLEAN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            error "未知参数: $1"
            usage
            ;;
    esac
done

# 规范化平台名
PLATFORM_LOWER=$(echo "$PLATFORM" | tr '[:upper:]' '[:lower:]')
case "$PLATFORM_LOWER" in
    macos|mac|darwin)   PLATFORM="macos" ;;
    ios|iphone)         PLATFORM="ios" ;;
    android|apk)        PLATFORM="android" ;;
    windows|win)        PLATFORM="windows" ;;
    linux)              PLATFORM="linux" ;;
    *)
        error "不支持的平台: $PLATFORM"
        error "可选: macos, ios, android, windows, linux"
        exit 1
        ;;
esac

# 规范化构建模式
MODE_LOWER=$(echo "$MODE" | tr '[:upper:]' '[:lower:]')
case "$MODE_LOWER" in
    debug|dbg)      MODE="debug" ;;
    release|rel)    MODE="release" ;;
    profile|prof)   MODE="profile" ;;
    *)
        error "不支持的模式: $MODE"
        error "可选: debug, release, profile"
        exit 1
        ;;
esac

# 检测当前操作系统
detect_host_os() {
    case "$(uname -s)" in
        Darwin*)  echo "macos" ;;
        Linux*)   echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)        echo "unknown" ;;
    esac
}

HOST_OS=$(detect_host_os)

# 平台兼容性检查
validate_platform() {
    case "$PLATFORM" in
        macos|ios)
            if [[ "$HOST_OS" != "macos" ]]; then
                error "$PLATFORM 只能在 macOS 上构建"
                exit 1
            fi
            ;;
        windows)
            if [[ "$HOST_OS" != "windows" ]]; then
                error "windows 只能在 Windows 上构建"
                exit 1
            fi
            ;;
        linux)
            if [[ "$HOST_OS" != "linux" ]]; then
                error "linux 只能在 Linux 上构建"
                exit 1
            fi
            ;;
        android)
            # Android 可以在任何平台上交叉编译
            ;;
    esac
}

validate_platform

# 切换到 client 目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$CLIENT_DIR"

info "平台: $PLATFORM | 模式: $MODE | 运行: $RUN"
info "工作目录: $CLIENT_DIR"

# Clean
if [[ "$CLEAN" == true ]]; then
    info "执行 flutter clean..."
    flutter clean
    ok "clean 完成"
fi

# 构建参数
BUILD_ARGS=()
if [[ "$VERBOSE" == true ]]; then
    BUILD_ARGS+=("--verbose")
fi

case "$MODE" in
    debug)   BUILD_ARGS+=("--debug") ;;
    release) BUILD_ARGS+=("--release") ;;
    profile) BUILD_ARGS+=("--profile") ;;
esac

# 平台特定参数
case "$PLATFORM" in
    android)
        BUILD_ARGS+=("--target-platform" "android-arm64")
        ;;
esac

# 执行构建或运行
FLUTTER_CMD="build"
if [[ "$RUN" == true ]]; then
    FLUTTER_CMD="run"
fi

DEVICE_ARG=""
case "$PLATFORM" in
    macos)   DEVICE_ARG="-d macos" ;;
    ios)     DEVICE_ARG="-d ios" ;;
    android) DEVICE_ARG="-d android" ;;
    windows) DEVICE_ARG="-d windows" ;;
    linux)   DEVICE_ARG="-d linux" ;;
esac

# 构建命令
if [[ "$FLUTTER_CMD" == "run" ]]; then
    CMD="flutter run $DEVICE_ARG ${BUILD_ARGS[*]}"
else
    CMD="flutter build $PLATFORM ${BUILD_ARGS[*]}"
fi

info "执行: $CMD"
echo ""

eval "$CMD"
EXIT_CODE=$?

echo ""
if [[ $EXIT_CODE -eq 0 ]]; then
    ok "构建成功！平台=$PLATFORM 模式=$MODE"
else
    error "构建失败 (exit code: $EXIT_CODE)"
    exit $EXIT_CODE
fi
