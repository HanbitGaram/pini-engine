#!/bin/bash
# 에디터(Editor/pini)가 ctypes 로 읽어 들이는 네이티브 모듈을 arm64 macOS 용으로 빌드한다.
#
#  - atl.so    : ATL(애니메이션 타임라인) 계산기. 에디터의 WYSIWYG 프리뷰에 필수.
#                엔진과 같은 소스(runtime-src/Classes/ATL.cpp)를 -DGPP_FOR_PYTHON=1 로 빌드한다.
#                저장소에 있던 pini_distribute/atl.so 는 Windows x86 시절 산출물이라 못 쓴다.
#  - native.so : BSP 이미지 패킹. 기존 것은 Mach-O 조차 아니라 재빌드가 필요하다.
#
# 옛 빌드 스크립트(Engine/ATL_compile.py, Editor/nativeUtil/native_compile.py)는 python2 이고
# 인자 배열에 쉼표가 빠져 `-DGPP_FOR_PYTHON=1-E` 가 되는 등 그대로는 동작하지 않는다.
# 이 스크립트가 그 둘을 대체한다.
#
# 사용법: scripts/build-editor-natives.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLASSES="$REPO_ROOT/Engine/VisNovel/frameworks/runtime-src/Classes"
EXTERNAL="$REPO_ROOT/Engine/VisNovel/frameworks/cocos2d-x/external"   # rapidjson 헤더
NATIVE_UTIL="$REPO_ROOT/Editor/nativeUtil"
DEST="$REPO_ROOT/Editor/pini"

ARCH="${ARCH:-arm64}"
DEPLOY_TARGET="${DEPLOY_TARGET:-11.0}"

COMMON=(-shared -fPIC -O2 -arch "$ARCH" -mmacosx-version-min="$DEPLOY_TARGET")

echo "== atl.so"
# ATL.py 는 cdll.LoadLibrary("ATL.so") 로 부른다. macOS 파일시스템은 기본이 대소문자 구분을
# 하지 않아 atl.so 로도 열리고, .gitignore 도 소문자 이름으로 잡혀 있어 그대로 맞춘다.
clang++ "${COMMON[@]}" -std=c++11 \
  -DGPP_FOR_PYTHON=1 \
  -I "$CLASSES" -I "$EXTERNAL" \
  "$CLASSES/ATL.cpp" "$CLASSES/utils.cpp" \
  -o "$DEST/atl.so"

# native.so 는 기본으로 만들지 않는다.
#  - 포팅된 에디터 코드 어디에서도 이 라이브러리를 로드하지 않는다 (ctypes 참조 없음).
#  - 저장소에 커밋된 Editor/pini/native.so 는 Mach-O 조차 아닌 다른 플랫폼 산출물이라,
#    여기서 덮어쓰면 추적 중인 파일을 mac 전용 바이너리로 바꿔 버린다.
# 나중에 BSP 이미지 패킹을 실제로 쓰게 되면 WITH_NATIVE=1 로 빌드하고, 그때
# Editor/pini/native.so 를 .gitignore 로 옮길지 함께 정하는 편이 좋다.
if [ "${WITH_NATIVE:-0}" = "1" ]; then
  echo "== native.so"
  clang++ "${COMMON[@]}" -std=c++11 \
    "$NATIVE_UTIL"/*.cpp \
    -o "$DEST/native.so"
fi

for f in "$DEST/atl.so" "$DEST/native.so"; do
  [ -f "$f" ] && printf '%-28s %s\n' "$(basename "$f")" "$(lipo -info "$f" 2>/dev/null | sed 's/.*: //')"
done
