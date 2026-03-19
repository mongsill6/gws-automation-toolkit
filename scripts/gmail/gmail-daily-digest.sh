#!/usr/bin/env bash
# gmail-daily-digest.sh — 미읽은 메일 일일 요약 (발신자/라벨별 그룹핑, 마크다운 출력)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../utils/common.sh"
source "${SCRIPT_DIR}/../../utils/gws-helpers.sh"
check_gws_deps

MAX_RESULTS="${1:-50}"
OUTPUT_FILE="${2:-}"

# --- 헬퍼 함수 ---

header_extract() {
  local json="$1" name="$2"
  echo "$json" | jq -r ".payload.headers[] | select(.name==\"$name\") | .value" | head -1
}

parse_sender_name() {
  local from="$1"
  # "Name <email>" → Name, 없으면 이메일 그대로
  if [[ "$from" =~ ^\"?([^\"<]+)\"?[[:space:]]*\< ]]; then
    local _match="${BASH_REMATCH[1]}"
    echo "${_match%"${_match##*[![:space:]]}"}"
  else
    echo "$from"
  fi
}

parse_sender_email() {
  local from="$1"
  if [[ "$from" =~ \<([^>]+)\> ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "$from"
  fi
}

# --- 라벨 맵 구성 ---

LABELS_JSON=$(gws gmail users labels list --params '{"userId":"me"}')

declare -A LABEL_MAP
while IFS='|' read -r lid lname; do
  [ -n "$lid" ] && LABEL_MAP["$lid"]="$lname"
done < <(echo "$LABELS_JSON" | jq -r '.labels[] | "\(.id)|\(.name)"')

# --- 통계용 카운터 ---

# 오늘 수신 메일 수
TODAY=$(date +%Y/%m/%d)
TODAY_MSGS=$(gws gmail users messages list --params "{\"userId\":\"me\",\"q\":\"after:$TODAY\",\"maxResults\":1}")
TODAY_ESTIMATE=$(echo "$TODAY_MSGS" | jq -r '.resultSizeEstimate // 0')

# 미읽은 메일
UNREAD_MSGS=$(gws gmail users messages list --params "{\"userId\":\"me\",\"q\":\"is:unread\",\"maxResults\":1}")
UNREAD_ESTIMATE=$(echo "$UNREAD_MSGS" | jq -r '.resultSizeEstimate // 0')

# 스타 메일
STAR_MSGS=$(gws gmail users messages list --params "{\"userId\":\"me\",\"q\":\"is:starred is:unread\",\"maxResults\":1}")
STAR_ESTIMATE=$(echo "$STAR_MSGS" | jq -r '.resultSizeEstimate // 0')

# --- 미읽은 메일 상세 조회 ---

MESSAGES=$(gws gmail users messages list --params "{\"userId\":\"me\",\"q\":\"is:unread\",\"maxResults\":$MAX_RESULTS}")
MSG_IDS=$(echo "$MESSAGES" | jq -r '.messages[]?.id' 2>/dev/null)

# 발신자별, 라벨별 그룹핑용 임시 파일
TMP_DIR=$(make_temp_dir "gmail-digest")

SENDER_DIR="$TMP_DIR/senders"
LABEL_DIR="$TMP_DIR/labels"
IMPORTANT_FILE="$TMP_DIR/important.md"
mkdir -p "$SENDER_DIR" "$LABEL_DIR"
touch "$IMPORTANT_FILE"

MSG_COUNT=0

if [ -n "$MSG_IDS" ]; then
  while read -r MSG_ID; do
    [ -z "$MSG_ID" ] && continue

    MSG=$(gws gmail users messages get --params "{\"userId\":\"me\",\"id\":\"$MSG_ID\",\"format\":\"metadata\",\"metadataHeaders\":[\"From\",\"Subject\",\"Date\"]}")

    FROM=$(header_extract "$MSG" "From")
    SUBJECT=$(header_extract "$MSG" "Subject")
    DATE=$(header_extract "$MSG" "Date")
    SNIPPET=$(echo "$MSG" | jq -r '.snippet // ""' | head -c 120)

    SENDER_NAME=$(parse_sender_name "$FROM")
    SENDER_EMAIL=$(parse_sender_email "$FROM")
    MSG_LABELS=$(echo "$MSG" | jq -r '.labelIds[]?' 2>/dev/null)

    IS_IMPORTANT=false

    # 중요 메일 판별: IMPORTANT 라벨 또는 STARRED
    while read -r LBL; do
      [ -z "$LBL" ] && continue
      if [ "$LBL" = "IMPORTANT" ] || [ "$LBL" = "STARRED" ]; then
        IS_IMPORTANT=true
      fi
    done <<< "$MSG_LABELS"

    # 발신자별 그룹핑
    SAFE_SENDER=$(echo "$SENDER_EMAIL" | tr '/@.' '___')
    SENDER_FILE="$SENDER_DIR/$SAFE_SENDER"
    if [ ! -f "$SENDER_FILE" ]; then
      {
        echo "SENDER_NAME=$SENDER_NAME"
        echo "SENDER_EMAIL=$SENDER_EMAIL"
        echo "COUNT=0"
        echo "---MAILS---"
      } > "$SENDER_FILE"
    fi
    # 카운트 증가
    CUR_COUNT=$(grep '^COUNT=' "$SENDER_FILE" | cut -d= -f2)
    sed -i "s/^COUNT=.*/COUNT=$((CUR_COUNT + 1))/" "$SENDER_FILE"
    STAR_MARK=""
    $IS_IMPORTANT && STAR_MARK=" **[!]**"
    echo "- ${SUBJECT}${STAR_MARK}" >> "$SENDER_FILE"

    # 라벨별 그룹핑 (시스템 라벨 UNREAD, INBOX, CATEGORY_* 제외)
    while read -r LBL; do
      [ -z "$LBL" ] && continue
      [[ "$LBL" == "UNREAD" ]] && continue
      [[ "$LBL" == "INBOX" ]] && continue
      [[ "$LBL" == CATEGORY_* ]] && continue

      LABEL_NAME="${LABEL_MAP[$LBL]:-$LBL}"
      SAFE_LABEL=$(echo "$LBL" | tr '/@. ' '____')
      LABEL_FILE="$LABEL_DIR/$SAFE_LABEL"
      if [ ! -f "$LABEL_FILE" ]; then
        echo "LABEL_NAME=$LABEL_NAME" > "$LABEL_FILE"
        echo "COUNT=0" >> "$LABEL_FILE"
        echo "---MAILS---" >> "$LABEL_FILE"
      fi
      L_COUNT=$(grep '^COUNT=' "$LABEL_FILE" | cut -d= -f2)
      sed -i "s/^COUNT=.*/COUNT=$((L_COUNT + 1))/" "$LABEL_FILE"
      echo "- [$SENDER_NAME] $SUBJECT" >> "$LABEL_FILE"
    done <<< "$MSG_LABELS"

    # 중요 메일 목록
    if $IS_IMPORTANT; then
      echo "- **$SUBJECT** — _${SENDER_NAME}_ (${DATE})" >> "$IMPORTANT_FILE"
      [ -n "$SNIPPET" ] && echo "  > ${SNIPPET}..." >> "$IMPORTANT_FILE"
    fi

    MSG_COUNT=$((MSG_COUNT + 1))
  done <<< "$MSG_IDS"
fi

# --- 마크다운 출력 생성 ---

NOW=$(date '+%Y-%m-%d %H:%M')
OUTPUT=""

OUTPUT+="# Gmail 일일 다이제스트"$'\n'
OUTPUT+="_${NOW} 기준_"$'\n\n'

# 통계
OUTPUT+="## 통계"$'\n\n'
OUTPUT+="- 오늘 수신: **${TODAY_ESTIMATE}**건"$'\n'
OUTPUT+="- 미읽은 메일: **${UNREAD_ESTIMATE}**건"$'\n'
OUTPUT+="- 스타 미읽은: **${STAR_ESTIMATE}**건"$'\n'
OUTPUT+="- 조회 처리: **${MSG_COUNT}**건"$'\n\n'

# 중요 메일 하이라이트
IMPORTANT_CONTENT=$(cat "$IMPORTANT_FILE")
if [ -n "$IMPORTANT_CONTENT" ]; then
  OUTPUT+="## 중요 메일 하이라이트"$'\n\n'
  OUTPUT+="$IMPORTANT_CONTENT"$'\n\n'
fi

# 발신자별 그룹
OUTPUT+="## 발신자별 그룹"$'\n\n'
if [ -d "$SENDER_DIR" ] && [ "$(ls -A "$SENDER_DIR" 2>/dev/null)" ]; then
  for SFILE in "$SENDER_DIR"/*; do
    S_NAME=$(grep '^SENDER_NAME=' "$SFILE" | cut -d= -f2-)
    S_EMAIL=$(grep '^SENDER_EMAIL=' "$SFILE" | cut -d= -f2-)
    S_COUNT=$(grep '^COUNT=' "$SFILE" | cut -d= -f2)
    OUTPUT+="### ${S_NAME} (${S_COUNT}건)"$'\n'
    OUTPUT+="_${S_EMAIL}_"$'\n'
    OUTPUT+="$(sed -n '/^---MAILS---$/,$p' "$SFILE" | tail -n +2)"$'\n\n'
  done
else
  OUTPUT+="_미읽은 메일이 없습니다._"$'\n\n'
fi

# 라벨별 그룹
OUTPUT+="## 라벨별 그룹"$'\n\n'
if [ -d "$LABEL_DIR" ] && [ "$(ls -A "$LABEL_DIR" 2>/dev/null)" ]; then
  for LFILE in "$LABEL_DIR"/*; do
    L_NAME=$(grep '^LABEL_NAME=' "$LFILE" | cut -d= -f2-)
    L_COUNT=$(grep '^COUNT=' "$LFILE" | cut -d= -f2)
    OUTPUT+="### ${L_NAME} (${L_COUNT}건)"$'\n'
    OUTPUT+="$(sed -n '/^---MAILS---$/,$p' "$LFILE" | tail -n +2)"$'\n\n'
  done
else
  OUTPUT+="_라벨 분류된 미읽은 메일이 없습니다._"$'\n\n'
fi

OUTPUT+="---"$'\n'
OUTPUT+="_Generated by gmail-daily-digest.sh_"$'\n'

# 출력
if [ -n "$OUTPUT_FILE" ]; then
  echo "$OUTPUT" > "$OUTPUT_FILE"
  echo "다이제스트 저장: $OUTPUT_FILE"
else
  echo "$OUTPUT"
fi
