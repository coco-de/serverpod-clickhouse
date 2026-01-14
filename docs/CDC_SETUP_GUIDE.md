# ClickHouse Cloud + ClickPipes CDC 설정 가이드

PostgreSQL (AWS RDS)에서 ClickHouse Cloud로 실시간 데이터 동기화를 위한 상세 가이드입니다.

## 목차

1. [개요](#1-개요)
2. [사전 요구사항](#2-사전-요구사항)
3. [ClickHouse Cloud 설정](#3-clickhouse-cloud-설정)
4. [RDS PostgreSQL CDC 설정](#4-rds-postgresql-cdc-설정)
5. [ClickPipes CDC 연결](#5-clickpipes-cdc-연결)
6. [Serverpod 통합](#6-serverpod-통합)
7. [모니터링 및 운영](#7-모니터링-및-운영)
8. [트러블슈팅](#8-트러블슈팅)
9. [비용 및 성능](#9-비용-및-성능)

---

## 1. 개요

### CDC (Change Data Capture)란?

CDC는 소스 데이터베이스의 변경사항(INSERT, UPDATE, DELETE)을 실시간으로 캡처하여 대상 시스템에 복제하는 기술입니다.

### 아키텍처

```
┌─────────────────┐     CDC      ┌──────────────────┐     Query     ┌─────────────┐
│  PostgreSQL     │ ──────────▶  │  ClickHouse      │ ◀──────────── │  Analytics  │
│  (RDS)          │  ClickPipes  │  Cloud           │               │  Dashboard  │
│  - OLTP 워크로드 │              │  - OLAP 워크로드  │               │  - Metabase │
└─────────────────┘              └──────────────────┘               │  - Grafana  │
                                                                    └─────────────┘
```

### 왜 이 구성인가?

| 구성 요소 | 선택 이유 |
|----------|----------|
| **ClickHouse Cloud** | 관리형 서비스, 자동 스케일링, ClickPipes 내장 |
| **ClickPipes** | 코드 없이 CDC 설정, PeerDB 기반, 안정적 |
| **AWS RDS** | 관리형 PostgreSQL, Logical Replication 지원 |

---

## 2. 사전 요구사항

### AWS 요구사항

- [ ] AWS RDS PostgreSQL 11+ (권장: 14+)
- [ ] RDS 인스턴스가 Public Accessible (또는 VPC Peering)
- [ ] Security Group에서 ClickHouse Cloud IP 허용

### ClickHouse Cloud 요구사항

- [ ] ClickHouse Cloud 계정 (https://clickhouse.cloud)
- [ ] 서비스 생성 완료
- [ ] 연결 정보 확보 (Host, Password)

### 권한 요구사항

- [ ] RDS 마스터 사용자 접근 권한
- [ ] AWS CLI 설정 (선택사항)

---

## 3. ClickHouse Cloud 설정

### 3.1 계정 생성 및 서비스 생성

#### 옵션 A: AWS Marketplace (PAYG)

```
1. AWS Marketplace에서 "ClickHouse Cloud" 검색
2. Subscribe 클릭
3. ClickHouse Cloud Console로 리다이렉트
4. 서비스 생성
```

**장점**: AWS 통합 결제, 기존 AWS 크레딧 사용 가능

#### 옵션 B: ClickHouse Cloud 직접 가입

```
1. https://clickhouse.cloud 접속
2. "Start Free" 클릭
3. Google/GitHub/이메일로 가입
4. $300 무료 크레딧 제공
```

### 3.2 서비스 생성

```
1. "New Service" 클릭
2. 설정:
   - Cloud Provider: AWS
   - Region: ap-northeast-2 (Seoul) ← RDS와 같은 리전 권장
   - Service Name: {project}-analytics-{env}
   - Tier: Development (시작) 또는 Production
3. "Create Service" 클릭
4. 연결 정보 저장
```

### 3.3 연결 정보 확인

서비스 생성 후 **Connect** 탭에서 확인:

| 항목 | 예시 |
|------|------|
| Host | `abc123.ap-northeast-2.aws.clickhouse.cloud` |
| Port | `8443` (HTTPS) |
| Username | `default` |
| Password | (자동 생성, 복사 저장) |

### 3.4 데이터베이스 생성

```bash
# 연결 테스트
curl --user 'default:{PASSWORD}' \
  --data-binary 'SELECT 1' \
  https://{HOST}:8443

# 분석용 데이터베이스 생성
curl --user 'default:{PASSWORD}' \
  --data-binary 'CREATE DATABASE IF NOT EXISTS {PROJECT}_analytics' \
  https://{HOST}:8443
```

---

## 4. RDS PostgreSQL CDC 설정

### 4.1 Logical Replication 활성화

#### Step 1: Parameter Group 확인

```bash
# 현재 파라미터 그룹 확인
aws rds describe-db-instances \
  --db-instance-identifier {RDS_INSTANCE} \
  --query 'DBInstances[0].DBParameterGroups[0].DBParameterGroupName'

# logical_replication 상태 확인
aws rds describe-db-parameters \
  --db-parameter-group-name {PARAMETER_GROUP} \
  --query "Parameters[?ParameterName=='rds.logical_replication']"
```

#### Step 2: Logical Replication 활성화

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name {PARAMETER_GROUP} \
  --parameters "ParameterName=rds.logical_replication,ParameterValue=1,ApplyMethod=pending-reboot"
```

#### Step 3: RDS 재부팅 (필수)

```bash
# 재부팅 (다운타임 발생)
aws rds reboot-db-instance --db-instance-identifier {RDS_INSTANCE}

# 상태 확인
aws rds describe-db-instances \
  --db-instance-identifier {RDS_INSTANCE} \
  --query 'DBInstances[0].DBInstanceStatus'
```

#### Step 4: 설정 확인

```sql
-- PostgreSQL에서 확인
SHOW wal_level;  -- 'logical' 이어야 함
```

### 4.2 CDC 전용 사용자 생성

```sql
-- 1. CDC 전용 사용자 생성
CREATE USER clickpipes_user WITH PASSWORD '{SECURE_PASSWORD}';

-- 2. RDS 복제 역할 부여
GRANT rds_replication TO clickpipes_user;

-- 3. 스키마 접근 권한
GRANT USAGE ON SCHEMA public TO clickpipes_user;

-- 4. 모든 테이블 SELECT 권한
GRANT SELECT ON ALL TABLES IN SCHEMA public TO clickpipes_user;

-- 5. 시퀀스 권한 (필요시)
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO clickpipes_user;
```

### 4.3 Publication 생성

#### 옵션 A: 특정 테이블만 복제 (권장)

```sql
-- 분석에 필요한 테이블만 선택
CREATE PUBLICATION analytics_pub FOR TABLE
  public.users,
  public.orders,
  public.payments,
  public.events;
```

#### 옵션 B: 전체 테이블 복제

```sql
-- 모든 테이블 복제 (주의: 데이터 양 증가)
CREATE PUBLICATION analytics_pub FOR ALL TABLES;
```

#### Publication 확인

```sql
-- Publication 목록
SELECT * FROM pg_publication;

-- Publication에 포함된 테이블
SELECT * FROM pg_publication_tables WHERE pubname = 'analytics_pub';
```

### 4.4 Security Group 설정

ClickHouse Cloud에서 RDS로 접근할 수 있도록 Security Group 설정:

```bash
# ClickHouse Cloud Seoul 리전 IP 확인
# https://clickhouse.com/docs/en/cloud/security/cloud-endpoints-api

# Security Group Inbound Rule 추가
aws ec2 authorize-security-group-ingress \
  --group-id {SECURITY_GROUP_ID} \
  --protocol tcp \
  --port 5432 \
  --cidr {CLICKHOUSE_IP}/32
```

**ClickHouse Cloud Seoul (ap-northeast-2) Egress IPs:**
- 확인 방법: ClickHouse Cloud Console → Settings → IP Access List

---

## 5. ClickPipes CDC 연결

### 5.1 ClickPipe 생성

```
1. ClickHouse Cloud Console 접속
2. Data Sources → ClickPipes → Add ClickPipe
3. "PostgreSQL CDC" 선택
```

### 5.2 연결 정보 입력

| 필드 | 값 | 설명 |
|------|-----|------|
| ClickPipe name | `{project}-{env}-cdc` | 식별하기 쉬운 이름 |
| Host | `{rds-endpoint}.rds.amazonaws.com` | RDS Public Endpoint |
| Port | `5432` | PostgreSQL 기본 포트 |
| Database | `{database_name}` | 데이터베이스 이름 |
| User | `clickpipes_user` | CDC 전용 사용자 |
| Password | `{password}` | CDC 사용자 비밀번호 |
| SSL Mode | `require` | RDS는 SSL 필수 |

### 5.3 Replication 설정

| 필드 | 권장 값 | 설명 |
|------|---------|------|
| Publication | `{publication_name}` | 생성한 Publication 선택 |
| Replication method | `Initial load + CDC` | 기존 데이터 + 실시간 변경 |
| Sync interval | `60` | 동기화 주기 (초) |
| Parallel threads | `4` | 초기 로드 병렬 처리 |

### 5.4 테이블 설정

| 옵션 | 권장 | 이유 |
|------|------|------|
| Target Database | `{project}_analytics` | 분석 전용 DB |
| Prefix with schema name | OFF | 깔끔한 테이블명 |
| Preserve NULL values | ON | NULL 값 분석에 유용 |

### 5.5 PostgreSQL 설정 권장사항

ClickPipes에서 다음 경고가 표시될 수 있습니다:

| 설정 | 현재 | 권장 | 영향도 |
|------|------|------|--------|
| `max_slot_wal_keep_size` | -1 | 설정 권장 | 낮음 (디스크) |
| `wal_sender_timeout` | 30000ms | 0 | 중간 (연결 안정성) |
| `statement_timeout` | 미설정 | 설정 권장 | 낮음 |
| `idle_in_transaction_session_timeout` | 86400000ms | 낮게 | 낮음 |

**Staging에서는 기본값으로 진행 가능**, Production에서는 조정 권장.

---

## 6. Serverpod 통합

### 6.1 serverpod-clickhouse 패키지 추가

```yaml
# pubspec.yaml
dependencies:
  serverpod_clickhouse:
    path: /path/to/serverpod-clickhouse
    # 또는 git:
    #   url: https://github.com/your-org/serverpod-clickhouse.git
```

### 6.2 환경 설정

```yaml
# config/passwords.yaml
staging:
  clickhouse_host: "{HOST}.ap-northeast-2.aws.clickhouse.cloud"
  clickhouse_port: "8443"
  clickhouse_database: "{project}_analytics"
  clickhouse_user: "default"
  clickhouse_password: "{PASSWORD}"

production:
  clickhouse_host: "{HOST}.ap-northeast-2.aws.clickhouse.cloud"
  clickhouse_port: "8443"
  clickhouse_database: "{project}_analytics"
  clickhouse_user: "default"
  clickhouse_password: "{PASSWORD}"
```

### 6.3 서버 초기화

```dart
// server.dart
import 'package:serverpod_clickhouse/serverpod_clickhouse.dart' as clickhouse;

Future<void> run(List<String> args) async {
  final pod = Serverpod(args, Protocol(), Endpoints());

  // ClickHouse 서비스 초기화
  try {
    await clickhouse.ClickHouseService.initialize(pod);
    print('✅ ClickHouse BI 서비스 초기화 성공');
  } on Exception catch (e) {
    print('❌ ClickHouse 초기화 실패: $e');
    print('서버는 계속 실행되지만 BI 기능이 비활성화됩니다.');
  }

  await pod.start();
}
```

### 6.4 분석 쿼리 예시

```dart
// CDC로 동기화된 테이블 쿼리
final result = await clickhouse.ClickHouseService.instance.query('''
  SELECT
    toDate(created_at) as date,
    count() as order_count,
    sum(amount) as total_revenue
  FROM orders
  WHERE created_at >= today() - 30
  GROUP BY date
  ORDER BY date
''');
```

---

## 7. 모니터링 및 운영

### 7.1 ClickPipes 상태 확인

```
ClickHouse Cloud Console → Data Sources → ClickPipes
```

| 상태 | 설명 |
|------|------|
| **Running** | 정상 동작 중 |
| **Syncing** | 초기 데이터 로드 중 |
| **Error** | 오류 발생 (상세 확인 필요) |
| **Paused** | 일시 중지됨 |

### 7.2 복제 지연 모니터링

```sql
-- ClickHouse에서 최신 데이터 확인
SELECT max(updated_at) as latest_update FROM orders;

-- PostgreSQL과 비교
-- (PostgreSQL)
SELECT max(updated_at) FROM orders;
```

### 7.3 PostgreSQL Replication Slot 확인

```sql
-- 복제 슬롯 상태
SELECT slot_name, active, restart_lsn, confirmed_flush_lsn
FROM pg_replication_slots;

-- WAL 지연 확인
SELECT
  slot_name,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) as replication_lag
FROM pg_replication_slots;
```

### 7.4 알림 설정

ClickHouse Cloud에서 알림 설정:

```
Settings → Alerts → Create Alert
- Replication lag > 5 minutes
- ClickPipe error
```

---

## 8. 트러블슈팅

### 8.1 연결 오류

#### "permission denied for schema public"

```sql
-- 해결: 스키마 권한 부여
GRANT USAGE ON SCHEMA public TO clickpipes_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO clickpipes_user;
```

#### "could not connect to server"

```bash
# 1. Security Group 확인
aws ec2 describe-security-groups --group-ids {SG_ID}

# 2. RDS Public Accessible 확인
aws rds describe-db-instances \
  --db-instance-identifier {RDS_INSTANCE} \
  --query 'DBInstances[0].PubliclyAccessible'

# 3. 연결 테스트
psql -h {RDS_ENDPOINT} -U clickpipes_user -d {DATABASE}
```

#### "FATAL: no pg_hba.conf entry"

```bash
# RDS는 pg_hba.conf 직접 수정 불가
# Security Group으로 IP 허용 필요
```

### 8.2 복제 오류

#### "replication slot does not exist"

```sql
-- Publication 확인
SELECT * FROM pg_publication;

-- 복제 슬롯 확인
SELECT * FROM pg_replication_slots;
```

#### "wal_level must be logical"

```bash
# RDS Parameter Group 수정 필요
aws rds modify-db-parameter-group \
  --db-parameter-group-name {PARAM_GROUP} \
  --parameters "ParameterName=rds.logical_replication,ParameterValue=1,ApplyMethod=pending-reboot"

# 재부팅 필수
aws rds reboot-db-instance --db-instance-identifier {RDS_INSTANCE}
```

### 8.3 성능 문제

#### 초기 로드가 느림

```
ClickPipes 설정에서:
- Parallel threads: 4 → 8 증가
- Snapshot rows per partition: 100000 → 500000 증가
```

#### WAL 디스크 증가

```sql
-- 사용하지 않는 복제 슬롯 삭제
SELECT pg_drop_replication_slot('unused_slot_name');
```

---

## 9. 비용 및 성능

### 9.1 ClickHouse Cloud 비용

| 티어 | 월 비용 (예상) | 적합한 사용 |
|------|---------------|------------|
| Development | $50-100 | 개발/테스트 |
| Production (Small) | $200-500 | 중소규모 서비스 |
| Production (Large) | $500+ | 대규모 분석 |

**포함 사항:**
- ClickPipes CDC: **무료** (2025.09까지)
- 스토리지: 일정량 포함
- 컴퓨팅: 사용량 기반

### 9.2 RDS 추가 비용

| 항목 | 비용 영향 |
|------|----------|
| Logical Replication | 약간의 CPU/IO 증가 |
| WAL 저장소 | 디스크 사용량 증가 가능 |
| 네트워크 | 동일 리전 무료 |

### 9.3 성능 최적화

#### ClickHouse 테이블 최적화

```sql
-- 분석에 최적화된 테이블 엔진 (자동 생성됨)
-- ReplacingMergeTree: UPDATE/DELETE 처리
-- ORDER BY: 자주 필터링하는 컬럼으로 설정
```

#### 쿼리 최적화

```sql
-- 날짜 필터 활용 (파티션 프루닝)
SELECT * FROM events
WHERE event_date >= '2025-01-01'  -- 파티션 키 활용
  AND user_id = 123;

-- 집계 쿼리 최적화
SELECT
  toStartOfHour(created_at) as hour,
  count() as cnt
FROM orders
GROUP BY hour
ORDER BY hour;
```

---

## 부록

### A. 유용한 명령어 모음

#### AWS CLI

```bash
# RDS 상태 확인
aws rds describe-db-instances --db-instance-identifier {INSTANCE}

# Parameter Group 수정
aws rds modify-db-parameter-group --db-parameter-group-name {GROUP} \
  --parameters "ParameterName=rds.logical_replication,ParameterValue=1,ApplyMethod=pending-reboot"

# RDS 재부팅
aws rds reboot-db-instance --db-instance-identifier {INSTANCE}
```

#### PostgreSQL

```sql
-- Logical Replication 상태
SHOW wal_level;

-- 복제 슬롯 확인
SELECT * FROM pg_replication_slots;

-- Publication 확인
SELECT * FROM pg_publication_tables;

-- CDC 사용자 권한 확인
SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'clickpipes_user';
```

#### ClickHouse

```sql
-- 테이블 목록
SHOW TABLES FROM {database};

-- 테이블 행 수
SELECT count() FROM {table};

-- 최신 데이터 확인
SELECT max(updated_at) FROM {table};
```

### B. 체크리스트

#### 신규 환경 설정 체크리스트

- [ ] ClickHouse Cloud 서비스 생성
- [ ] 분석용 데이터베이스 생성
- [ ] RDS `rds.logical_replication = 1` 설정
- [ ] RDS 재부팅
- [ ] CDC 사용자 생성 및 권한 부여
- [ ] Publication 생성
- [ ] Security Group 설정
- [ ] ClickPipes 생성
- [ ] 초기 데이터 로드 완료 확인
- [ ] Serverpod passwords.yaml 업데이트
- [ ] 서버 재시작 및 연결 테스트

### C. 참고 자료

- [ClickHouse Cloud 문서](https://clickhouse.com/docs/en/cloud)
- [ClickPipes PostgreSQL CDC](https://clickhouse.com/docs/en/integrations/clickpipes/postgres)
- [AWS RDS Logical Replication](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html#PostgreSQL.Concepts.General.FeatureSupport.LogicalReplication)
- [PeerDB (ClickPipes 기반)](https://docs.peerdb.io/)

---

## 변경 이력

| 날짜 | 버전 | 변경 내용 |
|------|------|----------|
| 2025-01-14 | 1.0.0 | 초기 문서 작성 |
