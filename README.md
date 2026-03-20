# gws-automation-toolkit

[![CI](https://github.com/mongsill6/gws-automation-toolkit/actions/workflows/ci.yml/badge.svg)](https://github.com/mongsill6/gws-automation-toolkit/actions/workflows/ci.yml)
[![ShellCheck](https://img.shields.io/badge/linter-ShellCheck-blue)](https://www.shellcheck.net/)
[![Bats](https://img.shields.io/badge/tests-Bats-brightgreen)](https://github.com/bats-core/bats-core)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> Google Workspace CLI(`gws`)를 활용한 업무 자동화 스크립트 모음
> Gmail, Drive, Sheets, Calendar를 하나의 CLI 워크플로우로 통합

## 프로젝트 구조

```
gws-automation-toolkit/
├── scripts/
│   ├── gmail/
│   │   ├── gmail-daily-digest.sh       # 미읽은 메일 일일 다이제스트
│   │   ├── gmail-label-archiver.sh     # 라벨별 메일 자동 아카이브
│   │   └── gmail-to-tasks.sh           # 메일 → Google Tasks 변환
│   ├── drive/
│   │   ├── drive-backup.sh             # 폴더 증분 백업 (로컬/Drive-to-Drive)
│   │   ├── drive-cleanup.sh            # 오래된 파일 정리
│   │   └── drive-share-audit.sh        # 공유 권한 감사 CSV 리포트
│   ├── sheets/
│   │   ├── sheets-report-gen.sh        # 템플릿 기반 리포트 생성
│   │   ├── sheets-to-bq.sh            # Sheets → BigQuery 동기화
│   │   └── sheets-validator.sh         # 데이터 유효성 검사 (빈셀/중복/형식)
│   ├── calendar/
│   │   ├── calendar-conflict-check.sh  # 일정 충돌 감지
│   │   └── calendar-meeting-prep.sh    # 회의 준비 자료 자동 수집
│   ├── workflows/
│   │   ├── morning-briefing.sh         # 아침 브리핑 (메일+일정+태스크)
│   │   ├── email-to-sheet-tracker.sh   # 메일 → Sheets 트래킹 (중복 방지)
│   │   └── weekly-review.sh            # 주간 활동 리뷰
│   └── gws-backup.sh                   # Drive 메타데이터 JSON 백업
├── utils/
│   ├── common.sh                       # 공통 유틸 (로깅, 에러 핸들링, 임시파일)
│   └── gws-helpers.sh                  # gws CLI 래퍼 함수 모음
├── tests/
│   └── common.bats                     # bats 단위 테스트
├── docs/
│   └── USAGE.md                        # 상세 사용법
├── .github/workflows/
│   └── ci.yml                          # CI (ShellCheck + shebang 검증 + Bats)
├── Makefile                            # install, lint, test, unit-test 타겟
├── .shellcheckrc                       # ShellCheck 설정
├── .env.example                        # 환경변수 템플릿
├── CONTRIBUTING.md                     # 기여 가이드
├── LICENSE                             # MIT License
└── .gitignore
```

**15개 스크립트 · 2개 유틸리티 · 1개 테스트 파일 — 총 3,200+ 줄**

## 사전 요구사항

- **bash** 4.0+
- **jq** 1.6+
- **gws CLI** — Google Workspace 커맨드라인 도구
- **shellcheck** (개발/CI용)
- **bats** (테스트용)

## 빠른 시작

```bash
# 1. 클론
git clone https://github.com/mongsill6/gws-automation-toolkit.git
cd gws-automation-toolkit

# 2. 의존성 확인
make install

# 3. 환경변수 설정
cp .env.example .env
# .env 파일에서 DRIVE_FOLDER_ID 등 필요한 값 입력

# 4. OAuth 인증 (최초 1회)
gws auth login

# 5. 바로 사용!
./scripts/workflows/morning-briefing.sh        # 아침 브리핑
./scripts/gmail/gmail-daily-digest.sh           # 미읽은 메일 요약
./scripts/drive/drive-share-audit.sh            # 공유 권한 감사
./scripts/calendar/calendar-conflict-check.sh   # 일정 충돌 확인
```

모든 스크립트는 `--help` 옵션과 `getopts` 기반 인자 파싱을 지원합니다.

## 설치 가이드

### gws CLI 설치

```bash
# npm으로 설치
npm install -g @nicholasgasior/gws

# 또는 소스에서 빌드
git clone https://github.com/nicholasgasior/gws.git
cd gws && make install
```

### OAuth 인증 설정

```bash
# Google Cloud Console에서 OAuth 2.0 클라이언트 ID 생성
# 필요한 API 스코프:
#   - Gmail API (gmail.modify, gmail.readonly)
#   - Drive API (drive, drive.metadata.readonly)
#   - Sheets API (spreadsheets)
#   - Calendar API (calendar.readonly)
#   - Tasks API (tasks)

# OAuth 토큰 파일 설정
export GWS_OAUTH_TOKEN="$HOME/.config/gws/token.json"

# 인증 실행
gws auth login
```

## 스크립트 상세

### Gmail (3개)

- **`gmail-daily-digest.sh`** (241줄) — 미읽은 메일을 발신자/라벨별로 그룹핑하여 마크다운 다이제스트 생성
- **`gmail-label-archiver.sh`** (98줄) — 지정 라벨의 오래된 메일을 자동 아카이브 (INBOX에서 제거)
- **`gmail-to-tasks.sh`** (94줄) — 특정 라벨/조건의 Gmail 메일을 Google Tasks로 자동 변환

### Drive (3개)

- **`drive-backup.sh`** (329줄) — Drive 폴더를 로컬 또는 다른 폴더로 증분 백업 (변경분만 처리)
- **`drive-cleanup.sh`** (82줄) — Google Drive에서 오래된 파일을 조회하고 휴지통으로 이동
- **`drive-share-audit.sh`** (207줄) — 파일/폴더 공유 권한을 감사하여 외부 공유 감지 및 CSV 리포트 출력

### Sheets (3개)

- **`sheets-report-gen.sh`** (381줄) — 템플릿 Sheets를 복사하여 날짜/제목 치환 및 데이터 삽입된 리포트 생성
- **`sheets-to-bq.sh`** (109줄) — Google Sheets 데이터를 CSV로 변환하여 BigQuery 테이블에 동기화
- **`sheets-validator.sh`** (437줄) — Sheets 데이터의 빈 셀, 중복값, 형식 오류를 감지하고 요약 리포트 출력

### Calendar (2개)

- **`calendar-conflict-check.sh`** (96줄) — 지정 기간 내 일정 충돌(시간 겹침) 감지
- **`calendar-meeting-prep.sh`** (262줄) — 다음 회의의 참석자 정보, 관련 문서, 이전 미팅 노트 자동 수집

### Workflows — 크로스 서비스 (3개)

- **`morning-briefing.sh`** (71줄) — 아침 브리핑: 미읽은 메일 요약 + 오늘 일정 + 할 일 목록 통합
- **`email-to-sheet-tracker.sh`** (157줄) — Gmail 메일을 검색하여 Sheets에 자동 기록 (중복 방지 내장)
- **`weekly-review.sh`** (167줄) — 주간 리뷰: 메일 통계 + 완료 태스크 + 회의 시간 + Drive 활동 요약

### 유틸리티 & 독립 스크립트

- **`utils/common.sh`** (74줄) — 공통 유틸리티: 컬러 로깅(`log_info/warn/error/success`), ERR 트랩, 임시파일 자동 정리, 의존성 체크
- **`utils/gws-helpers.sh`** (183줄) — gws CLI 래퍼 함수 모음 (Drive/Gmail/Sheets/Calendar API 호출 헬퍼)
- **`scripts/gws-backup.sh`** (213줄) — Drive 폴더의 파일 메타데이터를 날짜별 JSON으로 백업

## 크론 등록 예제

```bash
crontab -e
```

```cron
# 매일 오전 7시 — 일정 충돌 확인
0 7 * * * /path/to/gws-automation-toolkit/scripts/calendar/calendar-conflict-check.sh

# 매일 오전 8시 — 아침 브리핑
0 8 * * * /path/to/gws-automation-toolkit/scripts/workflows/morning-briefing.sh

# 매일 오전 9시 — 미읽은 메일 다이제스트
0 9 * * * /path/to/gws-automation-toolkit/scripts/gmail/gmail-daily-digest.sh

# 매일 자정 — 오래된 메일 아카이브
0 0 * * * /path/to/gws-automation-toolkit/scripts/gmail/gmail-label-archiver.sh

# 매일 새벽 2시 — Drive 백업
0 2 * * * /path/to/gws-automation-toolkit/scripts/drive/drive-backup.sh

# 매주 월요일 오전 9시 — 주간 리뷰
0 9 * * 1 /path/to/gws-automation-toolkit/scripts/workflows/weekly-review.sh

# 매주 금요일 오후 6시 — Drive 공유 권한 감사
0 18 * * 5 /path/to/gws-automation-toolkit/scripts/drive/drive-share-audit.sh

# 30분마다 — 메일 → Sheets 트래킹
*/30 * * * * /path/to/gws-automation-toolkit/scripts/workflows/email-to-sheet-tracker.sh
```

## 개발

### Makefile 타겟

```bash
make help        # 사용 가능한 타겟 목록
make install     # 의존성 확인 (gws, jq, shellcheck, bats, curl)
make lint        # ShellCheck 정적 분석 (warning 수준)
make unit-test   # Bats 단위 테스트만 실행
make test        # lint + unit-test 전체 실행
```

### 코딩 컨벤션

- Shebang: `#!/usr/bin/env bash`
- Strict mode: `set -euo pipefail`
- ShellCheck 전수 통과 필수
- `common.sh` 로깅 함수 사용 필수 (`log_info`, `log_warn`, `log_error`, `log_success`)
- 임시파일은 `make_temp` + EXIT 트랩으로 자동 정리
- gws API 호출은 `gws-helpers.sh` 래퍼 함수 사용

## CI/CD

GitHub Actions로 `push`/`PR` → `main` 시 자동 검증 (2단계 파이프라인):

1. **ShellCheck Lint** — 모든 `.sh` 파일 정적 분석 + shebang 라인 검증
2. **Bats Unit Tests** — `tests/` 디렉터리 단위 테스트 실행 (ShellCheck 통과 후)

```bash
# 로컬에서 동일한 검증 실행
make lint    # shellcheck
make test    # shellcheck + bats
```

## 문서

- [USAGE.md](docs/USAGE.md) — 전체 스크립트 상세 사용법 및 인자 설명
- [CONTRIBUTING.md](CONTRIBUTING.md) — 개발 환경 설정, 코딩 규칙, PR 프로세스

## License

MIT
