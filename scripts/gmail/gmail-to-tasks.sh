#!/usr/bin/env bash
# gmail-to-tasks.sh — 특정 라벨/조건의 메일을 Google Tasks로 변환

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../utils/common.sh"
source "${SCRIPT_DIR}/../../utils/gws-helpers.sh"

# ── 사용법 ──
usage() {
  cat <<'USAGE'
사용법: gmail-to-tasks.sh [옵션]

Gmail에서 특정 조건의 메일을 검색하여 Google Tasks로 자동 변환합니다.

옵션:
  -q, --query QUERY       Gmail 검색 조건 (기본: "label:action-required is:unread")
  -m, --max MAX           최대 처리 건수 (기본: 5)
  -h, --help              사용법 출력

예시:
  # 기본 설정으로 실행 (action-required 라벨, 미읽은 메일)
  gmail-to-tasks.sh

  # 특정 발신자 메일을 태스크로 변환
  gmail-to-tasks.sh -q "from:boss@company.com is:unread" -m 10

  # 위치 인자 호환 (기존 방식)
  gmail-to-tasks.sh "is:starred is:unread" 3
USAGE
  exit 0
}

# ── 인자 파싱 ──
QUERY="label:action-required is:unread"
MAX_RESULTS=5

while [ $# -gt 0 ]; do
  case "$1" in
    -q|--query)   QUERY="$2"; shift ;;
    -m|--max)     MAX_RESULTS="$2"; shift ;;
    -h|--help)    usage ;;
    -*)           echo "알 수 없는 옵션: $1"; usage ;;
    *)
      # 위치 인자 호환
      if [ "$QUERY" = "label:action-required is:unread" ]; then
        QUERY="$1"
      elif [ "$MAX_RESULTS" -eq 5 ] 2>/dev/null; then
        MAX_RESULTS="$1"
      fi
      ;;
  esac
  shift
done

check_gws_deps

log_info "Gmail to Tasks 변환"
log_info "검색 조건: $QUERY"

# 기본 태스크 리스트 ID 가져오기
LIST_ID=$(gws tasks tasklists list --params '{"maxResults":1}' | jq -r '.items[0].id')
if [ -z "$LIST_ID" ] || [ "$LIST_ID" = "null" ]; then
  log_error "태스크 리스트를 찾을 수 없습니다"
  exit 1
fi

# 메일 검색
MESSAGES=$(gws gmail users messages list --params "{\"userId\":\"me\",\"q\":\"$QUERY\",\"maxResults\":$MAX_RESULTS}")
MSG_IDS=$(echo "$MESSAGES" | jq -r '.messages[]?.id' 2>/dev/null)

if [ -z "$MSG_IDS" ]; then
  log_info "변환할 메일이 없습니다"
  exit 0
fi

COUNT=0
while read -r MSG_ID; do
  # 메일 상세 가져오기
  MSG=$(gws gmail users messages get --params "{\"userId\":\"me\",\"id\":\"$MSG_ID\",\"format\":\"metadata\",\"metadataHeaders\":[\"From\",\"Subject\",\"Date\"]}")
  SUBJECT=$(echo "$MSG" | jq -r '.payload.headers[] | select(.name=="Subject") | .value')
  FROM=$(echo "$MSG" | jq -r '.payload.headers[] | select(.name=="From") | .value')

  # 태스크 생성
  TASK_TITLE="[메일] $SUBJECT"
  TASK_NOTES="From: $FROM\nGmail ID: $MSG_ID"

  gws tasks tasks insert --params "{\"tasklist\":\"$LIST_ID\"}" \
    --json "{\"title\":\"$TASK_TITLE\",\"notes\":\"$TASK_NOTES\"}" >/dev/null 2>&1

  log_info "$TASK_TITLE"
  COUNT=$((COUNT + 1))
done <<< "$MSG_IDS"

log_success "총 ${COUNT}개 태스크 생성 완료"
