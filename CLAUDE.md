# CLAUDE.md

> 이 파일은 Claude Code가 프로젝트 컨텍스트를 이해하는 데 사용됩니다.

## 프로젝트 개요

**serverpod_clickhouse** - PostgreSQL 기반 Serverpod 서비스에 ClickHouse 분석 레이어를 추가하는 범용 Dart 패키지

### 주요 사용 사례
- 제품 분석 (Product Analytics)
- 행동 분석 (Behavioral Analytics)
- 매출/비즈니스 대시보드
- 실시간 이벤트 트래킹
- A/B 테스트 분석
- 퍼널/리텐션 분석

---

## 아키텍처

```
┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│ Flutter App │────▶│  Serverpod  │────▶│   PostgreSQL    │
│             │     │   Server    │     │   (운영 DB)      │
└──────┬──────┘     └──────┬──────┘     └────────┬────────┘
       │                   │                     │
       │                   │                     │ CDC/ETL
       ▼                   ▼                     ▼
  my_project_client   serverpod_clickhouse   ClickHouse
  (자동 생성)          _server               (분석 DB)
```

---

## 패키지 구조: 단일 서버 패키지

Serverpod가 Endpoint 기반으로 클라이언트 코드를 **자동 생성**하므로, 별도의 client/shared 패키지는 **불필요**.

```
serverpod_clickhouse/
└── serverpod_clickhouse_server/      # 서버 전용 (이게 전부!)
    ├── lib/
    │   ├── serverpod_clickhouse_server.dart
    │   └── src/
    │       ├── business/             # 비즈니스 로직
    │       │   ├── clickhouse_client.dart
    │       │   ├── event_tracker.dart
    │       │   ├── analytics_queries.dart
    │       │   └── schema_manager.dart
    │       ├── endpoints/            # Serverpod Endpoints
    │       │   ├── events_endpoint.dart
    │       │   └── analytics_endpoint.dart
    │       ├── models/               # .spy.yaml (Postgres 메타데이터)
    │       │   ├── sync_log.spy.yaml
    │       │   └── batch_status.spy.yaml
    │       └── generated/            # Serverpod 자동 생성
    └── pubspec.yaml
```

### 왜 client/shared 패키지가 없는가?

```
Flutter App
    │
    ▼
my_project_client  ◀── `serverpod generate`로 자동 생성
    │                   (ClickHouseAnalyticsEndpoint 포함)
    ▼
Serverpod Server
    │
    ▼
serverpod_clickhouse_server ──▶ ClickHouse
```

- Serverpod가 Endpoint 반환 타입을 자동으로 클라이언트에 생성
- 복잡한 타입도 `.spy.yaml`로 정의하면 자동 직렬화
- 별도 패키지 유지보수 부담 없음

---

## Serverpod 통합 설계

### 1. Postgres 메타데이터 테이블 (.spy.yaml)

ClickHouse 동기화 상태/로그는 Serverpod ORM으로 관리:

```yaml
# lib/src/models/sync_log.spy.yaml
class: ClickHouseSyncLog
table: serverpod_clickhouse_sync_log
fields:
  tableName: String
  lastSyncedAt: DateTime
  rowsSynced: int
  status: String          # pending, completed, failed
  errorMessage: String?
indexes:
  sync_log_table_idx:
    fields: tableName
```

```yaml
# lib/src/models/batch_status.spy.yaml  
class: ClickHouseBatchStatus
table: serverpod_clickhouse_batch_status
fields:
  batchId: String
  eventCount: int
  createdAt: DateTime
  sentAt: DateTime?
  status: String          # buffered, sending, sent, failed
  retryCount: int
```

### 2. Endpoint 설계 (상속 가능)

```dart
// lib/src/endpoints/analytics_endpoint.dart
class ClickHouseAnalyticsEndpoint extends Endpoint {
  late final AnalyticsQueryBuilder _analytics;
  
  @override
  void initialize(Server server, String name, String? moduleName) {
    super.initialize(server, name, moduleName);
    _analytics = AnalyticsQueryBuilder(_getClient());
  }
  
  /// DAU 조회 - 반환 타입은 Serverpod가 자동으로 클라이언트에 생성
  Future<List<DailyActiveUsers>> dau(Session session, {int days = 30}) async {
    final result = await _analytics.dau(days: days);
    return result.rows.map((r) => DailyActiveUsers.fromMap(r)).toList();
  }
  
  /// 퍼널 분석
  Future<FunnelAnalysis> funnel(
    Session session, 
    List<String> steps, {
    int days = 7,
  }) async {
    return _analytics.funnel(steps: steps, days: days);
  }
}

// 사용자가 상속해서 확장 가능
class MyAnalyticsEndpoint extends ClickHouseAnalyticsEndpoint {
  Future<MyCustomMetric> myCustomMetric(Session session) async {
    // 프로젝트별 커스텀 메트릭
  }
}
```

### 3. 이벤트 수집 Endpoint

```dart
// lib/src/endpoints/events_endpoint.dart
class ClickHouseEventsEndpoint extends Endpoint {
  late final EventTracker _tracker;
  
  /// 단일 이벤트 추적
  Future<void> track(
    Session session,
    String eventName, {
    Map<String, dynamic>? properties,
  }) async {
    final userId = await session.auth.authenticatedUserId;
    _tracker.track(
      eventName,
      userId: userId?.toString(),
      sessionId: session.sessionId,
      properties: properties ?? {},
    );
  }
  
  /// 배치 이벤트 추적
  Future<void> trackBatch(
    Session session,
    List<Map<String, dynamic>> events,
  ) async {
    for (final event in events) {
      _tracker.track(
        event['name'] as String,
        properties: event['properties'] as Map<String, dynamic>?,
      );
    }
  }
}
```

---

## 사용자 설치 플로우

### Step 1: 의존성 추가 (서버만!)

```yaml
# my_server/pubspec.yaml
dependencies:
  serverpod_clickhouse_server: ^1.0.0
```

### Step 2: generator.yaml에 모듈 등록

```yaml
# config/generator.yaml
modules:
  serverpod_clickhouse:
    nickname: ch
```

### Step 3: 코드 생성 & 마이그레이션

```bash
dart pub get
serverpod generate
serverpod create-migration
dart bin/main.dart --apply-migrations
```

### Step 4: 서버에서 초기화

```dart
// server.dart
import 'package:serverpod_clickhouse_server/serverpod_clickhouse_server.dart';

void run(List<String> args) async {
  final pod = Serverpod(...);
  
  // ClickHouse 초기화
  await ClickHouseService.initialize(
    host: pod.getPassword('clickhouse_host')!,
    database: pod.getPassword('clickhouse_database')!,
    username: pod.getPassword('clickhouse_username')!,
    password: pod.getPassword('clickhouse_password')!,
  );
  
  await pod.start();
}
```

### Step 5: Flutter 앱에서 사용

```dart
// Flutter 앱 - my_project_client 사용 (자동 생성됨)
final dau = await client.ch.analytics.dau(days: 30);
final funnel = await client.ch.analytics.funnel(['signup', 'purchase']);
await client.ch.events.track('button_click', properties: {'button': 'buy'});
```

---

## 핵심 설계 결정

### 1. 단일 서버 패키지
- `serverpod_clickhouse_server` 하나만 배포
- client/shared는 Serverpod codegen이 자동 처리
- 유지보수 간소화

### 2. HTTP 직접 호출 (gRPC 대신)
- gRPC는 proto 생성, 서버 설정 등 복잡도가 높음
- 분석 쿼리는 초 단위 응답이라 성능 이점 미미
- HTTP 인터페이스: 포트 8123(HTTP), 8443(HTTPS)

### 3. 하이브리드 DB 구조
- **PostgreSQL**: 운영 DB (Serverpod 필수), 동기화 메타데이터
- **ClickHouse**: 분석 전용 (이벤트, 집계, 대시보드)

---

## 구현 컴포넌트

### 1. ClickHouseClient
```dart
class ClickHouseConfig {
  final String host;
  final int port;           // 8443 (Cloud), 8123 (local)
  final String database;
  final String username;
  final String password;
  final bool useSsl;
  
  factory ClickHouseConfig.cloud({...});
  factory ClickHouseConfig.local({...});
}

class ClickHouseClient {
  Future<ClickHouseResult> query(String sql, {Map<String, dynamic>? params});
  Future<void> insert(String table, Map<String, dynamic> row);
  Future<void> insertBatch(String table, List<Map<String, dynamic>> rows);
  Future<void> execute(String sql);
  Future<bool> ping();
}
```

### 2. EventTracker
```dart
class EventTracker {
  void track(String eventName, {String? userId, Map<String, dynamic>? properties});
  void trackScreenView(String screenName, {...});
  void trackConversion(String type, {double? value, ...});
  Future<void> flush();
  Future<void> shutdown();
}
```

### 3. AnalyticsQueryBuilder
```dart
class AnalyticsQueryBuilder {
  Future<ClickHouseResult> dau({int days = 30});
  Future<ClickHouseResult> wau({int weeks = 12});
  Future<ClickHouseResult> mau({int months = 12});
  Future<FunnelResult> funnel({required List<String> steps, int days = 7});
  Future<ClickHouseResult> cohortRetention({...});
  Future<ClickHouseResult> nDayRetention({List<int> days = [1, 7, 30]});
  Future<ClickHouseResult> dailyRevenue({int days = 30});
  Future<ClickHouseResult> arpu({int months = 6});
}
```

### 4. SchemaManager
```dart
class SchemaManager {
  Future<void> createEventsTable({String tableName = 'events', int ttlDays = 180});
  Future<void> createOrdersTable({...});
  Future<void> initializeSchema();
}
```

---

## ClickHouse 테이블 스키마

### events (행동 이벤트)
```sql
CREATE TABLE events (
    event_id UUID DEFAULT generateUUIDv4(),
    event_name LowCardinality(String),
    user_id String,
    session_id String,
    timestamp DateTime64(3) DEFAULT now64(3),
    properties String CODEC(ZSTD(1)),
    device_type LowCardinality(String),
    app_version LowCardinality(String)
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (user_id, timestamp, event_id)
TTL timestamp + INTERVAL 180 DAY
```

### orders (매출 분석)
```sql
CREATE TABLE orders (
    order_id String,
    user_id String,
    total_amount Decimal64(2),
    status LowCardinality(String),
    created_at DateTime64(3)
)
ENGINE = ReplacingMergeTree(_synced_at)
PARTITION BY toYYYYMM(created_at)
ORDER BY (user_id, created_at, order_id)
```

---

## ClickHouse 타입 매핑

| ClickHouse | Dart |
|------------|------|
| String | String |
| UInt8/16/32 | int |
| UInt64/128/256 | BigInt or String |
| Float32/64 | double |
| DateTime64 | DateTime |
| Decimal64 | double |
| Array(T) | List<T> |
| Nullable(T) | T? |
| LowCardinality(T) | T (투명) |

---

## 참고 자료

- [Serverpod Modules](https://docs.serverpod.dev/concepts/modules)
- [Serverpod Endpoint Inheritance](https://docs.serverpod.dev/concepts/working-with-endpoints#endpoint-method-inheritance)
- [ClickHouse HTTP 인터페이스](https://clickhouse.com/docs/interfaces/http)
- [ClickHouse Cloud API](https://clickhouse.com/docs/cloud/manage/api/api-overview)

## 관련 프로젝트

- **mcp_analytics_advisor_dart**: 새 기능 분석 설계 제안 MCP 서버
  - 위치: `/Users/dongwoo/Development/cocode/mcp_analytics_advisor_dart/`
  - 기능: 기능 설명 → 이벤트/스키마/메트릭/쿼리 자동 생성
