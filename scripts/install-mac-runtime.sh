#!/bin/bash
# scripts/build-mac.sh 로 만든 arm64 런타임을 Engine/OSX.app 에 설치한다.
#
# 에디터(Editor/pini/view/Menu.py)의 darwin 분기는 실행 시 이 경로를 쓴다.
# 저장소에 원래 들어 있던 Engine/OSX.app 은 2015년 x86_64 산출물(실행파일 이름 "novel Mac",
# 번들 ID org.cocos2dx.hellolua)이라 Apple Silicon 에서는 Rosetta 가 필요하다.
#
# 사용법: scripts/install-mac-runtime.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILT="$REPO_ROOT/Engine/VisNovel/frameworks/runtime-src/proj.ios_mac/build/Release/pini_remote-desktop.app"
DEST="$REPO_ROOT/Engine/OSX.app"

if [ ! -d "$BUILT" ]; then
  echo "빌드 산출물이 없습니다: $BUILT" >&2
  echo "먼저 scripts/build-mac.sh 를 실행하세요." >&2
  exit 1
fi

echo "설치: $BUILT"
echo "  ->  $DEST"
rm -rf "$DEST"
cp -R "$BUILT" "$DEST"

BIN="$(ls "$DEST/Contents/MacOS/")"
printf '%-30s %s\n' "$BIN" "$(lipo -info "$DEST/Contents/MacOS/$BIN" | sed 's/.*: //')"
