#!/usr/bin/env bash
# gmail-label-archiver.sh — 지정 라벨의 오래된 메일 자동 아카이브

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../utils/common.sh"
source "${SCRIPT_DIR}/../../utils/gws-helpers.sh"

# ── 사용법 ──
usage() {
  cat <<'USAGE'
사용법: gmail-label-archiver.sh -l <label-name> [옵션]

지정 라벨의 오래된 메일을 자동으로 아카이브(INBOX에서 제거)합니다.

필수:
  -l, --label LABEL       아카이브 대상 Gmail 라벨 이름

옵션:
  -d, --days DAYS         기준 일수 (기본: 30일 이전 메일 대상)
  -h, --help              사용법 출력

예시:
  # "newsletters" 라벨의 30일 이전 메일 아카이브
  gmail-label-archiver.sh -l newsletters

  # "promotions" 라벨의 7일 이전 메일 아카이브
  gmail-label-archiver.sh -l promotions -d 7

  # 위치 인자 호환 (기존 방식)
  gmail-label-archiver.sh newsletters 7
USAGE
  exit 0
}

# ── 인자 파싱 ──
LABEL=""
DAYS_OLD=30

[ $# -eq 0 ] && usage

while [ $# -gt 0 ]; do
  case "$1" in
    -l|--label)     LABEL="$2"; shift ;;
    -d|--days)      DAYS_OLD="$2"; shift ;;
    -h|--help)      usage ;;
    -*)             echo "알 수 없는 옵션: $1"; usage ;;
    *)
      # 위치 인자 호환: 첫 번째는 label, 두 번째는 days
      if [ -z "$LABEL" ]; then
        LABEL="$1"
      elif [ "$DAYS_OLD" -eq 30 ] 2>/dev/null; then
        DAYS_OLD="$1"
      fi
      ;;
  esac
  shift
done

if [ -z "$LABEL" ]; then
  log_error "라벨 이름이 필요합니다. -l <label-name>"
  exit 1
fi

check_gws_deps

BEFORE_DATE=$(date -d "$DAYS_OLD days ago" +%Y/%m/%d 2>/dev/null || date "-v-${DAYS_OLD}d" +%Y/%m/%d)

log_info "Gmail 아카이브: label:$LABEL, ${DAYS_OLD}일 이전"

# 라벨 ID 찾기
LABELS=$(gws gmail users labels list --params '{"userId":"me"}')
LABEL_ID=$(echo "$LABELS" | jq -r ".labels[] | select(.name==\"$LABEL\") | .id")

if [ -z "$LABEL_ID" ] || [ "$LABEL_ID" = "null" ]; then
  log_error "라벨 '$LABEL' 을 찾을 수 없습니다"
  exit 1
fi

# 오래된 메일 검색
QUERY="label:$LABEL before:$BEFORE_DATE"
MESSAGES=$(gws gmail users messages list --params "{\"userId\":\"me\",\"q\":\"$QUERY\",\"maxResults\":100}")
MSG_IDS=$(echo "$MESSAGES" | jq -r '.messages[]?.id' 2>/dev/null)

if [ -z "$MSG_IDS" ]; then
  log_info "아카이브할 메일이 없습니다"
  exit 0
fi

COUNT=0
while read -r MSG_ID; do
  # INBOX 라벨 제거 (아카이브 = INBOX에서 제거)
  gws gmail users messages modify --params "{\"userId\":\"me\",\"id\":\"$MSG_ID\"}" \
    --json '{"removeLabelIds":["INBOX"]}' >/dev/null 2>&1
  COUNT=$((COUNT + 1))
  log_info "Archived: $MSG_ID"
done <<< "$MSG_IDS"

log_success "총 ${COUNT}개 메일 아카이브 완료"
