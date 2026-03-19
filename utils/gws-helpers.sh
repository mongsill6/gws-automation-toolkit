#!/usr/bin/env bash
# gws-helpers.sh — gws CLI 공통 래퍼 함수
# source this file: source "$(dirname "${BASH_SOURCE[0]}")/gws-helpers.sh"
# 의존성: common.sh (먼저 source 필요)

# ── Drive ──

# 파일 메타데이터 조회
# 사용법: gws_get_file_meta <fileId> [fields]
gws_get_file_meta() {
  local file_id="${1:?파일 ID 필수}"
  local fields="${2:-id,name,mimeType,size,modifiedTime,owners,permissions}"
  gws drive files get --params "{\"fileId\":\"${file_id}\",\"fields\":\"${fields}\"}"
}

# Drive 파일 검색
# 사용법: gws_list_files <query> [pageSize] [fields] [orderBy]
gws_list_files() {
  local query="${1:?검색 쿼리 필수}"
  local page_size="${2:-50}"
  local fields="${3:-files(id,name,mimeType,size,modifiedTime)}"
  local order_by="${4:-modifiedTime desc}"
  gws drive files list --params "{\"q\":\"${query}\",\"pageSize\":${page_size},\"fields\":\"nextPageToken,${fields}\",\"orderBy\":\"${order_by}\"}"
}

# Drive 파일 다운로드 (바이너리)
# 사용법: gws_download_file <fileId> > output.bin
gws_download_file() {
  local file_id="${1:?파일 ID 필수}"
  gws drive files get --params "{\"fileId\":\"${file_id}\",\"alt\":\"media\"}"
}

# Drive 파일 내보내기 (Google Docs 계열)
# 사용법: gws_export_file <fileId> <mimeType> > output.pdf
gws_export_file() {
  local file_id="${1:?파일 ID 필수}"
  local mime_type="${2:?MIME 타입 필수}"
  gws drive files export --params "{\"fileId\":\"${file_id}\",\"mimeType\":\"${mime_type}\"}"
}

# Drive 권한 목록 조회
# 사용법: gws_list_permissions <fileId>
gws_list_permissions() {
  local file_id="${1:?파일 ID 필수}"
  gws drive permissions list --params "{\"fileId\":\"${file_id}\",\"fields\":\"permissions(id,type,role,emailAddress,domain,allowFileDiscovery)\"}"
}

# ── Gmail ──

# 메일 검색
# 사용법: gws_search_mail <query> [maxResults]
gws_search_mail() {
  local query="${1:?검색 쿼리 필수}"
  local max_results="${2:-20}"
  gws gmail users messages list --params "{\"userId\":\"me\",\"q\":\"${query}\",\"maxResults\":${max_results}}"
}

# 메일 상세 조회 (메타데이터)
# 사용법: gws_get_mail_meta <messageId> [headers]
gws_get_mail_meta() {
  local msg_id="${1:?메시지 ID 필수}"
  local headers="${2:-From,Subject,Date}"
  local header_json
  header_json=$(echo "$headers" | jq -R 'split(",")' 2>/dev/null || echo "[\"From\",\"Subject\",\"Date\"]")
  gws gmail users messages get --params "{\"userId\":\"me\",\"id\":\"${msg_id}\",\"format\":\"metadata\",\"metadataHeaders\":${header_json}}"
}

# 메일 헤더 값 추출
# 사용법: gws_extract_header <message_json> <header_name>
gws_extract_header() {
  local json="$1"
  local name="$2"
  echo "$json" | jq -r ".payload.headers[] | select(.name==\"${name}\") | .value" | head -1
}

# 라벨 목록 조회
# 사용법: gws_list_labels
gws_list_labels() {
  gws gmail users labels list --params '{"userId":"me"}'
}

# 메일 라벨 수정
# 사용법: gws_modify_mail_labels <messageId> <addLabelIds_json> <removeLabelIds_json>
gws_modify_mail_labels() {
  local msg_id="${1:?메시지 ID 필수}"
  local add_labels="${2:-[]}"
  local remove_labels="${3:-[]}"
  gws gmail users messages modify --params "{\"userId\":\"me\",\"id\":\"${msg_id}\"}" \
    --json "{\"addLabelIds\":${add_labels},\"removeLabelIds\":${remove_labels}}"
}

# ── Calendar ──

# 일정 조회
# 사용법: gws_get_events <timeMin> <timeMax> [calendarId] [maxResults]
gws_get_events() {
  local time_min="${1:?시작 시간 필수 (RFC3339)}"
  local time_max="${2:?종료 시간 필수 (RFC3339)}"
  local calendar_id="${3:-primary}"
  local max_results="${4:-250}"
  gws calendar events list --params "{\"calendarId\":\"${calendar_id}\",\"timeMin\":\"${time_min}\",\"timeMax\":\"${time_max}\",\"singleEvents\":true,\"orderBy\":\"startTime\",\"maxResults\":${max_results}}"
}

# 오늘 일정 조회
# 사용법: gws_get_today_events [calendarId]
gws_get_today_events() {
  local calendar_id="${1:-primary}"
  local today
  today=$(date +%Y-%m-%d)
  gws_get_events "${today}T00:00:00+09:00" "${today}T23:59:59+09:00" "$calendar_id"
}

# ── Sheets ──

# 시트 값 읽기
# 사용법: gws_get_sheet_values <spreadsheetId> <range>
gws_get_sheet_values() {
  local spreadsheet_id="${1:?스프레드시트 ID 필수}"
  local range="${2:?범위 필수}"
  gws sheets spreadsheets.values get --params "{\"spreadsheetId\":\"${spreadsheet_id}\",\"range\":\"${range}\"}"
}

# 시트 값 업데이트
# 사용법: gws_update_sheet_values <spreadsheetId> <range> <values_json>
gws_update_sheet_values() {
  local spreadsheet_id="${1:?스프레드시트 ID 필수}"
  local range="${2:?범위 필수}"
  local values_json="${3:?값 JSON 필수}"
  gws sheets spreadsheets.values update \
    --params "{\"spreadsheetId\":\"${spreadsheet_id}\",\"range\":\"${range}\",\"valueInputOption\":\"USER_ENTERED\"}" \
    --json "{\"values\":${values_json}}"
}

# 시트 값 추가 (append)
# 사용법: gws_append_sheet_values <spreadsheetId> <range> <values_json>
gws_append_sheet_values() {
  local spreadsheet_id="${1:?스프레드시트 ID 필수}"
  local range="${2:?범위 필수}"
  local values_json="${3:?값 JSON 필수}"
  gws sheets spreadsheets.values append \
    --params "{\"spreadsheetId\":\"${spreadsheet_id}\",\"range\":\"${range}\",\"valueInputOption\":\"RAW\"}" \
    --json "{\"values\":${values_json}}"
}

# 스프레드시트 메타데이터 조회
# 사용법: gws_get_spreadsheet_meta <spreadsheetId> [fields]
gws_get_spreadsheet_meta() {
  local spreadsheet_id="${1:?스프레드시트 ID 필수}"
  local fields="${2:-sheets.properties}"
  gws sheets spreadsheets get --params "{\"spreadsheetId\":\"${spreadsheet_id}\",\"fields\":\"${fields}\"}"
}

# ── Tasks ──

# 태스크 리스트 조회
# 사용법: gws_list_tasklists [maxResults]
gws_list_tasklists() {
  local max_results="${1:-10}"
  gws tasks tasklists list --params "{\"maxResults\":${max_results}}"
}

# 태스크 생성
# 사용법: gws_create_task <tasklistId> <title> [notes]
gws_create_task() {
  local tasklist_id="${1:?태스크 리스트 ID 필수}"
  local title="${2:?제목 필수}"
  local notes="${3:-}"
  local json="{\"title\":\"${title}\"}"
  if [ -n "$notes" ]; then
    json="{\"title\":\"${title}\",\"notes\":\"${notes}\"}"
  fi
  gws tasks tasks insert --params "{\"tasklist\":\"${tasklist_id}\"}" --json "$json"
}

# ── People/Contacts ──

# 연락처 검색
# 사용법: gws_search_contacts <query> [pageSize]
gws_search_contacts() {
  local query="${1:?검색어 필수}"
  local page_size="${2:-5}"
  gws people people searchContacts --params "{\"query\":\"${query}\",\"readMask\":\"names,emailAddresses,organizations,phoneNumbers\",\"pageSize\":${page_size}}"
}
