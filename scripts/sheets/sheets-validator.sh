#!/usr/bin/env bash
# sheets-validator.sh — Google Sheets 데이터 유효성 검사 스크립트
# 빈 셀, 중복값, 형식 오류를 감지하고 요약 리포트 출력

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../utils/common.sh"
source "${SCRIPT_DIR}/../../utils/gws-helpers.sh"
check_gws_deps

# ── 사용법 ──
usage() {
  cat <<'USAGE'
사용법: sheets-validator.sh <spreadsheet-id> <range> [옵션]

옵션:
  --check-empty         빈 셀 검사 (기본: 활성)
  --check-duplicates    중복값 검사 (기본: 활성)
  --check-format        형식 오류 검사 (기본: 활성)
  --email-cols COL,...   이메일 형식 검증할 컬럼 (0-based, 쉼표 구분)
  --date-cols COL,...    날짜 형식 검증할 컬럼 (0-based, 쉼표 구분)
  --number-cols COL,...  숫자 형식 검증할 컬럼 (0-based, 쉼표 구분)
  --unique-cols COL,...  중복 검사 대상 컬럼 (0-based, 쉼표 구분. 미지정 시 전체)
  --required-cols COL,...  필수값 컬럼 (0-based, 쉼표 구분. 미지정 시 전체)
  --output FILE         결과 저장 파일 경로 (기본: /tmp/sheets-validation-*.txt)
  --csv                 CSV 형식으로 이슈 리포트 출력
  --quiet               요약만 출력

예시:
  # 기본 전체 검사
  sheets-validator.sh "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms" "Sheet1!A1:Z"

  # 이메일(2번 컬럼), 날짜(3번 컬럼) 형식 검증
  sheets-validator.sh "SHEET_ID" "Sheet1" --email-cols 2 --date-cols 3

  # 특정 컬럼만 중복 검사
  sheets-validator.sh "SHEET_ID" "Sheet1" --unique-cols 0,1
USAGE
  exit 1
}

# ── 인자 파싱 ──
[ $# -lt 2 ] && usage

SPREADSHEET_ID="$1"
RANGE="$2"
shift 2

CHECK_EMPTY=true
CHECK_DUPLICATES=true
CHECK_FORMAT=true
EMAIL_COLS=""
DATE_COLS=""
NUMBER_COLS=""
UNIQUE_COLS=""
REQUIRED_COLS=""
OUTPUT_FILE=""
CSV_MODE=false
QUIET=false

while [ $# -gt 0 ]; do
  case "$1" in
    --check-empty)      CHECK_EMPTY=true ;;
    --check-duplicates) CHECK_DUPLICATES=true ;;
    --check-format)     CHECK_FORMAT=true ;;
    --email-cols)       EMAIL_COLS="$2"; shift ;;
    --date-cols)        DATE_COLS="$2"; shift ;;
    --number-cols)      NUMBER_COLS="$2"; shift ;;
    --unique-cols)      UNIQUE_COLS="$2"; shift ;;
    --required-cols)    REQUIRED_COLS="$2"; shift ;;
    --output)           OUTPUT_FILE="$2"; shift ;;
    --csv)              CSV_MODE=true ;;
    --quiet)            QUIET=true ;;
    -h|--help)          usage ;;
    *)                  echo "알 수 없는 옵션: $1"; usage ;;
  esac
  shift
done

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
if [ -z "$OUTPUT_FILE" ]; then
  OUTPUT_FILE="/tmp/sheets-validation-${TIMESTAMP}.txt"
fi

# ── 유틸 함수 ──
_qlog() {
  if [ "$QUIET" = false ]; then
    log_info "$@"
  fi
}

# 이슈 카운터
ISSUE_EMPTY=0
ISSUE_DUPLICATE=0
ISSUE_FORMAT=0
ISSUE_TOTAL=0

# 이슈 저장 배열
declare -a ISSUES=()

add_issue() {
  local severity="$1"  # ERROR, WARN, INFO
  local category="$2"  # EMPTY, DUPLICATE, FORMAT
  local row="$3"
  local col="$4"
  local col_name="$5"
  local detail="$6"

  ISSUES+=("${severity}|${category}|${row}|${col}|${col_name}|${detail}")
  ((ISSUE_TOTAL++)) || true

  case "$category" in
    EMPTY)     ((ISSUE_EMPTY++)) || true ;;
    DUPLICATE) ((ISSUE_DUPLICATE++)) || true ;;
    FORMAT)    ((ISSUE_FORMAT++)) || true ;;
  esac
}

# 컬럼 번호 → 알파벳 변환
col_to_letter() {
  local n=$1
  local result=""
  while [ "$n" -ge 0 ]; do
    result=$(printf '%b' "$(printf '\\%03o' $((65 + n % 26)))")${result}
    n=$(( n / 26 - 1 ))
  done
  echo "$result"
}

# CSV 문자열에서 컬럼 인덱스 목록 파싱
parse_col_list() {
  echo "$1" | tr ',' '\n'
}

# ── 데이터 조회 ──
log_info "Sheets 데이터 유효성 검사"
log_info "스프레드시트: ${SPREADSHEET_ID}"
log_info "범위: ${RANGE}"

log_info "데이터 로드 중..."
DATA=$(gws sheets spreadsheets.values get --params "{\"spreadsheetId\":\"$SPREADSHEET_ID\",\"range\":\"$RANGE\"}") || {
  log_error "데이터 조회 실패. 스프레드시트 ID와 범위를 확인하세요."
  exit 1
}

# 값이 있는지 확인
ROW_COUNT=$(echo "$DATA" | jq '.values | length')
if [ "$ROW_COUNT" -eq 0 ] || [ "$ROW_COUNT" = "null" ]; then
  log_info "데이터가 비어 있습니다."
  exit 0
fi

# 헤더와 데이터 분리
HEADERS=$(echo "$DATA" | jq -r '.values[0]')
COL_COUNT=$(echo "$HEADERS" | jq 'length')
DATA_ROW_COUNT=$((ROW_COUNT - 1))

log_info "컬럼 수: ${COL_COUNT}"
log_info "데이터 행: ${DATA_ROW_COUNT}행 (헤더 제외)"

# 헤더명 캐시
declare -a HEADER_NAMES=()
for (( c=0; c<COL_COUNT; c++ )); do
  name=$(echo "$HEADERS" | jq -r ".[$c] // \"Column_$c\"")
  HEADER_NAMES+=("$name")
done

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. 빈 셀 검사
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if [ "$CHECK_EMPTY" = true ]; then
  _qlog "🔎 [1/3] 빈 셀 검사 중..."

  # 필수 컬럼 결정
  if [ -n "$REQUIRED_COLS" ]; then
    REQ_LIST=$(parse_col_list "$REQUIRED_COLS")
  else
    REQ_LIST=$(seq 0 $((COL_COUNT - 1)))
  fi

  for (( r=1; r<ROW_COUNT; r++ )); do
    row_data=$(echo "$DATA" | jq -c ".values[$r]")
    row_len=$(echo "$row_data" | jq 'length')

    for col_idx in $REQ_LIST; do
      col_idx=$((col_idx))  # 정수 변환
      [ "$col_idx" -ge "$COL_COUNT" ] && continue

      if [ "$col_idx" -ge "$row_len" ]; then
        value=""
      else
        value=$(echo "$row_data" | jq -r ".[$col_idx] // \"\"")
      fi

      # 빈 문자열 또는 공백만 있는 경우
      trimmed=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      if [ -z "$trimmed" ]; then
        col_letter=$(col_to_letter "$col_idx")
        add_issue "ERROR" "EMPTY" "$((r + 1))" "$col_letter" "${HEADER_NAMES[$col_idx]}" "빈 셀"
      fi
    done
  done

  _qlog "   빈 셀: ${ISSUE_EMPTY}건 발견"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. 중복값 검사
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if [ "$CHECK_DUPLICATES" = true ]; then
  _qlog "🔎 [2/3] 중복값 검사 중..."

  if [ -n "$UNIQUE_COLS" ]; then
    DUP_LIST=$(parse_col_list "$UNIQUE_COLS")
  else
    DUP_LIST=$(seq 0 $((COL_COUNT - 1)))
  fi

  for col_idx in $DUP_LIST; do
    col_idx=$((col_idx))
    [ "$col_idx" -ge "$COL_COUNT" ] && continue

    # 해당 컬럼의 모든 값 추출 (헤더 제외)
    declare -A seen_values=()
    declare -A seen_rows=()

    for (( r=1; r<ROW_COUNT; r++ )); do
      value=$(echo "$DATA" | jq -r ".values[$r][$col_idx] // \"\"")
      trimmed=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [ -z "$trimmed" ] && continue

      # 대소문자 무시 비교용 키
      key=$(echo "$trimmed" | tr '[:upper:]' '[:lower:]')

      if [ -n "${seen_values[$key]+x}" ]; then
        col_letter=$(col_to_letter "$col_idx")
        first_row="${seen_rows[$key]}"
        add_issue "WARN" "DUPLICATE" "$((r + 1))" "$col_letter" "${HEADER_NAMES[$col_idx]}" "중복값 \"${trimmed}\" (첫 등장: ${first_row}행)"
      else
        seen_values[$key]=1
        seen_rows[$key]=$((r + 1))
      fi
    done

    unset seen_values
    unset seen_rows
  done

  _qlog "   중복값: ${ISSUE_DUPLICATE}건 발견"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. 형식 오류 검사
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if [ "$CHECK_FORMAT" = true ]; then
  _qlog "🔎 [3/3] 형식 오류 검사 중..."

  # 이메일 형식 검증
  if [ -n "$EMAIL_COLS" ]; then
    for col_idx in $(parse_col_list "$EMAIL_COLS"); do
      col_idx=$((col_idx))
      [ "$col_idx" -ge "$COL_COUNT" ] && continue

      for (( r=1; r<ROW_COUNT; r++ )); do
        value=$(echo "$DATA" | jq -r ".values[$r][$col_idx] // \"\"")
        trimmed=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$trimmed" ] && continue

        # 기본 이메일 패턴 검증
        if ! echo "$trimmed" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
          col_letter=$(col_to_letter "$col_idx")
          add_issue "ERROR" "FORMAT" "$((r + 1))" "$col_letter" "${HEADER_NAMES[$col_idx]}" "잘못된 이메일 형식: \"${trimmed}\""
        fi
      done
    done
  fi

  # 날짜 형식 검증
  if [ -n "$DATE_COLS" ]; then
    for col_idx in $(parse_col_list "$DATE_COLS"); do
      col_idx=$((col_idx))
      [ "$col_idx" -ge "$COL_COUNT" ] && continue

      for (( r=1; r<ROW_COUNT; r++ )); do
        value=$(echo "$DATA" | jq -r ".values[$r][$col_idx] // \"\"")
        trimmed=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$trimmed" ] && continue

        # YYYY-MM-DD, YYYY/MM/DD, MM/DD/YYYY, DD-MM-YYYY 패턴
        if ! echo "$trimmed" | grep -qE '^([0-9]{4}[-/][0-9]{1,2}[-/][0-9]{1,2}|[0-9]{1,2}[-/][0-9]{1,2}[-/][0-9]{4})$'; then
          col_letter=$(col_to_letter "$col_idx")
          add_issue "ERROR" "FORMAT" "$((r + 1))" "$col_letter" "${HEADER_NAMES[$col_idx]}" "잘못된 날짜 형식: \"${trimmed}\""
        fi
      done
    done
  fi

  # 숫자 형식 검증
  if [ -n "$NUMBER_COLS" ]; then
    for col_idx in $(parse_col_list "$NUMBER_COLS"); do
      col_idx=$((col_idx))
      [ "$col_idx" -ge "$COL_COUNT" ] && continue

      for (( r=1; r<ROW_COUNT; r++ )); do
        value=$(echo "$DATA" | jq -r ".values[$r][$col_idx] // \"\"")
        trimmed=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$trimmed" ] && continue

        # 정수, 소수, 음수, 천단위 쉼표 허용
        cleaned=$(echo "$trimmed" | tr -d ',')
        if ! echo "$cleaned" | grep -qE '^-?[0-9]+\.?[0-9]*$'; then
          col_letter=$(col_to_letter "$col_idx")
          add_issue "ERROR" "FORMAT" "$((r + 1))" "$col_letter" "${HEADER_NAMES[$col_idx]}" "숫자 아님: \"${trimmed}\""
        fi
      done
    done
  fi

  # 형식 컬럼 미지정 시 자동 감지 (숫자/날짜 혼재 검사)
  if [ -z "$EMAIL_COLS" ] && [ -z "$DATE_COLS" ] && [ -z "$NUMBER_COLS" ]; then
    for (( c=0; c<COL_COUNT; c++ )); do
      # 컬럼 내 값 샘플링으로 타입 추론
      num_count=0
      date_count=0
      text_count=0
      total_count=0

      for (( r=1; r<ROW_COUNT && r<=20; r++ )); do
        value=$(echo "$DATA" | jq -r ".values[$r][$c] // \"\"")
        trimmed=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$trimmed" ] && continue
        ((total_count++)) || true

        cleaned=$(echo "$trimmed" | tr -d ',')
        if echo "$cleaned" | grep -qE '^-?[0-9]+\.?[0-9]*$'; then
          ((num_count++)) || true
        elif echo "$trimmed" | grep -qE '^([0-9]{4}[-/][0-9]{1,2}[-/][0-9]{1,2}|[0-9]{1,2}[-/][0-9]{1,2}[-/][0-9]{4})$'; then
          ((date_count++)) || true
        else
          ((text_count++)) || true
        fi
      done

      [ "$total_count" -eq 0 ] && continue

      # 80% 이상이 특정 타입이면, 나머지를 형식 오류로 판별
      if [ "$num_count" -gt 0 ] && [ $((num_count * 100 / total_count)) -ge 80 ]; then
        for (( r=1; r<ROW_COUNT; r++ )); do
          value=$(echo "$DATA" | jq -r ".values[$r][$c] // \"\"")
          trimmed=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
          [ -z "$trimmed" ] && continue
          cleaned=$(echo "$trimmed" | tr -d ',')
          if ! echo "$cleaned" | grep -qE '^-?[0-9]+\.?[0-9]*$'; then
            col_letter=$(col_to_letter "$c")
            add_issue "WARN" "FORMAT" "$((r + 1))" "$col_letter" "${HEADER_NAMES[$c]}" "숫자 컬럼에 비숫자값: \"${trimmed}\""
          fi
        done
      fi

      if [ "$date_count" -gt 0 ] && [ $((date_count * 100 / total_count)) -ge 80 ]; then
        for (( r=1; r<ROW_COUNT; r++ )); do
          value=$(echo "$DATA" | jq -r ".values[$r][$c] // \"\"")
          trimmed=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
          [ -z "$trimmed" ] && continue
          if ! echo "$trimmed" | grep -qE '^([0-9]{4}[-/][0-9]{1,2}[-/][0-9]{1,2}|[0-9]{1,2}[-/][0-9]{1,2}[-/][0-9]{4})$'; then
            col_letter=$(col_to_letter "$c")
            add_issue "WARN" "FORMAT" "$((r + 1))" "$col_letter" "${HEADER_NAMES[$c]}" "날짜 컬럼에 비날짜값: \"${trimmed}\""
          fi
        done
      fi
    done
  fi

  _qlog "   형식 오류: ${ISSUE_FORMAT}건 발견"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 결과 리포트 생성
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{
  echo "═══════════════════════════════════════════════"
  echo "📊 Sheets 데이터 유효성 검사 리포트"
  echo "═══════════════════════════════════════════════"
  echo "스프레드시트: ${SPREADSHEET_ID}"
  echo "범위: ${RANGE}"
  echo "검사 시각: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "컬럼 수: ${COL_COUNT}"
  echo "데이터 행: ${DATA_ROW_COUNT}"
  echo ""
  echo "── 검사 결과 요약 ──"
  echo ""

  if [ "$ISSUE_TOTAL" -eq 0 ]; then
    echo "  ✅ 모든 검사 통과 — 이슈 없음"
  else
    [ "$CHECK_EMPTY" = true ]      && echo "  🔴 빈 셀:     ${ISSUE_EMPTY}건"
    [ "$CHECK_DUPLICATES" = true ] && echo "  🟡 중복값:    ${ISSUE_DUPLICATE}건"
    [ "$CHECK_FORMAT" = true ]     && echo "  🔴 형식 오류: ${ISSUE_FORMAT}건"
    echo "  ──────────────────────"
    echo "  총 이슈:      ${ISSUE_TOTAL}건"
  fi

  echo ""
  echo "── 상세 이슈 목록 ──"
  echo ""

  if [ "$ISSUE_TOTAL" -eq 0 ]; then
    echo "  (없음)"
  else
    if [ "$CSV_MODE" = true ]; then
      echo "심각도,유형,행,열,컬럼명,상세"
      for issue in "${ISSUES[@]}"; do
        echo "$issue" | tr '|' ','
      done
    else
      printf "  %-6s %-10s %-5s %-4s %-20s %s\n" "심각도" "유형" "행" "열" "컬럼명" "상세"
      printf "  %-6s %-10s %-5s %-4s %-20s %s\n" "------" "----------" "-----" "----" "--------------------" "----"

      for issue in "${ISSUES[@]}"; do
        IFS='|' read -r sev cat row col cname detail <<< "$issue"
        printf "  %-6s %-10s %-5s %-4s %-20s %s\n" "$sev" "$cat" "$row" "$col" "$cname" "$detail"
      done
    fi
  fi

  echo ""
  echo "═══════════════════════════════════════════════"
} | tee "$OUTPUT_FILE"

echo ""
echo "📁 리포트 저장됨: ${OUTPUT_FILE}"

# 종료 코드: 이슈가 있으면 1, 없으면 0
if [ "$ISSUE_TOTAL" -gt 0 ]; then
  exit 1
fi
exit 0
