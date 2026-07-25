#!/usr/bin/env bash
#
# 안드로이드 릴리스 서명키 발급.
#
# 왜 새로 발급하는가:
#   기존 piniremote.keystore 는 평문 비밀번호(ant.properties)와 함께 공개 저장소에
#   커밋돼 있었다. 파일과 비밀번호가 모두 노출된 서명키는 **되돌릴 수 없이 손상된** 것으로
#   봐야 한다 (제3자가 같은 키로 서명한 APK 를 만들 수 있다). 이력에서 지워도 이미
#   클론/포크한 사본은 회수할 수 없으므로, 키 자체를 교체하는 것 외에 방법이 없다.
#
# 주의: 새 키로 서명한 APK 는 기존 스토어 등록물의 **업데이트로 올릴 수 없다.**
#       신규 등록이 된다. (Play 앱 서명에 이미 등록돼 있다면 구글 지원으로 키 교체 요청이
#       가능할 수 있으니 먼저 확인할 것.)
#
# 산출물은 저장소 밖에 두지 않는다면 반드시 .gitignore 로 막혀 있어야 한다.
# proj.android/keystore.properties 와 *.keystore/*.jks 는 이미 무시 목록에 있다.
#
# 사용법:
#   scripts/make-release-keystore.sh                     # 대화식
#   KEY_PASS=... STORE_PASS=... scripts/make-release-keystore.sh --no-prompt
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="$REPO_ROOT/Engine/VisNovel/frameworks/runtime-src/proj.android"

KEYSTORE="${KEYSTORE:-$ANDROID_DIR/pini-release.keystore}"
ALIAS="${ALIAS:-pini-release}"
PROPS="$ANDROID_DIR/keystore.properties"

# 서명키 유효기간. Play 는 2033-10-22 이후까지 유효할 것을 요구하므로 넉넉히 잡는다.
VALIDITY_DAYS="${VALIDITY_DAYS:-10950}"   # 30년

info() { printf '\033[1;36m== %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m!! %s\033[0m\n' "$*" >&2; exit 1; }

command -v keytool >/dev/null || die "keytool 을 찾을 수 없다 (JDK 필요)"

if [ -e "$KEYSTORE" ]; then
	die "이미 있다: $KEYSTORE
   덮어쓰면 그 키로 서명한 앱의 업데이트 경로가 끊긴다. 지우려면 직접 지울 것."
fi

if [ "${1:-}" = "--no-prompt" ]; then
	: "${STORE_PASS:?--no-prompt 에는 STORE_PASS 가 필요하다}"
	: "${KEY_PASS:=$STORE_PASS}"
	DNAME="${DNAME:-CN=PiniEngine, O=nooslab, C=KR}"
else
	read -r -s -p "keystore 비밀번호 (6자 이상): " STORE_PASS; echo
	read -r -s -p "다시 입력: " STORE_PASS2; echo
	[ "$STORE_PASS" = "$STORE_PASS2" ] || die "비밀번호가 일치하지 않는다"
	[ "${#STORE_PASS}" -ge 6 ] || die "6자 이상이어야 한다"
	KEY_PASS="$STORE_PASS"
	read -r -p "CN (조직/앱 이름) [PiniEngine]: " CN; CN="${CN:-PiniEngine}"
	read -r -p "O  (조직) [nooslab]: " O; O="${O:-nooslab}"
	read -r -p "C  (국가코드) [KR]: " C; C="${C:-KR}"
	DNAME="CN=$CN, O=$O, C=$C"
fi

info "서명키 생성: $KEYSTORE (alias=$ALIAS, ${VALIDITY_DAYS}일)"
keytool -genkeypair \
	-keystore "$KEYSTORE" \
	-storetype PKCS12 \
	-alias "$ALIAS" \
	-keyalg RSA -keysize 4096 \
	-validity "$VALIDITY_DAYS" \
	-dname "$DNAME" \
	-storepass "$STORE_PASS" \
	-keypass "$KEY_PASS"

# Gradle 이 읽는 설정 파일. 비밀번호가 들어가므로 커밋 금지 (.gitignore 로 막혀 있다).
umask 077
cat > "$PROPS" <<EOF
# 자동 생성됨 (scripts/make-release-keystore.sh)
# 비밀번호가 들어 있다. 절대 커밋하지 말 것 — .gitignore 로 막혀 있다.
storeFile=$(basename "$KEYSTORE")
storePassword=$STORE_PASS
keyAlias=$ALIAS
keyPassword=$KEY_PASS
EOF

info "완료"
cat <<EOF

  keystore : $KEYSTORE
  설정     : $PROPS   (권한 600, 커밋 금지)

  릴리스 빌드:
      cd $ANDROID_DIR && ./gradlew assembleRelease

  지문 확인:
      keytool -list -v -keystore "$KEYSTORE" -alias $ALIAS

  ** 이 두 파일을 잃어버리면 앱 업데이트를 영영 못 올린다.
     저장소가 아닌 곳(암호 관리자/오프라인 백업)에 따로 보관할 것. **
EOF
