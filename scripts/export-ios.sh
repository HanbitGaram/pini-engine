#!/usr/bin/env bash
#
# PiniEngine iOS 익스포트 — 게임 리소스를 넣어 서명된 .ipa 를 만든다.
#
# 에디터의 "파일 > 익스포트 > iOS" 가 이 스크립트를 부른다. 커맨드라인에서도 그대로 쓸 수 있다.
#
# 왜 스크립트로 빼는가:
#   Export_Windows/Export_Android 는 도구 호출을 파이썬 안에 박아 놨고, 그래서 윈도우
#   도구체인에 묶여 버렸다(§6 Phase 5). 빌드 로직을 스크립트로 두면 에디터 없이도 돌릴 수
#   있고, CI 에 걸기도 쉽다.
#
# 리소스 주입 방식:
#   Xcode 프로젝트의 src/res 는 ../../../src, ../../../res 를 가리키는 **폴더 참조**다.
#   게임마다 다른 내용을 넣겠다고 저장소를 덮어쓰면 개발/미리보기 워크플로가 깨진다.
#   그래서 PINI_EXPORT_STAGE 빌드 설정을 보고 번들 안의 src/res 만 갈아끼우는
#   "Pini export stage" 빌드 페이즈를 타겟에 추가해 뒀다.
#
# 필수 인자 (환경변수):
#   STAGE          게임 리소스 스테이징 디렉터리 (src/ 와 res/ 를 담고 있어야 한다)
#   OUTDIR         산출물을 둘 디렉터리
#   APP_NAME       앱 표시 이름
#   BUNDLE_ID      번들 식별자 (예: com.example.mygame)
#
# 선택:
#   VERSION        CFBundleShortVersionString (기본 1.0)
#   BUILD_NUMBER   CFBundleVersion (기본 1)
#   TEAM_ID        Apple Developer 팀 ID. 없으면 서명 없이 .xcarchive 까지만 만든다
#   METHOD         development | ad-hoc | app-store | enterprise (기본 development)
#   DEPLOY_TARGET  기본 15.0
#   ICON           앱 아이콘 이미지. 1024x1024 정사각형 png 로 변환해 넣는다
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJ_DIR="$REPO_ROOT/Engine/VisNovel/frameworks/runtime-src/proj.ios_mac"
PROJ="$PROJ_DIR/pini_remote.xcodeproj"
SCHEME="pini_remote-mobile"

: "${STAGE:?STAGE 가 필요하다}"
: "${OUTDIR:?OUTDIR 이 필요하다}"
: "${APP_NAME:?APP_NAME 이 필요하다}"
: "${BUNDLE_ID:?BUNDLE_ID 가 필요하다}"
VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
TEAM_ID="${TEAM_ID:-}"
METHOD="${METHOD:-development}"
DEPLOY_TARGET="${DEPLOY_TARGET:-15.0}"
ICON="${ICON:-}"

APPICON_DIR="$PROJ_DIR/ios/Images.xcassets/AppIcon.appiconset"

info() { printf '\033[1;36m== %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m!! %s\033[0m\n' "$*" >&2; exit 1; }

command -v xcodebuild >/dev/null || die "xcodebuild 을 찾을 수 없다. Xcode 를 설치하고 'xcode-select --switch' 로 지정할 것."
[ -d "$STAGE/src" ] || die "스테이징에 src/ 가 없다: $STAGE"
[ -d "$STAGE/res" ] || die "스테이징에 res/ 가 없다: $STAGE"

mkdir -p "$OUTDIR"
ARCHIVE="$OUTDIR/$APP_NAME.xcarchive"
rm -rf "$ARCHIVE"

# 앱 아이콘 교체.
#
# 아이콘은 에셋 카탈로그로만 넣을 수 있는데(iOS 11+ 스토어 검증 요구), 에셋 카탈로그는
# src/res 처럼 폴더 참조로 바깥을 가리키게 할 수 없다. Xcode 프로젝트에 박힌 경로에서만
# 컴파일된다. 그래서 빌드 직전에 저장소의 아이콘을 바꿔치기하고 끝나면 되돌린다.
# 되돌리기는 trap 으로 걸어 두어 중간에 죽어도 원복된다.
if [ -n "$ICON" ]; then
	[ -f "$ICON" ] || die "아이콘 파일이 없다: $ICON"

	ICON_BACKUP="$(mktemp -d -t piniappicon)"
	cp "$APPICON_DIR"/*.png "$ICON_BACKUP"/
	restore_icon() {
		cp "$ICON_BACKUP"/*.png "$APPICON_DIR"/
		rm -rf "$ICON_BACKUP"
	}
	trap restore_icon EXIT

	info "앱 아이콘 적용: $ICON"
	python3 "$REPO_ROOT/scripts/make-ios-appicon.py" "$ICON" "$APPICON_DIR"
fi

# Info.plist 는 저장소 것을 건드리지 않고 스테이징에 복사해서 고친다.
PLIST="$STAGE/Info.plist"
cp "$PROJ_DIR/ios/Info.plist" "$PLIST"
pb() { /usr/libexec/PlistBuddy -c "$1" "$PLIST" >/dev/null; }
pb "Set :CFBundleIdentifier $BUNDLE_ID"
pb "Set :CFBundleShortVersionString $VERSION"
pb "Set :CFBundleVersion $BUILD_NUMBER"
pb "Set :CFBundleDisplayName $APP_NAME" 2>/dev/null || pb "Add :CFBundleDisplayName string $APP_NAME"
pb "Set :CFBundleName $APP_NAME"        2>/dev/null || pb "Add :CFBundleName string $APP_NAME"

# build-ios.sh 와 같은 오버라이드가 필요하다 (하드코딩된 iphoneos11.0, armv7 등 — §11).
COMMON=(
	-project "$PROJ"
	-scheme "$SCHEME"
	-configuration Release
	-destination 'generic/platform=iOS'
	SDKROOT=iphoneos
	ARCHS=arm64
	VALID_ARCHS=arm64
	ONLY_ACTIVE_ARCH=NO
	IPHONEOS_DEPLOYMENT_TARGET="$DEPLOY_TARGET"
	CLANG_CXX_LANGUAGE_STANDARD=gnu++14
	INFOPLIST_FILE="$PLIST"
	PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"
	PINI_EXPORT_STAGE="$STAGE"
)

if [ -n "$TEAM_ID" ]; then
	COMMON+=( DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic )
else
	# 서명 정보가 없으면 아카이브까지만. 설치 가능한 .ipa 는 나오지 않는다.
	COMMON+=( CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" )
fi

info "아카이브 생성: $ARCHIVE"
xcodebuild archive "${COMMON[@]}" -archivePath "$ARCHIVE" -allowProvisioningUpdates

[ -d "$ARCHIVE" ] || die "아카이브가 만들어지지 않았다"

# 스테이징이 실제로 반영됐는지 확인한다. 조용히 저장소 src 가 들어가면 엉뚱한 게임이 나온다.
BUNDLED="$ARCHIVE/Products/Applications/$SCHEME.app"
if [ -d "$BUNDLED" ]; then
	[ -e "$BUNDLED/src/_export_execute_.lua" ] \
		|| die "번들에 _export_execute_.lua 가 없다 — 리소스 주입이 안 됐다"

	# 에셋 카탈로그가 실제로 컴파일됐는지 본다. 이게 빠지면 아카이브는 성공하지만
	# 스토어 업로드에서 "Missing required icon file" 로 거부당한다 (§15).
	[ -e "$BUNDLED/Assets.car" ] \
		|| die "번들에 Assets.car 가 없다 — 앱 아이콘 에셋 카탈로그가 빠졌다"
	/usr/libexec/PlistBuddy -c "Print :CFBundleIconName" "$BUNDLED/Info.plist" >/dev/null 2>&1 \
		|| die "Info.plist 에 CFBundleIconName 이 없다"

	# Assets.car 가 있다고 끝이 아니다. 검증이 콕 집어 요구하는 세 크기가 실제
	# 렌디션으로 들어 있는지 본다 (1024 한 장만 넣으면 여기서 걸린다).
	info "앱 아이콘 렌디션 확인"
	xcrun assetutil --info "$BUNDLED/Assets.car" 2>/dev/null | python3 -c '
import json, sys
have = set()
for e in json.load(sys.stdin):
    if str(e.get("Name", "")).startswith("AppIcon") and e.get("PixelWidth"):
        have.add((e["PixelWidth"], e["PixelHeight"]))
missing = [f"{w}x{w}" for w in (120, 152, 167) if (w, w) not in have]
if missing:
    sys.exit("앱 아이콘 렌디션 누락: " + ", ".join(missing))
print("  " + " ".join(f"{w}x{h}" for w, h in sorted(have)))
' || die "앱 아이콘 렌디션 검사 실패 — 스토어 업로드에서 거부당한다"
fi

if [ -z "$TEAM_ID" ]; then
	info "TEAM_ID 가 없어 .ipa 는 만들지 않았다 (아카이브만)"
	echo "$ARCHIVE"
	exit 0
fi

OPTS="$STAGE/ExportOptions.plist"
cat > "$OPTS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>$METHOD</string>
	<key>teamID</key><string>$TEAM_ID</string>
	<key>signingStyle</key><string>automatic</string>
	<key>stripSwiftSymbols</key><true/>
	<key>compileBitcode</key><false/>
</dict>
</plist>
EOF

info "IPA 추출 (method=$METHOD)"
xcodebuild -exportArchive \
	-archivePath "$ARCHIVE" \
	-exportOptionsPlist "$OPTS" \
	-exportPath "$OUTDIR" \
	-allowProvisioningUpdates

IPA="$(/usr/bin/find "$OUTDIR" -maxdepth 1 -name '*.ipa' -print -quit)"
[ -n "$IPA" ] || die ".ipa 를 찾을 수 없다"

info "완료: $IPA"
echo "$IPA"
