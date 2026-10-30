#!/bin/bash
# Cross-compile cyrus-sasl 2.1.25 for iOS: device arm64 + simulator x86_64/arm64
# Mirrors upstream prepare-cyrus-sasl.sh (uses --host=arm / --host=i386 which the
# ancient config.sub recognizes; real arch comes from -arch in CFLAGS).
set -e
SRC=/tmp/sasl/cyrus-sasl-2.1.25
LOG=/tmp/sasl/cfg.log
: > "$LOG"

cd "$SRC"
# --- sed tweaks (make md5 tool + ranlib) ---
cd "$SRC/include"
sed -E 's/\.\/makemd5 /.\/makemd5i386 /' < Makefile.am > Makefile.am.new && mv Makefile.am.new Makefile.am
sed -E 's/\.\/makemd5 /.\/makemd5i386 /' < Makefile.in > Makefile.in.new && mv Makefile.in.new Makefile.in
cd "$SRC/lib"
sed -E 's/\$\(AR\) cru \.libs\/\$@ \$\(SASL_STATIC_OBJS\)/&; \$\(RANLIB\) .libs\/\$@/' < Makefile.in > Makefile.in.new && mv Makefile.in.new Makefile.in

# --- build host tool makemd5 (native macOS) ---
cd "$SRC"
env -u SDKROOT -u IPHONEOS_DEPLOYMENT_TARGET CC=clang CPPFLAGS= CFLAGS= LDFLAGS= \
  ./configure --build=i386-apple-darwin --host=i386-apple-darwin >> "$LOG" 2>&1
( cd include && make makemd5 >> "$LOG" 2>&1 )
mv "$SRC/include/makemd5" "$SRC/include/makemd5i386"
make clean >> "$LOG" 2>&1 || true
make distclean >> "$LOG" 2>&1 || true
find "$SRC" -name config.cache -delete || true

DEVSDK=$(xcodebuild -version -sdk iphoneos 2>/dev/null | awk '/^Path: /{print $2}')
SIMSDK=$(xcodebuild -version -sdk iphonesimulator 2>/dev/null | awk '/^Path: /{print $2}')
MIN=15.0
WARNFIX="-Wno-error=incompatible-function-pointer-types -Wno-error=implicit-int -Wno-error=implicit-function-declaration -Wno-error=int-conversion -Wno-error=deprecated-non-prototype -Wno-error=return-type"
COMMON="--enable-shared=no --enable-static=yes --without-pam --disable-getspnam --disable-crypt-tests --enable-otp=no --enable-digest=no --with-des=no --enable-login"

build_one() {
  local sysroot=$1 march=$2 host=$3 prefix=$4 build=$5 triple=$6
  echo "### building triple=$triple host=$host -> $prefix"
  cd "$SRC"
  rm -rf "$prefix"
  export SDKROOT=
  export CC="clang $WARNFIX -target $triple -isysroot $sysroot"
  export CFLAGS="-target $triple -isysroot $sysroot -Os $WARNFIX"
  export CPPFLAGS="-target $triple -isysroot $sysroot"
  export LDFLAGS="-target $triple -isysroot $sysroot"
  ./configure --build="$build" --host="$host" --prefix="$prefix" $COMMON >> "$LOG" 2>&1
  make -j8 >> "$LOG" 2>&1
  # manual install (avoid macframework install-exec-hook)
  mkdir -p "$prefix/lib/sasl2" "$prefix/include/sasl"
  cp lib/.libs/libsasl2.a "$prefix/lib/"
  cp plugins/.libs/libanonymous.a plugins/.libs/libcrammd5.a plugins/.libs/libplain.a plugins/.libs/libsasldb.a plugins/.libs/liblogin.a "$prefix/lib/sasl2/"
  cp include/sasl.h include/saslplug.h include/saslutil.h include/prop.h include/md5global.h "$prefix/include/sasl/"
  make clean >> "$LOG" 2>&1 || true
  make distclean >> "$LOG" 2>&1 || true
  find "$SRC" -name config.cache -delete || true
}

# device arm64 (host arm != build i386 => cross mode)
build_one "$DEVSDK" arm64 "arm-apple-darwin" /tmp/sasl/p-device-arm64 "i386-apple-darwin" "arm64-apple-ios$MIN"
# simulator x86_64 (host i386 != build arm => cross mode; sim binaries cannot run on host)
build_one "$SIMSDK" x86_64 "i386-apple-darwin" /tmp/sasl/p-sim-x86_64 "arm-apple-darwin" "x86_64-apple-ios$MIN-simulator"
# simulator arm64
build_one "$SIMSDK" arm64 "i386-apple-darwin" /tmp/sasl/p-sim-arm64 "arm-apple-darwin" "arm64-apple-ios$MIN-simulator"

echo "=== SASL_BUILD_OK ==="
