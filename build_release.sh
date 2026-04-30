#!/bin/zsh
# ─────────────────────────────────────────────────────────────────────
# CView v2 — Release .app Bundle Builder
# SPM executableTarget → macOS .app 번들 패키징
# Usage:  ./build_release.sh
# Output: Release/CView.app
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── 설정 ──────────────────────────────────────────────────────────────
APP_NAME="CView"
BUNDLE_ID="com.cview.CView2"
EXECUTABLE="CViewApp"
MIN_MACOS="15.0"

# [Single Source of Truth] 버전은 SupportFiles/Info.plist 에서 읽어온다.
# release_to_github.sh 와 동일 소스를 사용하여 두 스크립트의 버전 불일치를 방지.
INFO_PLIST_VERSION_SRC="${0:A:h}/SupportFiles/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST_VERSION_SRC")

# ── 빌드 번호 자동 증가 ──────────────────────────────────────────────
BUILD_NUMBER_FILE="${0:A:h}/.build_number"
if [[ -f "$BUILD_NUMBER_FILE" ]]; then
    BUILD_NUMBER=$(( $(cat "$BUILD_NUMBER_FILE") + 1 ))
else
    BUILD_NUMBER=1
fi
echo "$BUILD_NUMBER" > "$BUILD_NUMBER_FILE"
echo "📦 버전: ${VERSION} (${BUILD_NUMBER})"

SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"

# ── SPM scratch 경로: Xcode DerivedData와 동일 루트(/Volumes/hdd/app-work/build) 하위 SPM/ ──
# 로컬 디스크의 .build 대신 외장 SSD를 사용 (VS Code swift.buildPath 와 동일 경로)
SPM_SCRATCH_PATH="/Volumes/hdd/app-work/build/SPM"
mkdir -p "$SPM_SCRATCH_PATH"

RELEASE_DIR="$SCRIPT_DIR/Release"
APP_BUNDLE="$RELEASE_DIR/${APP_NAME}.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"

# ── 1. 릴리즈 빌드 ───────────────────────────────────────────────────
echo "━━━ [1/5] Release 빌드 시작... ━━━"
# -j: CPU 코어 수만큼 병렬 빌드, --disable-automatic-resolution: 매번 패키지 resolve 방지
JOBS=$(sysctl -n hw.performancecores 2>/dev/null || sysctl -n hw.ncpu)
# [Fix] `swift build | tail -5` 는 tail 이 먼저 종료되면 SIGPIPE 로 swift build 가 141 로 죽고
# `set -euo pipefail` 과 맞물려 스크립트 전체가 실패한다. 로그는 파일로 받고 tail 은 별도로 호출.
SWIFT_BUILD_LOG="$(mktemp -t cview_swift_build).log"
if ! swift build -c release -j "$JOBS" --scratch-path "$SPM_SCRATCH_PATH" --disable-automatic-resolution >"$SWIFT_BUILD_LOG" 2>&1; then
    echo "❌ Swift 빌드 실패 (마지막 30줄):"
    tail -30 "$SWIFT_BUILD_LOG"
    exit 1
fi
tail -5 "$SWIFT_BUILD_LOG"
echo "✅ 빌드 완료"

# 빌드 산출물 경로
BUILD_BIN="$(swift build -c release --scratch-path "$SPM_SCRATCH_PATH" --show-bin-path)"
echo "   빌드 경로: $BUILD_BIN"

# ── 2. .app 번들 구조 생성 ────────────────────────────────────────────
echo "━━━ [2/5] .app 번들 구조 생성... ━━━"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES" "$FRAMEWORKS"

# ── 3. 실행 파일 복사 ─────────────────────────────────────────────────
echo "━━━ [3/5] 실행 파일 및 프레임워크 복사... ━━━"
cp "$BUILD_BIN/$EXECUTABLE" "$MACOS_DIR/$APP_NAME"

# VLCKit.framework 복사 (SPM 빌드 산출물에서)
VLC_FW_SRC="$BUILD_BIN/VLCKit.framework"
if [[ -d "$VLC_FW_SRC" ]]; then
    cp -R "$VLC_FW_SRC" "$FRAMEWORKS/"
    echo "   VLCKit.framework 복사 완료"

    # rpath 수정: 실행 파일이 Frameworks/ 내 VLCKit을 찾도록
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true

    # VLCKit의 install name 변경 (필요 시)
    VLC_DYLIB="$FRAMEWORKS/VLCKit.framework/Versions/A/VLCKit"
    if [[ -f "$VLC_DYLIB" ]]; then
        CURRENT_ID=$(otool -D "$VLC_DYLIB" | tail -1)
        install_name_tool -id "@rpath/VLCKit.framework/Versions/A/VLCKit" "$VLC_DYLIB" 2>/dev/null || true
        # 실행 파일 내 VLCKit 참조도 @rpath로 변경
        install_name_tool -change "$CURRENT_ID" "@rpath/VLCKit.framework/Versions/A/VLCKit" "$MACOS_DIR/$APP_NAME" 2>/dev/null || true
    fi
else
    echo "❌ VLCKit.framework를 찾을 수 없습니다: $VLC_FW_SRC"
    echo "   → SPM 의존성 확인: swift package resolve"
    echo "   → 네트워크 연결 및 VLCKitSPM 저장소 접근 확인"
    exit 1
fi

# ── 4. 리소스 복사 ────────────────────────────────────────────────────
echo "━━━ [4/5] 리소스 복사... ━━━"

# [Fix 32] Info.plist 단일화 (B-1) + ATS 정책 정렬 (SEC-1)
# SupportFiles/Info.plist 를 single source of truth 로 사용하고 plutil 로 동적 키만 치환.
# → Xcode 빌드와 SPM 릴리스 빌드의 ATS/권한 정책 차이를 제거.
INFO_PLIST_SRC="$SCRIPT_DIR/SupportFiles/Info.plist"
if [[ ! -f "$INFO_PLIST_SRC" ]]; then
    echo "❌ SupportFiles/Info.plist 를 찾을 수 없습니다: $INFO_PLIST_SRC"
    exit 1
fi
cp "$INFO_PLIST_SRC" "$CONTENTS/Info.plist"
plutil -replace CFBundleExecutable        -string "$APP_NAME"     "$CONTENTS/Info.plist"
plutil -replace CFBundleIdentifier        -string "$BUNDLE_ID"    "$CONTENTS/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION"     "$CONTENTS/Info.plist"
plutil -replace CFBundleVersion           -string "$BUILD_NUMBER" "$CONTENTS/Info.plist"
plutil -replace LSMinimumSystemVersion    -string "$MIN_MACOS"    "$CONTENTS/Info.plist"
# 검증
if ! plutil -lint "$CONTENTS/Info.plist" >/dev/null 2>&1; then
    echo "❌ Info.plist 검증 실패"
    plutil -lint "$CONTENTS/Info.plist"
    exit 1
fi
echo "   Info.plist 생성 완료 (SupportFiles/Info.plist 기반, plutil 치환)"

# AppIcon.icns 복사
ICNS_SRC="$SCRIPT_DIR/SupportFiles/Assets.xcassets/AppIcon.icns"
if [[ -f "$ICNS_SRC" ]]; then
    cp "$ICNS_SRC" "$RESOURCES/AppIcon.icns"
    echo "   AppIcon.icns 복사 완료"
else
    echo "⚠️  AppIcon.icns 없음 — 기본 아이콘 사용"
fi

# Entitlements 복사 (codesign 시 사용)
ENTITLEMENTS="$SCRIPT_DIR/SupportFiles/CView_v2.entitlements"

# PkgInfo
echo -n "APPL????" > "$CONTENTS/PkgInfo"

# ── 5. 코드 서명 ──────────────────────────────────────────────────────
echo "━━━ [5/5] 코드 서명... ━━━"
# [Gatekeeper] 서명 전 모든 확장 속성 제거 (SPM 빌드 산출물에 명시적으로 않은 xattr 이 묻어버리면
# macOS 15+ Gatekeeper 가 "악성 코드가 없음을 확인할 수 없습니다" 다이얼로그를 띄움).
xattr -cr "$APP_BUNDLE" 2>/dev/null || true
# VLCKit 먼저 서명 (앱과 동일한 ad-hoc + hardened runtime — macOS 26 필수)
if [[ -d "$FRAMEWORKS/VLCKit.framework" ]]; then
    codesign --force --sign - --timestamp=none --generate-entitlement-der --options runtime "$FRAMEWORKS/VLCKit.framework"
    echo "   VLCKit.framework 서명 완료 (hardened runtime)"
fi

# 앱 번들 전체 서명 (ad-hoc + hardened runtime, entitlements 적용)
if [[ -f "$ENTITLEMENTS" ]]; then
    codesign --force --sign - --timestamp=none --generate-entitlement-der --options runtime --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
else
    codesign --force --sign - --timestamp=none --generate-entitlement-der --options runtime "$APP_BUNDLE"
fi
echo "✅ 코드 서명 완료 (ad-hoc)"

# 코드 서명 검증
echo "   코드 서명 검증 중..."
if ! codesign --verify --deep --strict "$APP_BUNDLE" 2>/dev/null; then
    echo "❌ 코드 서명 검증 실패!"
    exit 1
fi
echo "   코드 서명 검증 통과"

# ── 완료 ──────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ ${APP_NAME}.app 릴리즈 빌드 완료!"
echo "  📁 위치: $APP_BUNDLE"
echo "  📦 버전: $VERSION ($BUILD_NUMBER)"
echo ""

# 번들 크기 출력
APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
echo "  💾 크기: $APP_SIZE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "실행: open \"$APP_BUNDLE\""
echo "DMG 생성: hdiutil create -volname \"$APP_NAME\" -srcfolder \"$RELEASE_DIR\" -ov -format UDZO \"$RELEASE_DIR/${APP_NAME}.dmg\""
