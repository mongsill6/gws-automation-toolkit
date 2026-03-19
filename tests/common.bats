#!/usr/bin/env bats
# tests/common.bats — utils/common.sh 로깅/의존성 체크 함수 단위 테스트

# ── 헬퍼: common.sh를 안전하게 source ──
# set -e / trap ERR 을 비활성화하여 bats 환경에서 동작하도록 함
setup() {
  # common.sh의 set -euo pipefail과 trap을 우회하여 함수만 로드
  eval "$(
    sed -e 's/^set -euo pipefail//' \
        -e "/^trap/d" \
        "$(dirname "$BATS_TEST_DIRNAME")/utils/common.sh"
  )"
}

# ═══════════════════════════════════════
# 로깅 함수 테스트
# ═══════════════════════════════════════

@test "log_info: stdout에 [INFO] 태그 포함" {
  run log_info "테스트 메시지"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[INFO]"* ]]
  [[ "$output" == *"테스트 메시지"* ]]
}

@test "log_warn: stderr에 [WARN] 태그 포함" {
  run bash -c 'source <(sed -e "s/^set -euo pipefail//" -e "/^trap/d" "'"$(dirname "$BATS_TEST_DIRNAME")/utils/common.sh"'"); log_warn "경고 메시지" 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"경고 메시지"* ]]
}

@test "log_error: stderr에 [ERROR] 태그 포함" {
  run bash -c 'source <(sed -e "s/^set -euo pipefail//" -e "/^trap/d" "'"$(dirname "$BATS_TEST_DIRNAME")/utils/common.sh"'"); log_error "에러 발생" 2>&1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ERROR]"* ]]
  [[ "$output" == *"에러 발생"* ]]
}

@test "log_success: stdout에 [SUCCESS] 태그 포함" {
  run log_success "작업 완료"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[SUCCESS]"* ]]
  [[ "$output" == *"작업 완료"* ]]
}

@test "log_info: HH:MM:SS 형식 타임스탬프 포함" {
  run log_info "시간 체크"
  [ "$status" -eq 0 ]
  [[ "$output" =~ [0-9]{2}:[0-9]{2}:[0-9]{2} ]]
}

# ═══════════════════════════════════════
# 의존성 체크 함수 테스트
# ═══════════════════════════════════════

@test "check_deps: 존재하는 명령어 — 성공 (exit 0)" {
  run check_deps bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"의존성 확인 완료"* ]]
}

@test "check_deps: 여러 존재하는 명령어 — 성공" {
  run check_deps bash cat ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"의존성 확인 완료"* ]]
}

@test "check_deps: 존재하지 않는 명령어 — 실패 (exit 1)" {
  run bash -c 'source <(sed -e "s/^set -euo pipefail//" -e "/^trap/d" "'"$(dirname "$BATS_TEST_DIRNAME")/utils/common.sh"'"); check_deps __nonexistent_cmd_xyz__ 2>&1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"필수 도구 미설치"* ]]
  [[ "$output" == *"__nonexistent_cmd_xyz__"* ]]
}

@test "check_deps: 혼합 (존재 + 미존재) — 실패하고 미설치 목록 출력" {
  run bash -c 'source <(sed -e "s/^set -euo pipefail//" -e "/^trap/d" "'"$(dirname "$BATS_TEST_DIRNAME")/utils/common.sh"'"); check_deps bash __fake_tool_abc__ 2>&1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"__fake_tool_abc__"* ]]
}

# ═══════════════════════════════════════
# 임시파일 함수 테스트
# ═══════════════════════════════════════

@test "make_temp: 임시파일 생성 및 경로 반환" {
  run make_temp "bats-test"
  [ "$status" -eq 0 ]
  [ -f "$output" ]
  rm -f "$output"
}

@test "make_temp_dir: 임시디렉토리 생성 및 경로 반환" {
  run make_temp_dir "bats-test"
  [ "$status" -eq 0 ]
  [ -d "$output" ]
  rm -rf "$output"
}
