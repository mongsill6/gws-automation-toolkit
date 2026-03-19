#!/usr/bin/env bash
# gmail-to-tasks.sh — 특정 라벨/조건의 메일을 Google Tasks로 변환
set -euo pipefail

QUERY="${1:-label:action-required is:unread}"
MAX_RESULTS="${2:-5}"

echo "📧→✅ Gmail to Tasks 변환"
echo "검색 조건: $QUERY"
echo "---"

# 기본 태스크 리스트 ID 가져오기
LIST_ID=$(gws tasks tasklists list --params '{"maxResults":1}' | jq -r '.items[0].id')
if [ -z "$LIST_ID" ] || [ "$LIST_ID" = "null" ]; then
  echo "ERROR: 태스크 리스트를 찾을 수 없습니다"
  exit 1
fi

# 메일 검색
MESSAGES=$(gws gmail users messages list --params "{\"userId\":\"me\",\"q\":\"$QUERY\",\"maxResults\":$MAX_RESULTS}")
MSG_IDS=$(echo "$MESSAGES" | jq -r '.messages[]?.id' 2>/dev/null)

if [ -z "$MSG_IDS" ]; then
  echo "변환할 메일이 없습니다"
  exit 0
fi

COUNT=0
echo "$MSG_IDS" | while read -r MSG_ID; do
  # 메일 상세 가져오기
  MSG=$(gws gmail users messages get --params "{\"userId\":\"me\",\"id\":\"$MSG_ID\",\"format\":\"metadata\",\"metadataHeaders\":[\"From\",\"Subject\",\"Date\"]}")
  SUBJECT=$(echo "$MSG" | jq -r '.payload.headers[] | select(.name=="Subject") | .value')
  FROM=$(echo "$MSG" | jq -r '.payload.headers[] | select(.name=="From") | .value')

  # 태스크 생성
  TASK_TITLE="[메일] $SUBJECT"
  TASK_NOTES="From: $FROM\nGmail ID: $MSG_ID"

  gws tasks tasks insert --params "{\"tasklist\":\"$LIST_ID\"}" \
    --json "{\"title\":\"$TASK_TITLE\",\"notes\":\"$TASK_NOTES\"}" >/dev/null 2>&1

  echo "  ✅ $TASK_TITLE"
  COUNT=$((COUNT + 1))
done

echo "---"
echo "총 ${COUNT}개 태스크 생성 완료"
