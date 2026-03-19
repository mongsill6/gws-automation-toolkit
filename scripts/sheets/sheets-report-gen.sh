#!/usr/bin/env bash
# sheets-report-gen.sh — 템플릿 Google Sheets를 복사하여 새 리포트 자동 생성
# 날짜/제목 자동 치환, 데이터 범위 업데이트, 차트 포함 템플릿 지원

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../utils/common.sh"
source "${SCRIPT_DIR}/../../utils/gws-helpers.sh"
check_gws_deps

# ── 사용법 ──
usage() {
  cat <<'USAGE'
사용법: sheets-report-gen.sh <template-spreadsheet-id> [옵션]

템플릿 Sheets를 복사하여 새 리포트를 생성합니다.
플레이스홀더 치환, 데이터 삽입, 폴더 지정을 지원합니다.

필수:
  <template-spreadsheet-id>   복사할 템플릿 스프레드시트 ID

옵션:
  --title TITLE           새 리포트 제목 (기본: "리포트 - YYYY-MM-DD")
  --folder FOLDER_ID      생성할 Drive 폴더 ID (미지정 시 루트)
  --date DATE             기준 날짜 (YYYY-MM-DD, 기본: 오늘)
  --sheet SHEET_NAME      데이터를 업데이트할 시트 이름 (기본: "Sheet1")
  --data-range RANGE      데이터를 삽입할 범위 (예: "A2:D100")
  --data-file FILE        삽입할 데이터 CSV/JSON 파일 경로
  --data-json JSON        삽입할 데이터 JSON 문자열 (values 배열)
  --placeholders JSON     치환할 플레이스홀더 JSON (예: '{"{{TITLE}}":"월간보고","{{AUTHOR}}":"홍길동"}')
  --share EMAIL           완성된 리포트를 공유할 이메일 (쉼표 구분)
  --share-role ROLE       공유 권한 (reader|writer, 기본: reader)
  --open                  완성 후 브라우저 URL 출력
  --quiet                 최소 출력
  -h, --help              사용법 출력

예시:
  # 기본 사용 — 템플릿 복사 + 날짜 치환
  sheets-report-gen.sh "TEMPLATE_ID" --title "3월 주간보고"

  # 데이터 삽입 + 특정 폴더에 생성
  sheets-report-gen.sh "TEMPLATE_ID" --title "매출 리포트" \
    --folder "FOLDER_ID" \
    --data-range "B2:E50" --data-file sales.csv

  # 플레이스홀더 치환 + 공유
  sheets-report-gen.sh "TEMPLATE_ID" \
    --placeholders '{"{{DEPT}}":"마케팅","{{PERIOD}}":"2026-Q1"}' \
    --share "team@company.com" --share-role writer

  # JSON 데이터 직접 전달
  sheets-report-gen.sh "TEMPLATE_ID" --sheet "Data" \
    --data-range "A1:C3" \
    --data-json '[["이름","수량","금액"],["A",10,5000],["B",20,10000]]'
USAGE
  exit 1
}

# ── 인자 파싱 ──
[ $# -lt 1 ] && usage

TEMPLATE_ID="$1"
shift

TODAY=$(date +%Y-%m-%d)
TITLE=""
FOLDER_ID=""
REPORT_DATE="$TODAY"
SHEET_NAME="Sheet1"
DATA_RANGE=""
DATA_FILE=""
DATA_JSON=""
PLACEHOLDERS=""
SHARE_EMAILS=""
SHARE_ROLE="reader"
OPEN_URL=false
QUIET=false

while [ $# -gt 0 ]; do
  case "$1" in
    --title)        TITLE="$2"; shift ;;
    --folder)       FOLDER_ID="$2"; shift ;;
    --date)         REPORT_DATE="$2"; shift ;;
    --sheet)        SHEET_NAME="$2"; shift ;;
    --data-range)   DATA_RANGE="$2"; shift ;;
    --data-file)    DATA_FILE="$2"; shift ;;
    --data-json)    DATA_JSON="$2"; shift ;;
    --placeholders) PLACEHOLDERS="$2"; shift ;;
    --share)        SHARE_EMAILS="$2"; shift ;;
    --share-role)   SHARE_ROLE="$2"; shift ;;
    --open)         OPEN_URL=true ;;
    --quiet)        QUIET=true ;;
    -h|--help)      usage ;;
    *)              echo "알 수 없는 옵션: $1"; usage ;;
  esac
  shift
done

# 기본 제목
if [ -z "$TITLE" ]; then
  TITLE="리포트 - ${REPORT_DATE}"
fi

_qlog() {
  if [ "$QUIET" = false ]; then
    log_info "$@"
  fi
}

# ── 날짜 파생 변수 ──
YEAR=$(echo "$REPORT_DATE" | cut -d'-' -f1)
MONTH=$(echo "$REPORT_DATE" | cut -d'-' -f2)
DAY=$(echo "$REPORT_DATE" | cut -d'-' -f3)
# 주차 계산 (ISO week)
WEEK=$(date -d "$REPORT_DATE" +%V 2>/dev/null || echo "01")
QUARTER=$(( (10#$MONTH - 1) / 3 + 1 ))

_qlog "📊 Sheets 리포트 생성기"
_qlog "   템플릿: ${TEMPLATE_ID}"
_qlog "   제목:   ${TITLE}"
_qlog "   날짜:   ${REPORT_DATE}"
_qlog "---"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. 템플릿 복사
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
_qlog "📋 [1/5] 템플릿 복사 중..."

COPY_BODY="{\"name\":\"${TITLE}\"}"
if [ -n "$FOLDER_ID" ]; then
  COPY_BODY="{\"name\":\"${TITLE}\",\"parents\":[\"${FOLDER_ID}\"]}"
fi

COPY_RESULT=$(gws drive files copy \
  --params "{\"fileId\":\"${TEMPLATE_ID}\"}" \
  --json "$COPY_BODY") || {
  echo "❌ 템플릿 복사 실패. 스프레드시트 ID와 권한을 확인하세요."
  exit 1
}

NEW_ID=$(echo "$COPY_RESULT" | jq -r '.id')
NEW_URL="https://docs.google.com/spreadsheets/d/${NEW_ID}"

if [ -z "$NEW_ID" ] || [ "$NEW_ID" = "null" ]; then
  echo "❌ 복사된 파일 ID를 가져올 수 없습니다."
  echo "$COPY_RESULT" | jq .
  exit 1
fi

_qlog "   새 스프레드시트: ${NEW_ID}"
_qlog "   URL: ${NEW_URL}"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. 기본 플레이스홀더 치환
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
_qlog "🔄 [2/5] 플레이스홀더 치환 중..."

# 시트 목록 가져오기
SHEETS_META=$(gws sheets spreadsheets get \
  --params "{\"spreadsheetId\":\"${NEW_ID}\",\"fields\":\"sheets.properties\"}") || {
  echo "⚠️ 시트 메타데이터 조회 실패 — 치환 건너뜀"
  SHEETS_META=""
}

# 치환 대상 시트 이름 목록 추출
SHEET_NAMES=()
if [ -n "$SHEETS_META" ]; then
  while IFS= read -r name; do
    SHEET_NAMES+=("$name")
  done < <(echo "$SHEETS_META" | jq -r '.sheets[].properties.title')
fi

# 기본 플레이스홀더 맵 구성
declare -A REPLACE_MAP=(
  ["{{DATE}}"]="$REPORT_DATE"
  ["{{TODAY}}"]="$REPORT_DATE"
  ["{{YEAR}}"]="$YEAR"
  ["{{MONTH}}"]="$MONTH"
  ["{{DAY}}"]="$DAY"
  ["{{WEEK}}"]="W${WEEK}"
  ["{{QUARTER}}"]="Q${QUARTER}"
  ["{{TITLE}}"]="$TITLE"
)

# 사용자 정의 플레이스홀더 추가
if [ -n "$PLACEHOLDERS" ]; then
  while IFS='=' read -r key val; do
    key=$(echo "$key" | sed 's/^"//;s/"$//')
    val=$(echo "$val" | sed 's/^"//;s/"$//')
    REPLACE_MAP["$key"]="$val"
  done < <(echo "$PLACEHOLDERS" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
fi

# 각 시트에서 플레이스홀더 검색 & 치환
REPLACED_COUNT=0
for sname in "${SHEET_NAMES[@]}"; do
  # 시트 데이터 읽기 (전체)
  SHEET_DATA=$(gws sheets spreadsheets.values get \
    --params "{\"spreadsheetId\":\"${NEW_ID}\",\"range\":\"'${sname}'\"}" 2>/dev/null) || continue

  VALUES=$(echo "$SHEET_DATA" | jq -c '.values // []')
  ROW_COUNT=$(echo "$VALUES" | jq 'length')
  [ "$ROW_COUNT" -eq 0 ] && continue

  # 플레이스홀더가 있는지 빠르게 확인
  HAS_PLACEHOLDER=false
  for ph in "${!REPLACE_MAP[@]}"; do
    if echo "$VALUES" | grep -q "$ph"; then
      HAS_PLACEHOLDER=true
      break
    fi
  done
  [ "$HAS_PLACEHOLDER" = false ] && continue

  # 치환 수행
  UPDATED_VALUES="$VALUES"
  for ph in "${!REPLACE_MAP[@]}"; do
    replacement="${REPLACE_MAP[$ph]}"
    # jq를 사용한 안전한 치환
    UPDATED_VALUES=$(echo "$UPDATED_VALUES" | jq -c \
      --arg find "$ph" \
      --arg replace "$replacement" \
      '[.[] | [.[] | gsub($find; $replace)]]')
    if [ "$UPDATED_VALUES" != "$VALUES" ]; then
      ((REPLACED_COUNT++)) || true
    fi
  done

  # 변경된 경우에만 업데이트
  if [ "$UPDATED_VALUES" != "$VALUES" ]; then
    COL_COUNT=$(echo "$UPDATED_VALUES" | jq '.[0] | length')
    END_COL=$(printf "\\$(printf '%03o' $((64 + COL_COUNT)))")
    UPDATE_RANGE="'${sname}'!A1:${END_COL}${ROW_COUNT}"

    gws sheets spreadsheets.values update \
      --params "{\"spreadsheetId\":\"${NEW_ID}\",\"range\":\"${UPDATE_RANGE}\",\"valueInputOption\":\"USER_ENTERED\"}" \
      --json "{\"values\":${UPDATED_VALUES}}" > /dev/null 2>&1 || {
      echo "⚠️ 시트 '${sname}' 플레이스홀더 치환 실패"
    }
  fi
done

_qlog "   치환 완료 (${REPLACED_COUNT}개 플레이스홀더)"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. 데이터 삽입
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
_qlog "📥 [3/5] 데이터 삽입 중..."

DATA_ROWS=0

if [ -n "$DATA_RANGE" ] && { [ -n "$DATA_FILE" ] || [ -n "$DATA_JSON" ]; }; then
  # 데이터 준비
  if [ -n "$DATA_JSON" ]; then
    INSERT_VALUES="$DATA_JSON"
  elif [ -n "$DATA_FILE" ]; then
    if [ ! -f "$DATA_FILE" ]; then
      echo "❌ 데이터 파일을 찾을 수 없습니다: ${DATA_FILE}"
      exit 1
    fi

    EXT="${DATA_FILE##*.}"
    case "$EXT" in
      csv)
        # CSV → JSON 배열 변환
        INSERT_VALUES=$(python3 -c "
import csv, json, sys
with open('${DATA_FILE}', 'r', encoding='utf-8') as f:
    reader = csv.reader(f)
    data = [row for row in reader]
print(json.dumps(data))
") || {
          echo "❌ CSV 파싱 실패: ${DATA_FILE}"
          exit 1
        }
        ;;
      json)
        INSERT_VALUES=$(cat "$DATA_FILE")
        ;;
      *)
        echo "❌ 지원하지 않는 파일 형식: .${EXT} (csv, json만 지원)"
        exit 1
        ;;
    esac
  fi

  # 데이터 유효성 확인
  DATA_ROWS=$(echo "$INSERT_VALUES" | jq 'length' 2>/dev/null || echo 0)

  if [ "$DATA_ROWS" -gt 0 ]; then
    UPDATE_RANGE="'${SHEET_NAME}'!${DATA_RANGE}"

    gws sheets spreadsheets.values update \
      --params "{\"spreadsheetId\":\"${NEW_ID}\",\"range\":\"${UPDATE_RANGE}\",\"valueInputOption\":\"USER_ENTERED\"}" \
      --json "{\"values\":${INSERT_VALUES}}" > /dev/null 2>&1 || {
      echo "❌ 데이터 삽입 실패"
      exit 1
    }

    _qlog "   ${DATA_ROWS}행 삽입 완료 (${SHEET_NAME}!${DATA_RANGE})"
  else
    _qlog "   삽입할 데이터 없음"
  fi
else
  _qlog "   데이터 삽입 건너뜀 (--data-range와 --data-file/--data-json 미지정)"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. 스프레드시트 제목 업데이트
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
_qlog "✏️  [4/5] 스프레드시트 메타데이터 업데이트 중..."

# 스프레드시트 제목이 파일명과 다를 수 있으므로 batchUpdate로 제목 동기화
gws sheets spreadsheets batchUpdate \
  --params "{\"spreadsheetId\":\"${NEW_ID}\"}" \
  --json "{\"requests\":[{\"updateSpreadsheetProperties\":{\"properties\":{\"title\":\"${TITLE}\"},\"fields\":\"title\"}}]}" \
  > /dev/null 2>&1 || {
  _qlog "⚠️ 스프레드시트 제목 업데이트 실패 (무시)"
}

_qlog "   제목: ${TITLE}"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 5. 공유 설정
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
_qlog "🔗 [5/5] 공유 설정 중..."

if [ -n "$SHARE_EMAILS" ]; then
  IFS=',' read -ra EMAILS <<< "$SHARE_EMAILS"
  SHARED_COUNT=0

  for email in "${EMAILS[@]}"; do
    email=$(echo "$email" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$email" ] && continue

    gws drive permissions create \
      --params "{\"fileId\":\"${NEW_ID}\"}" \
      --json "{\"role\":\"${SHARE_ROLE}\",\"type\":\"user\",\"emailAddress\":\"${email}\"}" \
      > /dev/null 2>&1 && {
      ((SHARED_COUNT++)) || true
      _qlog "   ${email} (${SHARE_ROLE})"
    } || {
      echo "⚠️ 공유 실패: ${email}"
    }
  done

  _qlog "   ${SHARED_COUNT}명에게 공유 완료"
else
  _qlog "   공유 설정 건너뜀"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 결과 요약
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo ""
echo "═══════════════════════════════════════════════"
echo "✅ 리포트 생성 완료"
echo "═══════════════════════════════════════════════"
echo "  제목:     ${TITLE}"
echo "  날짜:     ${REPORT_DATE}"
echo "  시트 ID:  ${NEW_ID}"
echo "  URL:      ${NEW_URL}"
[ "$DATA_ROWS" -gt 0 ] && echo "  데이터:   ${DATA_ROWS}행 삽입"
[ -n "$SHARE_EMAILS" ] && echo "  공유:     ${SHARE_EMAILS}"
echo "═══════════════════════════════════════════════"

if [ "$OPEN_URL" = true ]; then
  echo ""
  echo "🔗 ${NEW_URL}"
fi

# 결과 JSON 출력 (파이프라인 연동용)
if [ "$QUIET" = true ]; then
  jq -n \
    --arg id "$NEW_ID" \
    --arg url "$NEW_URL" \
    --arg title "$TITLE" \
    --arg date "$REPORT_DATE" \
    --argjson rows "$DATA_ROWS" \
    '{spreadsheetId: $id, url: $url, title: $title, date: $date, dataRows: $rows}'
fi
