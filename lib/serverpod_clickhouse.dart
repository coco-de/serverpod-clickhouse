/// Serverpod + ClickHouse 통합 패키지
///
/// PostgreSQL 기반 Serverpod 서비스에 ClickHouse 분석 레이어를 추가합니다.
///
/// ## 주요 기능
/// - ClickHouse HTTP 클라이언트
/// - 이벤트 트래킹 (배치 전송)
/// - 분석 쿼리 빌더 (DAU, 퍼널, 리텐션 등)
/// - 스키마 관리
/// - Serverpod Endpoints (Events, Analytics)
/// - PostgreSQL → ClickHouse 동기화
///
/// ## Serverpod 모듈 설치
///
/// ### 1. 서버 의존성 추가
/// ```yaml
/// # my_server/pubspec.yaml
/// dependencies:
///   serverpod_clickhouse: ^1.0.0
/// ```
///
/// ### 2. 모듈 등록
/// ```yaml
/// # my_server/config/generator.yaml
/// modules:
///   serverpod_clickhouse:
///     nickname: ch
/// ```
///
/// ### 3. ClickHouse 설정
/// ```yaml
/// # my_server/config/passwords.yaml
/// development:
///   clickhouse_host: 'xxx.clickhouse.cloud'
///   clickhouse_database: 'analytics'
///   clickhouse_username: 'default'
///   clickhouse_password: 'your-password'
///   clickhouse_use_ssl: 'true'
/// ```
///
/// ### 4. 코드 생성
/// ```bash
/// dart pub get
/// serverpod generate
/// serverpod create-migration
/// dart bin/main.dart --apply-migrations
/// ```
///
/// ### 5. 서버 초기화
/// ```dart
/// // server.dart
/// import 'package:serverpod_clickhouse/serverpod_clickhouse.dart';
///
/// void run(List<String> args) async {
///   final pod = Serverpod(...);
///   await ClickHouseService.initialize(pod);
///   await pod.start();
/// }
/// ```
///
/// ### 6. Flutter 클라이언트 사용
/// ```dart
/// // 이벤트 추적
/// await client.ch.events.track(eventName: 'button_click');
///
/// // 분석 조회
/// final dau = await client.ch.analytics.getDau(days: 30);
/// ```
///
/// ## 직접 사용 (Serverpod 없이)
/// ```dart
/// // 클라이언트 생성
/// final clickhouse = ClickHouseClient(
///   ClickHouseConfig.cloud(
///     host: 'xxx.clickhouse.cloud',
///     database: 'analytics',
///     username: 'default',
///     password: 'xxx',
///   ),
/// );
///
/// // 이벤트 트래커
/// final tracker = EventTracker(clickhouse);
/// tracker.track('page_view', userId: 'user123', properties: {'page': '/home'});
///
/// // 분석 쿼리
/// final analytics = AnalyticsQueryBuilder(clickhouse);
/// final dau = await analytics.dau(days: 30);
/// ```
library;

// ============================================================
// Business Layer (Core ClickHouse functionality)
// ============================================================

/// ClickHouse HTTP 클라이언트
export 'src/business/clickhouse_client.dart';

/// 이벤트 트래킹 (배치 버퍼링 지원)
export 'src/business/event_tracker.dart';

/// 분석 쿼리 빌더 (DAU, WAU, MAU, Funnel, Retention 등)
export 'src/business/analytics_queries.dart';

/// ClickHouse 스키마 관리
export 'src/business/schema_manager.dart';

/// BI 이벤트 상수 (이벤트 이름, 속성 키)
export 'src/business/bi_events.dart';

// ============================================================
// Service Layer (Serverpod integration)
// ============================================================

/// ClickHouseService 싱글톤 (Serverpod 초기화 및 전역 접근)
export 'src/service/clickhouse_service.dart';

// ============================================================
// Endpoints (Serverpod API)
// ============================================================

/// 이벤트 수집 Endpoint (client.ch.events.xxx)
export 'src/endpoints/clickhouse_events_endpoint.dart';

/// 분석 API Endpoint (client.ch.analytics.xxx)
export 'src/endpoints/clickhouse_analytics_endpoint.dart';

// ============================================================
// Sync Utilities
// ============================================================

/// PostgreSQL → ClickHouse 동기화 유틸리티
export 'src/future_calls/sync_to_clickhouse_call.dart';

// ============================================================
// Generated Protocol (Serverpod generate 실행 후 사용 가능)
// ============================================================
// 주의: 아래 export는 `serverpod generate` 실행 후에만 동작합니다.
// 생성 전에는 주석 처리를 유지하세요.
//
// export 'src/generated/protocol.dart';
