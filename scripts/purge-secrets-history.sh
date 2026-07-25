#!/usr/bin/env bash
#
# git 이력에서 유출된 비밀 제거 (HANDOVER §5.5 / §13).
#
# !! 되돌릴 수 없는 작업이다. 모든 커밋의 SHA 가 바뀐다. !!
#
# 실행 전 백업이 있는지 확인할 것:
#   /Users/miraihasegawa/projects/pini-engine-backup-20260726.bundle       (전체 이력)
#   /Users/miraihasegawa/projects/pini-engine-backup-20260726-secrets/     (구 keystore 사본)
#
# 복구:
#   git clone pini-engine-backup-20260726.bundle 복구본
#
set -euo pipefail

FR="${FR:-$HOME/Library/Python/3.13/bin/git-filter-repo}"
[ -x "$FR" ] || { echo "git-filter-repo 가 없다: $FR"; exit 1; }

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# 프로젝트는 예전에 novel/ 아래 있다가 Engine/ 로 옮겨졌다.
# Engine/ 쪽은 이미 1차 실행에서 제거됐고, 여기서는 novel/ 시절 사본과
# 별도의 test_keystore/ 를 제거한다.
N=novel/VisNovel/frameworks/runtime-src/proj.android

"$FR" --force --invert-paths \
	--path "$N/piniremote.keystore" \
	--path "$N/ant.properties" \
	--path "$N/fabric.properties" \
	--path test_keystore/

echo
echo "== 검증 =="
git rev-list --all | while read -r c; do git ls-tree -r --name-only "$c"; done | sort -u \
	| grep -iE '(^|/)(piniremote\.keystore|fabric\.properties)$|^test_keystore/' \
	&& { echo "!! 아직 남아 있다"; exit 1; } || echo "OK: 비밀 파일 없음"

for s in 02881212 ab3dd822716f15df61f3549b74f04b569f4667dd \
         14ba4625da3a3d5123a34675aa2a0a260ab48f54722264c5ba19d4dd6cab8928; do
	n=$(git log --all --oneline -S "$s" 2>/dev/null | wc -l | tr -d ' ')
	echo "  $s : $n commits"
done

cat <<'EOF'

== 다음 단계 (직접 판단해서 실행할 것) ==

git-filter-repo 가 origin 을 지웠다. 다시 붙이려면:

    git remote add origin git@github.com:HanbitGaram/pini-engine.git

원격에 반영하려면 force push 가 필요하다. 이건 되돌릴 수 없고 협업자에게 영향을 준다:

    git push --force --all origin
    git push --force --tags origin

!! 그 전에 반드시 읽을 것 !!
  - 모든 커밋 SHA 가 바뀐다. 기존 PR/이슈의 커밋 링크가 깨진다.
  - 포크(예: Scincy/pini-engine)와 이미 클론한 사본에는 옛 이력이 그대로 남는다.
    GitHub 캐시에도 남을 수 있으니, 확실히 지우려면 GitHub 지원에 가비지 컬렉션을
    요청해야 한다.
  - **이력에서 지워도 유출은 되돌려지지 않는다.** 이미 공개됐던 서명키는 폐기하고
    새 키를 쓰는 것이 유일한 해결책이다: scripts/make-release-keystore.sh
EOF
