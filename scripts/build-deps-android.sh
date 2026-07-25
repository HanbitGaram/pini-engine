#!/bin/bash
# ============================================================================
# PiniEngine — cocos2d-x external 의존성 Android 재빌드 스크립트
# ============================================================================
# 왜 필요한가:
#  1) external/chipmunk/include 와 external/lua/luajit/include 는 **전 플랫폼 공용**이다.
#     Phase 1 에서 mac 용으로 chipmunk 7.0.3 / LuaJIT 2.1 로 올렸기 때문에, 안드로이드
#     프리빌트(2016년산 chipmunk 7.0.1 / LuaJIT 2.0)와 헤더가 어긋난다.
#     LuaJIT 2.0 에는 luaL_setfuncs 가 없어 실제로 링크가 깨진다.
#  2) 2016년산 openssl arm64-v8a 프리빌트는 -fPIC 로 빌드되지 않아 최신 NDK 의 lld 가
#     공유 라이브러리 링크를 거부한다. mac 과 같은 방침으로 **libwebsockets 를 SSL 없이**
#     다시 만들어 openssl 의존 자체를 없앤다 (게임 Lua 는 WebSocket 을 쓰지 않는다).
#
# 사용법:
#   ANDROID_NDK_HOME=<ndk> scripts/build-deps-android.sh              # 전체
#   ANDROID_NDK_HOME=<ndk> scripts/build-deps-android.sh luajit       # 일부만
#   ABIS="arm64-v8a armeabi-v7a" ... (기본값)
# ============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXTERNAL="$REPO_ROOT/Engine/VisNovel/frameworks/cocos2d-x/external"
SRC="$REPO_ROOT/build/deps-apple/src"          # 소스는 apple 쪽과 공유 (버전 핀도 동일)
WORK="$REPO_ROOT/build/deps-android"
OUT="$WORK/out"

: "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME 을 지정하세요 (예: \$ANDROID_HOME/ndk/27.1.12297006)}"
ABIS="${ABIS:-arm64-v8a armeabi-v7a}"
API="${API:-24}"

CHIPMUNK_VER=7.0.3
LWS_VER=2.1.0
OPENSSL_VER=1.1.1w      # vendored 헤더가 1.1.0c 다. 1.1.x 는 ABI 호환이라 그대로 쓸 수 있다.
LUAJIT_BRANCH=v2.1

NDK_BIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin"
mkdir -p "$SRC" "$OUT"

log() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
fetch() {
  local url="$1" name="$2"
  [ -f "$SRC/$name" ] || { log "download $name"; curl -fL --retry 3 -o "$SRC/$name.part" "$url"; mv "$SRC/$name.part" "$SRC/$name"; }
}
unpack() { [ -d "$SRC/$2" ] || tar -xf "$SRC/$1" -C "$SRC"; }

# ABI -> LuaJIT/clang 트리플
abi_triple() {
  case "$1" in
    arm64-v8a)   echo "aarch64-linux-android" ;;
    armeabi-v7a) echo "armv7a-linux-androideabi" ;;
    x86_64)      echo "x86_64-linux-android" ;;
    *) echo "지원하지 않는 ABI: $1" >&2; exit 1 ;;
  esac
}

install_lib() { # <built.a> <external-subdir> <abi> <dest-name>
  local built="$1" sub="$2" abi="$3" dest="$4"
  mkdir -p "$EXTERNAL/$sub/prebuilt/android/$abi"
  cp "$built" "$EXTERNAL/$sub/prebuilt/android/$abi/$dest"
  printf '   -> %s\n' "$sub/prebuilt/android/$abi/$dest"
}

# ---------------------------------------------------------------- LuaJIT ----
build_luajit() {
  log "LuaJIT $LUAJIT_BRANCH (android)"
  [ -d "$SRC/LuaJIT" ] || git clone --depth 1 --branch "$LUAJIT_BRANCH" https://github.com/LuaJIT/LuaJIT.git "$SRC/LuaJIT"
  for abi in $ABIS; do
    local triple; triple="$(abi_triple "$abi")"
    local cc="$NDK_BIN/${triple}${API}-clang"
    log "  $abi ($triple)"
    # CROSS 접두어 + CC=clang 조합으로 타깃 컴파일러를 지정한다
    # ($NDK_BIN/aarch64-linux-android24-clang 이 실제 실행 파일이다).
    # ar/strip 은 그 접두어로 존재하지 않으므로 llvm-* 로 따로 지정해야 한다.
    # STATIC_CC/DYNAMIC_CC 만 넘기면 크로스 설정이 먹지 않아 호스트(Mach-O) 오브젝트가 나온다.
    # LuaJIT 소스 트리는 mac/iOS 빌드와 공유된다. 같은 트리에서 타깃만 바꿔 make 하면
    # 이전 산출물이 남아 "Nothing to be done" 이 되고 호스트 오브젝트가 그대로 설치된다.
    # ABI 별로 소스를 복사해서 빌드한다.
    local ljsrc="$WORK/luajit-$abi"
    rm -rf "$ljsrc"; mkdir -p "$ljsrc"
    # git archive 로 추적 파일만 꺼내 온다 (cp -R 은 이전 빌드 산출물까지 딸려와서
    # make 가 "Nothing to be done" 이라고 판단해 버린다).
    git -C "$SRC/LuaJIT" archive HEAD | tar -x -C "$ljsrc"
    ( cd "$ljsrc" \
      && make -j"$(sysctl -n hw.ncpu)" \
        HOST_CC="clang" \
        CROSS="$NDK_BIN/${triple}${API}-" CC=clang \
        TARGET_AR="$NDK_BIN/llvm-ar rcus" TARGET_STRIP="$NDK_BIN/llvm-strip" \
        TARGET_SYS=Linux )
    # 산출물이 정말 ELF(안드로이드)인지 확인한다. 호스트 오브젝트가 섞이면 링크 단계에서
    # "neither ET_REL nor LLVM bitcode" 로 터진다.
    if ! "$NDK_BIN/llvm-objdump" -a "$ljsrc/src/libluajit.a" 2>/dev/null | grep -q 'elf64\|elf32'; then
      echo "LuaJIT 산출물이 ELF 가 아닙니다 ($abi)" >&2; exit 1
    fi
    install_lib "$ljsrc/src/libluajit.a" lua/luajit "$abi" libluajit.a
  done
}

# -------------------------------------------------------------- chipmunk ----
build_chipmunk() {
  log "Chipmunk2D $CHIPMUNK_VER (android)"
  fetch "https://github.com/slembcke/Chipmunk2D/archive/refs/tags/Chipmunk-$CHIPMUNK_VER.tar.gz" "Chipmunk2D-$CHIPMUNK_VER.tar.gz"
  unpack "Chipmunk2D-$CHIPMUNK_VER.tar.gz" "Chipmunk2D-Chipmunk-$CHIPMUNK_VER"

  # Chipmunk 7.0.3 은 _WIN32 가 아니면 무조건 <sys/sysctl.h> 를 포함하는데 bionic(안드로이드)
  # 에는 이 헤더가 없다. 실제 sysctlbyname 호출은 이미 __APPLE__ 로 가드되어 있으므로
  # include 만 막으면 된다. (apple 빌드에는 영향 없음 — 멱등)
  local hasty="$SRC/Chipmunk2D-Chipmunk-$CHIPMUNK_VER/src/cpHastySpace.c"
  if ! grep -q '__ANDROID__' "$hasty"; then
    /usr/bin/sed -i '' \
      's|^#include <sys/sysctl.h>$|#if !defined(__ANDROID__)  /* bionic 에는 sys/sysctl.h 가 없다 */\
#include <sys/sysctl.h>\
#endif|' "$hasty"
  fi
  for abi in $ABIS; do
    log "  $abi"
    cmake -S "$SRC/Chipmunk2D-Chipmunk-$CHIPMUNK_VER" -B "$WORK/chipmunk-$abi" -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
      -DANDROID_ABI="$abi" -DANDROID_PLATFORM="android-$API" \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -DCMAKE_INSTALL_PREFIX="$OUT/chipmunk-$abi" \
      -DBUILD_DEMOS=OFF -DINSTALL_DEMOS=OFF -DBUILD_SHARED=OFF -DBUILD_STATIC=ON -DINSTALL_STATIC=ON
    cmake --build "$WORK/chipmunk-$abi" --target install
    install_lib "$OUT/chipmunk-$abi/lib/libchipmunk.a" chipmunk "$abi" libchipmunk.a
  done
}

# ------------------------------------------------------------ websockets ----
build_websockets() {
  log "libwebsockets $LWS_VER (android, SSL 없이)"
  # SSL 없이 빌드해 openssl 의존을 끊는다. 2016년산 openssl arm64 프리빌트가 non-PIC 라
  # 최신 NDK 에서 공유 라이브러리로 링크되지 않기 때문이다. ws:// 만 동작한다.
  fetch "https://github.com/warmcat/libwebsockets/archive/refs/tags/v$LWS_VER.tar.gz" "libwebsockets-$LWS_VER.tar.gz"
  unpack "libwebsockets-$LWS_VER.tar.gz" "libwebsockets-$LWS_VER"
  for abi in $ABIS; do
    log "  $abi"
    cmake -S "$SRC/libwebsockets-$LWS_VER" -B "$WORK/lws-$abi" -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
      -DANDROID_ABI="$abi" -DANDROID_PLATFORM="android-$API" \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_C_FLAGS="-Wno-error -fPIC" \
      -DCMAKE_INSTALL_PREFIX="$OUT/lws-$abi" \
      -DLWS_WITH_SSL=OFF -DLWS_WITH_SHARED=OFF -DLWS_WITH_STATIC=ON \
      -DLWS_WITHOUT_TESTAPPS=ON -DLWS_WITHOUT_TEST_SERVER=ON -DLWS_WITHOUT_TEST_CLIENT=ON \
      -DLWS_WITHOUT_TEST_PING=ON -DLWS_WITHOUT_TEST_ECHO=ON -DLWS_WITHOUT_TEST_FRAGGLE=ON \
      -DLWS_WITH_ZLIB=ON
    cmake --build "$WORK/lws-$abi" --target install
    install_lib "$OUT/lws-$abi/lib/libwebsockets.a" websockets "$abi" libwebsockets.a
  done
}

# ---------------------------------------------------------------- openssl ----
build_openssl() {
  log "openssl $OPENSSL_VER (android)"
  # 저장소의 arm64-v8a 프리빌트(2016년산)는 -fPIC 로 빌드되지 않아 최신 NDK 의 lld 가
  #   "relocation R_AARCH64_ADR_PREL_LO21 cannot be used against symbol 'poly1305_blocks'"
  # 로 거부한다. openssl 은 websockets 뿐 아니라 **curl(https)** 도 쓰기 때문에 그냥 뺄 수 없다.
  # 1.1.x 로 다시 빌드해 vendored 헤더(1.1.0c)와 ABI 를 맞춘다.
  fetch "https://github.com/openssl/openssl/releases/download/OpenSSL_${OPENSSL_VER//./_}/openssl-$OPENSSL_VER.tar.gz" "openssl-$OPENSSL_VER.tar.gz"
  unpack "openssl-$OPENSSL_VER.tar.gz" "openssl-$OPENSSL_VER"
  for abi in $ABIS; do
    case "$abi" in
      arm64-v8a)   local target=android-arm64 ;;
      armeabi-v7a) local target=android-arm ;;
      x86_64)      local target=android-x86_64 ;;
      *) echo "지원하지 않는 ABI: $abi" >&2; exit 1 ;;
    esac
    log "  $abi ($target)"
    local bdir="$WORK/openssl-$abi"
    rm -rf "$bdir"; mkdir -p "$bdir"
    ( cd "$bdir"
      ANDROID_NDK_ROOT="$ANDROID_NDK_HOME" PATH="$NDK_BIN:$PATH" \
        "$SRC/openssl-$OPENSSL_VER/Configure" "$target" -D__ANDROID_API__=$API \
        no-shared no-tests no-ui-console -fPIC
      ANDROID_NDK_ROOT="$ANDROID_NDK_HOME" PATH="$NDK_BIN:$PATH" make -j"$(sysctl -n hw.ncpu)" build_libs )
    install_lib "$bdir/libcrypto.a" openssl "$abi" libcrypto.a
    install_lib "$bdir/libssl.a"    openssl "$abi" libssl.a
  done
}

ALL=(luajit chipmunk websockets openssl)
TARGETS=("$@"); [ ${#TARGETS[@]} -eq 0 ] && TARGETS=("${ALL[@]}")
for t in "${TARGETS[@]}"; do "build_$t"; done
log "완료 (ABI: $ABIS, API: $API)"
