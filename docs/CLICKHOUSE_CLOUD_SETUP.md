# ClickHouse Cloud + ClickPipes CDC 설정 가이드

Serverpod 프로젝트에 ClickHouse Cloud와 ClickPipes CDC를 설정하는 가이드입니다.

## 목차

1. [아키텍처 개요](#아키텍처-개요)
2. [ClickHouse Cloud 설정](#1-clickhouse-cloud-설정)
3. [RDS PostgreSQL CDC 설정](#2-rds-postgresql-cdc-설정)
4. [ClickPipes CDC 설정](#3-clickpipes-cdc-설정)
5. [Serverpod 서버 설정](#4-serverpod-서버-설정)
6. [테이블 동기화 전략](#5-테이블-동기화-전략)
7. [비용 예상](#6-비용-예상)
8. [체크리스트](#7-체크리스트)
9. [문제 해결](#8-문제-해결)
10. [참고 자료](#9-참고-자료)

---

## 아키텍처 개요

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Flutter App    │────▶│  Serverpod      │────▶│  PostgreSQL     │
│                 │     │  Server         │     │  (RDS)          │
└─────────────────┘     └────────┬────────┘     └────────┬────────┘
                                 │                       │
                                 │ HTTP/HTTPS            │ CDC (ClickPipes)
                                 │                       │
                                 ▼                       ▼
                        ┌─────────────────────────────────────────┐
                        │          ClickHouse Cloud               │
                        │          (분석 전용 DB)                  │
                        │                                         │
                        │  ┌─────────────┐    ┌────────────────┐  │
                        │  │   events    │    │ CDC 복제 테이블 │  │
                        │  │  (직접 삽입) │    │   (자동 동기화) │  │
                        │  └─────────────┘    └────────────────┘  │
                        └─────────────────────────────────────────┘
```

### 데이터 흐름

| 경로 | 설명 | 용도 |
|------|------|------|
| App → Serverpod → ClickHouse | 이벤트 직접 전송 | 행동 분석, 클릭 추적 |
| PostgreSQL → ClickPipes → ClickHouse | CDC 자동 동기화 | 매출 분석, 마스터 데이터 |

---

## 1. ClickHouse Cloud 설정

### Step 1: ClickHouse Cloud 가입

1. https://clickhouse.cloud 접속
2. "Start Free" 클릭
3. Google/GitHub 또는 이메일로 가입
4. **무료 크레딧 $300 제공**

### Step 2: 서비스 생성

1. "New Service" 클릭
2. 설정:
   - **Cloud Provider**: AWS (권장) 또는 GCP
   - **Region**: 앱 서버와 가까운 리전 선택
     - 한국: `Asia Pacific (Seoul) ap-northeast-2`
     - 일본: `Asia Pacific (Tokyo) ap-northeast-1`
     - 미국: `US East (N. Virginia) us-east-1`
   - **Service Name**: `{project_name}-analytics`
   - **Tier**: Development (시작용) 또는 Production
3. "Create Service" 클릭
4. **연결 정보 저장** (중요!):

```
Host: xxx.{region}.aws.clickhouse.cloud
Port: 8443
Username: default
Password: (자동 생성됨 - 반드시 저장)
```

### Step 3: 데이터베이스 및 테이블 생성

ClickHouse Cloud Console의 **SQL Console**에서 실행:

```sql
-- 1. 데이터베이스 생성
CREATE DATABASE IF NOT EXISTS analytics;

-- 2. 이벤트 테이블 생성 (serverpod_clickhouse용)
CREATE TABLE IF NOT EXISTS analytics.events (
    event_id UUID DEFAULT generateUUIDv4(),
    event_name LowCardinality(String),
    user_id String,
    session_id String,
    timestamp DateTime64(3) DEFAULT now64(3),
    properties String CODEC(ZSTD(1)),
    context String CODEC(ZSTD(1)),
    device_type LowCardinality(String) DEFAULT '',
    app_version LowCardinality(String) DEFAULT ''
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (event_name, user_id, timestamp)
TTL timestamp + INTERVAL 180 DAY;

-- 3. 주문/매출 테이블 (CDC 또는 직접 삽입용)
CREATE TABLE IF NOT EXISTS analytics.orders (
    order_id String,
    user_id String,
    total_amount Decimal64(2),
    currency LowCardinality(String) DEFAULT 'KRW',
    status LowCardinality(String),
    created_at DateTime64(3),
    _synced_at DateTime64(3) DEFAULT now64(3)
)
ENGINE = ReplacingMergeTree(_synced_at)
PARTITION BY toYYYYMM(created_at)
ORDER BY (user_id, created_at, order_id);
```

### Step 4: 연결 테스트

```sql
-- 버전 확인
SELECT version();

-- 테이블 확인
SHOW TABLES FROM analytics;

-- 테스트 데이터 삽입
INSERT INTO analytics.events (event_name, user_id, session_id)
VALUES ('test_event', 'user_001', 'session_001');

-- 조회
SELECT * FROM analytics.events;
```

---

## 2. RDS PostgreSQL CDC 설정

ClickPipes CDC를 사용하려면 PostgreSQL에서 논리적 복제(Logical Replication)를 활성화해야 합니다.

### Step 1: RDS Parameter Group 수정

1. AWS Console → RDS → Parameter Groups
2. 프로젝트에서 사용 중인 Parameter Group 선택 (또는 새로 생성)
3. `rds.logical_replication` 검색
4. 값을 `1`로 변경
5. **RDS 인스턴스 재부팅 필요!**

> **주의**: 재부팅 시 1-3분간 다운타임 발생

### Step 2: CDC 전용 사용자 생성

RDS에 접속하여 실행:

```sql
-- 1. 복제 권한을 가진 사용자 생성
CREATE USER clickpipes_user WITH REPLICATION PASSWORD 'secure_password_here';

-- 2. 스키마 접근 권한
GRANT USAGE ON SCHEMA public TO clickpipes_user;
GRANT USAGE ON SCHEMA serverpod TO clickpipes_user;

-- 3. 테이블 읽기 권한 (CDC 대상 테이블만)
-- 예시: 주문, 사용자, 상품 테이블
GRANT SELECT ON public.orders TO clickpipes_user;
GRANT SELECT ON public.users TO clickpipes_user;
GRANT SELECT ON public.products TO clickpipes_user;
GRANT SELECT ON serverpod.serverpod_user_info TO clickpipes_user;

-- 4. Publication 생성 (CDC 대상 테이블 지정)
CREATE PUBLICATION analytics_pub FOR TABLE
    public.orders,
    public.users,
    public.products,
    serverpod.serverpod_user_info;
```

### Step 3: RDS 보안 그룹 설정

1. AWS Console → EC2 → Security Groups
2. RDS 보안 그룹 선택
3. Inbound Rules → Edit
4. 추가:
   - **Type**: PostgreSQL
   - **Port**: 5432
   - **Source**: ClickHouse Cloud IP 범위

ClickHouse Cloud IP 범위 확인:
- ClickHouse Console → Settings → Networking → IP Access List

> **팁**: Production 환경에서는 AWS PrivateLink 사용 권장

---

## 3. ClickPipes CDC 설정

### Step 1: ClickPipes 생성

1. ClickHouse Cloud Console → Data Sources → ClickPipes
2. "Add ClickPipe" 클릭
3. **"PostgreSQL CDC"** 선택

### Step 2: PostgreSQL 연결 설정

```yaml
Host: your-rds.xxx.{region}.rds.amazonaws.com
Port: 5432
Database: your_database  # 또는 serverpod
User: clickpipes_user
Password: <위에서 설정한 비밀번호>
SSL Mode: require
```

### Step 3: 복제할 테이블 선택

체크박스로 동기화할 테이블 선택:

```
✅ orders            - 매출 분석
✅ users             - 사용자 정보
✅ products          - 상품 정보 (마스터)
✅ serverpod_user_info - Serverpod 사용자
```

### Step 4: 대상 데이터베이스 설정

```yaml
Target Database: analytics
Table Naming: 원본 테이블명 유지  # 또는 접두사 추가
```

### Step 5: 고급 설정 (선택사항)

```yaml
# 초기 스냅샷 설정
Initial Snapshot: Enabled (권장)
Snapshot Rows per Partition: 500000

# 복제 설정
Sync Interval: 60 seconds  # 1분마다 동기화
Soft Delete: false         # 삭제된 행 처리 방식
```

### Step 6: 생성 및 모니터링

1. "Validate" 클릭하여 연결 테스트
2. 모든 검증 통과 확인
3. "Create ClickPipe" 클릭
4. 초기 스냅샷 진행 상태 모니터링 (대용량 테이블은 수 분 소요)

---

## 4. Serverpod 서버 설정

### passwords.yaml 설정

```yaml
# config/passwords.yaml

development:
  clickhouse_host: 'localhost'
  clickhouse_port: '8123'
  clickhouse_database: 'analytics'
  clickhouse_username: 'default'
  clickhouse_password: ''
  clickhouse_use_ssl: 'false'

staging:
  clickhouse_host: 'xxx.{region}.aws.clickhouse.cloud'
  clickhouse_port: '8443'
  clickhouse_database: 'analytics'
  clickhouse_username: 'default'
  clickhouse_password: '<ClickHouse Cloud 비밀번호>'
  clickhouse_use_ssl: 'true'

production:
  clickhouse_host: 'xxx.{region}.aws.clickhouse.cloud'
  clickhouse_port: '8443'
  clickhouse_database: 'analytics'
  clickhouse_username: 'default'
  clickhouse_password: '<ClickHouse Cloud 비밀번호>'
  clickhouse_use_ssl: 'true'
```

### 서버 초기화

```dart
// server.dart
import 'package:serverpod_clickhouse/serverpod_clickhouse.dart';

void run(List<String> args) async {
  final pod = Serverpod(...);

  // ClickHouse 초기화
  await ClickHouseService.initialize(pod);

  // 연결 테스트
  final connected = await ClickHouseService.instance.client.ping();
  print('ClickHouse connected: $connected');

  await pod.start();
}
```

### 환경별 동작

| 환경 | ClickHouse | 동작 |
|------|------------|------|
| development | Local (Docker) | 로컬 테스트 |
| staging | ClickHouse Cloud | CDC 동기화 테스트 |
| production | ClickHouse Cloud | 실서비스 |

---

## 5. 테이블 동기화 전략

### 직접 삽입 vs CDC

| 방식 | 테이블 유형 | 예시 |
|------|------------|------|
| **직접 삽입** | 이벤트, 로그 | events, api_logs, errors |
| **CDC (ClickPipes)** | 트랜잭션, 마스터 | orders, users, products |

### 추천 테이블 분류

#### 직접 삽입 (EventTracker 사용)

```dart
// 이벤트 데이터 - 앱에서 직접 전송
tracker.track('page_view', userId: 'user_123');
tracker.track('button_click', properties: {'button': 'buy'});
```

| 테이블 | 설명 | 특징 |
|--------|------|------|
| events | 행동 이벤트 | 대용량, Append-only |
| api_logs | API 성능 로그 | 시계열 데이터 |
| errors | 에러 로그 | 빠른 삽입 필요 |

#### CDC 동기화 (ClickPipes)

| 테이블 | 설명 | 특징 |
|--------|------|------|
| orders | 주문/매출 | 트랜잭션, UPDATE 있음 |
| users | 사용자 정보 | 마스터 데이터 |
| products | 상품 정보 | 마스터 데이터 |
| subscriptions | 구독 정보 | 상태 변경 추적 |

### CDC 테이블 ClickHouse 스키마

CDC로 동기화되는 테이블은 ReplacingMergeTree 사용:

```sql
-- PostgreSQL orders 테이블과 매칭
CREATE TABLE analytics.orders (
    id Int64,
    user_id Int64,
    total_amount Decimal64(2),
    status String,
    created_at DateTime64(3),
    updated_at DateTime64(3),
    -- CDC 메타데이터 (ClickPipes가 자동 추가)
    _peerdb_synced_at DateTime64(3),
    _peerdb_is_deleted UInt8
)
ENGINE = ReplacingMergeTree(_peerdb_synced_at)
PARTITION BY toYYYYMM(created_at)
ORDER BY id;
```

---

## 6. 비용 예상

### ClickHouse Cloud 요금

| 티어 | 월 비용 | 용도 |
|------|---------|------|
| Development | $50-100 | 개발/스테이징 |
| Production (Small) | $200-500 | 소규모 서비스 |
| Production (Medium) | $500-1500 | 중규모 서비스 |

### 추가 비용

| 항목 | 비용 | 비고 |
|------|------|------|
| ClickPipes CDC | 무료 | 2025.09까지 무료 |
| 데이터 전송 (인바운드) | 무료 | |
| 데이터 전송 (아웃바운드) | 일정량 무료 | 초과 시 과금 |
| 스토리지 | 포함 | 압축 후 기준 |

### 비용 절감 팁

1. **TTL 설정**: 오래된 데이터 자동 삭제
2. **ZSTD 압축**: 스토리지 50-80% 절감
3. **LowCardinality**: 반복 문자열 최적화
4. **Development 티어**: 개발 환경에서 사용

---

## 7. 체크리스트

### ClickHouse Cloud 설정

- [ ] ClickHouse Cloud 계정 생성
- [ ] 앱 서버와 같은 리전에 서비스 생성
- [ ] 연결 정보 저장 (host, port, password)
- [ ] analytics 데이터베이스 생성
- [ ] events 테이블 생성

### RDS PostgreSQL 설정

- [ ] `rds.logical_replication = 1` 설정
- [ ] RDS 인스턴스 재부팅
- [ ] `clickpipes_user` 사용자 생성
- [ ] 테이블 SELECT 권한 부여
- [ ] Publication 생성
- [ ] 보안 그룹 인바운드 규칙 추가

### ClickPipes CDC 설정

- [ ] PostgreSQL CDC ClickPipe 생성
- [ ] 연결 테스트 통과
- [ ] 동기화 테이블 선택
- [ ] 초기 스냅샷 완료 확인
- [ ] 실시간 동기화 확인

### Serverpod 서버

- [ ] passwords.yaml 업데이트 (development/staging/production)
- [ ] 서버 재시작
- [ ] ClickHouse 연결 테스트 (`ping()`)
- [ ] 이벤트 전송 테스트

---

## 8. 문제 해결

### 연결 실패

```
ClickHouseException: Connection refused
```

**해결**:
1. Host/Port 확인 (Cloud는 8443, Local은 8123)
2. 보안 그룹 확인
3. SSL 설정 확인 (`useSsl: true` for Cloud)

### CDC 동기화 지연

```
ClickPipes: Replication lag > 5 minutes
```

**해결**:
1. RDS 성능 확인 (CPU, IOPS)
2. ClickPipes 로그 확인
3. 대용량 테이블은 배치 크기 조정

### Publication 없음 에러

```
ERROR: publication "analytics_pub" does not exist
```

**해결**:
```sql
CREATE PUBLICATION analytics_pub FOR TABLE
    public.orders,
    public.users;
```

### 논리적 복제 비활성화

```
ERROR: logical decoding requires wal_level >= logical
```

**해결**:
1. RDS Parameter Group에서 `rds.logical_replication = 1` 설정
2. RDS 인스턴스 재부팅

---

## 9. 참고 자료

### 공식 문서

- [ClickHouse Cloud 시작하기](https://clickhouse.com/docs/cloud/get-started)
- [ClickPipes PostgreSQL CDC](https://clickhouse.com/docs/integrations/clickpipes/postgres)
- [AWS RDS 논리적 복제](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html#PostgreSQL.Concepts.General.FeatureSupport.LogicalReplication)

### ClickHouse 블로그

- [ClickPipes PostgreSQL CDC GA](https://clickhouse.com/blog/postgres-cdc-connector-clickpipes-ga)
- [PostgreSQL CDC Year in Review 2025](https://clickhouse.com/blog/postgres-cdc-year-in-review-2025)

### Serverpod

- [Serverpod Modules](https://docs.serverpod.dev/concepts/modules)
- [Serverpod Configuration](https://docs.serverpod.dev/concepts/configuration)

---

## 다음 단계

1. [BI 이벤트 가이드](./BI_EVENTS_GUIDE.md) - 이벤트 추적 구현
2. [Flutter 통합 가이드](./BI_EVENTS_GUIDE.md#flutter-통합-가이드) - 앱 자동 추적 설정
3. [분석 쿼리 사용법](../README.md#분석-쿼리) - DAU, 퍼널, 리텐션 분석
