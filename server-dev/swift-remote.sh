#!/bin/bash
# ============================================================
# CView_v2 Swift 소스 원격 동기화 & 관리 도구
# 사용법: ./server-dev/swift-remote.sh <command> [options]
#
# 서버(cv.dododo.app)의 ~/CView_v2와 로컬 소스를 동기화하고
# 원격 Swift 스크립트 실행, REPL, 코드 검색 등을 지원합니다.
# ※ macOS 전용 프레임워크(SwiftUI/AppKit) 의존으로
#   Swift 패키지 빌드는 로컬 macOS에서만 가능합니다.
# ============================================================

set -euo pipefail

# ── 설정 ──────────────────────────────────────────────────────
SERVER="cv.dododo.app"
REMOTE_PROJECT="/home/dodolab/CView_v2"
LOCAL_PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT_ENV='export PATH="$HOME/swift/usr/bin:$PATH"'

# macOS 전용 파일/폴더 (서버 동기화 제외)
EXCLUDE_ARGS=(
    --exclude='.build'
    --exclude='Build'
    --exclude='.git'
    --exclude='.DS_Store'
    --exclude='*.xcodeproj'
    --exclude='*.xcworkspace'
    --exclude='*.xcframework'
    --exclude='server-dev'
    --exclude='.swiftpm'
    --exclude='Package.resolved'
)

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERR]${NC} $*" >&2; }
header(){ echo -e "\n${CYAN}━━━ $* ━━━${NC}"; }

# ── 연결 확인 ─────────────────────────────────────────────────
check_ssh() {
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$SERVER" "true" 2>/dev/null; then
        err "SSH 연결 실패: $SERVER"
        exit 1
    fi
}

# ── 명령어 ────────────────────────────────────────────────────

# 소스 동기화: 로컬 → 서버
cmd_sync() {
    header "소스 동기화: 로컬 → 서버"
    rsync -avz --delete \
        "${EXCLUDE_ARGS[@]}" \
        "$LOCAL_PROJECT/Sources/" \
        "$SERVER:$REMOTE_PROJECT/Sources/"
    
    rsync -avz --delete \
        "${EXCLUDE_ARGS[@]}" \
        "$LOCAL_PROJECT/Tests/" \
        "$SERVER:$REMOTE_PROJECT/Tests/"
    
    rsync -avz "$LOCAL_PROJECT/Package.swift" "$SERVER:$REMOTE_PROJECT/"
    
    ok "소스 동기화 완료"
}

# 소스 동기화: 서버 → 로컬
cmd_pull() {
    header "소스 동기화: 서버 → 로컬"
    rsync -avz --delete \
        "${EXCLUDE_ARGS[@]}" \
        "$SERVER:$REMOTE_PROJECT/Sources/" \
        "$LOCAL_PROJECT/Sources/"
    
    rsync -avz --delete \
        "${EXCLUDE_ARGS[@]}" \
        "$SERVER:$REMOTE_PROJECT/Tests/" \
        "$LOCAL_PROJECT/Tests/"
    
    ok "서버 → 로컬 동기화 완료"
}

# diff: 로컬 vs 서버
cmd_diff() {
    header "Diff: 로컬 vs 서버"
    local has_diff=0
    
    local src_diff
    src_diff=$(rsync -avnc --delete \
        "${EXCLUDE_ARGS[@]}" \
        "$LOCAL_PROJECT/Sources/" \
        "$SERVER:$REMOTE_PROJECT/Sources/" 2>&1 | grep -v '^\.\|^sending\|^sent\|^total' || true)
    
    if [[ -n "$src_diff" ]]; then
        echo -e "${BOLD}Sources:${NC}"
        echo "$src_diff"
        has_diff=1
    fi
    
    local test_diff
    test_diff=$(rsync -avnc --delete \
        "${EXCLUDE_ARGS[@]}" \
        "$LOCAL_PROJECT/Tests/" \
        "$SERVER:$REMOTE_PROJECT/Tests/" 2>&1 | grep -v '^\.\|^sending\|^sent\|^total' || true)
    
    if [[ -n "$test_diff" ]]; then
        echo -e "${BOLD}Tests:${NC}"
        echo "$test_diff"
        has_diff=1
    fi
    
    if [[ $has_diff -eq 0 ]]; then
        ok "차이 없음"
    fi
}

# 원격 코드 검색 (grep)
cmd_grep() {
    local pattern="${1:-}"
    local path="${2:-Sources}"
    if [[ -z "$pattern" ]]; then
        err "검색 패턴을 지정하세요"
        exit 1
    fi
    header "원격 코드 검색: '$pattern' in $path"
    ssh "$SERVER" "cd $REMOTE_PROJECT && grep -rn --include='*.swift' --color=always '$pattern' $path" || ok "결과 없음"
}

# 원격 파일 보기
cmd_cat() {
    local file="${1:-}"
    if [[ -z "$file" ]]; then
        err "파일 경로를 지정하세요 (예: Sources/CViewCore/Models/MetricsModels.swift)"
        exit 1
    fi
    ssh "$SERVER" "cat $REMOTE_PROJECT/$file"
}

# 원격 파일 목록
cmd_ls() {
    local path="${1:-Sources}"
    ssh "$SERVER" "find $REMOTE_PROJECT/$path -name '*.swift' | sed 's|$REMOTE_PROJECT/||' | sort"
}

# 원격 파일 라인 수 통계
cmd_stats() {
    header "코드 통계"
    ssh "$SERVER" "cd $REMOTE_PROJECT && find Sources -name '*.swift' | xargs wc -l | sort -n | tail -20"
    echo ""
    ssh "$SERVER" "cd $REMOTE_PROJECT && echo '모듈별:' && for d in Sources/*/; do mod=\$(basename \$d); lines=\$(find \$d -name '*.swift' -exec cat {} + 2>/dev/null | wc -l); files=\$(find \$d -name '*.swift' | wc -l); printf '  %-20s %5d lines (%d files)\n' \$mod \$lines \$files; done"
}

# Swift REPL
cmd_repl() {
    header "Swift REPL (서버)"
    ssh -t "$SERVER" "$SWIFT_ENV && swift repl"
}

# Swift 스크립트 실행
cmd_run() {
    local script="${1:-}"
    if [[ -z "$script" ]]; then
        err "스크립트 파일 경로를 지정하세요"
        exit 1
    fi
    header "스크립트 실행: $script"
    # 로컬 파일을 서버에 전송하고 실행
    local remote_tmp="/tmp/swift-run-$(date +%s).swift"
    scp "$script" "$SERVER:$remote_tmp"
    ssh "$SERVER" "$SWIFT_ENV && swift $remote_tmp; rm -f $remote_tmp"
}

# Swift 버전 정보
cmd_version() {
    header "Swift 환경"
    echo -e "${BOLD}로컬:${NC}"
    swift --version 2>/dev/null || echo "  (로컬 Swift 없음)"
    echo ""
    echo -e "${BOLD}서버:${NC}"
    ssh "$SERVER" "$SWIFT_ENV && swift --version && echo '' && echo 'Platform:' && uname -m && echo '' && echo 'OS:' && cat /etc/os-release | head -2"
}

# 패키지 정보
cmd_describe() {
    header "패키지 정보"
    ssh "$SERVER" "$SWIFT_ENV && cd $REMOTE_PROJECT && swift package describe 2>&1"
}

# 패키지 resolve
cmd_resolve() {
    header "패키지 의존성 해결"
    cmd_sync
    ssh "$SERVER" "$SWIFT_ENV && cd $REMOTE_PROJECT && swift package resolve 2>&1"
    ok "패키지 resolve 완료"
}

# 패키지 clean
cmd_clean() {
    header "빌드 캐시 정리"
    ssh "$SERVER" "$SWIFT_ENV && cd $REMOTE_PROJECT && swift package clean 2>&1"
    ok "빌드 캐시 정리 완료"
}

# ── 도움말 ────────────────────────────────────────────────────
cmd_help() {
    cat <<EOF

${CYAN}CView_v2 Swift 원격 개발 도구${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

${GREEN}소스 동기화:${NC}
  sync                로컬 → 서버 소스 동기화
  pull                서버 → 로컬 소스 동기화
  diff                로컬 vs 서버 차이 확인

${GREEN}코드 탐색:${NC}
  grep <pattern> [path]  원격 코드 검색 (기본: Sources)
  cat <file>             원격 파일 내용 보기
  ls [path]              Swift 파일 목록 (기본: Sources)
  stats                  코드 라인 수 통계

${GREEN}Swift 실행:${NC}
  repl                서버에서 Swift REPL
  run <script.swift>  Swift 스크립트 원격 실행

${GREEN}패키지 관리:${NC}
  describe            패키지 구조 출력
  resolve             패키지 의존성 해결
  clean               빌드 캐시 정리
  version             Swift 환경 정보 (로컬/서버)

${YELLOW}참고:${NC} 이 프로젝트는 SwiftUI/AppKit에 의존하므로
  Swift 패키지 빌드/테스트는 macOS 로컬에서 실행하세요.
  (xcodebuild 또는 VS Code 빌드 태스크 사용)

${YELLOW}예시:${NC}
  ./server-dev/swift-remote.sh sync
  ./server-dev/swift-remote.sh grep "MetricsForwarder"
  ./server-dev/swift-remote.sh cat Sources/CViewCore/Models/MetricsModels.swift
  ./server-dev/swift-remote.sh stats
  ./server-dev/swift-remote.sh repl

EOF
}

# ── 메인 ──────────────────────────────────────────────────────
command="${1:-help}"
shift 2>/dev/null || true

case "$command" in
    sync)        check_ssh; cmd_sync ;;
    pull)        check_ssh; cmd_pull ;;
    diff)        check_ssh; cmd_diff ;;
    grep)        check_ssh; cmd_grep "$@" ;;
    cat)         check_ssh; cmd_cat "$@" ;;
    ls)          check_ssh; cmd_ls "$@" ;;
    stats)       check_ssh; cmd_stats ;;
    repl)        check_ssh; cmd_repl ;;
    run)         check_ssh; cmd_run "$@" ;;
    describe)    check_ssh; cmd_describe ;;
    resolve)     check_ssh; cmd_resolve ;;
    clean)       check_ssh; cmd_clean ;;
    version)     check_ssh; cmd_version ;;
    help|--help|-h) cmd_help ;;
    *)           err "알 수 없는 명령: $command"; cmd_help; exit 1 ;;
esac
