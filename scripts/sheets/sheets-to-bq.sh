#!/usr/bin/env bash
# sheets-to-bq.sh — Google Sheets 데이터를 BigQuery 테이블로 동기화

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../utils/common.sh"
source "${SCRIPT_DIR}/../../utils/gws-helpers.sh"
check_deps gws jq bq

SPREADSHEET_ID="${1:?Usage: $0 <spreadsheet-id> <sheet-name> <dataset.table>}"
SHEET_NAME="${2:?시트명을 입력하세요}"
BQ_TABLE="${3:?BQ 테이블을 입력하세요 (dataset.table)}"
PROJECT="${BQ_PROJECT:-inspiring-bonus-484905-v9}"

log_info "Sheets → BigQuery 동기화"
log_info "  Sheets: $SPREADSHEET_ID / $SHEET_NAME"
log_info "  BQ: $PROJECT:$BQ_TABLE"

# 1. Sheets에서 데이터 읽기
DATA=$(gws sheets spreadsheets values get --params "{\"spreadsheetId\":\"$SPREADSHEET_ID\",\"range\":\"$SHEET_NAME\"}")

# 2. 헤더 추출
HEADERS=$(echo "$DATA" | jq -r '.values[0] | @csv')
log_info "컬럼: $HEADERS"

# 3. CSV로 변환
TMPFILE=$(make_temp "sheets-export")
echo "$DATA" | jq -r '.values[] | @csv' > "$TMPFILE"
ROWS=$(wc -l < "$TMPFILE")
log_info "총 ${ROWS}행 (헤더 포함)"

# 4. BigQuery에 로드
log_info "BQ 로드 중..."
bq load \
  --project_id="$PROJECT" \
  --source_format=CSV \
  --skip_leading_rows=1 \
  --replace \
  "$BQ_TABLE" \
  "$TMPFILE"

log_success "$BQ_TABLE에 $((ROWS - 1))행 동기화 완료"
