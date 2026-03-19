# Usage Guide

gws-automation-toolkit의 모든 스크립트 사용법을 정리한 가이드입니다.

## 사전 요구사항

- **bash** 4.0 이상
- **gws** CLI (Google Workspace CLI) — OAuth 인증 완료 상태
- **jq** — JSON 파서
- **bq** CLI — `sheets-to-bq.sh` 사용 시 필요
- **python3** — `sheets-report-gen.sh` CSV 파싱 시 필요

## 환경변수

| 변수 | 필수 | 기본값 | 설명 |
|------|------|--------|------|
| `BQ_PROJECT` | `sheets-to-bq.sh` 사용 시 | `inspiring-bonus-484905-v9` | BigQuery 프로젝트 ID |

gws CLI의 OAuth 토큰은 gws가 내부적으로 관리합니다. 별도 환경변수 설정이 필요 없습니다.

## 공통 구조

모든 스크립트는 `utils/common.sh`를 source하여 다음 기능을 사용합니다:

- 컬러 로깅 (`log_info`, `log_warn`, `log_error`, `log_success`)
- 에러 트랩 (실패 시 라인 번호/명령어 자동 출력)
- 임시파일 자동 정리 (`make_temp`, `make_temp_dir`)
- 의존성 검사 (`check_deps`, `check_gws_deps`)

---

## Gmail 스크립트

### gmail-daily-digest.sh

미읽은 메일을 발신자별/라벨별로 그룹핑한 일일 요약을 마크다운으로 출력합니다.

```bash
# 기본 사용 (최대 50건, stdout 출력)
bash scripts/gmail/gmail-daily-digest.sh

# 최대 100건, 파일로 저장
bash scripts/gmail/gmail-daily-digest.sh 100 /tmp/digest.md
```

**인자:**
- `$1` (선택): 최대 조회 건수 (기본값: 50)
- `$2` (선택): 출력 파일 경로 (미지정 시 stdout)

### gmail-label-archiver.sh

지정 라벨의 오래된 메일에서 INBOX 라벨을 제거(아카이브)합니다.

```bash
# "newsletter" 라벨의 30일 이상 된 메일 아카이브
bash scripts/gmail/gmail-label-archiver.sh newsletter

# 60일 이상 된 메일만 아카이브
bash scripts/gmail/gmail-label-archiver.sh newsletter 60
```

**인자:**
- `$1` (필수): Gmail 라벨 이름
- `$2` (선택): 기준 일수 (기본값: 30)

### gmail-to-tasks.sh

조건에 맞는 메일을 Google Tasks로 변환합니다.

```bash
# 기본: action-required 라벨의 미읽은 메일 5건
bash scripts/gmail/gmail-to-tasks.sh

# 커스텀 쿼리로 10건 처리
bash scripts/gmail/gmail-to-tasks.sh "from:boss@company.com is:unread" 10
```

**인자:**
- `$1` (선택): Gmail 검색 쿼리 (기본값: `label:action-required is:unread`)
- `$2` (선택): 최대 처리 건수 (기본값: 5)

---

## Drive 스크립트

### drive-backup.sh

Drive 폴더를 증분 백업합니다. 마지막 백업 이후 변경된 파일만 처리합니다.

```bash
# 로컬 백업 (기본)
bash scripts/drive/drive-backup.sh FOLDER_ID

# Drive-to-Drive 백업
bash scripts/drive/drive-backup.sh FOLDER_ID drive TARGET_FOLDER_ID

# 로컬 경로 지정
bash scripts/drive/drive-backup.sh FOLDER_ID local /backup/drive
```

**인자:**
- `$1` (필수): 소스 Drive 폴더 ID
- `$2` (선택): 모드 — `local` 또는 `drive` (기본값: `local`)
- `$3` (선택): 대상 경로 (기본값: `/tmp/drive-backup`)

**상태 파일:** `~/.drive-backup/<폴더ID>.state`
**로그:** `~/.drive-backup/logs/backup-<timestamp>.log`

### drive-cleanup.sh

오래된 파일을 조회하고 선택적으로 휴지통으로 이동합니다.

```bash
# 90일 이상 된 파일 목록 조회 (dry-run)
bash scripts/drive/drive-cleanup.sh

# 180일 기준, 실제 삭제 실행
bash scripts/drive/drive-cleanup.sh 180 false
```

**인자:**
- `$1` (선택): 기준 일수 (기본값: 90)
- `$2` (선택): dry-run 여부 — `true` 또는 `false` (기본값: `true`)

### drive-share-audit.sh

Drive 공유 권한을 감사하여 CSV 리포트를 생성합니다.

```bash
# 기본: spigen.com 도메인 기준, root 폴더 감사
bash scripts/drive/drive-share-audit.sh

# 특정 도메인과 폴더 지정
bash scripts/drive/drive-share-audit.sh mycompany.com FOLDER_ID /reports
```

**인자:**
- `$1` (선택): 회사 도메인 (기본값: `spigen.com`)
- `$2` (선택): 대상 폴더 ID (기본값: `root`)
- `$3` (선택): 출력 디렉토리 (기본값: `/tmp`)

**출력:** `<출력디렉토리>/drive-share-audit-<timestamp>.csv`

---

## Sheets 스크립트

### sheets-to-bq.sh

Google Sheets 데이터를 BigQuery 테이블로 동기화합니다.

```bash
# Sheets → BigQuery 동기화
bash scripts/sheets/sheets-to-bq.sh SPREADSHEET_ID "Sheet1" "dataset.table_name"

# 프로젝트 ID 지정
BQ_PROJECT=my-project bash scripts/sheets/sheets-to-bq.sh SPREADSHEET_ID "매출" "sales.raw_data"
```

**인자:**
- `$1` (필수): Google Spreadsheet ID
- `$2` (필수): 시트 이름
- `$3` (필수): BigQuery 대상 테이블 (`dataset.table`)

**환경변수:** `BQ_PROJECT` (기본값: `inspiring-bonus-484905-v9`)
**추가 의존성:** `bq` CLI

### sheets-report-gen.sh

템플릿 Sheets를 복사하고 데이터를 삽입하여 새 보고서를 생성합니다.

```bash
# 기본 사용
bash scripts/sheets/sheets-report-gen.sh TEMPLATE_SPREADSHEET_ID --title "월간 보고서"

# 전체 옵션 예시
bash scripts/sheets/sheets-report-gen.sh TEMPLATE_SPREADSHEET_ID \
  --title "2026년 3월 매출 보고서" \
  --folder DRIVE_FOLDER_ID \
  --date "2026-03-01" \
  --sheet "Sheet1" \
  --data-range "A2" \
  --data-file /tmp/data.csv \
  --placeholders "TEAM=마케팅,REGION=KR" \
  --share "user@example.com" \
  --share-role writer \
  --quiet
```

**인자:**
- `$1` (필수): 템플릿 Spreadsheet ID

**옵션:**
- `--title TEXT`: 생성할 파일 제목
- `--folder ID`: Drive 저장 폴더 ID
- `--date YYYY-MM-DD`: 기준 날짜
- `--sheet NAME`: 대상 시트 이름
- `--data-range RANGE`: 데이터 삽입 시작 셀 (예: `A2`)
- `--data-file PATH`: CSV/JSON 데이터 파일 경로
- `--data-json JSON`: 인라인 JSON 데이터
- `--placeholders KEY=VAL,...`: 커스텀 플레이스홀더
- `--share EMAIL`: 공유 대상 이메일
- `--share-role ROLE`: 공유 권한 (`reader`/`writer`)
- `--open`: 생성 후 브라우저에서 열기
- `--quiet`: JSON 결과만 출력 (파이프라인 연동용)

**내장 플레이스홀더:** `{{DATE}}`, `{{TODAY}}`, `{{YEAR}}`, `{{MONTH}}`, `{{DAY}}`, `{{WEEK}}`, `{{QUARTER}}`, `{{TITLE}}`

### sheets-validator.sh

Sheets 데이터의 유효성을 검사합니다 (빈 셀, 중복, 형식 오류).

```bash
# 기본 검사
bash scripts/sheets/sheets-validator.sh SPREADSHEET_ID "Sheet1!A1:Z100"

# 상세 검사 옵션
bash scripts/sheets/sheets-validator.sh SPREADSHEET_ID "A1:Z100" \
  --email-cols "C,E" \
  --date-cols "B" \
  --number-cols "F,G,H" \
  --unique-cols "A" \
  --required-cols "A,B,C" \
  --output /tmp/validation.txt \
  --csv
```

**인자:**
- `$1` (필수): Spreadsheet ID
- `$2` (필수): 셀 범위 (예: `Sheet1!A1:Z100`)

**옵션:**
- `--email-cols COL,...`: 이메일 형식 검증 컬럼
- `--date-cols COL,...`: 날짜 형식 검증 컬럼
- `--number-cols COL,...`: 숫자 형식 검증 컬럼
- `--unique-cols COL,...`: 중복 검사 컬럼
- `--required-cols COL,...`: 필수값 컬럼
- `--output PATH`: 결과 파일 경로
- `--csv`: CSV 형식 출력
- `--quiet`: 요약만 출력

**종료 코드:** 이슈 발견 시 `exit 1` (CI 파이프라인 연동 가능)

---

## Calendar 스크립트

### calendar-conflict-check.sh

향후 N일간 일정 충돌을 감지합니다.

```bash
# 향후 7일 충돌 검사 (기본)
bash scripts/calendar/calendar-conflict-check.sh

# 향후 14일 검사
bash scripts/calendar/calendar-conflict-check.sh 14
```

**인자:**
- `$1` (선택): 검사 기간 일수 (기본값: 7)

### calendar-meeting-prep.sh

다음 회의의 준비 자료를 자동 수집하여 마크다운으로 출력합니다.

```bash
# 향후 24시간 내 다음 회의 준비
bash scripts/calendar/calendar-meeting-prep.sh

# 향후 48시간 범위로 검색
bash scripts/calendar/calendar-meeting-prep.sh 48
```

**인자:**
- `$1` (선택): 검색 범위 시간 (기본값: 24)

**수집 항목:**
1. 다음 회의 정보 (Google Calendar)
2. 참석자 연락처 (People API)
3. 관련 Drive 문서 (회의 제목 키워드 검색)
4. 이전 미팅 노트 검색
5. 준비 체크리스트 (불참자/미응답자 경고)

---

## Workflow 스크립트

### morning-briefing.sh

아침 브리핑 3종 세트를 출력합니다 (메일 + 일정 + 태스크).

```bash
bash scripts/workflows/morning-briefing.sh
```

**인자:** 없음

**크론 등록 예시:**
```bash
# 매일 오전 8시 실행
0 8 * * * /path/to/scripts/workflows/morning-briefing.sh >> /var/log/briefing.log 2>&1
```

### email-to-sheet-tracker.sh

Gmail 검색 결과를 Google Sheets에 자동 기록합니다 (중복 자동 방지).

```bash
# 발주 관련 메일 추적
bash scripts/workflows/email-to-sheet-tracker.sh \
  "subject:발주 OR subject:PO" \
  SPREADSHEET_ID

# 시트명과 건수 지정
bash scripts/workflows/email-to-sheet-tracker.sh \
  "from:supplier@example.com" \
  SPREADSHEET_ID \
  "SupplierMails" \
  50
```

**인자:**
- `$1` (필수): Gmail 검색 쿼리
- `$2` (필수): 대상 Spreadsheet ID
- `$3` (선택): 시트 이름 (기본값: `EmailTracker`)
- `$4` (선택): 최대 처리 건수 (기본값: 20)

**기록 컬럼:** MessageID, From, Subject, Date, Snippet, Labels

### weekly-review.sh

주간 리뷰 마크다운 보고서를 생성합니다.

```bash
bash scripts/workflows/weekly-review.sh
```

**인자:** 없음

**보고서 섹션:**
1. Gmail 통계 (수신/발신/미읽음)
2. 완료된 태스크 목록
3. 회의 통계 (건수, 총 시간, 평균, 요일별 분포)
4. Drive 활동 (이번 주 수정/생성 파일)

---

## Makefile 타겟

```bash
make help        # 사용법 출력
make install     # 의존성 확인 (gws, jq, shellcheck, bats)
make test        # shellcheck + bats 전체 실행
make lint        # shellcheck만 실행
make unit-test   # bats만 실행
```
