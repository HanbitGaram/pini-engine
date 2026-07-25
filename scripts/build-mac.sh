#!/bin/bash
# PiniEngine macOS 런타임(pini_remote-desktop) arm64 네이티브 빌드
#
# 2015년산 Xcode 프로젝트(pini_remote.xcodeproj, Xcode 3.2 포맷)를 현행 Xcode 로 빌드하기 위한
# 커맨드라인 오버라이드 모음. 프로젝트 파일을 최소한만 고치고, 다음 값들은 여기서 덮어쓴다:
#
#  - SDKROOT=macosx          : cocos2d_libs/lua_bindings 의 mac 타겟에 SDKROOT=iphoneos11.0 이
#                              하드코딩되어 있어 그대로면 "unable to find sdk" 로 즉시 실패한다.
#  - ARCHS/VALID_ARCHS=arm64 : Rosetta 의존 금지(HANDOVER.md §1). 프로젝트 원본은 x86_64 전용.
#  - MACOSX_DEPLOYMENT_TARGET: 원본 10.7/10.8 은 현행 SDK 에서 지원 하한 미달.
#  - CLANG_CXX_LANGUAGE_STANDARD=gnu++14 : 원본 c++0x 로는 cocos/lua-bindings 가 컴파일되지 않음.
#
# 사용법:
#   scripts/build-mac.sh                    # 앱 전체 빌드 (Release)
#   scripts/build-mac.sh "libcocos2d Mac"   # 특정 타겟만
#   CONFIG=Debug scripts/build-mac.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COCOS_BUILD="$REPO_ROOT/Engine/VisNovel/frameworks/cocos2d-x/build"
APP_PROJ_DIR="$REPO_ROOT/Engine/VisNovel/frameworks/runtime-src/proj.ios_mac"

CONFIG="${CONFIG:-Release}"
DEPLOY_TARGET="${DEPLOY_TARGET:-11.0}"

COMMON_ARGS=(
  -configuration "$CONFIG"
  SDKROOT=macosx
  ARCHS=arm64
  VALID_ARCHS=arm64
  ONLY_ACTIVE_ARCH=NO
  MACOSX_DEPLOYMENT_TARGET="$DEPLOY_TARGET"
  CLANG_CXX_LANGUAGE_STANDARD=gnu++14
  CODE_SIGNING_ALLOWED=NO
)

TARGET="${1:-}"

if [ -n "$TARGET" ]; then
  case "$TARGET" in
    "libcocos2d Mac")
      cd "$COCOS_BUILD"
      exec xcodebuild -project cocos2d_libs.xcodeproj -target "$TARGET" "${COMMON_ARGS[@]}"
      ;;
    "libluacocos2d Mac")
      cd "$REPO_ROOT/Engine/VisNovel/frameworks/cocos2d-x/cocos/scripting/lua-bindings/proj.ios_mac"
      exec xcodebuild -project cocos2d_lua_bindings.xcodeproj -target "$TARGET" "${COMMON_ARGS[@]}"
      ;;
    "libsimulator Mac")
      cd "$REPO_ROOT/Engine/VisNovel/frameworks/cocos2d-x/tools/simulator/libsimulator/proj.ios_mac"
      exec xcodebuild -project libsimulator.xcodeproj -target "$TARGET" "${COMMON_ARGS[@]}"
      ;;
  esac
fi

cd "$APP_PROJ_DIR"
exec xcodebuild -project pini_remote.xcodeproj -target pini_remote-desktop "${COMMON_ARGS[@]}"
