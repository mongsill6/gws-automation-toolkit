#!/usr/bin/env bash
# sheets-to-bq.sh — Google Sheets 데이터를 BigQuery 테이블로 동기화
set -euo pipefail

SPREADSHEET_ID="${1:?Usage: $0 <spreadsheet-id> <sheet-name> <dataset.table>}"
SHEET_NAME="${2:?시트명을 입력하세요}"
BQ_TABLE="${3:?BQ 테이블을 입력하세요 (dataset.table)}"
PROJECT="${BQ_PROJECT:-inspiring-bonus-484905-v9}"

echo "📊 Sheets → BigQuery 동기화"
echo "  Sheets: $SPREADSHEET_ID / $SHEET_NAME"
echo "  BQ: $PROJECT:$BQ_TABLE"
echo "---"

# 1. Sheets에서 데이터 읽기
DATA=$(gws sheets spreadsheets values get --params "{\"spreadsheetId\":\"$SPREADSHEET_ID\",\"range\":\"$SHEET_NAME\"}")

# 2. 헤더 추출
HEADERS=$(echo "$DATA" | jq -r '.values[0] | @csv')
echo "컬럼: $HEADERS"

# 3. CSV로 변환
TMPFILE=$(mktemp /tmp/sheets-export-XXXX.csv)
echo "$DATA" | jq -r '.values[] | @csv' > "$TMPFILE"
ROWS=$(wc -l < "$TMPFILE")
echo "총 ${ROWS}행 (헤더 포함)"

# 4. BigQuery에 로드
echo "BQ 로드 중..."
bq load \
  --project_id="$PROJECT" \
  --source_format=CSV \
  --skip_leading_rows=1 \
  --replace \
  "$BQ_TABLE" \
  "$TMPFILE"

echo "---"
echo "✅ $BQ_TABLE에 $((ROWS - 1))행 동기화 완료"

rm -f "$TMPFILE"
