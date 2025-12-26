# Serverpod + ClickHouse 통합 패키지

PostgreSQL 기반의 Serverpod 서비스에 **ClickHouse 분석 레이어**를 추가합니다.

## 🎯 핵심 아키텍처

```
┌─────────────┐     ┌─────────────┐     ┌─────────────────┐
│ Flutter App │────▶│  Serverpod  │────▶│   PostgreSQL    │
│             │     │   Server    │     │   (운영 DB)      │
└─────────────┘     └──────┬──────┘     └────────┬────────┘
                           │                     │
                           │                     │ CDC/ETL
                           ▼                     ▼
                    ┌─────────────────────────────────┐
                    │         ClickHouse Cloud        │
                    │         (분석 전용 DB)          │
                    └─────────────────────────────────┘
```

## 📦 설치

```yaml
# pubspec.yaml
dependencies:
  serverpod_clickhouse:
    path: ../serverpod_clickhouse  # 또는 pub.dev 배포 후 버전 지정
```

## 🚀 빠른 시작

### 1. ClickHouse 클라이언트 설정

```dart
import 'package:serverpod_clickhouse/serverpod_clickhouse.dart';

// ClickHouse Cloud 연결
final clickhouse = ClickHouseClient(
  ClickHouseConfig.cloud(
    host: 'xxx.clickhouse.cloud',
    database: 'analytics',
    username: 'default',
    password: 'your-password',
  ),
);

// 연결 테스트
final connected = await clickhouse.ping();
print('Connected: $connected');
```

### 2. 이벤트 추적

```dart
final tracker = EventTracker(clickhouse);

// 공통 컨텍스트 설정
tracker.commonContext = {
  'app_version': '1.0.0',
  'device_type': 'mobile',
};

// 이벤트 추적
tracker.track(
  'button_click',
  userId: 'user123',
  sessionId: 'session456',
  properties: {
    'button_name': 'purchase',
    'screen': 'product_detail',
  },
);

// 화면 조회
tracker.trackScreenView('home', userId: 'user123');

// 전환 이벤트
tracker.trackConversion(
  'purchase',
  userId: 'user123',
  value: 29900,
  currency: 'KRW',
);

// 종료 시 남은 이벤트 전송
await tracker.shutdown();
```

### 3. 분석 쿼리

```dart
final analytics = AnalyticsQueryBuilder(clickhouse);

// DAU
final dau = await analytics.dau(days: 30);
for (final row in dau.rows) {
  print('${row['date']}: ${row['dau']} users');
}

// 퍼널 분석
final funnel = await analytics.funnel(
  steps: ['sign_up_started', 'email_entered', 'sign_up_completed'],
  days: 7,
);
print(funnel); // 단계별 전환율 출력

// 리텐션
final retention = await analytics.nDayRetention(
  cohortEvent: 'sign_up_completed',
  returnEvent: 'app_opened',
  days: [1, 7, 30],
);

// 매출
final revenue = await analytics.dailyRevenue(days: 30);
```

### 4. 스키마 초기화

```dart
final schema = SchemaManager(clickhouse);

// 모든 기본 테이블 생성
await schema.initializeSchema();

// 또는 개별 테이블 생성
await schema.createEventsTable(ttlDays: 180);
await schema.createOrdersTable(ttlDays: 365 * 2);
await schema.createUsersTable();
```

## 📊 기본 테이블 스키마

### events (행동 이벤트)

| 컬럼 | 타입 | 설명 |
|------|------|------|
| event_id | UUID | 이벤트 고유 ID |
| event_name | LowCardinality(String) | 이벤트 이름 |
| user_id | String | 사용자 ID |
| session_id | String | 세션 ID |
| timestamp | DateTime64(3) | 이벤트 시간 |
| properties | String (JSON) | 이벤트 속성 |
| device_type | LowCardinality(String) | 디바이스 유형 |
| app_version | LowCardinality(String) | 앱 버전 |

### orders (매출)

| 컬럼 | 타입 | 설명 |
|------|------|------|
| order_id | String | 주문 ID |
| user_id | String | 사용자 ID |
| total_amount | Decimal64(2) | 총 금액 |
| status | LowCardinality(String) | 상태 |
| created_at | DateTime64(3) | 생성 시간 |

## 🔧 Serverpod 통합

### 서비스 클래스

```dart
// lib/src/services/clickhouse_service.dart
class ClickHouseService {
  static ClickHouseService? _instance;
  static ClickHouseService get instance => _instance ??= ClickHouseService._();
  
  late final ClickHouseClient client;
  late final EventTracker tracker;
  late final AnalyticsQueryBuilder analytics;
  
  Future<void> initialize(/* config */) async {
    client = ClickHouseClient(ClickHouseConfig.cloud(...));
    tracker = EventTracker(client);
    analytics = AnalyticsQueryBuilder(client);
  }
}
```

### Endpoint 예시

```dart
class EventsEndpoint extends Endpoint {
  Future<void> track(Session session, String eventName, Map<String, dynamic>? properties) async {
    final userId = await session.auth.authenticatedUserId;
    ClickHouseService.instance.tracker.track(
      eventName,
      userId: userId?.toString(),
      properties: properties ?? {},
    );
  }
}

class AnalyticsEndpoint extends Endpoint {
  Future<List<Map<String, dynamic>>> getDau(Session session, int days) async {
    final result = await ClickHouseService.instance.analytics.dau(days: days);
    return result.rows;
  }
}
```

자세한 예시는 [example/serverpod_integration.dart](example/serverpod_integration.dart)를 참고하세요.

## 📈 지원하는 분석 쿼리

| 메서드 | 설명 |
|--------|------|
| `dau()` | 일별 활성 사용자 |
| `wau()` | 주별 활성 사용자 |
| `mau()` | 월별 활성 사용자 |
| `eventCounts()` | 이벤트별 발생 횟수 |
| `funnel()` | 퍼널 분석 (windowFunnel) |
| `cohortRetention()` | 코호트 리텐션 |
| `nDayRetention()` | N일 리텐션 (Day 1/7/30) |
| `dailyRevenue()` | 일별 매출 |
| `topProductsByRevenue()` | 상품별 매출 TOP N |
| `arpu()` | 사용자당 평균 매출 |
| `custom()` | 커스텀 SQL |

## 🔄 PostgreSQL → ClickHouse 동기화

### 옵션 1: ClickPipes (권장)

ClickHouse Cloud의 관리형 CDC 서비스를 사용합니다.

### 옵션 2: 배치 동기화

```dart
class SyncToClickHouseTask extends ScheduledTask {
  @override
  Duration get interval => Duration(minutes: 5);
  
  @override
  Future<void> run(Session session) async {
    final syncUtility = SyncUtility(ClickHouseService.instance.client);
    
    final orders = await Order.db.find(session, where: (t) => t.updatedAt > lastSync);
    await syncUtility.syncOrders(orders.map((o) => o.toMap()).toList());
  }
}
```

### 옵션 3: Debezium + Kafka

대규모 실시간 동기화가 필요한 경우.

## 🎓 Unibook RBA 적용 예시

```dart
// 학습 행동 추적
tracker.track('page_read', userId: studentId, properties: {
  'book_id': bookId,
  'page_number': pageNumber,
  'duration_seconds': duration,
});

// 학습 완료 분석
final completion = await analytics.custom('''
  SELECT 
    book_id,
    user_id,
    count(DISTINCT page_number) AS pages_read,
    sum(JSONExtractInt(properties, 'duration_seconds')) AS total_duration
  FROM events
  WHERE event_name = 'page_read'
    AND timestamp >= now() - INTERVAL 30 DAY
  GROUP BY book_id, user_id
''');
```

## 📁 프로젝트 구조

```
serverpod_clickhouse/
├── lib/
│   ├── serverpod_clickhouse.dart    # 라이브러리 export
│   └── src/
│       ├── clickhouse_client.dart   # HTTP 클라이언트
│       ├── event_tracker.dart       # 이벤트 배치 전송
│       ├── analytics_queries.dart   # 분석 쿼리 빌더
│       └── schema_manager.dart      # 스키마 관리
├── example/
│   └── serverpod_integration.dart   # Serverpod 통합 예시
├── pubspec.yaml
└── README.md
```

## 📄 License

MIT
