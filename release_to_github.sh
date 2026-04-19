#!/bin/zsh
# ─────────────────────────────────────────────────────────────────────
# CView v2 — GitHub Release Publisher
#
# 1. build_release.sh 실행 (Release/CView.app 생성)
# 2. .zip 으로 압축
# 3. git tag 생성 & push
# 4. gh CLI 로 GitHub Release 생성 + asset 업로드
#
# 사전 조건:
#   - gh CLI 로그인 완료 (`gh auth login`)
#   - git remote 가 GitHub 저장소를 가리킴 (theel4134/CView_v2)
#   - main 브랜치 커밋/푸시 완료 (태그 생성 가능 상태)
#
# Usage:
#   ./release_to_github.sh              # Info.plist 의 버전으로 태그 생성
#   ./release_to_github.sh 2.0.1        # 명시적 버전 지정
#   ./release_to_github.sh 2.0.1 draft  # draft 릴리스로 생성
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"

# ── 설정 ──────────────────────────────────────────────────────────────
REPO_SLUG="theel4134/CView_v2"   # UpdateService.repository 와 일치해야 함
APP_NAME="CView"
INFO_PLIST="$SCRIPT_DIR/SupportFiles/Info.plist"

# ── 1. 버전 결정 ──────────────────────────────────────────────────────
if [[ $# -ge 1 && -n "$1" ]]; then
    VERSION="$1"
else
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
fi
TAG="v${VERSION}"

DRAFT_FLAG=""
if [[ "${2:-}" == "draft" ]]; then
    DRAFT_FLAG="--draft"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  📦 GitHub Release 생성"
echo "  Repository: $REPO_SLUG"
echo "  Tag:        $TAG"
echo "  Draft:      ${DRAFT_FLAG:-no}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 2. 사전 검증 ──────────────────────────────────────────────────────
if ! command -v gh >/dev/null 2>&1; then
    echo "❌ gh CLI 가 설치되어 있지 않습니다. brew install gh"
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "❌ gh CLI 로그인이 필요합니다:  gh auth login"
    exit 1
fi

CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
if [[ "$CURRENT_REMOTE" != *"$REPO_SLUG"* ]]; then
    echo "❌ git remote origin 이 $REPO_SLUG 가 아닙니다: $CURRENT_REMOTE"
    exit 1
fi

# 태그 중복 검사 (원격)
if gh release view "$TAG" --repo "$REPO_SLUG" >/dev/null 2>&1; then
    echo "⚠️  이미 $TAG 릴리스가 존재합니다."
    echo "    덮어쓰려면 먼저:  gh release delete $TAG --repo $REPO_SLUG --yes --cleanup-tag"
    exit 1
fi

# ── 3. 릴리스 .app 빌드 ───────────────────────────────────────────────
echo ""
echo "━━━ [1/4] Release .app 빌드 ━━━"
"$SCRIPT_DIR/build_release.sh"

APP_BUNDLE="$SCRIPT_DIR/Release/${APP_NAME}.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "❌ 빌드 산출물이 없습니다: $APP_BUNDLE"
    exit 1
fi

# ── 4. .zip 패키징 ────────────────────────────────────────────────────
echo ""
echo "━━━ [2/4] .zip 패키징 ━━━"
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_BUNDLE/Contents/Info.plist")
ZIP_NAME="${APP_NAME}-${VERSION}-${BUILD_NUMBER}.zip"
ZIP_PATH="$SCRIPT_DIR/Release/$ZIP_NAME"
rm -f "$ZIP_PATH"

# ditto 는 macOS 메타데이터(서명, 확장 속성)를 보존하며 압축
pushd "$SCRIPT_DIR/Release" >/dev/null
ditto -c -k --sequesterRsrc --keepParent "${APP_NAME}.app" "$ZIP_NAME"
popd >/dev/null

ZIP_SIZE=$(du -sh "$ZIP_PATH" | cut -f1)
echo "   ✅ $ZIP_NAME  ($ZIP_SIZE)"

# ── 5. git 태그 생성 & push ───────────────────────────────────────────
echo ""
echo "━━━ [3/4] git 태그 $TAG 생성 & push ━━━"
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "   ℹ️  로컬 태그 $TAG 존재함 — 재사용"
else
    git tag -a "$TAG" -m "Release $TAG"
    echo "   ✅ 로컬 태그 생성"
fi

if git ls-remote --tags origin | grep -q "refs/tags/$TAG$"; then
    echo "   ℹ️  원격 태그 $TAG 존재함 — push 생략"
else
    git push origin "$TAG"
    echo "   ✅ 원격 푸시 완료"
fi

# ── 6. GitHub Release 생성 + asset 업로드 ────────────────────────────
echo ""
echo "━━━ [4/4] GitHub Release 생성 ━━━"

RELEASE_NOTES=$(cat <<EOF
## CView $VERSION (build $BUILD_NUMBER)

macOS 15.0 이상 지원.

### 설치
1. \`$ZIP_NAME\` 다운로드
2. 압축 해제 후 \`CView.app\` 을 \`/Applications\` 로 이동
3. 최초 실행 시 macOS 경고가 뜨면 우클릭 → 열기

### 자동 업데이트
앱 내 자동 업데이트 버튼에서 이후 버전 감지·설치가 가능합니다.
EOF
)

gh release create "$TAG" \
    --repo "$REPO_SLUG" \
    --title "CView $VERSION" \
    --notes "$RELEASE_NOTES" \
    $DRAFT_FLAG \
    "$ZIP_PATH"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🎉 릴리스 게시 완료"
echo "  🔗 https://github.com/$REPO_SLUG/releases/tag/$TAG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
