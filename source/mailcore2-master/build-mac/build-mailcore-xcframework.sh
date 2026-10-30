#!/bin/bash
###############################################################################
# build-mailcore-xcframework.sh
#
# 一键把 MailCore 打包成支持【真机 arm64 + 模拟器 x86_64/arm64】的
# MailCore.xcframework（可被 Swift 直接 `import MailCore`）。
#
# 流程（全程按平台分别构建，最后用 xcframework 封装 —— 因为真机 arm64 与
# 模拟器 arm64 架构同名但平台不同，lipo 无法合并进同一个二进制）：
#   1. 拉取依赖源码(ctemplate / tidy-html5 / libetpan，含 cyrus-sasl 源码包)
#   2. cyrus-sasl: 交叉编译 libsasl2 (arm64 真机 + x86_64/arm64 模拟器)
#   3. ctemplate / tidy / libetpan: 分 SDK 编译 .a + 头文件
#   4. 组装 Externals，分 SDK 编译 MailCore.framework (iphoneos / iphonesimulator)
#   5. xcodebuild -create-xcframework 合并
#
# 用法：
#   ./build-mailcore-xcframework.sh            # 增量构建(已存在的克隆会复用)
#   ./build-mailcore-xcframework.sh clean      # 先清空中间目录再构建
#   OUTPUT=/path/to/My.xcframework ./build-mailcore-xcframework.sh  # 自定义输出
#   MC_DEPS_SRC=/path/deps ./build-mailcore-xcframework.sh          # 指定本地依赖源码根
#   依赖源码(ctemplate/tidy/libetpan)优先用本地，本地没有才从远端克隆
# 默认输出: <workspace 根>/lib/MailCore.xcframework (由脚本位置动态上溯 3 级得到, 不写死)
###############################################################################
set -uo pipefail

# ----------------------------- 可配置项 --------------------------------------
MIN_IOS="${MIN_IOS:-15.0}"                       # Xcode 27 最低支持 15.0
DEVICE_ARCHS="${DEVICE_ARCHS:-arm64}"
SIM_ARCHS="${SIM_ARCHS:-x86_64 arm64}"
OUTPUT="${OUTPUT:-}"                             # 最终 xcframework 输出路径
# 依赖源码本地优先(找不到才远端克隆)。可用下列方式指定本地源码:
#   MC_DEPS_SRC=/dir      父目录(内含 ctemplate/tidy/libetpan，或目录本身就是某个源码)
#   CTEMPLATE_SRC / TIDY_SRC / ETPAN_SRC   单独指定某个依赖源码目录
# 也会自动复用 $HOME/MailCore-Builds/dependencies/downloads/<name> 等惯例位置
MC_DEPS_SRC="${MC_DEPS_SRC:-}"
CONFIG=Release

# 新版 clang 把这些旧代码问题当硬错误，降级为警告
WARN="-Wno-error=incompatible-function-pointer-types -Wno-error=implicit-function-declaration -Wno-error=int-conversion -Wno-error=return-type -Wno-error=deprecated-non-prototype -Wno-error=nontrivial-memcall"

# 依赖源码仓库与固定版本(与 scripts/build-*-ios.sh 保持一致)
CTEMPLATE_URL="https://github.com/dinhviethoa/ctemplate";     CTEMPLATE_REV="2c6ff9ae7d0ae1b973e57dd19859b95282776194"
TIDY_URL="https://github.com/dinhviethoa/tidy-html5";         TIDY_REV="71aaa8669c664447743bba73e07d70c291548dca"
ETPAN_URL="https://github.com/driverZhan/libetpan.git";       ETPAN_REV="5164ba2ebd3c7cbc7a9230aad32bdf8e24e207de"

# ----------------------------- 路径 ------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"     # build-mac
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"                           # 仓库根
BUILD_DIR="$SCRIPT_DIR/.xcframework-build"                     # 中间产物
SRC="$BUILD_DIR/src"
OUT="$BUILD_DIR/depsout"
EXT="$ROOT/Externals"
DD="$BUILD_DIR/derived"
LOG="$BUILD_DIR/build.log"
# 上层 workspace 根(build-mac 上溯 3 级: build-mac -> mailcore2-master -> source -> <workspace>)
# 不写死绝对路径, 目录前缀变化时自动适配; 也可用 OUTPUT=... 环境变量覆盖
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
mkdir -p "$BUILD_DIR"
: > "$LOG"
if [[ -z "$OUTPUT" ]]; then OUTPUT="$WORKSPACE_ROOT/lib/MailCore.xcframework"; fi

DEV_SDK="$(xcodebuild -version -sdk iphoneos Path)"
SIM_SDK="$(xcodebuild -version -sdk iphonesimulator Path)"

c_step() { printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }
c_ok()   { printf "\033[1;32m  ✓ %s\033[0m\n" "$*"; }
c_err()  { printf "\033[1;31m  ✗ %s\033[0m\n" "$*" >&2; }
die()    { c_err "$*"; exit 1; }

# clean 参数
if [[ "${1:-}" == "clean" ]]; then
  c_step "clean: 删除 $BUILD_DIR 与 $EXT"
  rm -rf "$BUILD_DIR" "$EXT"
fi
mkdir -p "$SRC" "$OUT" "$DD" "$EXT"

###############################################################################
# 1. 拉取依赖源码
###############################################################################
clone_at() { # url rev dir
  local url="$1" rev="$2" dir="$3" attempt
  if [[ -d "$dir/.git" ]]; then
    ( cd "$dir" && git checkout -q "$rev" 2>/dev/null || { git fetch -q --all; git checkout -q "$rev"; } ) && return 0
  fi
  c_step "克隆 $(basename "$dir") @ ${rev:0:10}"
  for attempt in 1 2 3; do
    git clone -q --filter=blob:none "$url" "$dir" 2>>"$LOG" || git clone -q "$url" "$dir" 2>>"$LOG" || true
    [[ -d "$dir/.git" ]] && break
    c_err "克隆失败，重试 $attempt/3 ..."; rm -rf "$dir"; sleep 3
  done
  [[ -d "$dir/.git" ]] || return 1
  ( cd "$dir" && git checkout -q "$rev" ) || return 1
}

###############################################################################
# 1b. 本地源码优先：按优先级查找已有源码，找不到才远端克隆
###############################################################################
# 在候选目录中找出含 marker 的本地源码(命中输出该目录)
# 优先级: 环境变量指定 > MC_DEPS_SRC > 脚本已准备的 > $HOME 缓存 > 仓库相邻
find_local_src() { # name marker ovr_dir
  local name="$1" marker="$2" ovr="$3" cand
  local -a bases=()
  [[ -n "$ovr" ]] && bases+=("$ovr")
  [[ -n "${MC_DEPS_SRC:-}" ]] && bases+=("$MC_DEPS_SRC/$name" "$MC_DEPS_SRC")
  bases+=("$SRC/$name" "$HOME/MailCore-Builds/dependencies/downloads/$name" \
          "$ROOT/Externals/tmp/dependencies/downloads/$name" "$ROOT/../$name")
  for cand in "${bases[@]}"; do
    [[ -n "$cand" && -e "$cand/$marker" ]] && { echo "$cand"; return 0; }
  done
  return 1
}

# 解析并准备某依赖源码到 $SRC/<name>(本地优先，否则克隆)，成功返回 0
prep_src() { # name url rev marker env_override
  local name="$1" url="$2" rev="$3" marker="$4" ovr="${5:-}"
  local local_dir
  if [[ -e "$SRC/$name/$marker" ]]; then
    c_ok "$name: 复用已准备好的本地源码 $SRC/$name"
    return 0
  fi
  local_dir="$(find_local_src "$name" "$marker" "$ovr")" || local_dir=""
  if [[ -n "$local_dir" ]]; then
    c_step "$name: 使用本地源码 $local_dir"
    rm -rf "$SRC/$name"; mkdir -p "$SRC/$name"
    cp -R "$local_dir/." "$SRC/$name/" 2>>"$LOG" || die "拷贝本地源码失败: $local_dir"
    # 若为 git 仓库则定到固定版本(只影响副本, 不动本地原仓)
    [[ -d "$SRC/$name/.git" ]] && ( cd "$SRC/$name" && git checkout -q "$rev" 2>>"$LOG" || true )
    [[ -e "$SRC/$name/$marker" ]] && return 0
    die "本地源码 $local_dir 不含 $marker"
  fi
  c_step "$name: 本地无源码，从远端克隆"
  clone_at "$url" "$rev" "$SRC/$name"
}

###############################################################################
# 通用：用 xcodeproj 分 SDK 编译某依赖，收集 .a + 头
###############################################################################
build_apple_dep() { # name projdir scheme libname
  local name="$1" projdir="$2" scheme="$3" lib="$4"
  c_step "编译 $name (真机 $DEVICE_ARCHS / 模拟器 $SIM_ARCHS)"
  local ddx="$DD/$name"
  xcodebuild -derivedDataPath "$ddx" -project "$projdir" -scheme "$scheme" \
      -sdk iphoneos -configuration "$CONFIG" \
      ARCHS="$DEVICE_ARCHS" ONLY_ACTIVE_ARCH=NO IPHONEOS_DEPLOYMENT_TARGET="$MIN_IOS" \
      ENABLE_BITCODE=NO GCC_TREAT_WARNINGS_AS_ERRORS=NO OTHER_CFLAGS="\$(inherited) $WARN" \
      build >>"$LOG" 2>&1 || { c_err "$name 真机构建失败"; tail -15 "$LOG"; return 1; }
  xcodebuild -derivedDataPath "$ddx" -project "$projdir" -scheme "$scheme" \
      -sdk iphonesimulator -configuration "$CONFIG" \
      ARCHS="$SIM_ARCHS" ONLY_ACTIVE_ARCH=NO IPHONEOS_DEPLOYMENT_TARGET="$MIN_IOS" \
      ENABLE_BITCODE=NO GCC_TREAT_WARNINGS_AS_ERRORS=NO OTHER_CFLAGS="\$(inherited) $WARN" \
      build >>"$LOG" 2>&1 || { c_err "$name 模拟器构建失败"; tail -15 "$LOG"; return 1; }

  local pd="$ddx/Build/Products/Release-iphoneos" sd="$ddx/Build/Products/Release-iphonesimulator"
  mkdir -p "$OUT/$name/dev" "$OUT/$name/sim"
  cp "$pd/$lib" "$OUT/$name/dev/" || die "找不到 $name 真机 $lib"
  cp "$pd/$lib" "$OUT/$name/sim/" 2>/dev/null || true
  cp -R "$pd/include" "$OUT/$name/dev/" || true
  rm -f "$OUT/$name/sim/$lib"; cp "$sd/$lib" "$OUT/$name/sim/" || die "找不到 $name 模拟器 $lib"
  c_ok "$name: dev=$(lipo -archs "$OUT/$name/dev/$lib")  sim=$(lipo -archs "$OUT/$name/sim/$lib")"
}

###############################################################################
# 2. cyrus-sasl 交叉编译
###############################################################################
build_sasl() {
  c_step "交叉编译 cyrus-sasl (libsasl2)"
  local lepan="$SRC/libetpan"
  local pkg="$lepan/build-mac/dependencies/packages" patch="$lepan/build-mac/dependencies/cyrus-2.1.25-libetpan.patch"
  local sdir="$BUILD_DIR/sasl/cyrus-sasl-2.1.25"
  local tarball; tarball="$(ls "$pkg"/cyrus-sasl-*.tar.gz 2>/dev/null | head -1)"
  [[ -f "$tarball" && -f "$patch" ]] || die "未找到 cyrus-sasl 源码包($tarball)或补丁($patch)"

  rm -rf "$BUILD_DIR/sasl"; mkdir -p "$BUILD_DIR/sasl"
  tar xzf "$tarball" -C "$BUILD_DIR/sasl"
  ( cd "$sdir" && patch -p1 < "$patch" >/dev/null 2>&1 ) || die "cyrus-sasl 打补丁失败"

  local LOGC="$BUILD_DIR/sasl/cfg.log"; : > "$LOGC"
  # sed 微调(与上游 prepare-cyrus-sasl.sh 一致)
  sed -E -i.bak 's/\.\/makemd5 /.\/makemd5i386 /' "$sdir/include/Makefile.am" "$sdir/include/Makefile.in"; rm -f "$sdir/include/Makefile.am.bak" "$sdir/include/Makefile.in.bak"
  sed -E -i.bak 's/\$\(AR\) cru \.libs\/\$@ \$\(SASL_STATIC_OBJS\)/&; \$\(RANLIB\) .libs\/\$@/' "$sdir/lib/Makefile.in"; rm -f "$sdir/lib/Makefile.in.bak"

  # 先构建宿主工具 makemd5(在 macOS 上运行); 它在 include/ 里生成, 需就地改名供后续构建调用 ./makemd5i386
  ( cd "$sdir" && env -u SDKROOT -u IPHONEOS_DEPLOYMENT_TARGET CC=clang CPPFLAGS= CFLAGS= LDFLAGS= \
      ./configure --build=i386-apple-darwin --host=i386-apple-darwin >>"$LOGC" 2>&1 \
      && ( cd include && make makemd5 >>"$LOGC" 2>&1 && mv makemd5 makemd5i386 ) \
      && ( cd "$sdir" && { make clean >>"$LOGC" 2>&1 || true; make distclean >>"$LOGC" 2>&1 || true; } ) ) \
      || { tail -20 "$LOGC"; die "makemd5 构建失败"; }

  local COMMON="--enable-shared=no --enable-static=yes --without-pam --disable-getspnam --disable-crypt-tests --enable-otp=no --enable-digest=no --with-des=no --enable-login"
  sasl_one() { # sysroot host prefix build triple
    local sysroot="$1" host="$2" prefix="$3" build="$4" triple="$5"
    rm -rf "$prefix"
    ( cd "$sdir" && \
      export SDKROOT= CC="clang $WARN -target $triple -isysroot $sysroot" \
             CFLAGS="-target $triple -isysroot $sysroot -Os $WARN" \
             CPPFLAGS="-target $triple -isysroot $sysroot" LDFLAGS="-target $triple -isysroot $sysroot"
      ./configure --build="$build" --host="$host" --prefix="$prefix" $COMMON >>"$LOGC" 2>&1 \
      && make -j8 >>"$LOGC" 2>&1 \
      && mkdir -p "$prefix/lib/sasl2" "$prefix/include/sasl" \
      && cp lib/.libs/libsasl2.a "$prefix/lib/" \
      && cp plugins/.libs/libanonymous.a plugins/.libs/libcrammd5.a plugins/.libs/libplain.a plugins/.libs/libsasldb.a plugins/.libs/liblogin.a "$prefix/lib/sasl2/" \
      && cp include/sasl.h include/saslplug.h include/saslutil.h include/prop.h include/md5global.h "$prefix/include/sasl/" \
      && { make clean >>"$LOGC" 2>&1 || true; make distclean >>"$LOGC" 2>&1 || true; } ) \
      || { tail -20 "$LOGC"; die "sasl 构建失败 (triple=$triple)"; }
  }
  # 模拟器必须用显式 -target ...-simulator，否则平台标记会被误判为 iOS 真机
  sasl_one "$DEV_SDK" "arm-apple-darwin"  "$BUILD_DIR/sasl/p-dev"  "i386-apple-darwin" "arm64-apple-ios${MIN_IOS}"
  sasl_one "$SIM_SDK" "i386-apple-darwin" "$BUILD_DIR/sasl/p-simx" "arm-apple-darwin"  "x86_64-apple-ios${MIN_IOS}-simulator"
  sasl_one "$SIM_SDK" "i386-apple-darwin" "$BUILD_DIR/sasl/p-sima" "arm-apple-darwin"  "arm64-apple-ios${MIN_IOS}-simulator"

  # 汇总到 depsout/sasl/{dev,sim}
  rm -rf "$OUT/sasl"; mkdir -p "$OUT/sasl/dev" "$OUT/sasl/sim/lib/sasl2" "$OUT/sasl/sim/include/sasl"
  cp -R "$BUILD_DIR/sasl/p-dev/"* "$OUT/sasl/dev/"
  cp "$BUILD_DIR/sasl/p-simx/include/sasl/"* "$OUT/sasl/sim/include/sasl/"
  lipo -create "$BUILD_DIR/sasl/p-simx/lib/libsasl2.a" "$BUILD_DIR/sasl/p-sima/lib/libsasl2.a" -output "$OUT/sasl/sim/lib/libsasl2.a"
  for p in libanonymous libcrammd5 libplain libsasldb liblogin; do
    lipo -create "$BUILD_DIR/sasl/p-simx/lib/sasl2/$p.a" "$BUILD_DIR/sasl/p-sima/lib/sasl2/$p.a" -output "$OUT/sasl/sim/lib/sasl2/$p.a"
  done
  c_ok "libsasl2: dev=$(lipo -archs "$OUT/sasl/dev/lib/libsasl2.a")  sim=$(lipo -archs "$OUT/sasl/sim/lib/libsasl2.a")"
}

###############################################################################
# 4a. 组装 Externals (头平台无关，.a 按平台切换)
###############################################################################
assemble_externals() { # dev|sim
  local plat="$1"
  rm -rf "$EXT/libetpan-ios" "$EXT/ctemplate-ios" "$EXT/tidy-html5-ios" "$EXT/libsasl-ios"
  mkdir -p "$EXT/libetpan-ios"/{lib,include} "$EXT/ctemplate-ios"/{lib,include} \
           "$EXT/tidy-html5-ios"/{lib,include} "$EXT/libsasl-ios"/{lib,include}
  # 头文件(取 dev 构建产物)
  cp -R "$OUT/etpan/dev/include/libetpan"  "$EXT/libetpan-ios/include/"
  cp -R "$OUT/ctemplate/dev/include/ctemplate" "$EXT/ctemplate-ios/include/"
  cp -R "$OUT/tidy/dev/include/tidy"       "$EXT/tidy-html5-ios/include/tidy"
  cp -R "$OUT/sasl/dev/include/sasl"        "$EXT/libsasl-ios/include/"
  # 库(按平台)
  cp "$OUT/etpan/$plat/libetpan-ios.a"     "$EXT/libetpan-ios/lib/"
  cp "$OUT/ctemplate/$plat/libctemplate-ios.a" "$EXT/ctemplate-ios/lib/"
  cp "$OUT/tidy/$plat/libtidy.a"           "$EXT/tidy-html5-ios/lib/"
  cp -R "$OUT/sasl/$plat/lib/"*            "$EXT/libsasl-ios/lib/"
}

###############################################################################
# 4b. 编译 MailCore.framework
###############################################################################
build_mailcore() { # dev|sim
  local plat="$1" sdk archs outdir dd
  if [[ "$plat" == "dev" ]]; then sdk="$DEV_SDK"; archs="$DEVICE_ARCHS"; dd="$DD/mailcore"; outdir="$BUILD_DIR/fw/device"
  else sdk="$SIM_SDK"; archs="$SIM_ARCHS"; dd="$DD/mailcore-sim"; outdir="$BUILD_DIR/fw/sim"; fi
  c_step "编译 MailCore.framework ($plat: $archs)"
  assemble_externals "$plat"
  ( cd "$SCRIPT_DIR" && xcodebuild -derivedDataPath "$dd" -project mailcore2.xcodeproj \
      -scheme "mailcore ios" -sdk "$sdk" -configuration "$CONFIG" \
      ARCHS="$archs" ONLY_ACTIVE_ARCH=NO IPHONEOS_DEPLOYMENT_TARGET="$MIN_IOS" \
      ENABLE_BITCODE=NO CODE_SIGNING_ALLOWED=NO GCC_TREAT_WARNINGS_AS_ERRORS=NO \
      OTHER_CFLAGS="\$(inherited) $WARN" build >>"$LOG" 2>&1 ) \
      || { tail -20 "$LOG"; die "MailCore.framework($plat) 构建失败"; }
  local fw; fw="$(find "$dd/Build/Products" -name MailCore.framework -type d | head -1)"
  [[ -d "$fw" ]] || die "未找到构建出的 MailCore.framework"
  rm -rf "$outdir"; mkdir -p "$outdir"; cp -R "$fw" "$outdir/"
  c_ok "MailCore.framework($plat): $(lipo -archs "$fw/MailCore")"
}

###############################################################################
# main
###############################################################################
c_step "环境: Xcode=$(xcodebuild -version | head -1)  MIN_IOS=$MIN_IOS"
c_step "SDK: device=$DEV_SDK  simulator=$SIM_SDK"

if [[ "${SKIP_DEPS:-0}" == "1" ]]; then
  c_step "步骤 1-3/5：跳过依赖构建 (SKIP_DEPS=1, 复用 $OUT)"
  [[ -f "$OUT/etpan/dev/libetpan-ios.a" && -f "$OUT/ctemplate/dev/libctemplate-ios.a" \
     && -f "$OUT/tidy/dev/libtidy.a" && -f "$OUT/sasl/dev/lib/libsasl2.a" ]] \
     || die "SKIP_DEPS=1 但 $OUT 依赖不完整"
else
c_step "步骤 1/5：准备依赖源码(本地优先)"
prep_src ctemplate "$CTEMPLATE_URL" "$CTEMPLATE_REV" "build-mac/ctemplate.xcodeproj" "${CTEMPLATE_SRC:-}" || die "准备 ctemplate 源码失败"
prep_src tidy      "$TIDY_URL"      "$TIDY_REV"      "build-mac/Tidy.xcodeproj"      "${TIDY_SRC:-}"      || die "准备 tidy 源码失败"
prep_src libetpan  "$ETPAN_URL"     "$ETPAN_REV"     "build-mac/libetpan.xcodeproj"  "${ETPAN_SRC:-}"     || die "准备 libetpan 源码失败"
[[ "${_SRC_ONLY:-}" == "1" ]] && { c_ok "仅准备源码(_SRC_ONLY=1)，提前结束"; exit 0; }

# libetpan 里 system() 在 iOS 标 unavailable，就近桩化
for f in "$SRC/libetpan/src/engine/mailprivacy_tools.c" "$SRC/libetpan/src/engine/mailprivacy_smime.c"; do
  [[ -f "$f" ]] && ! grep -q "lepan_stub_system" "$f" && \
    { printf 'static int lepan_stub_system(const char *c){(void)c;return -1;}\n#define system lepan_stub_system\n' | cat - "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }
done
# libetpan iOS 目标需要 build-mac/libsasl-ios/{include,lib}(编译只要头)
mkdir -p "$SRC/libetpan/build-mac/libsasl-ios"/include

c_step "步骤 2/5：cyrus-sasl"
build_sasl
# sasl 头供 libetpan 编译使用(工程搜索路径 build-mac/libsasl-ios/include)
mkdir -p "$SRC/libetpan/build-mac/libsasl-ios"/include "$SRC/libetpan/build-mac/libsasl-ios"/lib
cp -R "$OUT/sasl/dev/include/sasl" "$SRC/libetpan/build-mac/libsasl-ios/include/"
cp -R "$OUT/sasl/dev/lib/"*        "$SRC/libetpan/build-mac/libsasl-ios/lib/"

c_step "步骤 3/5：原生依赖 .a"
build_apple_dep ctemplate "$SRC/ctemplate/build-mac/ctemplate.xcodeproj" ctemplate-ios libctemplate-ios.a || exit 1
build_apple_dep tidy      "$SRC/tidy/build-mac/Tidy.xcodeproj"          tidy          libtidy.a           || exit 1
build_apple_dep etpan     "$SRC/libetpan/build-mac/libetpan.xcodeproj"  "libetpan ios" libetpan-ios.a     || exit 1
fi

c_step "步骤 4/5：MailCore.framework"
build_mailcore dev
build_mailcore sim

c_step "步骤 5/5：封装 xcframework"
mkdir -p "$(dirname "$OUTPUT")"
rm -rf "$OUTPUT"
xcodebuild -create-xcframework \
    -framework "$BUILD_DIR/fw/device/MailCore.framework" \
    -framework "$BUILD_DIR/fw/sim/MailCore.framework" \
    -output "$OUTPUT" >>"$LOG" 2>&1 || { tail -20 "$LOG"; die "create-xcframework 失败"; }

printf "\n\033[1;32m================ 完成 ================\033[0m\n"
echo "产物: $OUTPUT"
for d in "$OUTPUT"/ios-*; do
  echo "  $(basename "$d"): $(lipo -archs "$d/MailCore.framework/MailCore")"
done
echo "详细日志: $LOG"
