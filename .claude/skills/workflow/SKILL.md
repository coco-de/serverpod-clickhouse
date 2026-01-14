---
name: workflow
description: 이슈 생성부터 머지까지 전체 개발 사이클 자동화
---

# Workflow

작업 내용으로 이슈 생성부터 머지 승인까지 전체 개발 사이클을 자동화하는 스킬입니다.

## Scope and Capabilities

### 핵심 기능

| 기능 | 설명 |
|------|------|
| 작업 분석 | 키워드 기반 타입/스코프/복잡도 자동 추론 |
| 이슈 생성 | GitHub 이슈 자동 생성 및 라벨링 |
| 테스트 실행 | dart analyze, dart test 자동 실행 |
| 코드 리뷰 | /review 통합 |
| 머지 승인 | 사용자 승인 후 스쿼시 머지 |

### 8단계 워크플로우

| 단계 | 설명 |
|------|------|
| 1 | 작업 내용 분석 (타입/스코프/복잡도) |
| 2 | GitHub 이슈 생성 |
| 3 | 브랜치 생성 |
| 4 | 구현 작업 |
| 5 | dart analyze 및 테스트 실행 |
| 6 | PR 생성 |
| 7 | 코드 리뷰 진행 |
| 8 | 머지 승인 대기 |

## Quick Start

### 기본 사용

```bash
# 작업 내용으로 전체 사이클 시작
/workflow "Dictionary 지원 추가"
```

### 기존 이슈로 시작

```bash
# 이슈 번호로 시작 (Step 3부터)
/workflow 5
```

### 옵션 사용

```bash
# 타입 명시
/workflow --type feat "percentiles() 함수 추가"

# 스코프 명시
/workflow --scope analytics "통계 함수 추가"

# 테스트 스킵 (긴급)
/workflow --skip-tests "긴급 수정"

# 코드 리뷰 스킵 (긴급)
/workflow --skip-review "긴급 핫픽스"
```

## 자동 추론 규칙

### 타입 추론

| 키워드 | 타입 | Gitmoji |
|--------|------|---------|
| 추가, 구현, 생성, 지원 | feat | ✨ |
| 수정, 고치기, 버그, 에러 | fix | 🐛 |
| 개선, 리팩토링, 최적화 | refactor | ♻️ |
| 설정, 빌드, 환경 | chore | 🔧 |
| 문서, docs, README | docs | 📝 |

### 스코프 추론

| 키워드 | 스코프 |
|--------|--------|
| 쿼리, 분석, analytics | analytics |
| 스키마, 테이블, DDL | schema |
| 클라이언트, HTTP | client |
| 이벤트, 트래킹 | events |
| 동기화, sync | sync |

### 복잡도 산정

| 복잡도 | Point | 조건 |
|--------|-------|------|
| 간단 | 1 | 단일 파일 수정 |
| 보통 | 3 | 2-3개 파일 수정 |
| 복잡 | 5 | 새 클래스/기능 추가 |
| 대형 | 8 | 새 파일 + 테스트 + 문서 |

## 결과 형식

### 완료 시

```
╔════════════════════════════════════════════════════════════════╗
║  Workflow Complete: #5                                         ║
╠════════════════════════════════════════════════════════════════╣
║                                                                ║
║  📋 Issue: #5 - Dictionary 지원 추가                            ║
║  🔀 PR: #6                                                     ║
║  🌿 Branch: feature/5-dictionary-support (deleted)             ║
║                                                                ║
║  ✅ Analyze: No issues found                                   ║
║  ✅ Tests: All passed                                          ║
║  ✅ Review: All issues resolved                                ║
║                                                                ║
║  🏁 Final State: MERGED                                        ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
```

## 관련 커맨드

- `/review <PR번호>` - 코드 리뷰 실행
- `/commit` - 커밋 생성
- `/pr` - PR 생성

## 프로젝트별 설정

### serverpod_clickhouse 전용

- **테스트 명령어**: `dart test`
- **분석 명령어**: `dart analyze`
- **브랜치 전략**: `feature/<issue>-<slug>`, `fix/<issue>-<slug>`
- **PR 대상**: `main` 브랜치
