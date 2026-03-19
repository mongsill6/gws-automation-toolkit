#!/usr/bin/env bash
# morning-briefing.sh — 아침 브리핑: 미읽은 메일 + 오늘 일정 + 태스크

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../utils/common.sh"
source "${SCRIPT_DIR}/../../utils/gws-helpers.sh"

# ── 사용법 ──
usage() {
  cat <<'USAGE'
사용법: morning-briefing.sh [옵션]

아침 브리핑을 생성합니다: 미읽은 메일 요약, 오늘 일정, 할 일 목록.

옵션:
  -h, --help              사용법 출력

예시:
  morning-briefing.sh
USAGE
  exit 0
}

# ── 인자 파싱 ──
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)   usage ;;
    -*)          echo "알 수 없는 옵션: $1"; usage ;;
    *)           ;;
  esac
  shift
done

check_gws_deps

TODAY=$(date +%Y-%m-%d)
log_info "=== 아침 브리핑 ($TODAY) ==="
echo ""

# 1. 미읽은 메일 요약
log_info "미읽은 메일"
UNREAD=$(gws gmail users messages list --params "{\"userId\":\"me\",\"q\":\"is:unread\",\"maxResults\":10}" 2>/dev/null)
echo "$UNREAD" | jq -r '.messages[]? | .id' | while read -r MSG_ID; do
  HEADERS=$(gws gmail users messages get --params "{\"userId\":\"me\",\"id\":\"$MSG_ID\",\"format\":\"metadata\",\"metadataHeaders\":[\"From\",\"Subject\"]}" 2>/dev/null)
  FROM=$(echo "$HEADERS" | jq -r '.payload.headers[] | select(.name=="From") | .value' 2>/dev/null | head -1)
  SUBJECT=$(echo "$HEADERS" | jq -r '.payload.headers[] | select(.name=="Subject") | .value' 2>/dev/null | head -1)
  echo "  - [$FROM] $SUBJECT"
done
echo ""

# 2. 오늘 일정
log_info "오늘 일정"
echo "---"
TIME_MIN="${TODAY}T00:00:00+09:00"
TIME_MAX="${TODAY}T23:59:59+09:00"
EVENTS=$(gws calendar events list --params "{\"calendarId\":\"primary\",\"timeMin\":\"$TIME_MIN\",\"timeMax\":\"$TIME_MAX\",\"singleEvents\":true,\"orderBy\":\"startTime\"}" 2>/dev/null)
echo "$EVENTS" | jq -r '.items[]? | "  - \(.start.dateTime // .start.date | split("T")[1]? // "종일") \(.summary)"' 2>/dev/null
echo ""

# 3. 오늘 할 일 (Google Tasks)
log_info "할 일"
echo "---"
TASKLISTS=$(gws tasks tasklists list --params '{"maxResults":1}' 2>/dev/null)
LIST_ID=$(echo "$TASKLISTS" | jq -r '.items[0].id' 2>/dev/null)
if [ -n "$LIST_ID" ] && [ "$LIST_ID" != "null" ]; then
  TASKS=$(gws tasks tasks list --params "{\"tasklist\":\"$LIST_ID\",\"showCompleted\":false,\"maxResults\":10}" 2>/dev/null)
  echo "$TASKS" | jq -r '.items[]? | "  - \(.title)"' 2>/dev/null
fi

echo ""
log_success "브리핑 완료"
