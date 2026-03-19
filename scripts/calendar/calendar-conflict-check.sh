#!/usr/bin/env bash
# calendar-conflict-check.sh — 일정 충돌 감지

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../utils/common.sh"
source "${SCRIPT_DIR}/../../utils/gws-helpers.sh"

# ── 사용법 ──
usage() {
  cat <<'USAGE'
사용법: calendar-conflict-check.sh [옵션]

Google Calendar에서 지정 기간 내 일정 충돌(시간 겹침)을 감지합니다.

옵션:
  -d, --days DAYS         검사할 기간 (기본: 7일)
  -h, --help              사용법 출력

예시:
  # 앞으로 7일간 충돌 검사
  calendar-conflict-check.sh

  # 앞으로 14일간 충돌 검사
  calendar-conflict-check.sh -d 14

  # 위치 인자 호환 (기존 방식)
  calendar-conflict-check.sh 14
USAGE
  exit 0
}

# ── 인자 파싱 ──
DAYS_AHEAD=7

while [ $# -gt 0 ]; do
  case "$1" in
    -d|--days)   DAYS_AHEAD="$2"; shift ;;
    -h|--help)   usage ;;
    -*)          echo "알 수 없는 옵션: $1"; usage ;;
    *)
      # 위치 인자 호환
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        DAYS_AHEAD="$1"
      fi
      ;;
  esac
  shift
done

check_gws_deps

TODAY=$(date +%Y-%m-%d)
END_DATE=$(date -d "$DAYS_AHEAD days" +%Y-%m-%d 2>/dev/null || date "-v+${DAYS_AHEAD}d" +%Y-%m-%d)

log_info "일정 충돌 검사: $TODAY ~ $END_DATE"

TIME_MIN="${TODAY}T00:00:00+09:00"
TIME_MAX="${END_DATE}T23:59:59+09:00"

# 일정 가져오기
EVENTS=$(gws calendar events list --params "{
  \"calendarId\":\"primary\",
  \"timeMin\":\"$TIME_MIN\",
  \"timeMax\":\"$TIME_MAX\",
  \"singleEvents\":true,
  \"orderBy\":\"startTime\"
}")

# JSON으로 이벤트 파싱 후 충돌 검사
echo "$EVENTS" | jq -r '
  [.items[]? | select(.start.dateTime != null) | {
    summary: .summary,
    start: .start.dateTime,
    end: .end.dateTime
  }] |
  . as $events |
  reduce range(length) as $i (
    [];
    . + [
      reduce range($i+1; $events | length) as $j (
        [];
        if ($events[$i].end > $events[$j].start) and ($events[$i].start < $events[$j].end)
        then . + [{
          event1: $events[$i].summary,
          event2: $events[$j].summary,
          overlap_start: (if $events[$i].start > $events[$j].start then $events[$i].start else $events[$j].start end),
          overlap_end: (if $events[$i].end < $events[$j].end then $events[$i].end else $events[$j].end end)
        }]
        else .
        end
      )
    ]
  ) | flatten | if length == 0 then "충돌 없음"
  else .[] | "  \(.event1) <-> \(.event2)\n     겹치는 시간: \(.overlap_start) ~ \(.overlap_end)"
  end
'
