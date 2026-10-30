#!/bin/bash
# Populate ../Externals (relative to build-mac) with per-platform dep libs + headers.
# usage: assemble.sh <dev|sim>
set -e
PLAT=$1
EXT=/Users/zhanyong/workspace/mailcore-ios/source/mailcore2-master/Externals
OUT=/tmp/depsout
rm -rf "$EXT/libetpan-ios" "$EXT/ctemplate-ios" "$EXT/tidy-html5-ios" "$EXT/libsasl-ios"
mkdir -p "$EXT/libetpan-ios/lib" "$EXT/libetpan-ios/include"
mkdir -p "$EXT/ctemplate-ios/lib" "$EXT/ctemplate-ios/include"
mkdir -p "$EXT/tidy-html5-ios/lib" "$EXT/tidy-html5-ios/include"
mkdir -p "$EXT/libsasl-ios/lib" "$EXT/libsasl-ios/include"

# headers (platform-independent, taken from device build tree)
cp -R "$OUT/etpan/dev/include/libetpan" "$EXT/libetpan-ios/include/"
cp -R "$OUT/ctemplate/dev/include/ctemplate" "$EXT/ctemplate-ios/include/"
cp -R "$OUT/tidy/dev/include-tidy" "$EXT/tidy-html5-ios/include/tidy"
cp -R "$OUT/sasl/dev/include/sasl" "$EXT/libsasl-ios/include/"

# libs (per platform)
cp "$OUT/etpan/$PLAT/libetpan-ios.a" "$EXT/libetpan-ios/lib/"
cp "$OUT/ctemplate/$PLAT/libctemplate-ios.a" "$EXT/ctemplate-ios/lib/"
cp "$OUT/tidy/$PLAT/libtidy.a" "$EXT/tidy-html5-ios/lib/"
cp -R "$OUT/sasl/$PLAT/lib/"* "$EXT/libsasl-ios/lib/"

echo "== Externals populated for platform: $PLAT =="
for a in libetpan-ios/lib/libetpan-ios.a ctemplate-ios/lib/libctemplate-ios.a tidy-html5-ios/lib/libtidy.a libsasl-ios/lib/libsasl2.a; do
  lipo -info "$EXT/$a"
done
