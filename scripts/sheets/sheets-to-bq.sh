#!/usr/bin/env bash
# sheets-to-bq.sh — Google Sheets 데이터를 BigQuery 테이블로 동기화

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../utils/common.sh"
source "${SCRIPT_DIR}/../../utils/gws-helpers.sh"

# ── 사용법 ──
usage() {
  cat <<'USAGE'
사용법: sheets-to-bq.sh -s <spreadsheet-id> -n <sheet-name> -t <dataset.table> [옵션]

Google Sheets 데이터를 CSV로 변환하여 BigQuery 테이블에 동기화합니다.

필수:
  -s, --spreadsheet ID    Google Sheets 스프레드시트 ID
  -n, --sheet-name NAME   시트 이름
  -t, --table TABLE       BigQuery 테이블 (dataset.table 형식)

옵션:
  -p, --project PROJECT   GCP 프로젝트 ID (기본: inspiring-bonus-484905-v9)
  -h, --help              사용법 출력

예시:
  # 기본 프로젝트로 동기화
  sheets-to-bq.sh -s "1BxiMVs0XRA..." -n "Sheet1" -t "dataset.my_table"

  # 프로젝트 지정
  sheets-to-bq.sh -s "1BxiMVs0XRA..." -n "매출" -t "sales.monthly" -p "my-project-id"

  # 위치 인자 호환 (기존 방식)
  sheets-to-bq.sh "1BxiMVs0XRA..." "Sheet1" "dataset.table"
USAGE
  exit 0
}

# ── 인자 파싱 ──
SPREADSHEET_ID=""
SHEET_NAME=""
BQ_TABLE=""
PROJECT="${BQ_PROJECT:-inspiring-bonus-484905-v9}"

[ $# -eq 0 ] && usage

while [ $# -gt 0 ]; do
  case "$1" in
    -s|--spreadsheet) SPREADSHEET_ID="$2"; shift ;;
    -n|--sheet-name)  SHEET_NAME="$2"; shift ;;
    -t|--table)       BQ_TABLE="$2"; shift ;;
    -p|--project)     PROJECT="$2"; shift ;;
    -h|--help)        usage ;;
    -*)               echo "알 수 없는 옵션: $1"; usage ;;
    *)
      # 위치 인자 호환
      if [ -z "$SPREADSHEET_ID" ]; then
        SPREADSHEET_ID="$1"
      elif [ -z "$SHEET_NAME" ]; then
        SHEET_NAME="$1"
      elif [ -z "$BQ_TABLE" ]; then
        BQ_TABLE="$1"
      fi
      ;;
  esac
  shift
done

if [ -z "$SPREADSHEET_ID" ]; then
  log_error "스프레드시트 ID가 필요합니다. -s <spreadsheet-id>"
  exit 1
fi
if [ -z "$SHEET_NAME" ]; then
  log_error "시트 이름이 필요합니다. -n <sheet-name>"
  exit 1
fi
if [ -z "$BQ_TABLE" ]; then
  log_error "BQ 테이블이 필요합니다. -t <dataset.table>"
  exit 1
fi

check_deps gws jq bq

log_info "Sheets -> BigQuery 동기화"
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
