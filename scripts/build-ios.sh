#!/bin/bash
# PiniEngine iOS 런타임(pini_remote-mobile) arm64 실기기 빌드
#
# build-mac.sh 와 같은 이유로 커맨드라인 오버라이드가 필요하다. iOS 쪽에 추가로 필요한 것:
#  - SDKROOT=iphoneos          : 서브프로젝트들에 iphoneos11.0 이 하드코딩되어 있다 (없는 SDK)
#  - IPHONEOS_DEPLOYMENT_TARGET: 원본은 5.0~6.0 이라 현행 SDK 의 지원 하한 미달
#  - ARCHS=arm64 / VALID_ARCHS : 원본은 armv7 을 포함한다 (Xcode 26 에서 지원 안 함)
#  - CODE_SIGNING_ALLOWED=NO   : 서명 없이 빌드 검증만 (실기기 설치는 Apple 계정 필요)
#
# 시뮬레이터 빌드는 불가능하다: cocos 의 iOS 프리빌트에 arm64 시뮬레이터 슬라이스가 없다
# (HANDOVER.md §4.2). Apple Silicon 에서는 실기기 빌드만 가능하다.
#
# 사용법:
#   scripts/build-ios.sh                     # 앱 전체 빌드 (Release)
#   scripts/build-ios.sh "libcocos2d iOS"    # 특정 타겟만
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COCOS_BUILD="$REPO_ROOT/Engine/VisNovel/frameworks/cocos2d-x/build"
APP_PROJ_DIR="$REPO_ROOT/Engine/VisNovel/frameworks/runtime-src/proj.ios_mac"

CONFIG="${CONFIG:-Release}"
DEPLOY_TARGET="${DEPLOY_TARGET:-15.0}"

COMMON_ARGS=(
  -configuration "$CONFIG"
  -sdk iphoneos
  SDKROOT=iphoneos
  ARCHS=arm64
  VALID_ARCHS=arm64
  ONLY_ACTIVE_ARCH=NO
  IPHONEOS_DEPLOYMENT_TARGET="$DEPLOY_TARGET"
  CLANG_CXX_LANGUAGE_STANDARD=gnu++14
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY=""
)

TARGET="${1:-}"

if [ -n "$TARGET" ]; then
  case "$TARGET" in
    "libcocos2d iOS")
      cd "$COCOS_BUILD"
      exec xcodebuild -project cocos2d_libs.xcodeproj -target "$TARGET" "${COMMON_ARGS[@]}"
      ;;
    "libluacocos2d iOS")
      cd "$REPO_ROOT/Engine/VisNovel/frameworks/cocos2d-x/cocos/scripting/lua-bindings/proj.ios_mac"
      exec xcodebuild -project cocos2d_lua_bindings.xcodeproj -target "$TARGET" "${COMMON_ARGS[@]}"
      ;;
    "libsimulator iOS")
      cd "$REPO_ROOT/Engine/VisNovel/frameworks/cocos2d-x/tools/simulator/libsimulator/proj.ios_mac"
      exec xcodebuild -project libsimulator.xcodeproj -target "$TARGET" "${COMMON_ARGS[@]}"
      ;;
  esac
fi

cd "$APP_PROJ_DIR"
exec xcodebuild -project pini_remote.xcodeproj -target pini_remote-mobile "${COMMON_ARGS[@]}"
