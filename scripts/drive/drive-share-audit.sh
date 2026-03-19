#!/usr/bin/env bash
# drive-share-audit.sh — Drive 파일/폴더 공유 권한 감사 스크립트
# 외부 공유 감지, CSV 리포트 출력

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../utils/common.sh"
source "${SCRIPT_DIR}/../../utils/gws-helpers.sh"
check_gws_deps

# ── 설정 ──
COMPANY_DOMAIN="${1:-spigen.com}"
TARGET_FOLDER="${2:-root}"  # 감사 대상 폴더 ID (기본: root)
OUTPUT_DIR="${3:-/tmp}"
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
      echo "⚠️ 파일 목록 조회 실패"
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
    echo "  ⚠️ 권한 조회 실패: ${file_name}"
    return 0
  }

  echo "$perms" | jq -c '.permissions[]?' 2>/dev/null | while IFS= read -r perm; do
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
  done
}

# ── 메인 실행 ──
log_info "파일 목록 조회 중..."
FILES_JSON=$(fetch_files)

if [ -z "$FILES_JSON" ]; then
  echo "ℹ️ 감사 대상 파일이 없습니다."
  exit 0
fi

log_info "권한 감사 진행 중..."
while IFS= read -r file; do
  FILE_ID=$(echo "$file" | jq -r '.id')
  FILE_NAME=$(echo "$file" | jq -r '.name')
  MIME_TYPE=$(echo "$file" | jq -r '.mimeType // "unknown"')
  CREATED=$(echo "$file" | jq -r '.createdTime // "unknown"')

  ((TOTAL_FILES++)) || true
  echo "  📄 [${TOTAL_FILES}] ${FILE_NAME}"

  audit_permissions "$FILE_ID" "$FILE_NAME" "$MIME_TYPE" "$CREATED"
done <<< "$FILES_JSON"

# ── 요약 리포트 ──
TOTAL_PERMS=$(( $(wc -l < "$CSV_FILE") - 1 ))

echo ""
echo "═══════════════════════════════════"
echo "📊 감사 결과 요약"
echo "═══════════════════════════════════"
echo "  총 감사 파일:    ${TOTAL_FILES}개"
echo "  총 권한 항목:    ${TOTAL_PERMS}개"
echo "  🔴 외부 공유:    ${EXTERNAL_SHARES}건"
echo "  🟡 링크 공유:    ${LINK_SHARES}건"
echo "  🔴 전체 공개:    ${ANYONE_SHARES}건"
echo "═══════════════════════════════════"

# 외부 공유 상세 출력
if [ "$EXTERNAL_SHARES" -gt 0 ] 2>/dev/null || [ "$ANYONE_SHARES" -gt 0 ] 2>/dev/null; then
  echo ""
  echo "⚠️ 외부 공유 감지 항목:"
  awk -F',' 'NR>1 && $7=="\"Y\"" {printf "  → %s (%s, 역할: %s)\n", $2, $6, $5}' "$CSV_FILE"
fi

echo ""
echo "📁 CSV 리포트 저장됨: ${CSV_FILE}"
echo "💡 전체 결과 확인: cat ${CSV_FILE} | column -t -s,"
