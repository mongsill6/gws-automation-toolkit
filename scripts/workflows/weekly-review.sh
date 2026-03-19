#!/usr/bin/env bash
# weekly-review.sh — 주간 리뷰: 메일 통계 + 완료 태스크 + 회의 시간 합계 + Drive 활동 요약

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../utils/common.sh"
source "${SCRIPT_DIR}/../../utils/gws-helpers.sh"
check_gws_deps

# 이번 주 월~금 날짜 범위 계산
DOW=$(date +%u)  # 1=월 ~ 7=일
MON_OFFSET=$(( DOW - 1 ))
FRI_OFFSET=$(( DOW - 5 ))
WEEK_START=$(date -d "-${MON_OFFSET} days" +%Y-%m-%d)
WEEK_END=$(date -d "-${FRI_OFFSET} days" +%Y-%m-%d)
# 주말에 실행 시에도 이번 주 금요일까지
if [ "$DOW" -gt 5 ]; then
  WEEK_END=$(date -d "-$(( DOW - 5 )) days" +%Y-%m-%d)
fi

TIME_MIN="${WEEK_START}T00:00:00+09:00"
TIME_MAX="${WEEK_END}T23:59:59+09:00"

echo "# 📊 주간 리뷰"
echo ""
echo "**기간**: ${WEEK_START} (월) ~ ${WEEK_END} (금)"
echo ""
echo "---"
echo ""

# ─────────────────────────────────────
# 1. Gmail 통계
# ─────────────────────────────────────
echo "## 📬 이메일 통계"
echo ""

# 수신 메일 수
RECEIVED=$(gws gmail users messages list --params "{\"userId\":\"me\",\"q\":\"after:${WEEK_START} before:${WEEK_END} in:inbox\",\"maxResults\":500}" 2>/dev/null)
RECEIVED_COUNT=$(echo "$RECEIVED" | jq '.resultSizeEstimate // 0' 2>/dev/null)

# 발신 메일 수
SENT=$(gws gmail users messages list --params "{\"userId\":\"me\",\"q\":\"after:${WEEK_START} before:${WEEK_END} in:sent\",\"maxResults\":500}" 2>/dev/null)
SENT_COUNT=$(echo "$SENT" | jq '.resultSizeEstimate // 0' 2>/dev/null)

# 미읽은 메일 수
UNREAD=$(gws gmail users messages list --params "{\"userId\":\"me\",\"q\":\"after:${WEEK_START} before:${WEEK_END} is:unread\",\"maxResults\":500}" 2>/dev/null)
UNREAD_COUNT=$(echo "$UNREAD" | jq '.resultSizeEstimate // 0' 2>/dev/null)

echo "- **수신**: ${RECEIVED_COUNT}건"
echo "- **발신**: ${SENT_COUNT}건"
echo "- **미읽음**: ${UNREAD_COUNT}건"
echo ""

# ─────────────────────────────────────
# 2. 완료된 Google Tasks
# ─────────────────────────────────────
echo "## ✅ 완료된 태스크"
echo ""

COMPLETED_TOTAL=0
TASKLISTS=$(gws tasks tasklists list --params '{"maxResults":100}' 2>/dev/null)
LIST_IDS=$(echo "$TASKLISTS" | jq -r '.items[]?.id' 2>/dev/null)

for LIST_ID in $LIST_IDS; do
  LIST_NAME=$(echo "$TASKLISTS" | jq -r ".items[] | select(.id==\"$LIST_ID\") | .title" 2>/dev/null)
  COMPLETED=$(gws tasks tasks list --params "{\"tasklist\":\"$LIST_ID\",\"showCompleted\":true,\"showHidden\":true,\"completedMin\":\"${TIME_MIN}\",\"completedMax\":\"${TIME_MAX}\"}" 2>/dev/null)
  ITEMS=$(echo "$COMPLETED" | jq -r '.items[]? | select(.status=="completed") | .title' 2>/dev/null)
  if [ -n "$ITEMS" ]; then
    echo "**${LIST_NAME}**:"
    while read -r TITLE; do
      echo "- [x] ${TITLE}"
      COMPLETED_TOTAL=$((COMPLETED_TOTAL + 1))
    done <<< "$ITEMS"
    echo ""
  fi
done

if [ "$COMPLETED_TOTAL" -eq 0 ]; then
  echo "_이번 주 완료된 태스크가 없습니다._"
  echo ""
fi

# ─────────────────────────────────────
# 3. Calendar 회의 통계
# ─────────────────────────────────────
echo "## 📅 회의 통계"
echo ""

EVENTS=$(gws calendar events list --params "{\"calendarId\":\"primary\",\"timeMin\":\"$TIME_MIN\",\"timeMax\":\"$TIME_MAX\",\"singleEvents\":true,\"orderBy\":\"startTime\",\"maxResults\":250}" 2>/dev/null)

MEETING_COUNT=0
TOTAL_MINUTES=0

while IFS='|' read -r START_DT END_DT _; do
  # 종일 일정 제외 (dateTime이 있는 것만 카운트)
  if [ -n "$START_DT" ] && [ "$START_DT" != "null" ] && [ -n "$END_DT" ] && [ "$END_DT" != "null" ]; then
    START_EPOCH=$(date -d "$START_DT" +%s 2>/dev/null || echo 0)
    END_EPOCH=$(date -d "$END_DT" +%s 2>/dev/null || echo 0)
    if [ "$START_EPOCH" -gt 0 ] && [ "$END_EPOCH" -gt 0 ]; then
      DURATION=$(( (END_EPOCH - START_EPOCH) / 60 ))
      TOTAL_MINUTES=$((TOTAL_MINUTES + DURATION))
      MEETING_COUNT=$((MEETING_COUNT + 1))
    fi
  fi
done < <(echo "$EVENTS" | jq -r '.items[]? | "\(.start.dateTime // "null")|\(.end.dateTime // "null")|\(.summary // "제목 없음")"' 2>/dev/null)

HOURS=$((TOTAL_MINUTES / 60))
MINS=$((TOTAL_MINUTES % 60))

echo "- **총 회의 수**: ${MEETING_COUNT}건"
echo "- **총 회의 시간**: ${HOURS}시간 ${MINS}분"
if [ "$MEETING_COUNT" -gt 0 ]; then
  AVG=$((TOTAL_MINUTES / MEETING_COUNT))
  echo "- **평균 회의 시간**: ${AVG}분"
fi
echo ""

# 요일별 회의 분포
echo "**요일별 회의 분포**:"
for DAY_OFFSET in 0 1 2 3 4; do
  DAY_DATE=$(date -d "${WEEK_START} +${DAY_OFFSET} days" +%Y-%m-%d)
  DAY_NAME=$(date -d "${WEEK_START} +${DAY_OFFSET} days" +%a)
  DAY_COUNT=$(echo "$EVENTS" | jq "[.items[]? | select(.start.dateTime != null) | select(.start.dateTime | startswith(\"${DAY_DATE}\"))] | length" 2>/dev/null)
  echo "- ${DAY_NAME} (${DAY_DATE}): ${DAY_COUNT}건"
done
echo ""

# ─────────────────────────────────────
# 4. Drive 최근 활동
# ─────────────────────────────────────
echo "## 📁 Drive 활동"
echo ""

# 이번 주 수정된 파일
MODIFIED=$(gws drive files list --params "{\"q\":\"modifiedTime > '${WEEK_START}T00:00:00' and trashed = false\",\"fields\":\"files(id,name,mimeType,modifiedTime,lastModifyingUser)\",\"orderBy\":\"modifiedTime desc\",\"pageSize\":20}" 2>/dev/null)

FILE_COUNT=$(echo "$MODIFIED" | jq '.files | length' 2>/dev/null)
echo "**이번 주 수정/생성된 파일**: ${FILE_COUNT}건"
echo ""

if [ "$FILE_COUNT" -gt 0 ]; then
  echo "$MODIFIED" | jq -r '.files[]? | "- **\(.name)** — \(.modifiedTime | split("T")[0]) \(if .mimeType == "application/vnd.google-apps.spreadsheet" then "📊" elif .mimeType == "application/vnd.google-apps.document" then "📝" elif .mimeType == "application/vnd.google-apps.presentation" then "📽️" elif .mimeType == "application/vnd.google-apps.folder" then "📂" else "📄" end)"' 2>/dev/null
  echo ""
fi

# ─────────────────────────────────────
# 요약
# ─────────────────────────────────────
echo "---"
echo ""
echo "## 📈 주간 요약"
echo ""
echo "- 이메일 처리: 수신 ${RECEIVED_COUNT}건 / 발신 ${SENT_COUNT}건 / 미읽음 ${UNREAD_COUNT}건"
echo "- 회의: ${MEETING_COUNT}건 (${HOURS}h ${MINS}m)"
echo "- Drive 활동: ${FILE_COUNT}건 파일 수정"
echo ""
echo "_Generated at $(date '+%Y-%m-%d %H:%M:%S')_"
