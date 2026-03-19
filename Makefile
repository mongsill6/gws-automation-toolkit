.PHONY: help lint test

SHELL_FILES := $(shell find scripts/ utils/ -name '*.sh' -type f)
TEST_FILES  := $(wildcard tests/*.bats)

help: ## 사용법 출력
	@echo "gws-automation-toolkit — Google Workspace 자동화 도구 모음"
	@echo ""
	@echo "타겟:"
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "예시:"
	@echo "  make lint    # shellcheck으로 모든 .sh 파일 검사"
	@echo "  make test    # bats 단위 테스트 실행"

lint: ## shellcheck으로 모든 셸 스크립트 정적 분석
	@echo "[LINT] shellcheck 실행 중..."
	@shellcheck -x -S warning -e SC1091 $(SHELL_FILES)
	@echo "[LINT] 완료 — 문제 없음"

test: ## bats 단위 테스트 실행
	@echo "[TEST] bats 테스트 실행 중..."
	@bats tests/
	@echo "[TEST] 완료"
