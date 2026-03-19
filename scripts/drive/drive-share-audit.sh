#!/usr/bin/env bash
# drive-share-audit.sh — Drive 파일/폴더 공유 권한 감사 스크립트
# 외부 공유 감지, CSV 리포트 출력

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../utils/common.sh"
source "${SCRIPT_DIR}/../../utils/gws-helpers.sh"

# ── 사용법 ──
usage() {
  cat <<'USAGE'
사용법: drive-share-audit.sh [옵션]

Google Drive 파일/폴더의 공유 권한을 감사하여 외부 공유를 감지합니다.
CSV 형식의 리포트를 생성합니다.

옵션:
  -d, --domain DOMAIN     회사 도메인 (기본: spigen.com)
  -f, --folder FOLDER_ID  감사 대상 폴더 ID (기본: root)
  -o, --output DIR        리포트 출력 디렉토리 (기본: /tmp)
  -h, --help              사용법 출력

예시:
  # 기본 설정 (spigen.com, root 폴더)
  drive-share-audit.sh

  # 특정 도메인과 폴더 지정
  drive-share-audit.sh -d company.com -f "1ABC_FolderID"

  # 리포트 출력 경로 지정
  drive-share-audit.sh -o /home/user/reports

  # 위치 인자 호환 (기존 방식)
  drive-share-audit.sh spigen.com root /tmp
USAGE
  exit 0
}

# ── 인자 파싱 ──
COMPANY_DOMAIN="spigen.com"
TARGET_FOLDER="root"
OUTPUT_DIR="/tmp"

while [ $# -gt 0 ]; do
  case "$1" in
    -d|--domain)   COMPANY_DOMAIN="$2"; shift ;;
    -f|--folder)   TARGET_FOLDER="$2"; shift ;;
    -o|--output)   OUTPUT_DIR="$2"; shift ;;
    -h|--help)     usage ;;
    -*)            echo "알 수 없는 옵션: $1"; usage ;;
    *)
      # 위치 인자 호환
      if [ "$COMPANY_DOMAIN" = "spigen.com" ] && [[ "$1" == *.* ]]; then
        COMPANY_DOMAIN="$1"
      elif [ "$TARGET_FOLDER" = "root" ]; then
        TARGET_FOLDER="$1"
      elif [ "$OUTPUT_DIR" = "/tmp" ]; then
        OUTPUT_DIR="$1"
      fi
      ;;
  esac
  shift
done

check_gws_deps

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CSV_FILE="${OUTPUT_DIR}/drive-share-audit-${TIMESTAMP}.csv"
PAGE_SIZE=100

log_info "Drive 공유 권한 감사 시작"
log_info "   도메인: ${COMPANY_DOMAIN}"
log_info "   대상 폴더: ${TARGET_FOLDER}"
log_info "   리포트: ${CSV_FILE}"

# CSV 헤더
echo "파일ID,파일명,MIME타입,권한유형,역할,이메일/도메인,외부공유,링크공유,생성일" > "$CSV_FILE"

# 카운터
TOTAL_FILES=0
EXTERNAL_SHARES=0
LINK_SHARES=0
ANYONE_SHARES=0

# ── 파일 목록 조회 ──
fetch_files() {
  local page_token=""
  local query="'${TARGET_FOLDER}' in parents and trashed = false"

  while true; do
    local params="{\"q\":\"${query}\",\"pageSize\":${PAGE_SIZE},\"fields\":\"nextPageToken,files(id,name,mimeType,createdTime)\"}"
    if [ -n "$page_token" ]; then
      params="{\"q\":\"${query}\",\"pageSize\":${PAGE_SIZE},\"pageToken\":\"${page_token}\",\"fields\":\"nextPageToken,files(id,name,mimeType,createdTime)\"}"
    fi

    local result
    result=$(gws drive files list --params "$params" 2>/dev/null) || {
      log_error "파일 목록 조회 실패"
      return 1
    }

    echo "$result" | jq -c '.files[]?' 2>/dev/null

    page_token=$(echo "$result" | jq -r '.nextPageToken // empty' 2>/dev/null)
    [ -z "$page_token" ] && break
  done
}

# ── 권한 감사 ──
audit_permissions() {
  local file_id="$1"
  local file_name="$2"
  local mime_type="$3"
  local created_time="$4"

  local perms
  perms=$(gws drive permissions list --params "{\"fileId\":\"${file_id}\",\"fields\":\"permissions(id,type,role,emailAddress,domain,allowFileDiscovery)\"}" 2>/dev/null) || {
    log_warn "권한 조회 실패: ${file_name}"
    return 0
  }

  while IFS= read -r perm; do
    local perm_type perm_role perm_email is_external is_link

    perm_type=$(echo "$perm" | jq -r '.type // "unknown"')
    perm_role=$(echo "$perm" | jq -r '.role // "unknown"')
    perm_email=$(echo "$perm" | jq -r '.emailAddress // .domain // "N/A"')

    # 외부 공유 판별
    is_external="N"
    is_link="N"

    case "$perm_type" in
      "anyone")
        is_external="Y"
        is_link="Y"
        perm_email="anyone(공개)"
        ((ANYONE_SHARES++)) 2>/dev/null || true
        ((LINK_SHARES++)) 2>/dev/null || true
        ((EXTERNAL_SHARES++)) 2>/dev/null || true
        ;;
      "domain")
        if [ "$perm_email" != "$COMPANY_DOMAIN" ]; then
          is_external="Y"
          ((EXTERNAL_SHARES++)) 2>/dev/null || true
        fi
        ;;
      "user"|"group")
        if [[ "$perm_email" != *"@${COMPANY_DOMAIN}" ]]; then
          is_external="Y"
          ((EXTERNAL_SHARES++)) 2>/dev/null || true
        fi
        ;;
    esac

    # CSV 출력 (쉼표 포함 파일명 이스케이프)
    local safe_name="${file_name//\"/\"\"}"
    echo "\"${file_id}\",\"${safe_name}\",\"${mime_type}\",\"${perm_type}\",\"${perm_role}\",\"${perm_email}\",\"${is_external}\",\"${is_link}\",\"${created_time:0:10}\"" >> "$CSV_FILE"
  done < <(echo "$perms" | jq -c '.permissions[]?' 2>/dev/null)
}

# ── 메인 실행 ──
log_info "파일 목록 조회 중..."
FILES_JSON=$(fetch_files)

if [ -z "$FILES_JSON" ]; then
  log_info "감사 대상 파일이 없습니다."
  exit 0
fi

log_info "권한 감사 진행 중..."
while IFS= read -r file; do
  FILE_ID=$(echo "$file" | jq -r '.id')
  FILE_NAME=$(echo "$file" | jq -r '.name')
  MIME_TYPE=$(echo "$file" | jq -r '.mimeType // "unknown"')
  CREATED=$(echo "$file" | jq -r '.createdTime // "unknown"')

  ((TOTAL_FILES++)) || true
  log_info "[${TOTAL_FILES}] ${FILE_NAME}"

  audit_permissions "$FILE_ID" "$FILE_NAME" "$MIME_TYPE" "$CREATED"
done <<< "$FILES_JSON"

# ── 요약 리포트 ──
TOTAL_PERMS=$(( $(wc -l < "$CSV_FILE") - 1 ))

echo ""
echo "==================================="
echo "감사 결과 요약"
echo "==================================="
echo "  총 감사 파일:    ${TOTAL_FILES}개"
echo "  총 권한 항목:    ${TOTAL_PERMS}개"
echo "  외부 공유:       ${EXTERNAL_SHARES}건"
echo "  링크 공유:       ${LINK_SHARES}건"
echo "  전체 공개:       ${ANYONE_SHARES}건"
echo "==================================="

# 외부 공유 상세 출력
if [ "$EXTERNAL_SHARES" -gt 0 ] 2>/dev/null || [ "$ANYONE_SHARES" -gt 0 ] 2>/dev/null; then
  echo ""
  echo "외부 공유 감지 항목:"
  awk -F',' 'NR>1 && $7=="\"Y\"" {printf "  -> %s (%s, 역할: %s)\n", $2, $6, $5}' "$CSV_FILE"
fi

echo ""
echo "CSV 리포트 저장됨: ${CSV_FILE}"
echo "전체 결과 확인: cat ${CSV_FILE} | column -t -s,"
