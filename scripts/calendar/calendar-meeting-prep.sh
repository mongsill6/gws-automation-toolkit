#!/usr/bin/env bash
# calendar-meeting-prep.sh — 다음 회의 준비 자료 자동 수집
# 기능: 참석자 정보, 관련 Drive 문서, 이전 미팅 노트, 아젠다 요약

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../utils/common.sh"
source "${SCRIPT_DIR}/../../utils/gws-helpers.sh"
check_gws_deps

# 설정
HOURS_AHEAD="${1:-24}"
NOW=$(date -u +%Y-%m-%dT%H:%M:%S+09:00)
END=$(date -u -d "$HOURS_AHEAD hours" +%Y-%m-%dT%H:%M:%S+09:00 2>/dev/null \
  || date "-v+${HOURS_AHEAD}H" -u +%Y-%m-%dT%H:%M:%S+09:00)
MAX_DRIVE_RESULTS=10
MAX_PAST_NOTES=5

log_info "회의 준비 자료 수집기"
log_info "조회 범위: 지금 ~ ${HOURS_AHEAD}시간 후"
echo ""

# ─── 1단계: 다음 예정 회의 조회 ───
log_info "다음 예정 회의를 조회 중..."

EVENTS=$(gws calendar events list --params "{
  \"calendarId\":\"primary\",
  \"timeMin\":\"$NOW\",
  \"timeMax\":\"$END\",
  \"singleEvents\":true,
  \"orderBy\":\"startTime\",
  \"maxResults\":5
}")

EVENT_COUNT=$(echo "$EVENTS" | jq '[.items[]? | select(.start.dateTime != null)] | length')

if [ "$EVENT_COUNT" -eq 0 ]; then
  log_success "${HOURS_AHEAD}시간 내 예정된 회의가 없습니다."
  exit 0
fi

# 첫 번째 회의 추출
NEXT_EVENT=$(echo "$EVENTS" | jq '[.items[] | select(.start.dateTime != null)][0]')
EVENT_SUMMARY=$(echo "$NEXT_EVENT" | jq -r '.summary // "제목 없음"')
EVENT_START=$(echo "$NEXT_EVENT" | jq -r '.start.dateTime // .start.date')
EVENT_END=$(echo "$NEXT_EVENT" | jq -r '.end.dateTime // .end.date')
EVENT_LOCATION=$(echo "$NEXT_EVENT" | jq -r '.location // "지정 안 됨"')
EVENT_DESC=$(echo "$NEXT_EVENT" | jq -r '.description // ""')
EVENT_LINK=$(echo "$NEXT_EVENT" | jq -r '.htmlLink // ""')
EVENT_HANGOUT=$(echo "$NEXT_EVENT" | jq -r '.hangoutLink // ""')
EVENT_ORGANIZER=$(echo "$NEXT_EVENT" | jq -r '.organizer.email // "알 수 없음"')

# 시간 포맷
START_FORMATTED=$(date -d "$EVENT_START" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$EVENT_START")
END_FORMATTED=$(date -d "$EVENT_END" "+%H:%M" 2>/dev/null || echo "$EVENT_END")

echo ""
echo "## 📅 다음 회의"
echo ""
echo "- **제목**: $EVENT_SUMMARY"
echo "- **시간**: $START_FORMATTED ~ $END_FORMATTED"
echo "- **장소**: $EVENT_LOCATION"
echo "- **주최자**: $EVENT_ORGANIZER"
if [ -n "$EVENT_HANGOUT" ]; then
  echo "- **화상회의**: $EVENT_HANGOUT"
fi
if [ -n "$EVENT_LINK" ]; then
  echo "- **캘린더 링크**: $EVENT_LINK"
fi
if [ -n "$EVENT_DESC" ]; then
  echo ""
  echo "### 📝 회의 설명"
  echo "$EVENT_DESC"
fi

# ─── 2단계: 참석자 정보 조회 ───
ATTENDEES=$(echo "$NEXT_EVENT" | jq -r '[.attendees[]?] | length')
echo ""
echo "---"
echo "## 👥 참석자 정보 ($ATTENDEES명)"
echo ""

if [ "$ATTENDEES" -gt 0 ]; then
  # 참석자 이메일 목록 추출
  ATTENDEE_EMAILS=$(echo "$NEXT_EVENT" | jq -r '.attendees[]?.email // empty')
  ATTENDEE_NAMES=""

  while IFS= read -r email; do
    [ -z "$email" ] && continue

    RESPONSE_STATUS=$(echo "$NEXT_EVENT" | jq -r ".attendees[] | select(.email == \"$email\") | .responseStatus // \"unknown\"")
    DISPLAY_NAME=$(echo "$NEXT_EVENT" | jq -r ".attendees[] | select(.email == \"$email\") | .displayName // \"\"")
    IS_ORGANIZER=$(echo "$NEXT_EVENT" | jq -r ".attendees[] | select(.email == \"$email\") | .organizer // false")

    # 응답 상태 아이콘
    case "$RESPONSE_STATUS" in
      accepted) STATUS_ICON="✅" ;;
      declined) STATUS_ICON="❌" ;;
      tentative) STATUS_ICON="❓" ;;
      needsAction) STATUS_ICON="⏳" ;;
      *) STATUS_ICON="❔" ;;
    esac

    # 이름 표시
    NAME_DISPLAY="$email"
    if [ -n "$DISPLAY_NAME" ]; then
      NAME_DISPLAY="$DISPLAY_NAME ($email)"
    fi

    # 주최자 태그
    ORG_TAG=""
    if [ "$IS_ORGANIZER" = "true" ]; then
      ORG_TAG=" [주최자]"
    fi

    echo "- $STATUS_ICON $NAME_DISPLAY$ORG_TAG — $RESPONSE_STATUS"

    # 연락처 추가 정보 조회 시도
    CONTACT_INFO=$(gws people people searchContacts --params "{\"query\":\"$email\",\"readMask\":\"names,emailAddresses,organizations,phoneNumbers\",\"pageSize\":1}" 2>/dev/null || echo "{}")
    CONTACT_ORG=$(echo "$CONTACT_INFO" | jq -r '.results[0]?.person.organizations[0]?.name // empty' 2>/dev/null || true)
    CONTACT_TITLE=$(echo "$CONTACT_INFO" | jq -r '.results[0]?.person.organizations[0]?.title // empty' 2>/dev/null || true)
    CONTACT_PHONE=$(echo "$CONTACT_INFO" | jq -r '.results[0]?.person.phoneNumbers[0]?.value // empty' 2>/dev/null || true)

    if [ -n "$CONTACT_ORG" ] || [ -n "$CONTACT_TITLE" ] || [ -n "$CONTACT_PHONE" ]; then
      [ -n "$CONTACT_ORG" ] && echo "  - 소속: $CONTACT_ORG"
      [ -n "$CONTACT_TITLE" ] && echo "  - 직함: $CONTACT_TITLE"
      [ -n "$CONTACT_PHONE" ] && echo "  - 전화: $CONTACT_PHONE"
    fi

    # 검색용 이름 수집 (Drive 문서 검색에 활용)
    if [ -n "$DISPLAY_NAME" ]; then
      ATTENDEE_NAMES="$ATTENDEE_NAMES $DISPLAY_NAME"
    fi
  done <<< "$ATTENDEE_EMAILS"
else
  echo "참석자 정보가 없습니다."
fi

# ─── 3단계: 관련 Drive 문서 검색 ───
echo ""
echo "---"
echo "## 📁 관련 Drive 문서"
echo ""

# 회의 제목에서 검색 키워드 추출 (특수문자 제거, 공백으로 분리)
SEARCH_KEYWORD=$(echo "$EVENT_SUMMARY" | sed 's/[^가-힣a-zA-Z0-9 ]//g' | xargs)

if [ -n "$SEARCH_KEYWORD" ]; then
  echo "🔍 키워드 \"$SEARCH_KEYWORD\"로 검색 중..."
  echo ""

  DRIVE_RESULTS=$(gws drive files list --params "{
    \"q\":\"fullText contains '$SEARCH_KEYWORD' and trashed=false\",
    \"pageSize\":$MAX_DRIVE_RESULTS,
    \"orderBy\":\"modifiedTime desc\",
    \"fields\":\"files(id,name,mimeType,modifiedTime,webViewLink,owners)\"
  }" 2>/dev/null || echo '{"files":[]}')

  DOC_COUNT=$(echo "$DRIVE_RESULTS" | jq '.files | length')

  if [ "$DOC_COUNT" -gt 0 ]; then
    echo "$DRIVE_RESULTS" | jq -r '.files[] | "- [\(.name)](\(.webViewLink // "링크 없음"))\n  수정일: \(.modifiedTime // "알 수 없음") | 유형: \(.mimeType // "알 수 없음")"'
  else
    echo "관련 문서를 찾지 못했습니다."
  fi
else
  echo "검색할 키워드가 없습니다."
fi

# ─── 4단계: 이전 미팅 노트 조회 ───
echo ""
echo "---"
echo "## 📒 이전 미팅 노트"
echo ""

# "미팅 노트", "회의록", "MOM" 등의 키워드로 관련 문서 검색
NOTES_QUERY="(name contains '회의록' or name contains '미팅' or name contains 'MOM' or name contains 'meeting notes')"
if [ -n "$SEARCH_KEYWORD" ]; then
  NOTES_QUERY="$NOTES_QUERY and fullText contains '$SEARCH_KEYWORD'"
fi
NOTES_QUERY="$NOTES_QUERY and trashed=false"

PAST_NOTES=$(gws drive files list --params "{
  \"q\":\"$NOTES_QUERY\",
  \"pageSize\":$MAX_PAST_NOTES,
  \"orderBy\":\"modifiedTime desc\",
  \"fields\":\"files(id,name,modifiedTime,webViewLink)\"
}" 2>/dev/null || echo '{"files":[]}')

NOTES_COUNT=$(echo "$PAST_NOTES" | jq '.files | length')

if [ "$NOTES_COUNT" -gt 0 ]; then
  echo "$PAST_NOTES" | jq -r '.files[] | "- [\(.name)](\(.webViewLink // "링크 없음"))\n  수정일: \(.modifiedTime // "알 수 없음")"'
else
  echo "관련 이전 미팅 노트를 찾지 못했습니다."
fi

# ─── 5단계: 아젠다 요약 ───
echo ""
echo "---"
echo "## 📌 회의 준비 체크리스트"
echo ""
echo "- [ ] 회의 자료 사전 검토"

if [ "$DOC_COUNT" -gt 0 ] 2>/dev/null; then
  echo "- [ ] 관련 Drive 문서 ${DOC_COUNT}건 확인"
fi

if [ "$NOTES_COUNT" -gt 0 ] 2>/dev/null; then
  echo "- [ ] 이전 미팅 노트 ${NOTES_COUNT}건 리뷰"
fi

if [ "$ATTENDEES" -gt 0 ]; then
  DECLINED_COUNT=$(echo "$NEXT_EVENT" | jq '[.attendees[]? | select(.responseStatus == "declined")] | length')
  PENDING_COUNT=$(echo "$NEXT_EVENT" | jq '[.attendees[]? | select(.responseStatus == "needsAction")] | length')
  if [ "$DECLINED_COUNT" -gt 0 ]; then
    echo "- [ ] ⚠️ 불참 예정 ${DECLINED_COUNT}명 확인"
  fi
  if [ "$PENDING_COUNT" -gt 0 ]; then
    echo "- [ ] ⏳ 미응답 ${PENDING_COUNT}명 리마인드"
  fi
fi

if [ -n "$EVENT_HANGOUT" ]; then
  echo "- [ ] 화상회의 링크 접속 테스트"
fi

echo "- [ ] 아젠다 최종 확인"
echo ""
echo "========================"
echo "✅ 회의 준비 자료 수집 완료!"
