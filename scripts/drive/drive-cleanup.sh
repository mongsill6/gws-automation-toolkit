#!/usr/bin/env bash
# drive-cleanup.sh — Drive에서 오래된 파일 목록 조회 및 정리

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../utils/common.sh"
source "${SCRIPT_DIR}/../../utils/gws-helpers.sh"

# ── 사용법 ──
usage() {
  cat <<'USAGE'
사용법: drive-cleanup.sh [옵션]

Google Drive에서 오래된 파일을 조회하고 선택적으로 휴지통으로 이동합니다.

옵션:
  -d, --days DAYS         기준 일수 (기본: 90일 이전 파일 대상)
  --dry-run               목록만 조회 (기본 동작)
  --execute               실제로 휴지통으로 이동
  -h, --help              사용법 출력

예시:
  # 90일 이전 파일 목록 조회 (dry run)
  drive-cleanup.sh

  # 30일 이전 파일 목록 조회
  drive-cleanup.sh -d 30

  # 60일 이전 파일을 실제로 휴지통으로 이동
  drive-cleanup.sh -d 60 --execute

  # 위치 인자 호환 (기존 방식)
  drive-cleanup.sh 90 true
USAGE
  exit 0
}

# ── 인자 파싱 ──
DAYS_OLD=90
DRY_RUN=true

while [ $# -gt 0 ]; do
  case "$1" in
    -d|--days)      DAYS_OLD="$2"; shift ;;
    --dry-run)      DRY_RUN=true ;;
    --execute)      DRY_RUN=false ;;
    -h|--help)      usage ;;
    -*)             echo "알 수 없는 옵션: $1"; usage ;;
    *)
      # 위치 인자 호환
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        DAYS_OLD="$1"
      elif [ "$1" = "false" ] || [ "$1" = "true" ]; then
        DRY_RUN="$1"
      fi
      ;;
  esac
  shift
done

check_gws_deps

BEFORE_DATE=$(date -d "$DAYS_OLD days ago" +%Y-%m-%dT00:00:00 2>/dev/null || date "-v-${DAYS_OLD}d" +%Y-%m-%dT00:00:00)

log_info "Drive 파일 정리: ${DAYS_OLD}일 이전 (dry_run=$DRY_RUN)"

# 오래된 파일 검색 (내가 소유한 것만)
FILES=$(gws drive files list --params "{\"q\":\"modifiedTime < '$BEFORE_DATE' and 'me' in owners and trashed = false\",\"pageSize\":50,\"fields\":\"files(id,name,modifiedTime,size,mimeType)\"}")

echo "$FILES" | jq -r '.files[]? | "\(.name)\t\(.modifiedTime[:10])\t\(.size // "?")\t\(.id)"' | while IFS=$'\t' read -r NAME DATE SIZE ID; do
  SIZE_MB=$(echo "scale=1; ${SIZE:-0}/1048576" | bc 2>/dev/null || echo "?")
  log_info "$NAME ($DATE, ${SIZE_MB}MB)"

  if [ "$DRY_RUN" = "false" ]; then
    gws drive files update --params "{\"fileId\":\"$ID\"}" --json '{"trashed":true}' >/dev/null 2>&1
    log_info "-> 휴지통으로 이동"
  fi
done

echo "---"
if [ "$DRY_RUN" = "true" ]; then
  log_info "dry run 모드입니다. 실제 삭제: $0 --execute"
fi
