#!/usr/bin/env bash
# drive-backup.sh — Drive 폴더 증분 백업 스크립트
# 지정 폴더를 로컬 또는 다른 Drive 폴더로 백업, 변경분만 처리
set -euo pipefail

# ── 설정 ──
SOURCE_FOLDER="${1:?사용법: $0 <소스폴더ID> [백업모드] [대상경로/폴더ID]}"
BACKUP_MODE="${2:-local}"        # local | drive
BACKUP_TARGET="${3:-/tmp/drive-backup}"
STATE_DIR="${HOME}/.drive-backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${STATE_DIR}/logs"
STATE_FILE="${STATE_DIR}/${SOURCE_FOLDER}.state"
LOG_FILE="${LOG_DIR}/backup-${TIMESTAMP}.log"
PAGE_SIZE=100

# 상태/로그 디렉토리 생성
mkdir -p "$STATE_DIR" "$LOG_DIR"

# ── 로깅 ──
log() {
  local level="$1"; shift
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*"
  echo "$msg" | tee -a "$LOG_FILE"
}

log "INFO" "Drive 증분 백업 시작"
log "INFO" "  소스 폴더: ${SOURCE_FOLDER}"
log "INFO" "  백업 모드: ${BACKUP_MODE}"
log "INFO" "  백업 대상: ${BACKUP_TARGET}"

# ── 마지막 백업 시점 조회 ──
LAST_BACKUP=""
if [ -f "$STATE_FILE" ]; then
  LAST_BACKUP=$(cat "$STATE_FILE")
  log "INFO" "  마지막 백업: ${LAST_BACKUP}"
else
  log "INFO" "  최초 백업 (전체 백업 수행)"
fi

# ── 카운터 ──
TOTAL_FILES=0
BACKED_UP=0
SKIPPED=0
FAILED=0

# ── 파일 목록 조회 (증분: modifiedTime 기반) ──
fetch_files() {
  local page_token=""
  local query="'${SOURCE_FOLDER}' in parents and trashed = false"

  # 증분 백업: 마지막 백업 이후 수정된 파일만
  if [ -n "$LAST_BACKUP" ]; then
    query="${query} and modifiedTime > '${LAST_BACKUP}'"
    log "INFO" "증분 모드: ${LAST_BACKUP} 이후 변경 파일만 조회"
  fi

  while true; do
    local params
    if [ -n "$page_token" ]; then
      params="{\"q\":\"${query}\",\"pageSize\":${PAGE_SIZE},\"pageToken\":\"${page_token}\",\"fields\":\"nextPageToken,files(id,name,mimeType,size,modifiedTime,md5Checksum)\"}"
    else
      params="{\"q\":\"${query}\",\"pageSize\":${PAGE_SIZE},\"fields\":\"nextPageToken,files(id,name,mimeType,size,modifiedTime,md5Checksum)\"}"
    fi

    local result
    result=$(gws drive files list --params "$params" 2>/dev/null) || {
      log "ERROR" "파일 목록 조회 실패"
      return 1
    }

    echo "$result" | jq -c '.files[]?' 2>/dev/null

    page_token=$(echo "$result" | jq -r '.nextPageToken // empty' 2>/dev/null)
    [ -z "$page_token" ] && break
  done
}

# ── Google Docs MIME → export 포맷 매핑 ──
get_export_mime() {
  local mime="$1"
  case "$mime" in
    "application/vnd.google-apps.document")     echo "application/pdf" ;;
    "application/vnd.google-apps.spreadsheet")  echo "text/csv" ;;
    "application/vnd.google-apps.presentation") echo "application/pdf" ;;
    "application/vnd.google-apps.drawing")      echo "image/png" ;;
    "application/vnd.google-apps.form")         echo "application/pdf" ;;
    *) echo "" ;;
  esac
}

get_export_ext() {
  local mime="$1"
  case "$mime" in
    "application/vnd.google-apps.document")     echo ".pdf" ;;
    "application/vnd.google-apps.spreadsheet")  echo ".csv" ;;
    "application/vnd.google-apps.presentation") echo ".pdf" ;;
    "application/vnd.google-apps.drawing")      echo ".png" ;;
    "application/vnd.google-apps.form")         echo ".pdf" ;;
    *) echo "" ;;
  esac
}

# ── 로컬 백업: 파일 다운로드 ──
backup_to_local() {
  local file_id="$1"
  local file_name="$2"
  local mime_type="$3"
  local file_size="$4"
  local md5="$5"

  local dest_dir="${BACKUP_TARGET}/${TIMESTAMP}"
  mkdir -p "$dest_dir"

  local dest_path="${dest_dir}/${file_name}"

  # Google Docs 계열은 export
  local export_mime
  export_mime=$(get_export_mime "$mime_type")

  if [ -n "$export_mime" ]; then
    local ext
    ext=$(get_export_ext "$mime_type")
    dest_path="${dest_dir}/${file_name}${ext}"

    gws drive files export --params "{\"fileId\":\"${file_id}\",\"mimeType\":\"${export_mime}\"}" > "$dest_path" 2>/dev/null || {
      log "ERROR" "내보내기 실패: ${file_name}"
      ((FAILED++)) || true
      return 0
    }
  elif [[ "$mime_type" == application/vnd.google-apps.* ]]; then
    # 기타 Google 앱 (폴더, 사이트 등)은 스킵
    log "SKIP" "지원하지 않는 Google 앱 타입: ${file_name} (${mime_type})"
    ((SKIPPED++)) || true
    return 0
  else
    # 일반 파일 다운로드
    gws drive files get --params "{\"fileId\":\"${file_id}\",\"alt\":\"media\"}" > "$dest_path" 2>/dev/null || {
      log "ERROR" "다운로드 실패: ${file_name}"
      ((FAILED++)) || true
      return 0
    }
  fi

  # MD5 검증 (일반 파일만, export 파일은 해시가 다름)
  if [ -n "$md5" ] && [ -z "$export_mime" ] && command -v md5sum &>/dev/null; then
    local local_md5
    local_md5=$(md5sum "$dest_path" | awk '{print $1}')
    if [ "$local_md5" != "$md5" ]; then
      log "WARN" "MD5 불일치: ${file_name} (원본: ${md5}, 로컬: ${local_md5})"
    fi
  fi

  local size_display="${file_size:-0}"
  if [ "${file_size:-0}" -gt 1048576 ] 2>/dev/null; then
    size_display="$((file_size / 1048576))MB"
  elif [ "${file_size:-0}" -gt 1024 ] 2>/dev/null; then
    size_display="$((file_size / 1024))KB"
  else
    size_display="${file_size:-0}B"
  fi

  log "OK" "백업 완료: ${file_name} (${size_display})"
  ((BACKED_UP++)) || true
}

# ── Drive 백업: 파일 복사 ──
backup_to_drive() {
  local file_id="$1"
  local file_name="$2"
  local mime_type="$3"

  # Google Docs 계열이 아닌 경우 또는 Google Docs 계열 모두 복사 가능
  local copy_params="{\"fileId\":\"${file_id}\",\"resource\":{\"name\":\"[백업 ${TIMESTAMP}] ${file_name}\",\"parents\":[\"${BACKUP_TARGET}\"]}}"

  gws drive files copy --params "$copy_params" >/dev/null 2>&1 || {
    log "ERROR" "Drive 복사 실패: ${file_name}"
    ((FAILED++)) || true
    return 0
  }

  log "OK" "Drive 복사 완료: ${file_name} → ${BACKUP_TARGET}"
  ((BACKED_UP++)) || true
}

# ── 하위 폴더 재귀 탐색 ──
backup_folder_recursive() {
  local folder_id="$1"
  local depth="${2:-0}"
  local indent=""
  for ((i=0; i<depth; i++)); do indent+="  "; done

  # 현재 폴더의 파일 백업
  local files_json
  files_json=$(SOURCE_FOLDER="$folder_id" fetch_files)

  if [ -z "$files_json" ]; then
    return 0
  fi

  while IFS= read -r file; do
    local fid fname fmime fsize fmd5 fmod
    fid=$(echo "$file" | jq -r '.id')
    fname=$(echo "$file" | jq -r '.name')
    fmime=$(echo "$file" | jq -r '.mimeType // "unknown"')
    fsize=$(echo "$file" | jq -r '.size // "0"')
    fmd5=$(echo "$file" | jq -r '.md5Checksum // empty')
    fmod=$(echo "$file" | jq -r '.modifiedTime // "unknown"')

    ((TOTAL_FILES++)) || true
    echo "${indent}  📄 [${TOTAL_FILES}] ${fname} (${fmod})"

    # 하위 폴더면 재귀
    if [ "$fmime" = "application/vnd.google-apps.folder" ]; then
      log "INFO" "${indent}📁 하위 폴더 진입: ${fname}"
      backup_folder_recursive "$fid" "$((depth + 1))"
      continue
    fi

    # 백업 실행
    if [ "$BACKUP_MODE" = "local" ]; then
      backup_to_local "$fid" "$fname" "$fmime" "$fsize" "$fmd5"
    else
      backup_to_drive "$fid" "$fname" "$fmime"
    fi
  done <<< "$files_json"
}

# ── 메인 실행 ──
echo "═══════════════════════════════════"
echo "📦 Drive 증분 백업"
echo "═══════════════════════════════════"

# 소스 폴더 정보 확인
FOLDER_INFO=$(gws drive files get --params "{\"fileId\":\"${SOURCE_FOLDER}\",\"fields\":\"id,name,mimeType\"}" 2>/dev/null) || {
  log "ERROR" "소스 폴더 정보 조회 실패: ${SOURCE_FOLDER}"
  exit 1
}

FOLDER_NAME=$(echo "$FOLDER_INFO" | jq -r '.name // "Unknown"')
log "INFO" "소스 폴더명: ${FOLDER_NAME}"

# 로컬 모드일 때 대상 디렉토리 확인
if [ "$BACKUP_MODE" = "local" ]; then
  mkdir -p "${BACKUP_TARGET}/${TIMESTAMP}"
  log "INFO" "로컬 백업 경로: ${BACKUP_TARGET}/${TIMESTAMP}"
fi

echo ""
echo "📂 파일 스캔 및 백업 중..."
backup_folder_recursive "$SOURCE_FOLDER"

# ── 백업 상태 저장 (증분 기준점) ──
date -u +%Y-%m-%dT%H:%M:%SZ > "$STATE_FILE"
log "INFO" "백업 상태 저장: $(cat "$STATE_FILE")"

# ── 요약 리포트 ──
echo ""
echo "═══════════════════════════════════"
echo "📊 백업 결과 요약"
echo "═══════════════════════════════════"
echo "  소스 폴더:       ${FOLDER_NAME}"
echo "  백업 모드:       ${BACKUP_MODE}"
echo "  총 파일 수:      ${TOTAL_FILES}개"
echo "  ✅ 백업 성공:    ${BACKED_UP}건"
echo "  ⏭️  스킵:         ${SKIPPED}건"
echo "  ❌ 실패:         ${FAILED}건"
if [ -n "$LAST_BACKUP" ]; then
  echo "  📅 증분 기준:    ${LAST_BACKUP} 이후"
else
  echo "  📅 백업 유형:    전체 백업 (최초)"
fi
echo "═══════════════════════════════════"
echo ""
echo "📋 백업 로그: ${LOG_FILE}"

if [ "$BACKUP_MODE" = "local" ]; then
  BACKUP_SIZE=$(du -sh "${BACKUP_TARGET}/${TIMESTAMP}" 2>/dev/null | awk '{print $1}')
  echo "💾 백업 크기: ${BACKUP_SIZE:-0}"
  echo "📁 백업 경로: ${BACKUP_TARGET}/${TIMESTAMP}"
fi

# 실패 건이 있으면 exit 1
if [ "$FAILED" -gt 0 ]; then
  log "WARN" "일부 파일 백업 실패 (${FAILED}건). 로그를 확인하세요."
  exit 1
fi

log "INFO" "백업 완료"
