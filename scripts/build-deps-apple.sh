#!/bin/bash
# ============================================================================
# PiniEngine — cocos2d-x external 의존성 Apple(arm64) 재빌드 스크립트
# ============================================================================
# 왜 필요한가:
#   저장소에 vendored 된 cocos2d-x 3.15.1 의 `external/*/prebuilt/mac/*.a` 는 전부
#   2016년산 x86_64(일부 +i386) 전용이다. Rosetta 2 는 macOS 27 까지만 일반 지원되므로
#   (HANDOVER.md §1) 최종 산출물은 arm64 네이티브여야 하고, 그러려면 이 프리빌트들을
#   arm64 로 다시 만들어야 한다.
#
# 무엇을 하는가:
#   1. 아래 고정 버전 소스를 내려받아 arm64(기본) 정적 라이브러리로 빌드
#   2. 결과 .a 를 `external/<lib>/prebuilt/mac/` 에 덮어씀
#   3. 라이브러리와 짝이 맞는 **헤더도 같이** `external/<lib>/include/mac/` 에 갱신
#      (헤더/라이브러리 버전이 어긋나면 struct 레이아웃 불일치로 런타임에 깨진다.
#       특히 jpeg 9 헤더 + libjpeg-turbo 라이브러리 조합이 위험하다.)
#
# 시스템 라이브러리로 대체해서 여기서 빌드하지 않는 것 (HANDOVER.md §4.7-1):
#   zlib / curl / iconv / sqlite3  → macOS SDK 의 .tbd 를 직접 링크 (scripts/build-mac.sh 참조)
#
# 사용법:
#   scripts/build-deps-apple.sh              # 전체
#   scripts/build-deps-apple.sh png freetype # 일부만
#   ARCHS="arm64;x86_64" scripts/build-deps-apple.sh   # universal 로 (인텔 맥 지원 유지 시)
#
# 요구사항: Xcode, cmake, ninja, git, curl
#   cmake/ninja 가 없으면: pip3 install cmake ninja
# ============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTERNAL="$REPO_ROOT/Engine/VisNovel/frameworks/cocos2d-x/external"
WORK="$REPO_ROOT/build/deps-apple"          # 다운로드 + 빌드 트리 (.gitignore 대상)
SRC="$WORK/src"
OUT="$WORK/out"

ARCHS="${ARCHS:-arm64}"
DEPLOY_TARGET="${DEPLOY_TARGET:-11.0}"

# ---- 고정 버전 -------------------------------------------------------------
# 갱신할 때는 반드시 헤더도 같이 갱신되므로(이 스크립트가 자동으로 한다) 버전만 올리면 된다.
PNG_VER=1.6.44
JPEG_VER=3.0.4            # libjpeg-turbo (IJG jpeg9 대신 사용: arm64 NEON + 유지보수)
TIFF_VER=4.7.0
WEBP_VER=1.4.0
FREETYPE_VER=2.13.3
CHIPMUNK_VER=7.0.3        # vendored 헤더는 7.0.1 이었음. cocos 3.15 는 chipmunk 7 API 사용
GLFW_VER=3.4              # vendored 헤더는 3.2.0. macOS 26 SDK 에서 3.2 는 빌드 위험
LWS_VER=2.1.0             # cocos 3.15 의 WebSocket.cpp 가 lws 2.1 API 로 작성됨 — 버전 올리면 안 됨
LUAJIT_BRANCH=v2.1        # LuaJIT 2.1 브랜치 (arm64 macOS 지원). 2.0 은 arm64 macOS 미지원

mkdir -p "$SRC" "$OUT"
export MACOSX_DEPLOYMENT_TARGET="$DEPLOY_TARGET"

CMAKE_COMMON=(
  -G Ninja
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_OSX_ARCHITECTURES="$ARCHS"
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOY_TARGET"
  -DBUILD_SHARED_LIBS=OFF
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5   # cmake 4 는 cmake<3.5 를 요구하는 옛 프로젝트를 거부한다
)

log()  { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
fetch() { # fetch <url> <tarball-name>
  local url="$1" name="$2"
  if [ ! -f "$SRC/$name" ]; then
    log "download $name"
    curl -fL --retry 3 -o "$SRC/$name.part" "$url"
    mv "$SRC/$name.part" "$SRC/$name"
  fi
}
unpack() { # unpack <tarball> <expected-dir>
  local name="$1" dir="$2"
  [ -d "$SRC/$dir" ] || tar -xf "$SRC/$name" -C "$SRC"
}
install_lib() { # install_lib <built.a> <external-subdir> <dest-name>
  local built="$1" sub="$2" dest="$3"
  mkdir -p "$EXTERNAL/$sub/prebuilt/mac"
  cp "$built" "$EXTERNAL/$sub/prebuilt/mac/$dest"
  printf '   -> %s  (%s)\n' "$sub/prebuilt/mac/$dest" "$(lipo -info "$EXTERNAL/$sub/prebuilt/mac/$dest" | sed 's/.*: //')"
}

# ---------------------------------------------------------------- libpng ----
build_png() {
  log "libpng $PNG_VER"
  fetch "https://github.com/pnggroup/libpng/archive/refs/tags/v$PNG_VER.tar.gz" "libpng-$PNG_VER.tar.gz"
  unpack "libpng-$PNG_VER.tar.gz" "libpng-$PNG_VER"
  cmake -S "$SRC/libpng-$PNG_VER" -B "$WORK/png" "${CMAKE_COMMON[@]}" \
    -DCMAKE_INSTALL_PREFIX="$OUT/png" \
    -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_FRAMEWORK=OFF \
    -DPNG_TESTS=OFF -DPNG_TOOLS=OFF
  cmake --build "$WORK/png" --target install
  install_lib "$(find "$OUT/png/lib" -name 'libpng*.a' | head -1)" png libpng.a
  cp "$OUT/png/include/png.h" "$OUT/png/include/pngconf.h" "$OUT/png/include/pnglibconf.h" \
     "$EXTERNAL/png/include/mac/"
}

# --------------------------------------------------------------- libjpeg ----
build_jpeg() {
  log "libjpeg-turbo $JPEG_VER"
  fetch "https://github.com/libjpeg-turbo/libjpeg-turbo/archive/refs/tags/$JPEG_VER.tar.gz" "libjpeg-turbo-$JPEG_VER.tar.gz"
  unpack "libjpeg-turbo-$JPEG_VER.tar.gz" "libjpeg-turbo-$JPEG_VER"
  cmake -S "$SRC/libjpeg-turbo-$JPEG_VER" -B "$WORK/jpeg" "${CMAKE_COMMON[@]}" \
    -DCMAKE_INSTALL_PREFIX="$OUT/jpeg" \
    -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TURBOJPEG=OFF
  cmake --build "$WORK/jpeg" --target install
  install_lib "$OUT/jpeg/lib/libjpeg.a" jpeg libjpeg.a
  cp "$OUT/jpeg/include/jconfig.h" "$OUT/jpeg/include/jmorecfg.h" \
     "$OUT/jpeg/include/jpeglib.h"  "$OUT/jpeg/include/jerror.h" \
     "$EXTERNAL/jpeg/include/mac/"
}

# --------------------------------------------------------------- libtiff ----
build_tiff() {
  log "libtiff $TIFF_VER"
  fetch "https://download.osgeo.org/libtiff/tiff-$TIFF_VER.tar.gz" "tiff-$TIFF_VER.tar.gz"
  unpack "tiff-$TIFF_VER.tar.gz" "tiff-$TIFF_VER"
  # 코덱은 전부 끈다: cocos 는 무압축/기본 TIFF 만 읽고, 켜면 의존성이 줄줄이 붙는다.
  cmake -S "$SRC/tiff-$TIFF_VER" -B "$WORK/tiff" "${CMAKE_COMMON[@]}" \
    -DCMAKE_INSTALL_PREFIX="$OUT/tiff" \
    -Dtiff-tools=OFF -Dtiff-tests=OFF -Dtiff-docs=OFF -Dtiff-contrib=OFF \
    -Djpeg=OFF -Dold-jpeg=OFF -Dlzma=OFF -Dzstd=OFF -Dwebp=OFF -Djbig=OFF -Dlerc=OFF
  cmake --build "$WORK/tiff" --target install
  install_lib "$OUT/tiff/lib/libtiff.a" tiff libtiff.a
  cp "$OUT/tiff/include/tiff.h" "$OUT/tiff/include/tiffio.h" "$OUT/tiff/include/tiffvers.h" \
     "$EXTERNAL/tiff/include/mac/"
  # vendored tiffconf.h 는 __LP64__ 로 tiffconf-64.h / -32.h 를 골라 include 하는 래퍼다.
  # 래퍼는 그대로 두고 arm64(LP64) 가 쓰는 쪽만 갱신한다.
  cp "$OUT/tiff/include/tiffconf.h" "$EXTERNAL/tiff/include/mac/tiffconf-64.h"
}

# --------------------------------------------------------------- libwebp ----
build_webp() {
  log "libwebp $WEBP_VER"
  fetch "https://github.com/webmproject/libwebp/archive/refs/tags/v$WEBP_VER.tar.gz" "libwebp-$WEBP_VER.tar.gz"
  unpack "libwebp-$WEBP_VER.tar.gz" "libwebp-$WEBP_VER"
  cmake -S "$SRC/libwebp-$WEBP_VER" -B "$WORK/webp" "${CMAKE_COMMON[@]}" \
    -DCMAKE_INSTALL_PREFIX="$OUT/webp" \
    -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
    -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
    -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF
  cmake --build "$WORK/webp" --target install
  # webp 1.x 는 sharpyuv 를 별 라이브러리로 분리했다. cocos 링크 설정을 건드리지 않기 위해
  # 하나의 libwebp.a 로 합친다.
  local merged="$WORK/webp/libwebp-merged.a"
  if [ -f "$OUT/webp/lib/libsharpyuv.a" ]; then
    libtool -static -o "$merged" "$OUT/webp/lib/libwebp.a" "$OUT/webp/lib/libsharpyuv.a"
  else
    cp "$OUT/webp/lib/libwebp.a" "$merged"
  fi
  install_lib "$merged" webp libwebp.a
  # cocos 는 `#include "decode.h"` 형태로 쓴다 (flat 레이아웃)
  cp "$OUT/webp/include/webp/decode.h" "$OUT/webp/include/webp/encode.h" \
     "$OUT/webp/include/webp/types.h" "$EXTERNAL/webp/include/mac/"
}

# ------------------------------------------------------------- freetype2 ----
build_freetype() {
  log "freetype $FREETYPE_VER"
  fetch "https://download.savannah.gnu.org/releases/freetype/freetype-$FREETYPE_VER.tar.xz" "freetype-$FREETYPE_VER.tar.xz"
  unpack "freetype-$FREETYPE_VER.tar.xz" "freetype-$FREETYPE_VER"
  cmake -S "$SRC/freetype-$FREETYPE_VER" -B "$WORK/freetype" "${CMAKE_COMMON[@]}" \
    -DCMAKE_INSTALL_PREFIX="$OUT/freetype" \
    -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON -DFT_DISABLE_BZIP2=ON \
    -DFT_DISABLE_PNG=ON -DFT_DISABLE_ZLIB=ON
  cmake --build "$WORK/freetype" --target install
  install_lib "$OUT/freetype/lib/libfreetype.a" freetype2 libfreetype.a
  # cocos 의 include path 는 `external/freetype2/include/mac/freetype2` 이고 거기서
  # <ft2build.h> / FT_FREETYPE_H(=<freetype/freetype.h>) 를 찾는다. freetype 의 표준
  # 설치 레이아웃(include/freetype2/{ft2build.h,freetype/*}) 과 정확히 일치하므로 통째로 교체한다.
  rm -rf "$EXTERNAL/freetype2/include/mac/freetype2"
  cp -R "$OUT/freetype/include/freetype2" "$EXTERNAL/freetype2/include/mac/freetype2"
}

# -------------------------------------------------------------- chipmunk ----
build_chipmunk() {
  log "Chipmunk2D $CHIPMUNK_VER"
  fetch "https://github.com/slembcke/Chipmunk2D/archive/refs/tags/Chipmunk-$CHIPMUNK_VER.tar.gz" "Chipmunk2D-$CHIPMUNK_VER.tar.gz"
  unpack "Chipmunk2D-$CHIPMUNK_VER.tar.gz" "Chipmunk2D-Chipmunk-$CHIPMUNK_VER"
  cmake -S "$SRC/Chipmunk2D-Chipmunk-$CHIPMUNK_VER" -B "$WORK/chipmunk" "${CMAKE_COMMON[@]}" \
    -DCMAKE_INSTALL_PREFIX="$OUT/chipmunk" \
    -DBUILD_DEMOS=OFF -DINSTALL_DEMOS=OFF -DBUILD_SHARED=OFF -DBUILD_STATIC=ON -DINSTALL_STATIC=ON
  cmake --build "$WORK/chipmunk" --target install
  install_lib "$OUT/chipmunk/lib/libchipmunk.a" chipmunk libchipmunk.a
  rm -rf "$EXTERNAL/chipmunk/include/chipmunk"
  cp -R "$OUT/chipmunk/include/chipmunk" "$EXTERNAL/chipmunk/include/chipmunk"
}

# ----------------------------------------------------------------- glfw3 ----
build_glfw() {
  log "glfw $GLFW_VER"
  fetch "https://github.com/glfw/glfw/archive/refs/tags/$GLFW_VER.tar.gz" "glfw-$GLFW_VER.tar.gz"
  unpack "glfw-$GLFW_VER.tar.gz" "glfw-$GLFW_VER"
  cmake -S "$SRC/glfw-$GLFW_VER" -B "$WORK/glfw" "${CMAKE_COMMON[@]}" \
    -DCMAKE_INSTALL_PREFIX="$OUT/glfw" \
    -DGLFW_BUILD_EXAMPLES=OFF -DGLFW_BUILD_TESTS=OFF -DGLFW_BUILD_DOCS=OFF \
    -DGLFW_BUILD_WAYLAND=OFF -DGLFW_BUILD_X11=OFF
  cmake --build "$WORK/glfw" --target install
  install_lib "$OUT/glfw/lib/libglfw3.a" glfw3 libglfw3.a
  # cocos 는 `#include "glfw3.h"` (flat)
  cp "$OUT/glfw/include/GLFW/glfw3.h" "$OUT/glfw/include/GLFW/glfw3native.h" \
     "$EXTERNAL/glfw3/include/mac/"
}

# ------------------------------------------------------------ websockets ----
build_websockets() {
  log "libwebsockets $LWS_VER (SSL 없이)"
  # 게임 Lua 는 WebSocket 을 쓰지 않지만 cocos 의 network/WebSocket.cpp 가 이미 컴파일되어
  # lws_* 심볼 14개를 요구한다. openssl(2016년산 1.1.0c) 을 되살리지 않기 위해 SSL 없이 빌드한다.
  # → ws:// 만 동작, wss:// 는 불가. 게임이 쓰지 않으므로 무해. (HANDOVER.md §4.7-1)
  fetch "https://github.com/warmcat/libwebsockets/archive/refs/tags/v$LWS_VER.tar.gz" "libwebsockets-$LWS_VER.tar.gz"
  unpack "libwebsockets-$LWS_VER.tar.gz" "libwebsockets-$LWS_VER"
  # lws 2.1 은 -Werror 로 빌드된다. 최신 macOS SDK 가 MSG_NOSIGNAL 을 정의하게 되면서
  # lws 자신의 재정의가 에러가 되므로 -Wno-error 로 낮춘다.
  cmake -S "$SRC/libwebsockets-$LWS_VER" -B "$WORK/lws" "${CMAKE_COMMON[@]}" \
    -DCMAKE_INSTALL_PREFIX="$OUT/lws" \
    -DCMAKE_C_FLAGS="-Wno-error" \
    -DLWS_WITH_SSL=OFF -DLWS_WITH_SHARED=OFF -DLWS_WITH_STATIC=ON \
    -DLWS_WITHOUT_TESTAPPS=ON -DLWS_WITHOUT_TEST_SERVER=ON -DLWS_WITHOUT_TEST_CLIENT=ON \
    -DLWS_WITHOUT_TEST_PING=ON -DLWS_WITHOUT_TEST_ECHO=ON -DLWS_WITHOUT_TEST_FRAGGLE=ON \
    -DLWS_WITH_ZLIB=ON
  cmake --build "$WORK/lws" --target install
  install_lib "$OUT/lws/lib/libwebsockets.a" websockets libwebsockets.a
  cp "$OUT/lws/include/libwebsockets.h" "$EXTERNAL/websockets/include/mac/"
  [ -f "$OUT/lws/include/lws_config.h" ] && cp "$OUT/lws/include/lws_config.h" "$EXTERNAL/websockets/include/mac/"
}

# ---------------------------------------------------------------- LuaJIT ----
build_luajit() {
  log "LuaJIT $LUAJIT_BRANCH"
  if [ ! -d "$SRC/LuaJIT" ]; then
    git clone --depth 1 --branch "$LUAJIT_BRANCH" https://github.com/LuaJIT/LuaJIT.git "$SRC/LuaJIT"
  fi
  ( cd "$SRC/LuaJIT" && make clean >/dev/null 2>&1 || true
    make -j"$(sysctl -n hw.ncpu)" TARGET_SYS=Darwin MACOSX_DEPLOYMENT_TARGET="$DEPLOY_TARGET" )
  install_lib "$SRC/LuaJIT/src/libluajit.a" lua/luajit libluajit.a
  cp "$SRC/LuaJIT/src/lua.h" "$SRC/LuaJIT/src/lauxlib.h" "$SRC/LuaJIT/src/lualib.h" \
     "$SRC/LuaJIT/src/luaconf.h" "$SRC/LuaJIT/src/luajit.h" "$SRC/LuaJIT/src/lua.hpp" \
     "$EXTERNAL/lua/luajit/include/"
}

ALL=(png jpeg tiff webp freetype chipmunk glfw websockets luajit)
TARGETS=("$@")
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=("${ALL[@]}")

for t in "${TARGETS[@]}"; do
  "build_$t"
done

log "완료. ARCHS=$ARCHS, deployment target=$DEPLOY_TARGET"
for f in "$EXTERNAL"/*/prebuilt/mac/*.a "$EXTERNAL"/lua/luajit/prebuilt/mac/*.a; do
  [ -f "$f" ] && printf '%-46s %s\n' "${f#$EXTERNAL/}" "$(lipo -info "$f" | sed 's/.*: //')"
done
