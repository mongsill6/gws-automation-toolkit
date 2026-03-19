#!/usr/bin/env bash
# common.sh — 공통 유틸리티 (에러 핸들링, 로깅, 의존성 체크, 임시파일 정리)
# source this file: source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

set -euo pipefail

# ── 컬러 정의 ──
_CLR_RED='\033[0;31m'
_CLR_GREEN='\033[0;32m'
_CLR_YELLOW='\033[0;33m'
_CLR_BLUE='\033[0;34m'
_CLR_RESET='\033[0m'

# ── 로깅 함수 ──
log_info()    { echo -e "${_CLR_BLUE}[INFO]${_CLR_RESET}    $(date '+%H:%M:%S') $*"; }
log_warn()    { echo -e "${_CLR_YELLOW}[WARN]${_CLR_RESET}    $(date '+%H:%M:%S') $*" >&2; }
log_error()   { echo -e "${_CLR_RED}[ERROR]${_CLR_RESET}   $(date '+%H:%M:%S') $*" >&2; }
log_success() { echo -e "${_CLR_GREEN}[SUCCESS]${_CLR_RESET} $(date '+%H:%M:%S') $*"; }

# ── 에러 핸들링 (trap ERR) ──
_on_error() {
  local exit_code=$?
  local line_no=${BASH_LINENO[0]}
  local command="${BASH_COMMAND}"
  log_error "명령 실패 (exit $exit_code) at line $line_no: $command"
  exit "$exit_code"
}
trap '_on_error' ERR

# ── 임시파일 자동 정리 (trap EXIT) ──
_COMMON_TMPFILES=()

make_temp() {
  local tmpfile
  tmpfile=$(mktemp "/tmp/${1:-common}-XXXXXX")
  _COMMON_TMPFILES+=("$tmpfile")
  echo "$tmpfile"
}

_cleanup_tmpfiles() {
  for f in "${_COMMON_TMPFILES[@]:-}"; do
    [ -f "$f" ] && rm -f "$f"
  done
}
trap '_cleanup_tmpfiles' EXIT

# ── 의존성 체크 ──
check_deps() {
  local missing=()
  for cmd in "$@"; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done
  if [ ${#missing[@]} -gt 0 ]; then
    log_error "필수 도구 미설치: ${missing[*]}"
    log_error "설치 후 다시 실행하세요."
    return 1
  fi
  log_info "의존성 확인 완료: $*"
}

# 기본 의존성 체크 (gws, jq)
check_gws_deps() {
  check_deps gws jq
}
