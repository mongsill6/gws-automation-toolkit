#!/usr/bin/env bash
# email-to-sheet-tracker.sh — Gmail 메일을 Google Sheets에 자동 기록하는 트래커
# 발신자/제목/날짜/스니펫 추출, 메시지 ID로 중복 방지

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../utils/common.sh"
source "${SCRIPT_DIR}/../../utils/gws-helpers.sh"
check_gws_deps

QUERY="${1:?Usage: $0 <gmail-query> <spreadsheet-id> [sheet-name] [max-results]}"
SPREADSHEET_ID="${2:?Spreadsheet ID를 입력하세요}"
SHEET_NAME="${3:-EmailTracker}"
MAX_RESULTS="${4:-20}"

log_info "Email to Sheet Tracker"
log_info "  검색: $QUERY"
log_info "  시트: $SPREADSHEET_ID / $SHEET_NAME"

# 1. 기존 시트에서 이미 기록된 메시지 ID 목록 가져오기
EXISTING_IDS=""
EXISTING_DATA=$(gws sheets spreadsheets values get \
  --params "{\"spreadsheetId\":\"$SPREADSHEET_ID\",\"range\":\"${SHEET_NAME}!A:A\"}" 2>/dev/null || echo "{}")
if echo "$EXISTING_DATA" | jq -e '.values' >/dev/null 2>&1; then
  EXISTING_IDS=$(echo "$EXISTING_DATA" | jq -r '.values[]?[0]? // empty' 2>/dev/null | sort -u)
fi

# 헤더가 없으면 생성
if [ -z "$EXISTING_IDS" ]; then
  echo "시트에 헤더 생성 중..."
  gws sheets spreadsheets values append \
    --params "{\"spreadsheetId\":\"$SPREADSHEET_ID\",\"range\":\"${SHEET_NAME}!A1\",\"valueInputOption\":\"RAW\"}" \
    --json '{"values":[["MessageID","From","Subject","Date","Snippet","Labels"]]}' >/dev/null 2>&1
  echo "  헤더 생성 완료"
fi

# 2. Gmail에서 메일 검색
MESSAGES=$(gws gmail users messages list \
  --params "{\"userId\":\"me\",\"q\":\"$QUERY\",\"maxResults\":$MAX_RESULTS}" 2>/dev/null)
MSG_IDS=$(echo "$MESSAGES" | jq -r '.messages[]?.id' 2>/dev/null)

if [ -z "$MSG_IDS" ]; then
  log_info "기록할 메일이 없습니다"
  exit 0
fi

TOTAL=0
SKIPPED=0
ADDED=0
ROWS_TO_APPEND="[]"

while read -r MSG_ID; do
  [ -z "$MSG_ID" ] && continue
  TOTAL=$((TOTAL + 1))

  # 3. 중복 체크 — 이미 기록된 메시지 ID는 스킵
  if echo "$EXISTING_IDS" | grep -qx "$MSG_ID" 2>/dev/null; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # 4. 메일 상세 정보 가져오기
  MSG=$(gws gmail users messages get \
    --params "{\"userId\":\"me\",\"id\":\"$MSG_ID\",\"format\":\"metadata\",\"metadataHeaders\":[\"From\",\"Subject\",\"Date\"]}" 2>/dev/null)

  FROM=$(echo "$MSG" | jq -r '.payload.headers[]? | select(.name=="From") | .value' 2>/dev/null | head -1)
  SUBJECT=$(echo "$MSG" | jq -r '.payload.headers[]? | select(.name=="Subject") | .value' 2>/dev/null | head -1)
  DATE=$(echo "$MSG" | jq -r '.payload.headers[]? | select(.name=="Date") | .value' 2>/dev/null | head -1)
  SNIPPET=$(echo "$MSG" | jq -r '.snippet // ""' 2>/dev/null)
  LABELS=$(echo "$MSG" | jq -r '[.labelIds[]?] | join(", ")' 2>/dev/null)

  # JSON 특수문자 이스케이프
  FROM=$(echo "$FROM" | sed 's/\\/\\\\/g; s/"/\\"/g')
  SUBJECT=$(echo "$SUBJECT" | sed 's/\\/\\\\/g; s/"/\\"/g')
  SNIPPET=$(echo "$SNIPPET" | sed 's/\\/\\\\/g; s/"/\\"/g')

  # 행 데이터 누적
  ROW="[\"$MSG_ID\",\"$FROM\",\"$SUBJECT\",\"$DATE\",\"$SNIPPET\",\"$LABELS\"]"
  ROWS_TO_APPEND=$(echo "$ROWS_TO_APPEND" | jq --argjson row "$ROW" '. + [$row]')
  ADDED=$((ADDED + 1))

  echo "  + [$FROM] $SUBJECT"
done <<< "$MSG_IDS"

# 5. 누적된 행을 한 번에 Sheets에 추가 (API 호출 최소화)
if [ "$ADDED" -gt 0 ]; then
  APPEND_BODY=$(echo "$ROWS_TO_APPEND" | jq '{values: .}')
  gws sheets spreadsheets values append \
    --params "{\"spreadsheetId\":\"$SPREADSHEET_ID\",\"range\":\"${SHEET_NAME}!A:F\",\"valueInputOption\":\"RAW\"}" \
    --json "$APPEND_BODY" >/dev/null 2>&1
fi

log_success "결과: 총 ${TOTAL}건 검색, ${ADDED}건 추가, ${SKIPPED}건 중복 스킵"
