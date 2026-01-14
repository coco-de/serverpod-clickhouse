# Serverpod + ClickHouse 통합 패키지

[![GitHub](https://img.shields.io/badge/GitHub-coco--de%2Fserverpod__clickhouse-blue)](https://github.com/coco-de/serverpod_clickhouse)

PostgreSQL 기반의 Serverpod 서비스에 **ClickHouse 분석 레이어**를 추가합니다.

## 핵심 아키텍처

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

## 주요 기능

- **ClickHouse HTTP 클라이언트** - Cloud/Local 지원
- **이벤트 트래킹** - 배치 버퍼링, 자동 flush
- **분석 쿼리 빌더** - DAU, WAU, MAU, Funnel, Retention, 경로 분석
- **BI 이벤트 상수** - 30+ 표준 이벤트 정의
- **Serverpod Endpoints** - Events, Analytics API
- **PostgreSQL → ClickHouse 동기화** - FutureCall 기반

## 설치

### 1. 서버 의존성 추가

```yaml
# my_server/pubspec.yaml
dependencies:
  serverpod_clickhouse:
    git:
      url: https://github.com/coco-de/serverpod_clickhouse.git
```

### 2. 모듈 등록

```yaml
# config/generator.yaml
modules:
  serverpod_clickhouse:
    nickname: ch
```

### 3. ClickHouse 설정

```yaml
# config/passwords.yaml
development:
  clickhouse_host: 'xxx.clickhouse.cloud'
  clickhouse_database: 'analytics'
  clickhouse_username: 'default'
  clickhouse_password: 'your-password'
  clickhouse_use_ssl: 'true'
```

### 4. 코드 생성 & 마이그레이션

```bash
dart pub get
serverpod generate
serverpod create-migration
dart bin/main.dart --apply-migrations
```

### 5. 서버 초기화

```dart
// server.dart
import 'package:serverpod_clickhouse/serverpod_clickhouse.dart';

void run(List<String> args) async {
  final pod = Serverpod(...);
  await ClickHouseService.initialize(pod);
  await pod.start();
}
```

### 6. Flutter 클라이언트 사용

```dart
// 이벤트 추적
await client.ch.events.track(eventName: 'button_click');

// 분석 조회
final dau = await client.ch.analytics.getDau(days: 30);
```

## 빠른 시작 (Serverpod 없이)

### ClickHouse 클라이언트

```dart
import 'package:serverpod_clickhouse/serverpod_clickhouse.dart';

final clickhouse = ClickHouseClient(
  ClickHouseConfig.cloud(
    host: 'xxx.clickhouse.cloud',
    database: 'analytics',
    username: 'default',
    password: 'your-password',
  ),
);

final connected = await clickhouse.ping();
```

### 이벤트 추적

```dart
final tracker = EventTracker(clickhouse);

// BI 이벤트 상수 사용
tracker.track(
  BiEvents.buttonClick,
  userId: 'user123',
  properties: {
    BiEventProps.buttonName: 'purchase',
    BiEventProps.screenName: 'product_detail',
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

await tracker.shutdown();
```

### 분석 쿼리

```dart
final analytics = AnalyticsQueryBuilder(clickhouse);

// DAU
final dau = await analytics.dau(days: 30);

// 퍼널 분석
final funnel = await analytics.funnel(
  steps: ['sign_up_started', 'email_entered', 'sign_up_completed'],
  days: 7,
);

// N-Day 리텐션
final retention = await analytics.nDayRetention(
  cohortEvent: 'sign_up_completed',
  returnEvent: 'app_opened',
  days: [1, 7, 30],
);

// 경로 분석 (Sankey Diagram)
final paths = await analytics.navigationPaths(days: 7, minCount: 10);
```

## 지원하는 분석 쿼리

### 기본 지표

| 메서드 | 설명 |
|--------|------|
| `dau()` | 일별 활성 사용자 |
| `wau()` | 주별 활성 사용자 |
| `mau()` | 월별 활성 사용자 |
| `eventCounts()` | 이벤트별 발생 횟수 |

### 퍼널 & 리텐션

| 메서드 | 설명 |
|--------|------|
| `funnel()` | 퍼널 분석 (windowFunnel) |
| `cohortRetention()` | 코호트 리텐션 |
| `nDayRetention()` | N일 리텐션 (Day 1/7/30) |

### 매출 분석

| 메서드 | 설명 |
|--------|------|
| `dailyRevenue()` | 일별 매출 |
| `topProductsByRevenue()` | 상품별 매출 TOP N |
| `arpu()` | 사용자당 평균 매출 |

### 경로 분석 (Sankey Diagram)

| 메서드 | 설명 |
|--------|------|
| `navigationPaths()` | 화면 이동 경로 (from → to) |
| `flowStepConversion()` | 플로우별 단계 전환율 |
| `dropOffPoints()` | 이탈 지점 분석 |
| `entryPoints()` | 앱 진입점 분석 |
| `userJourney()` | 개별 사용자 경로 시퀀스 |
| `flowCompletionRates()` | 플로우 완료율 |
| `screensPerSession()` | 세션별 화면 수 |

### 커스텀

| 메서드 | 설명 |
|--------|------|
| `custom()` | 커스텀 SQL 실행 |

## BI 이벤트 상수

표준화된 이벤트 이름과 속성 키를 제공합니다.

```dart
// 이벤트 이름
BiEvents.appOpened
BiEvents.screenView
BiEvents.buttonClick
BiEvents.signUpStarted
BiEvents.purchaseCompleted
// ... 30+ 이벤트

// 속성 키
BiEventProps.screenName
BiEventProps.buttonName
BiEventProps.flowName
BiEventProps.stepIndex
// ... 다수 속성
```

자세한 내용은 [BI 이벤트 가이드](docs/BI_EVENTS_GUIDE.md)를 참조하세요.

## Flutter 통합

Flutter 앱에서 자동으로 이벤트를 추적하는 Observer 패턴을 제공합니다:

- **ClickHouseNavigatorObserver** - GoRouter 화면 이동 자동 추적
- **ClickHouseBlocObserver** - BLoC 상태 변경/에러 추적
- **ClickHouseLifecycleObserver** - 앱 라이프사이클 추적
- **ClickHouseDioInterceptor** - API 호출 성능 추적

자세한 구현 예시는 [BI 이벤트 가이드 - Flutter 통합](docs/BI_EVENTS_GUIDE.md#flutter-통합-가이드)을 참조하세요.

## 기본 테이블 스키마

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

## PostgreSQL → ClickHouse 동기화

### 옵션 1: ClickPipes (권장)

ClickHouse Cloud의 관리형 CDC 서비스를 사용합니다.

### 옵션 2: FutureCall 배치 동기화

```dart
// 패키지에 포함된 SyncToClickHouseCall 사용
await SyncToClickHouseCall.syncOrders(session, lastSyncTime);
```

### 옵션 3: Debezium + Kafka

대규모 실시간 동기화가 필요한 경우.

## 프로젝트 구조

```
serverpod_clickhouse/
├── lib/
│   ├── serverpod_clickhouse.dart      # 라이브러리 export
│   └── src/
│       ├── business/                   # 비즈니스 로직
│       │   ├── clickhouse_client.dart  # HTTP 클라이언트
│       │   ├── event_tracker.dart      # 이벤트 배치 전송
│       │   ├── analytics_queries.dart  # 분석 쿼리 빌더
│       │   ├── schema_manager.dart     # 스키마 관리
│       │   └── bi_events.dart          # BI 이벤트 상수
│       ├── endpoints/                  # Serverpod API
│       │   ├── clickhouse_events_endpoint.dart
│       │   └── clickhouse_analytics_endpoint.dart
│       ├── service/                    # 서비스 레이어
│       │   └── clickhouse_service.dart
│       ├── future_calls/               # 동기화 작업
│       │   └── sync_to_clickhouse_call.dart
│       └── models/                     # Serverpod 모델
│           └── *.spy.yaml
├── docs/
│   └── BI_EVENTS_GUIDE.md              # BI 이벤트 상세 가이드
├── example/
│   └── serverpod_integration.dart      # 통합 예시
├── config/
│   └── generator.yaml                  # Serverpod 모듈 설정
└── pubspec.yaml
```

## 문서

- [BI 이벤트 가이드](docs/BI_EVENTS_GUIDE.md) - 이벤트 정의, Flutter 통합, 경로 분석
- [ClickHouse Cloud 설정 가이드](docs/CLICKHOUSE_CLOUD_SETUP.md) - Cloud 설정, ClickPipes CDC 구성

## License

MIT
