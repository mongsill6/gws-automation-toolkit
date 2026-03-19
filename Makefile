.PHONY: help install test lint unit-test
.DEFAULT_GOAL := help

SHELL_FILES := $(shell find scripts/ utils/ -name '*.sh' -type f)
TEST_FILES  := $(wildcard tests/*.bats)

help: ## 사용법 출력
	@echo "gws-automation-toolkit — Google Workspace 자동화 도구 모음"
	@echo ""
	@echo "타겟:"
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "예시:"
	@echo "  make install     # 의존성 확인"
	@echo "  make test        # shellcheck 전체 검사 + bats 테스트"
	@echo "  make lint        # shellcheck 경고 수준 검사"

install: ## 필수 의존성 확인 (gws, jq, shellcheck, bats)
	@echo "[INSTALL] 의존성 확인 중..."
	@ok=true; \
	for cmd in gws jq shellcheck bats curl; do \
		if command -v $$cmd >/dev/null 2>&1; then \
			printf "  ✓ %-12s %s\n" "$$cmd" "$$($$cmd --version 2>/dev/null | head -1 || echo 'installed')"; \
		else \
			printf "  ✗ %-12s 설치 필요\n" "$$cmd"; \
			ok=false; \
		fi; \
	done; \
	if $$ok; then \
		echo "[INSTALL] 모든 의존성 충족"; \
	else \
		echo "[INSTALL] 누락된 의존성이 있습니다"; \
		exit 1; \
	fi

test: ## shellcheck 전체 스크립트 검사 + bats 단위 테스트
	@echo "[TEST] shellcheck 전체 검사 실행 중..."
	@shellcheck -x $(SHELL_FILES)
	@echo "[TEST] shellcheck 통과"
	@if [ -n "$(TEST_FILES)" ]; then \
		echo "[TEST] bats 단위 테스트 실행 중..."; \
		bats tests/; \
		echo "[TEST] bats 통과"; \
	else \
		echo "[TEST] bats 테스트 파일 없음 — 스킵"; \
	fi
	@echo "[TEST] 완료 — 모든 검사 통과"

lint: ## shellcheck --severity=warning 수준 정적 분석
	@echo "[LINT] shellcheck (severity=warning) 실행 중..."
	@shellcheck -x -S warning $(SHELL_FILES)
	@echo "[LINT] 완료 — 문제 없음"

unit-test: ## bats 단위 테스트만 실행
	@echo "[UNIT-TEST] bats 테스트 실행 중..."
	@bats tests/
	@echo "[UNIT-TEST] 완료"
