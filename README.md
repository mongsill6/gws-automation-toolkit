# gws-automation-toolkit

Google Workspace CLI(`gws`)를 활용한 업무 자동화 스크립트 모음

## 구조

```
scripts/
├── gmail/          # Gmail 자동화
├── drive/          # Drive 파일 관리
├── sheets/         # Sheets 데이터 처리
├── calendar/       # Calendar 일정 관리
└── workflows/      # 크로스 서비스 워크플로우
```

## 스크립트 목록

### Gmail
- `gmail-label-archiver.sh` — 지정 라벨 메일 자동 아카이브
- `gmail-to-tasks.sh` — 특정 조건 메일 → Google Tasks 변환
- `gmail-daily-digest.sh` — 미읽은 메일 일일 요약 생성

### Drive
- `drive-cleanup.sh` — 오래된 파일 정리/아카이브
- `drive-backup.sh` — 중요 폴더 자동 백업
- `drive-share-audit.sh` — 공유 권한 감사

### Sheets
- `sheets-to-bq.sh` — Sheets 데이터 → BigQuery 동기화
- `sheets-report-gen.sh` — 템플릿 기반 리포트 자동 생성
- `sheets-validator.sh` — 데이터 유효성 검사 (빈 셀/중복값/형식 오류 감지)

### Calendar
- `calendar-conflict-check.sh` — 일정 충돌 감지
- `calendar-meeting-prep.sh` — 회의 준비 자료 자동 수집

### Workflows
- `morning-briefing.sh` — 아침 브리핑 (메일 + 일정 + 태스크)
- `email-to-sheet-tracker.sh` — 메일 → Sheets 트래킹

## 사전 요구사항

- [gws CLI](https://github.com/nicholasgasior/gws) 설치 및 OAuth 인증 완료
- bash 4.0+, jq

## 사용법

```bash
# 아침 브리핑 실행
./scripts/workflows/morning-briefing.sh

# 크론 등록 (매일 오전 8시)
crontab -e
0 8 * * * /path/to/scripts/workflows/morning-briefing.sh
```

## License

MIT
