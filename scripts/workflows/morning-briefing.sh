#!/usr/bin/env bash
# morning-briefing.sh — 아침 브리핑: 미읽은 메일 + 오늘 일정 + 태스크

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../utils/common.sh"
source "${SCRIPT_DIR}/../../utils/gws-helpers.sh"
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
echo "📅 오늘 일정"
echo "---"
TIME_MIN="${TODAY}T00:00:00+09:00"
TIME_MAX="${TODAY}T23:59:59+09:00"
EVENTS=$(gws calendar events list --params "{\"calendarId\":\"primary\",\"timeMin\":\"$TIME_MIN\",\"timeMax\":\"$TIME_MAX\",\"singleEvents\":true,\"orderBy\":\"startTime\"}" 2>/dev/null)
echo "$EVENTS" | jq -r '.items[]? | "  - \(.start.dateTime // .start.date | split("T")[1]? // "종일") \(.summary)"' 2>/dev/null
echo ""

# 3. 오늘 할 일 (Google Tasks)
echo "✅ 할 일"
echo "---"
TASKLISTS=$(gws tasks tasklists list --params '{"maxResults":1}' 2>/dev/null)
LIST_ID=$(echo "$TASKLISTS" | jq -r '.items[0].id' 2>/dev/null)
if [ -n "$LIST_ID" ] && [ "$LIST_ID" != "null" ]; then
  TASKS=$(gws tasks tasks list --params "{\"tasklist\":\"$LIST_ID\",\"showCompleted\":false,\"maxResults\":10}" 2>/dev/null)
  echo "$TASKS" | jq -r '.items[]? | "  - \(.title)"' 2>/dev/null
fi

echo ""
echo "=== 브리핑 끝 ==="
