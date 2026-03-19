# Contributing Guide

gws-automation-toolkit에 기여하기 위한 가이드입니다.

## 개발 환경 설정

```bash
# 의존성 확인
make install

# 전체 테스트 실행
make test
```

**필수 도구:**
- bash 4.0+
- gws CLI (OAuth 인증 완료)
- jq
- shellcheck
- bats (Bash Automated Testing System)

## 코딩 컨벤션

### 셸 스크립트 기본 규칙

1. **Shebang**: 모든 스크립트는 `#!/usr/bin/env bash`로 시작
2. **엄격 모드**: `set -euo pipefail` 필수 (common.sh에서 적용)
3. **shellcheck 준수**: 모든 코드는 `shellcheck -S warning` 통과 필수
4. **common.sh 사용**: 모든 스크립트는 `utils/common.sh`를 source

```bash
#!/usr/bin/env bash
# 스크립트 설명 (한 줄)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../utils/common.sh"
source "${SCRIPT_DIR}/../../utils/gws-helpers.sh"  # 필요한 경우

check_gws_deps  # 의존성 검사
```

### 변수와 함수

- **변수명**: `UPPER_SNAKE_CASE` (환경변수/상수), `lower_snake_case` (지역변수)
- **함수명**: `lower_snake_case`
- **지역변수**: 함수 내부에서 `local` 키워드 사용
- **변수 참조**: 항상 `"${variable}"` 형식으로 쌍따옴표 사용

```bash
# 좋은 예
local file_count=0
readonly MAX_RETRIES=3
process_files "${target_dir}"

# 나쁜 예
fileCount=0
process_files $target_dir
```

### 로깅

`common.sh`의 로깅 함수를 사용합니다. `echo`를 직접 사용하지 않습니다.

```bash
log_info "처리를 시작합니다: ${file_name}"
log_warn "파일을 찾을 수 없습니다: ${path}"
log_error "API 호출 실패 (HTTP ${status})"
log_success "총 ${count}건 처리 완료"
```

### 임시파일

`common.sh`의 `make_temp` / `make_temp_dir`을 사용합니다. 스크립트 종료 시 자동 정리됩니다.

```bash
local tmp_file
tmp_file=$(make_temp "my-script")
echo "data" > "${tmp_file}"
# EXIT 트랩에 의해 자동 삭제됨
```

### 에러 처리

- `set -euo pipefail`이 적용되므로 파이프라인 실패도 감지됩니다
- 개별 명령어의 실패를 허용할 때는 `|| true` 사용
- `trap ERR`에 의해 실패 위치가 자동 출력됩니다

```bash
# 실패해도 계속 진행
local result
result=$(some_command 2>/dev/null) || true

# 명시적 에러 처리
if ! gws_list_files "${query}"; then
    log_error "Drive 검색 실패"
    return 1
fi
```

### gws CLI 호출

`gws` CLI를 직접 호출하지 말고, `utils/gws-helpers.sh`의 래퍼 함수를 사용합니다.

```bash
# 좋은 예
local meta
meta=$(gws_get_file_meta "${file_id}")

# 나쁜 예
local meta
meta=$(gws drive files get --fileId="${file_id}" --params '{"fields":"*"}')
```

### .shellcheckrc

프로젝트 루트의 `.shellcheckrc`에 전역 설정이 있습니다:

- `source-path=SCRIPTDIR`, `source-path=utils/` — source 경로 힌트
- `SC1091` 비활성화 — 런타임 경로 source 경고 무시
- `SC2155` 비활성화 — declare+할당 분리 권고 무시

인라인 비활성화가 필요한 경우 사유를 주석으로 남깁니다:

```bash
# shellcheck disable=SC2034  # 다른 스크립트에서 source하여 사용
MY_EXPORTED_VAR="value"
```

## 새 스크립트 추가 절차

1. 적절한 카테고리 디렉토리에 파일 생성 (`scripts/gmail/`, `scripts/drive/` 등)
2. 위의 코딩 컨벤션에 따라 작성
3. `make lint`로 shellcheck 통과 확인
4. 필요 시 `tests/`에 bats 테스트 추가
5. `docs/USAGE.md`에 사용법 문서 추가

## 테스트 작성 규칙

### bats 테스트 구조

테스트 파일은 `tests/` 디렉토리에 `*.bats` 확장자로 작성합니다.

```bash
#!/usr/bin/env bats

# common.sh의 set -euo pipefail과 trap이 bats와 충돌하므로
# sed로 제거 후 eval하는 패턴을 사용합니다.
setup() {
    UTILS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../utils" && pwd)"
    COMMON_SRC=$(sed -E \
        -e 's/^set -euo pipefail$//' \
        -e "/^trap '.*' ERR$/d" \
        "${UTILS_DIR}/common.sh")
    eval "${COMMON_SRC}"
}

@test "함수명: 동작 설명" {
    run my_function "arg1" "arg2"
    [ "$status" -eq 0 ]
    [[ "$output" == *"expected string"* ]]
}
```

### 테스트 작성 원칙

- 각 함수의 정상 케이스와 실패 케이스를 모두 테스트
- `run` 키워드로 명령 실행 후 `$status`와 `$output` 검증
- stderr 검증이 필요한 경우 `run bash -c '...'` 패턴 사용
- 외부 API(gws)를 호출하는 함수는 mock/stub 처리

## PR 절차

### 브랜치 전략

```
main ← feature/기능명
main ← fix/버그명
main ← docs/문서명
```

### PR 제출 전 체크리스트

- [ ] `make test` 전체 통과 (shellcheck + bats)
- [ ] 새 스크립트는 `docs/USAGE.md`에 사용법 추가
- [ ] 커밋 메시지는 [Conventional Commits](https://www.conventionalcommits.org/) 형식 사용
  - `feat:` 새 기능
  - `fix:` 버그 수정
  - `docs:` 문서 변경
  - `ci:` CI/CD 변경
  - `refactor:` 리팩터링
  - `test:` 테스트 추가/수정

### PR 프로세스

1. `main`에서 feature 브랜치 생성
2. 변경사항 커밋 (Conventional Commits 형식)
3. `make test` 통과 확인
4. PR 생성 — 변경사항 요약 + 테스트 결과 포함
5. GitHub Actions CI 통과 확인
6. 리뷰 승인 후 merge

### CI 파이프라인

PR 제출 시 자동 실행되는 검증:

1. **shellcheck**: 모든 `.sh` 파일 정적 분석 + shebang 검증
2. **bats**: `tests/` 디렉토리 단위 테스트

두 단계 모두 통과해야 merge 가능합니다.
