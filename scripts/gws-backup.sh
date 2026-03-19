#!/usr/bin/env bash
# gws-backup.sh — Google Drive 폴더 파일 목록을 JSON으로 백업
# .env의 DRIVE_FOLDER_ID 폴더 내 파일 메타데이터를 backups/ 디렉토리에 날짜별 저장

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/../utils/common.sh"
source "${SCRIPT_DIR}/../utils/gws-helpers.sh"

# ── 사용법 ──
usage() {
  cat <<'USAGE'
사용법: gws-backup.sh [옵션]

Google Drive 특정 폴더의 파일 목록을 JSON으로 백업합니다.
폴더 ID는 .env의 DRIVE_FOLDER_ID에서 읽거나 -f 옵션으로 지정합니다.

옵션:
  -f, --folder FOLDER_ID  대상 Drive 폴더 ID (.env 대신 직접 지정)
  -o, --output DIR        백업 출력 디렉토리 (기본: backups/)
  -r, --recursive         하위 폴더 재귀 탐색
  -h, --help              사용법 출력

예시:
  # .env에서 DRIVE_FOLDER_ID 읽어 백업
  gws-backup.sh

  # 폴더 ID 직접 지정
  gws-backup.sh -f "1ABC_FolderID"

  # 하위 폴더 포함, 커스텀 출력 경로
  gws-backup.sh -f "1ABC_FolderID" -r -o /tmp/my-backups
USAGE
  exit 0
}

# ── .env 로드 ──
load_env() {
  local env_file="${REPO_DIR}/.env"
  if [ -f "$env_file" ]; then
    log_info ".env 파일 로드: ${env_file}"
    set -a
    # shellcheck source=/dev/null
    source "$env_file"
    set +a
  fi
}

# ── 인자 파싱 ──
FOLDER_ID=""
BACKUP_DIR="${REPO_DIR}/backups"
RECURSIVE=false

while [ $# -gt 0 ]; do
  case "$1" in
    -f|--folder)   FOLDER_ID="$2"; shift ;;
    -o|--output)   BACKUP_DIR="$2"; shift ;;
    -r|--recursive) RECURSIVE=true ;;
    -h|--help)     usage ;;
    -*)            log_error "알 수 없는 옵션: $1"; usage ;;
    *)             [ -z "$FOLDER_ID" ] && FOLDER_ID="$1" ;;
  esac
  shift
done

# .env에서 폴더 ID 로드 (인자 미지정 시)
if [ -z "$FOLDER_ID" ]; then
  load_env
  FOLDER_ID="${DRIVE_FOLDER_ID:-}"
fi

if [ -z "$FOLDER_ID" ]; then
  log_error "DRIVE_FOLDER_ID가 필요합니다. .env에 설정하거나 -f 옵션을 사용하세요."
  exit 1
fi

check_gws_deps

# ── 설정 ──
DATE_STR=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/${DATE_STR}/file-list-${TIMESTAMP}.json"
PAGE_SIZE=100

mkdir -p "${BACKUP_DIR}/${DATE_STR}"

# ── 파일 목록 수집 (페이지네이션 지원) ──
collect_files() {
  local folder_id="$1"
  local page_token=""
  local query="'${folder_id}' in parents and trashed = false"
  local fields="files(id,name,mimeType,size,modifiedTime,createdTime,md5Checksum,owners)"
  local all_files
  all_files=$(make_temp "gws-backup")

  echo -n "[]" > "$all_files"

  while true; do
    local params
    if [ -n "$page_token" ]; then
      params="{\"q\":\"${query}\",\"pageSize\":${PAGE_SIZE},\"pageToken\":\"${page_token}\",\"fields\":\"nextPageToken,${fields}\",\"orderBy\":\"name\"}"
    else
      params="{\"q\":\"${query}\",\"pageSize\":${PAGE_SIZE},\"fields\":\"nextPageToken,${fields}\",\"orderBy\":\"name\"}"
    fi

    local result
    result=$(gws drive files list --params "$params" 2>/dev/null) || {
      log_error "파일 목록 조회 실패: folder=${folder_id}"
      return 1
    }

    # 기존 배열에 새 파일 병합
    local new_files
    new_files=$(echo "$result" | jq -c '.files // []')
    local merged
    merged=$(jq -s '.[0] + .[1]' "$all_files" <(echo "$new_files"))
    echo "$merged" > "$all_files"

    page_token=$(echo "$result" | jq -r '.nextPageToken // empty' 2>/dev/null)
    [ -z "$page_token" ] && break
  done

  cat "$all_files"
}

# ── 재귀 수집 ──
collect_files_recursive() {
  local folder_id="$1"
  local files
  files=$(collect_files "$folder_id") || return 1

  local folder_count
  folder_count=$(echo "$files" | jq '[.[] | select(.mimeType == "application/vnd.google-apps.folder")] | length')

  if [ "$RECURSIVE" = true ] && [ "$folder_count" -gt 0 ]; then
    local subfolder_ids
    subfolder_ids=$(echo "$files" | jq -r '.[] | select(.mimeType == "application/vnd.google-apps.folder") | .id')

    local sub_results
    sub_results=$(make_temp "gws-backup-sub")
    echo -n "[]" > "$sub_results"

    while IFS= read -r sub_id; do
      [ -z "$sub_id" ] && continue
      local sub_name
      sub_name=$(echo "$files" | jq -r ".[] | select(.id == \"${sub_id}\") | .name")
      log_info "하위 폴더 탐색: ${sub_name}"

      local sub_files
      sub_files=$(collect_files_recursive "$sub_id") || continue
      local merged
      merged=$(jq -s '.[0] + .[1]' "$sub_results" <(echo "$sub_files"))
      echo "$merged" > "$sub_results"
    done <<< "$subfolder_ids"

    # 메인 파일 + 하위 파일 병합
    jq -s '.[0] + .[1]' <(echo "$files") "$sub_results"
  else
    echo "$files"
  fi
}

# ── 메인 실행 ──
log_info "Google Drive 파일 목록 백업 시작"
log_info "  폴더 ID: ${FOLDER_ID}"
log_info "  재귀 탐색: ${RECURSIVE}"
log_info "  출력 경로: ${BACKUP_FILE}"

# 폴더 정보 조회
FOLDER_META=$(gws drive files get --params "{\"fileId\":\"${FOLDER_ID}\",\"fields\":\"id,name,mimeType\"}" 2>/dev/null) || {
  log_error "폴더 정보 조회 실패: ${FOLDER_ID}"
  exit 1
}
FOLDER_NAME=$(echo "$FOLDER_META" | jq -r '.name // "Unknown"')
log_info "  폴더명: ${FOLDER_NAME}"

# 파일 목록 수집
log_info "파일 목록 수집 중..."
FILES_JSON=$(collect_files_recursive "$FOLDER_ID") || {
  log_error "파일 목록 수집 실패"
  exit 1
}

FILE_COUNT=$(echo "$FILES_JSON" | jq 'length')
log_info "수집 완료: ${FILE_COUNT}개 파일"

# 백업 JSON 생성
BACKUP_JSON=$(jq -n \
  --arg folder_id "$FOLDER_ID" \
  --arg folder_name "$FOLDER_NAME" \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson file_count "$FILE_COUNT" \
  --argjson recursive "$RECURSIVE" \
  --argjson files "$FILES_JSON" \
  '{
    metadata: {
      folder_id: $folder_id,
      folder_name: $folder_name,
      backup_timestamp: $timestamp,
      file_count: $file_count,
      recursive: $recursive
    },
    files: $files
  }')

echo "$BACKUP_JSON" > "$BACKUP_FILE"

# 결과 출력
log_success "백업 완료"
log_info "  파일 수: ${FILE_COUNT}개"
log_info "  백업 파일: ${BACKUP_FILE}"
BACKUP_SIZE=$(du -h "$BACKUP_FILE" | awk '{print $1}')
log_info "  파일 크기: ${BACKUP_SIZE}"
