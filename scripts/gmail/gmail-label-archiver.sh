#!/usr/bin/env bash
# gmail-label-archiver.sh — 지정 라벨의 오래된 메일 자동 아카이브
set -euo pipefail

LABEL="${1:?Usage: $0 <label-name> [days-old]}"
DAYS_OLD="${2:-30}"

BEFORE_DATE=$(date -d "$DAYS_OLD days ago" +%Y/%m/%d 2>/dev/null || date -v-${DAYS_OLD}d +%Y/%m/%d)

echo "📦 Gmail 아카이브: label:$LABEL, ${DAYS_OLD}일 이전"
echo "---"

# 라벨 ID 찾기
LABELS=$(gws gmail users labels list --params '{"userId":"me"}')
LABEL_ID=$(echo "$LABELS" | jq -r ".labels[] | select(.name==\"$LABEL\") | .id")

if [ -z "$LABEL_ID" ] || [ "$LABEL_ID" = "null" ]; then
  echo "ERROR: 라벨 '$LABEL' 을 찾을 수 없습니다"
  exit 1
fi

# 오래된 메일 검색
QUERY="label:$LABEL before:$BEFORE_DATE"
MESSAGES=$(gws gmail users messages list --params "{\"userId\":\"me\",\"q\":\"$QUERY\",\"maxResults\":100}")
MSG_IDS=$(echo "$MESSAGES" | jq -r '.messages[]?.id' 2>/dev/null)

if [ -z "$MSG_IDS" ]; then
  echo "아카이브할 메일이 없습니다"
  exit 0
fi

COUNT=0
echo "$MSG_IDS" | while read -r MSG_ID; do
  # INBOX 라벨 제거 (아카이브 = INBOX에서 제거)
  gws gmail users messages modify --params "{\"userId\":\"me\",\"id\":\"$MSG_ID\"}" \
    --json '{"removeLabelIds":["INBOX"]}' >/dev/null 2>&1
  COUNT=$((COUNT + 1))
  echo "  📦 Archived: $MSG_ID"
done

echo "---"
echo "총 ${COUNT}개 메일 아카이브 완료"
