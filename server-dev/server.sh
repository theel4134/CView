#!/bin/bash
# ============================================================
# cv.dododo.app 서버 개발 도구
# 사용법: ./server-dev/server.sh <command> [options]
# ============================================================

set -euo pipefail

# ── 설정 ──────────────────────────────────────────────────────
SERVER="cv.dododo.app"
REMOTE_PROJECT="/home/dodolab/docker"
REMOTE_COLLECTOR="docker/chzzk-collector"
REMOTE_STATSWEB="docker/cview-stats-web"
REMOTE_NGINX="docker/nginx-ssl"
REMOTE_PROMETHEUS="prometheus"
REMOTE_GRAFANA="grafana"
LOCAL_MIRROR="$(cd "$(dirname "$0")" && pwd)/mirror"

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# 서버 상태 확인
cmd_status() {
    header "서버 상태"
    ssh "$SERVER" "cd $REMOTE_PROJECT && docker compose ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'"
}

# Docker 로그 보기
cmd_logs() {
    local service="${1:-chzzk-metrics}"
    local lines="${2:-100}"
    header "로그: $service (최근 ${lines}줄)"
    ssh "$SERVER" "cd $REMOTE_PROJECT && docker compose logs --tail=$lines -f $service"
}

# 원격 소스 → 로컬 미러 동기화 (pull)
cmd_pull() {
    local target="${1:-all}"
    header "Pull: 서버 → 로컬 미러"
    mkdir -p "$LOCAL_MIRROR"

    if [[ "$target" == "all" || "$target" == "collector" ]]; then
        info "chzzk-collector 동기화..."
        rsync -avz --delete \
            --exclude='__pycache__' --exclude='*.pyc' --exclude='.git' \
            "$SERVER:$REMOTE_PROJECT/$REMOTE_COLLECTOR/" \
            "$LOCAL_MIRROR/chzzk-collector/"
        ok "chzzk-collector 완료"
    fi

    if [[ "$target" == "all" || "$target" == "statsweb" ]]; then
        info "cview-stats-web 동기화..."
        rsync -avz --delete \
            --exclude='__pycache__' --exclude='*.pyc' --exclude='.git' \
            --exclude='migrations/versions' --exclude='node_modules' \
            "$SERVER:$REMOTE_PROJECT/$REMOTE_STATSWEB/" \
            "$LOCAL_MIRROR/cview-stats-web/"
        ok "cview-stats-web 완료"
    fi

    if [[ "$target" == "all" || "$target" == "nginx" ]]; then
        info "nginx-ssl 동기화..."
        rsync -avz --delete \
            "$SERVER:$REMOTE_PROJECT/$REMOTE_NGINX/" \
            "$LOCAL_MIRROR/nginx-ssl/"
        ok "nginx-ssl 완료"
    fi

    if [[ "$target" == "all" || "$target" == "compose" ]]; then
        info "docker-compose.yml 동기화..."
        rsync -avz "$SERVER:$REMOTE_PROJECT/docker-compose.yml" "$LOCAL_MIRROR/"
        ok "docker-compose.yml 완료"
    fi

    if [[ "$target" == "all" || "$target" == "scripts" ]]; then
        info "scripts 동기화..."
        rsync -avz --delete \
            "$SERVER:$REMOTE_PROJECT/scripts/" \
            "$LOCAL_MIRROR/scripts/"
        ok "scripts 완료"
    fi

    if [[ "$target" == "all" || "$target" == "prometheus" ]]; then
        info "prometheus 동기화..."
        rsync -avz --delete \
            "$SERVER:$REMOTE_PROJECT/$REMOTE_PROMETHEUS/" \
            "$LOCAL_MIRROR/prometheus/"
        ok "prometheus 완료"
    fi

    if [[ "$target" == "all" || "$target" == "grafana" ]]; then
        info "grafana 동기화..."
        rsync -avz --delete \
            "$SERVER:$REMOTE_PROJECT/$REMOTE_GRAFANA/" \
            "$LOCAL_MIRROR/grafana/"
        ok "grafana 완료"
    fi

    ok "Pull 완료: $LOCAL_MIRROR"
}

# 로컬 미러 → 서버 업로드 (push)
cmd_push() {
    local target="${1:-all}"
    header "Push: 로컬 미러 → 서버"

    if [[ ! -d "$LOCAL_MIRROR" ]]; then
        err "로컬 미러가 없습니다. 먼저 'pull'을 실행하세요."
        exit 1
    fi

    if [[ "$target" == "all" || "$target" == "collector" ]]; then
        info "chzzk-collector 업로드..."
        rsync -avz --delete \
            --exclude='__pycache__' --exclude='*.pyc' \
            "$LOCAL_MIRROR/chzzk-collector/" \
            "$SERVER:$REMOTE_PROJECT/$REMOTE_COLLECTOR/"
        ok "chzzk-collector 완료"
    fi

    if [[ "$target" == "all" || "$target" == "statsweb" ]]; then
        info "cview-stats-web 업로드..."
        rsync -avz --delete \
            --exclude='__pycache__' --exclude='*.pyc' \
            --exclude='migrations/versions' --exclude='node_modules' \
            "$LOCAL_MIRROR/cview-stats-web/" \
            "$SERVER:$REMOTE_PROJECT/$REMOTE_STATSWEB/"
        ok "cview-stats-web 완료"
    fi

    if [[ "$target" == "all" || "$target" == "nginx" ]]; then
        info "nginx-ssl 업로드..."
        rsync -avz --delete \
            "$LOCAL_MIRROR/nginx-ssl/" \
            "$SERVER:$REMOTE_PROJECT/$REMOTE_NGINX/"
        ok "nginx-ssl 완료"
    fi

    if [[ "$target" == "all" || "$target" == "compose" ]]; then
        info "docker-compose.yml 업로드..."
        rsync -avz "$LOCAL_MIRROR/docker-compose.yml" "$SERVER:$REMOTE_PROJECT/"
        ok "docker-compose.yml 완료"
    fi

    if [[ "$target" == "all" || "$target" == "prometheus" ]]; then
        info "prometheus 업로드..."
        rsync -avz --delete \
            "$LOCAL_MIRROR/prometheus/" \
            "$SERVER:$REMOTE_PROJECT/$REMOTE_PROMETHEUS/"
        ok "prometheus 완료"
    fi

    if [[ "$target" == "all" || "$target" == "grafana" ]]; then
        info "grafana 업로드..."
        rsync -avz --delete \
            "$LOCAL_MIRROR/grafana/" \
            "$SERVER:$REMOTE_PROJECT/$REMOTE_GRAFANA/"
        ok "grafana 완료"
    fi

    ok "Push 완료"
}

# 서비스 빌드 & 재시작
cmd_build() {
    local service="${1:-chzzk-metrics}"
    header "빌드 & 재시작: $service"
    ssh "$SERVER" "cd $REMOTE_PROJECT && docker compose build --no-cache $service && docker compose up -d $service"
    ok "$service 빌드 & 재시작 완료"
    sleep 2
    cmd_status
}

# 서비스 재시작 (빌드 없이)
cmd_restart() {
    local service="${1:-chzzk-metrics}"
    header "재시작: $service"
    ssh "$SERVER" "cd $REMOTE_PROJECT && docker compose restart $service"
    ok "$service 재시작 완료"
}

# 전체 스택 빌드 & 재시작
cmd_rebuild_all() {
    header "전체 스택 리빌드"
    ssh "$SERVER" "cd $REMOTE_PROJECT && docker compose build --no-cache && docker compose up -d"
    ok "전체 스택 리빌드 완료"
    sleep 3
    cmd_status
}

# push + build (편의 명령)
cmd_deploy() {
    local target="${1:-collector}"
    local service=""

    case "$target" in
        collector) service="chzzk-metrics" ;;
        statsweb)  service="cview-stats-web" ;;
        nginx)     service="nginx-ssl" ;;
        monitoring)
            header "배포: 모니터링 스택 (prometheus + grafana + exporters)"
            cmd_push "prometheus"
            cmd_push "grafana"
            cmd_push "compose"
            ssh "$SERVER" "cd $REMOTE_PROJECT && mkdir -p data/prometheus-data data/grafana-data"
            ssh "$SERVER" "cd $REMOTE_PROJECT && docker compose up -d prometheus grafana nginx-exporter postgres-exporter redis-exporter"
            ok "모니터링 스택 배포 완료"
            sleep 3
            cmd_status
            return
            ;;
        *)         err "알 수 없는 타겟: $target (collector|statsweb|nginx|monitoring)"; exit 1 ;;
    esac

    header "배포: $target → $service"
    cmd_push "$target"
    cmd_build "$service"
    ok "배포 완료: $target"
}

# 원격 셸 접속
cmd_ssh() {
    header "서버 SSH 접속"
    ssh -t "$SERVER" "cd $REMOTE_PROJECT && exec bash"
}

# 컨테이너 내부 셸
cmd_exec() {
    local service="${1:-chzzk-metrics}"
    header "컨테이너 셸: $service"
    ssh -t "$SERVER" "cd $REMOTE_PROJECT && docker compose exec $service /bin/sh"
}

# 서비스 중지
cmd_stop() {
    local service="${1:-}"
    if [[ -z "$service" ]]; then
        header "전체 스택 중지"
        ssh "$SERVER" "cd $REMOTE_PROJECT && docker compose stop"
    else
        header "서비스 중지: $service"
        ssh "$SERVER" "cd $REMOTE_PROJECT && docker compose stop $service"
    fi
    ok "중지 완료"
}

# 서비스 시작
cmd_start() {
    local service="${1:-}"
    if [[ -z "$service" ]]; then
        header "전체 스택 시작"
        ssh "$SERVER" "cd $REMOTE_PROJECT && docker compose up -d"
    else
        header "서비스 시작: $service"
        ssh "$SERVER" "cd $REMOTE_PROJECT && docker compose up -d $service"
    fi
    ok "시작 완료"
}

# 디스크/리소스 확인
cmd_resources() {
    header "서버 리소스"
    ssh "$SERVER" "echo '=== 디스크 ===' && df -h / && echo && echo '=== 메모리 ===' && free -h && echo && echo '=== Docker 디스크 ===' && docker system df 2>/dev/null"
}

# 파일 diff (로컬 미러 vs 서버)
cmd_diff() {
    local target="${1:-collector}"
    local remote_path=""

    case "$target" in
        collector) remote_path="$REMOTE_COLLECTOR" ;;
        statsweb)  remote_path="$REMOTE_STATSWEB" ;;
        nginx)     remote_path="$REMOTE_NGINX" ;;
        *)         err "알 수 없는 타겟: $target"; exit 1 ;;
    esac

    header "Diff: 로컬 vs 서버 ($target)"
    rsync -avnc --delete \
        --exclude='__pycache__' --exclude='*.pyc' \
        "$LOCAL_MIRROR/$target/" \
        "$SERVER:$REMOTE_PROJECT/$remote_path/" 2>&1 | grep -v '^\.' || ok "차이 없음"
}

# 원격 파일 직접 편집 (vim)
cmd_edit() {
    local file="${1:-}"
    if [[ -z "$file" ]]; then
        err "파일 경로를 지정하세요 (예: docker/chzzk-collector/server.py)"
        exit 1
    fi
    ssh -t "$SERVER" "vim $REMOTE_PROJECT/$file"
}

# Superset 연동 자동화 (views + datasets + dashboards + verify)
cmd_superset_sync() {
    local base_url="${1:-https://cv.dododo.app:9443}"
    local superset_user="${SUPERSET_USER:-admin}"
    local superset_pass="${SUPERSET_PASS:-admin}"
    local db_name="${SUPERSET_DB_NAME:-ChzzkMetricsDB}"

    header "Superset 연동: 메트릭 뷰/데이터셋/대시보드 동기화"
    info "BASE=$base_url, DB=$db_name, USER=$superset_user"

    info "1) PostgreSQL view 적용 (superset_views_poc.sql + views_app_metrics.sql)..."
    ssh "$SERVER" "cd $REMOTE_PROJECT && cat scripts/superset_views_poc.sql | docker compose exec -T postgres psql -U chzzk -d chzzk_db && cat scripts/sql/views_app_metrics.sql | docker compose exec -T postgres psql -U chzzk -d chzzk_db"
    ok "View 적용 완료"

    info "2) Superset dataset 등록/동기화..."
    ssh "$SERVER" "cd $REMOTE_PROJECT/scripts && SUPERSET_URL='$base_url' SUPERSET_USER='$superset_user' SUPERSET_PASS='$superset_pass' SUPERSET_DB_NAME='$db_name' python3 superset_register_datasets.py"
    ok "Dataset 동기화 완료"

    info "3) Superset 대시보드 생성/업데이트..."
    ssh "$SERVER" "cd $REMOTE_PROJECT/scripts && SUPERSET_BASE='$base_url' SUPERSET_USER='$superset_user' SUPERSET_PASSWORD='$superset_pass' python3 superset_create_dashboards.py"
    ok "Dashboard 동기화 완료"

    info "4) 대시보드 메타데이터 검증..."
    ssh "$SERVER" "cd $REMOTE_PROJECT && docker exec -t chzzk-superset python - <<'PY'
from superset.app import create_app
app = create_app()
from superset import db
from superset.models.dashboard import Dashboard
with app.app_context():
    rows = db.session.query(Dashboard.slug, Dashboard.dashboard_title).all()
    print('DASHBOARDS', rows)
PY"
    ok "Superset 연동 완료"
}

# ── 도움말 ────────────────────────────────────────────────────
cmd_help() {
    cat <<EOF

${CYAN}cv.dododo.app 서버 개발 도구${NC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

${GREEN}상태 & 모니터링:${NC}
  status              서버 컨테이너 상태
  logs [service] [n]  로그 보기 (기본: chzzk-metrics, 100줄)
  resources           디스크/메모리/Docker 리소스

${GREEN}소스 동기화:${NC}
  pull [target]       서버 → 로컬 미러 (all|collector|statsweb|nginx|compose|scripts)
  push [target]       로컬 미러 → 서버
  diff [target]       로컬 vs 서버 차이 확인

${GREEN}빌드 & 배포:${NC}
  build [service]     빌드 & 재시작 (기본: chzzk-metrics)
  restart [service]   재시작 (빌드 없이)
  deploy [target]     push + build (collector|statsweb|nginx)
    superset-sync [url] Superset 연동 실행 (view+dataset+dashboard)
  rebuild-all         전체 스택 리빌드

${GREEN}서비스 관리:${NC}
  start [service]     서비스/전체 시작
  stop [service]      서비스/전체 중지

${GREEN}접속:${NC}
  ssh                 서버 셸 접속
  exec [service]      컨테이너 내부 셸
  edit <file>         원격 파일 편집

${YELLOW}서비스 이름:${NC} chzzk-metrics, cview-stats-web, nginx-ssl, influxdb, postgres, redis
${YELLOW}타겟 이름:${NC}   collector, statsweb, nginx

${YELLOW}예시:${NC}
  ./server-dev/server.sh status
  ./server-dev/server.sh pull
  ./server-dev/server.sh logs chzzk-metrics 50
  ./server-dev/server.sh deploy collector
    ./server-dev/server.sh superset-sync
  ./server-dev/server.sh exec chzzk-metrics

EOF
}

# ── 메인 ──────────────────────────────────────────────────────
command="${1:-help}"
shift 2>/dev/null || true

case "$command" in
    status)      check_ssh; cmd_status ;;
    logs)        check_ssh; cmd_logs "$@" ;;
    pull)        check_ssh; cmd_pull "$@" ;;
    push)        check_ssh; cmd_push "$@" ;;
    diff)        check_ssh; cmd_diff "$@" ;;
    build)       check_ssh; cmd_build "$@" ;;
    restart)     check_ssh; cmd_restart "$@" ;;
    deploy)      check_ssh; cmd_deploy "$@" ;;
    superset-sync) check_ssh; cmd_superset_sync "$@" ;;
    rebuild-all) check_ssh; cmd_rebuild_all ;;
    start)       check_ssh; cmd_start "$@" ;;
    stop)        check_ssh; cmd_stop "$@" ;;
    ssh)         check_ssh; cmd_ssh ;;
    exec)        check_ssh; cmd_exec "$@" ;;
    edit)        check_ssh; cmd_edit "$@" ;;
    resources)   check_ssh; cmd_resources ;;
    help|--help|-h) cmd_help ;;
    *)           err "알 수 없는 명령: $command"; cmd_help; exit 1 ;;
esac
