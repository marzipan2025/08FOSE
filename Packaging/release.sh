#!/usr/bin/env bash
# 08FOSE 릴리즈 한 방 스크립트: 검사 → 빌드 → dmg → 눈으로 확인 → push → GitHub 릴리즈.
#
# 버전은 Theme.appVersion 하나가 단일 출처다. 이 스크립트는 그 값을 읽기만 하고
# 고치지 않는다 — 올리는 건 코드 수정의 일부이지 배포 단계의 일이 아니다.
#
#   Packaging/release.sh              전체 실행
#   Packaging/release.sh --dry-run    빌드/dmg까지만, push·릴리즈 안 함
#
# 업데이트 팝업 섬네일: Packaging/UpdateImages/X.Y.Z.png (560×236) 가 있으면
# 릴리즈에 update.png 라는 이름으로 첨부한다. 앱은 그 이름으로 찾는다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT_DIR"

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

VERSION="$(grep -m1 'static let appVersion' Sources/FontGrid/Theme.swift | sed -E 's/.*"([^"]+)".*/\1/')"
TAG="v${VERSION}"
DMG="dist/08FOSE.dmg"

die() { echo "✗ $*" >&2; exit 1; }

echo "▸ 릴리즈 준비: ${TAG}"

# ── 사전 검사 ───────────────────────────────────────────────────────────────
# 늦게 터지는 것들을 여기서 미리 잡는다. 30분짜리 빌드를 돌리고 나서
# gh 인증이 없다는 걸 알게 되는 것만큼 허무한 게 없다.
command -v gh >/dev/null       || die "gh 없음 → brew install gh && gh auth login"
gh auth status >/dev/null 2>&1 || die "gh 인증 안 됨 → gh auth login"
command -v create-dmg >/dev/null || die "create-dmg 없음 → brew install create-dmg"

[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "main 브랜치가 아님"

# 추적 파일에 변경이 남아 있으면 릴리즈가 커밋과 어긋난다. untracked 는 봐준다.
git diff --quiet && git diff --cached --quiet \
  || die "커밋 안 된 변경이 있음 → git status 확인"

git fetch origin --tags --quiet
git merge-base --is-ancestor origin/main HEAD \
  || die "origin/main 이 로컬보다 앞서 있음 → git pull --ff-only 먼저"

git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null \
  && die "${TAG} 태그가 이미 있음 → Theme.appVersion 을 올렸는지 확인"
gh release view "$TAG" >/dev/null 2>&1 \
  && die "${TAG} 릴리즈가 이미 GitHub 에 있음"

# 릴리즈 노트는 Settings 화면에 뜨는 문구를 그대로 쓴다. 사용자가 앱 안에서
# 읽는 문장과 GitHub 에 적힌 문장이 갈라지면 둘 중 하나는 반드시 낡는다.
NOTES="$(python3 - "$VERSION" <<'PY'
import re, sys
v = sys.argv[1]
src = open('Sources/FontGrid/SettingsView.swift', encoding='utf-8').read()
m = re.search(r'\("%s",\s*\n\s*"((?:[^"\\]|\\.)*)"\)' % re.escape(v), src)
print(m.group(1).encode().decode('unicode_escape') if m else '', end='')
PY
)"
[ -n "$NOTES" ] || die "SettingsView.releaseNotes 에 ${VERSION} 항목이 없음"

# 업데이트 팝업 섬네일. 없으면 실수인지 의도인지 사람이 정한다 — 이미지 없는
# 릴리즈도 팝업은 글만으로 잘 뜨지만, 빠뜨린 걸 모르고 나가면 되돌릴 수 없다.
UPDATE_IMG="Packaging/UpdateImages/${VERSION}.png"
if [ -f "$UPDATE_IMG" ]; then
  W="$(sips -g pixelWidth "$UPDATE_IMG" | awk '/pixelWidth/ {print $2}')"
  H="$(sips -g pixelHeight "$UPDATE_IMG" | awk '/pixelHeight/ {print $2}')"
  [ "$W" = 560 ] && [ "$H" = 236 ] || die "${UPDATE_IMG} 크기가 ${W}×${H} — 560×236 이어야 함"
  echo "▸ 업데이트 이미지: ${UPDATE_IMG}"
else
  UPDATE_IMG=""
  echo "! ${VERSION} 업데이트 이미지가 없음 (Packaging/UpdateImages/${VERSION}.png)"
  if [ "$DRY_RUN" = 0 ]; then
    printf '이미지 없이 릴리즈하려면 y, 중단하려면 그 외 아무 키: '
    read -r noimg
    [ "$noimg" = "y" ] || die "중단됨. 이미지를 넣고 다시 실행."
  fi
fi

echo "▸ 검사 통과. 노트: ${NOTES:0:60}…"

# ── 빌드 ───────────────────────────────────────────────────────────────────
./build-app.sh
"${SCRIPT_DIR}/make_dmg.sh"

BUILT="$(defaults read "$PWD/dist/08FOSE.app/Contents/Info" CFBundleShortVersionString)"
[ "$BUILT" = "$VERSION" ] || die "빌드된 앱이 v${BUILT} — Theme.appVersion(${VERSION}) 과 불일치"

if [ "$DRY_RUN" = 1 ]; then
  echo "✓ --dry-run 종료. ${DMG} 생성됨."
  exit 0
fi

# ── 눈으로 확인 ─────────────────────────────────────────────────────────────
# 색·레이아웃 변경은 빌드가 성공했다는 사실로 검증되지 않는다. 푸시 뒤에
# 되돌리려면 태그를 강제로 다시 밀어야 하므로, 그 전에 한 번 멈춘다.
open dist/08FOSE.app
printf '\n앱을 확인하고 계속하려면 y, 중단하려면 그 외 아무 키: '
read -r ok
[ "$ok" = "y" ] || die "중단됨. 커밋·태그는 로컬에 그대로 있음."

# ── 배포 ───────────────────────────────────────────────────────────────────
git tag "$TAG"
git push origin main
git push origin "$TAG"
ASSETS=("$DMG")
if [ -n "$UPDATE_IMG" ]; then
  cp "$UPDATE_IMG" dist/update.png
  ASSETS+=("dist/update.png")
fi
gh release create "$TAG" "${ASSETS[@]}" --title "08FOSE ${TAG}" --notes "$NOTES"

echo "✓ ${TAG} 릴리즈 완료"
gh release view "$TAG" --json url --jq .url
