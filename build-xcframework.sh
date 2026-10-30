#!/bin/bash
#
# 将 source/mailcore2-master 打包为 MailCore.xcframework，输出到根目录 lib/ 下。
#
# 用法:
#   ./build-xcframework.sh            # 默认 Release
#   ./build-xcframework.sh Debug      # Debug 配置
#
# 依赖: source/mailcore2-master/Externals 下已编译好的 libetpan-ios / ctemplate-ios / tidy-html5-ios
# 注意: Externals 中的 arm64 切片是模拟器版本，真机构建需要含 iOS 设备切片的依赖库，
#       可通过环境变量 DEVICE_EXTERNALS_DIR 指定其目录（默认自动探测同级 mailcore2-master 仓库）

set -euo pipefail

CONFIGURATION="${1:-Release}"
# 工程默认为 iOS 8.0，新版 Xcode 不再支持，需覆盖部署目标
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-15.0}"

SRC_ROOT="$(cd "$(dirname "$0")" && pwd)"
MAILCORE_DIR="$SRC_ROOT/source/mailcore2-master"
XCODE_PROJ="$MAILCORE_DIR/build-mac/mailcore2.xcodeproj"
BUILD_DIR="$SRC_ROOT/.xcframework-build"
TMP_ROOT="$BUILD_DIR/tmp"
OUTPUT_XCFW="$SRC_ROOT/lib/MailCore.xcframework"

# 无论成功还是失败，退出时都清理临时隐藏目录
trap 'rm -rf "$BUILD_DIR"' EXIT

# 真机构建时的依赖库搜索路径（需包含 iOS 设备 arm64 切片）
# 检查方法: 取 .a 的 arm64 切片中任一目标文件，看是否为 LC_VERSION_MIN_IPHONEOS(老真机)
# 或 LC_BUILD_VERSION platform 2(iOS 设备)；新版依赖库的 arm64 切片为 platform 7(模拟器)
arch_has_device_slice() {
    local lib="$1"
    mkdir -p "$TMP_ROOT" || return 1
    local tmp; tmp=$(mktemp -d "$TMP_ROOT/probe.XXXXXX") || return 1
    lipo "$lib" -thin arm64 -output "$tmp/arm64.a" 2>/dev/null || { rm -rf "$tmp"; return 1; }
    local obj; obj=$(ar t "$tmp/arm64.a" | grep -v SYMDEF | head -1)
    # 先 cd 到绝对路径再解压，避免 .o 散落到当前工作目录
    (cd "$tmp" && ar x "$tmp/arm64.a" "$obj" 2>/dev/null)
    local info
    info=$(otool -l "$tmp/$obj" 2>/dev/null | grep -E 'LC_VERSION_MIN_IPHONEOS|platform')
    rm -rf "$tmp"
    echo "$info" | grep -q 'LC_VERSION_MIN_IPHONEOS' && return 0
    echo "$info" | grep -A1 'LC_BUILD_VERSION' | grep -qE 'platform 2$'
}

DEVICE_LIB_PATHS=""
candidates=("${DEVICE_EXTERNALS_DIR:-}" "$SRC_ROOT/../mailcore2-master/Externals" "$MAILCORE_DIR/Externals")
for ext in "${candidates[@]}"; do
    [ -n "$ext" ] && [ -d "$ext/libetpan-ios/lib" ] || continue
    if arch_has_device_slice "$ext/ctemplate-ios/lib/libctemplate-ios.a"; then
        DEVICE_LIB_PATHS="$ext/libetpan-ios/lib $ext/ctemplate-ios/lib $ext/libsasl-ios/lib $ext/tidy-html5-ios/lib"
        echo "==> 真机依赖库使用: $ext"
        break
    fi
done

if [ -z "$DEVICE_LIB_PATHS" ]; then
    echo "警告: 未找到含 iOS 真机 arm64 切片的 Externals 依赖库，真机构建可能失败" >&2
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

for sdk in iphoneos iphonesimulator; do
    if [ "$sdk" = "iphoneos" ]; then
        platform="iOS"
    else
        platform="iOS Simulator"
    fi
    echo "==> 构建 mailcore ios ($sdk, $CONFIGURATION) ..."
    rm -rf "$BUILD_DIR/mailcore2-$sdk.xcarchive"
    EXTRA_ARGS=""
    if [ "$sdk" = "iphoneos" ] && [ -n "$DEVICE_LIB_PATHS" ]; then
        EXTRA_ARGS="LIBRARY_SEARCH_PATHS=$DEVICE_LIB_PATHS"
    fi
    xcodebuild archive \
        -project "$XCODE_PROJ" \
        -scheme "mailcore ios" \
        -configuration "$CONFIGURATION" \
        -sdk "$sdk" \
        -destination "generic/platform=$platform" \
        -archivePath "$BUILD_DIR/mailcore2-$sdk.xcarchive" \
        IPHONEOS_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        ${EXTRA_ARGS:+"$EXTRA_ARGS"} \
        | tail -5
done

FRAMEWORK_DEVICE="$BUILD_DIR/mailcore2-iphoneos.xcarchive/Products/Frameworks/MailCore.framework"
FRAMEWORK_SIM="$BUILD_DIR/mailcore2-iphonesimulator.xcarchive/Products/Frameworks/MailCore.framework"

if [ ! -d "$FRAMEWORK_DEVICE" ] || [ ! -d "$FRAMEWORK_SIM" ]; then
    echo "错误: 未找到编译产物 MailCore.framework，请检查上面的编译日志。" >&2
    exit 1
fi

echo "==> 合成 MailCore.xcframework ..."
rm -rf "$OUTPUT_XCFW"
mkdir -p "$(dirname "$OUTPUT_XCFW")"

xcodebuild -create-xcframework \
    -framework "$FRAMEWORK_DEVICE" \
    -framework "$FRAMEWORK_SIM" \
    -output "$OUTPUT_XCFW"

echo "==> 清理中间产物 ..."
rm -rf "$BUILD_DIR"

echo ""
echo "完成: $OUTPUT_XCFW"
lipo -info "$OUTPUT_XCFW/ios-arm64/MailCore.framework/MailCore" 2>/dev/null || true
lipo -info "$OUTPUT_XCFW/ios-arm64_x86_64-simulator/MailCore.framework/MailCore" 2>/dev/null || true
