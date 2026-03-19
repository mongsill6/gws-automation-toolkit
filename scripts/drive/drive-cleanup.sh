#!/usr/bin/env bash
# drive-cleanup.sh — Drive에서 오래된 파일 목록 조회 및 정리

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../utils/common.sh"
source "${SCRIPT_DIR}/../../utils/gws-helpers.sh"
check_gws_deps

DAYS_OLD="${1:-90}"
DRY_RUN="${2:-true}"  # true=목록만, false=실제 삭제

BEFORE_DATE=$(date -d "$DAYS_OLD days ago" +%Y-%m-%dT00:00:00 2>/dev/null || date -v-${DAYS_OLD}d +%Y-%m-%dT00:00:00)

log_info "Drive 파일 정리: ${DAYS_OLD}일 이전 (dry_run=$DRY_RUN)"

# 오래된 파일 검색 (내가 소유한 것만)
FILES=$(gws drive files list --params "{\"q\":\"modifiedTime < '$BEFORE_DATE' and 'me' in owners and trashed = false\",\"pageSize\":50,\"fields\":\"files(id,name,modifiedTime,size,mimeType)\"}")

echo "$FILES" | jq -r '.files[]? | "\(.name)\t\(.modifiedTime[:10])\t\(.size // "?")\t\(.id)"' | while IFS=$'\t' read -r NAME DATE SIZE ID; do
  SIZE_MB=$(echo "scale=1; ${SIZE:-0}/1048576" | bc 2>/dev/null || echo "?")
  log_info "$NAME ($DATE, ${SIZE_MB}MB)"

  if [ "$DRY_RUN" = "false" ]; then
    gws drive files update --params "{\"fileId\":\"$ID\"}" --json '{"trashed":true}' >/dev/null 2>&1
    log_info "→ 휴지통으로 이동"
  fi
done

echo "---"
if [ "$DRY_RUN" = "true" ]; then
  log_info "dry run 모드입니다. 실제 삭제: $0 $DAYS_OLD false"
fi
