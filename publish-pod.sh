#!/bin/bash
#
# CMailcore-ios CocoaPods 发布脚本
#
# 流程: 校验版本 -> (可选)重新打包 xcframework -> lint 校验 -> 提交打 tag 推送 -> trunk push
#
# 用法:
#   ./publish-pod.sh                    # 使用 podspec 中的当前版本号发布（产物已存在则不重编）
#   ./publish-pod.sh 0.3.0              # 先将 podspec 版本号改为 0.3.0，再执行发布
#   ./publish-pod.sh --rebuild          # 强制重新执行 build-xcframework.sh 后发布
#   ./publish-pod.sh 0.3.0 --rebuild    # 组合使用
#   ./publish-pod.sh --dry-run          # 只演练校验和 lint，不做提交/tag/推送/trunk 发布
#
# 前置条件:
#   1. git 工作区改动会被本脚本提交（Release <版本号>），如有不想提交的改动请先自行处理
#   2. trunk 发布需要已注册: pod trunk register <邮箱> '<姓名>'

set -euo pipefail

SRC_ROOT="$(cd "$(dirname "$0")" && pwd)"
PODSPEC="$SRC_ROOT/CMailcore-ios.podspec"
XCFW="$SRC_ROOT/lib/MailCore.xcframework"
GIT_URL="git@github.com:driverZhan/mailcore-ios.git"

REBUILD=NO
DRY_RUN=NO
NEW_VERSION=""
YES=NO

for arg in "$@"; do
    case "$arg" in
        --rebuild)  REBUILD=YES ;;
        --dry-run)  DRY_RUN=YES ;;
        --yes|-y)   YES=YES ;;
        *)          NEW_VERSION="$arg" ;;
    esac
done

info()  { echo "==> $*"; }
fail()  { echo "错误: $*" >&2; exit 1; }

confirm() {
    if [ "$YES" = YES ] || [ "$DRY_RUN" = YES ]; then
        return 0
    fi
    printf '%s [y/N] ' "$1"
    read -r ans
    [ "$ans" = "y" ] || [ "$ans" = "Y" ]
}

cd "$SRC_ROOT"

# ---------- 1. 版本号 ----------
[ -f "$PODSPEC" ] || fail "未找到 $PODSPEC"

CURRENT_VERSION=$(grep -oE 'spec\.version\s*=\s*"[^"]+"' "$PODSPEC" | sed -E 's/.*"([^"]+)".*/\1/')
[ -n "$CURRENT_VERSION" ] || fail "无法从 podspec 解析版本号"

if [ -n "$NEW_VERSION" ]; then
    if ! echo "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        fail "版本号格式不正确: ${NEW_VERSION}（应为 X.Y.Z）"
    fi
    VERSION="$NEW_VERSION"
else
    VERSION="$CURRENT_VERSION"
fi
info "发布版本: ${VERSION}"

if git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null; then
    fail "tag ${VERSION} 已存在，请更换版本号（历史 tag: $(git tag -l | tr '\n' ' ')）"
fi

# tag 校验通过后再修改 podspec，避免失败时留下脏改动
if [ -n "$NEW_VERSION" ] && [ "$DRY_RUN" = NO ]; then
    info "更新 podspec 版本号: ${CURRENT_VERSION} -> ${NEW_VERSION}"
    sed -i '' -E "s/(spec\.version\s*=\s*)\"[^\"]+\"/\1\"${NEW_VERSION}\"/" "$PODSPEC"
fi

# ---------- 2. 构建产物 ----------
if [ "$REBUILD" = YES ] || [ ! -d "$XCFW" ]; then
    info "执行 build-xcframework.sh 生成最新产物 ..."
    "$SRC_ROOT/build-xcframework.sh"
else
    info "使用已有产物 lib/MailCore.xcframework（如需重编请加 --rebuild）"
fi
[ -d "$XCFW" ] || fail "产物不存在: $XCFW"

# 校验双平台切片
for slice in ios-arm64 ios-arm64_x86_64-simulator; do
    bin="$XCFW/$slice/MailCore.framework/MailCore"
    [ -f "$bin" ] || fail "产物缺少 ${slice} 切片"
    info "切片检查: ${slice} -> $(lipo -archs "$bin")"
done

# ---------- 3. podspec 与 trunk 校验 ----------
info "校验 podspec 语法 ..."
pod ipc spec "$PODSPEC" > /dev/null

command -v pod > /dev/null || fail "未安装 cocoapods"

if [ "$DRY_RUN" = NO ]; then
    info "pod lib lint 校验（需要网络，首次较慢）..."
    if ! pod lib lint "$PODSPEC" --allow-warnings; then
        fail "pod lib lint 未通过，请根据上方日志修复后重试"
    fi
fi

# ---------- 4. 提交、打 tag、推送 ----------
info "当前分支: $(git rev-parse --abbrev-ref HEAD)"
git status --porcelain | grep -q . && info "注意: 以下改动将一并提交:" && git status --short

if [ "$DRY_RUN" = YES ]; then
    info "[dry-run] 跳过: git commit / tag / push / trunk push"
    exit 0
fi

confirm "确认提交并打 tag ${VERSION}，推送到 origin？" || fail "已取消"

git add -A
git commit -m "Release $VERSION"
git tag "$VERSION"
git push origin "$(git rev-parse --abbrev-ref HEAD)" --follow-tags
info "已推送 tag: ${VERSION}"

# ---------- 5. 发布到 trunk ----------
confirm "确认执行 pod trunk push 发布到 CocoaPods 官方仓库？" || fail "已跳过 trunk push，可稍后手动执行"

pod trunk push "$PODSPEC" --allow-warnings --remote="$GIT_URL"
info "发布完成: https://cocoapods.org/pods/CMailcore-ios (${VERSION})"
