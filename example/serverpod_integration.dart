/// Serverpod ClickHouse 모듈 통합 예시
///
/// 이 파일은 Serverpod 서버에서 serverpod_clickhouse 모듈을 사용하는 방법을 보여줍니다.
library;

// ============================================================================
// 1. 설치 및 설정
// ============================================================================

/*
## Step 1: 서버 의존성 추가

```yaml
# my_server/pubspec.yaml
dependencies:
  serverpod: ^2.1.0
  serverpod_clickhouse: ^1.0.0
```

## Step 2: 모듈 등록

```yaml
# my_server/config/generator.yaml
modules:
  serverpod_clickhouse:
    nickname: ch
```

## Step 3: ClickHouse 설정

```yaml
# my_server/config/passwords.yaml
development:
  clickhouse_host: 'xxx.clickhouse.cloud'
  clickhouse_database: 'analytics'
  clickhouse_username: 'default'
  clickhouse_password: 'your-password'
  clickhouse_use_ssl: 'true'

# 또는 환경 변수 사용:
# CLICKHOUSE_HOST, CLICKHOUSE_DATABASE, CLICKHOUSE_USERNAME,
# CLICKHOUSE_PASSWORD, CLICKHOUSE_USE_SSL
```

## Step 4: 코드 생성 및 마이그레이션

```bash
dart pub get
serverpod generate
serverpod create-migration
dart bin/main.dart --apply-migrations
```
*/

// ============================================================================
// 2. 서버 초기화 (server.dart)
// ============================================================================

/*
import 'package:serverpod/serverpod.dart';
import 'package:serverpod_clickhouse/serverpod_clickhouse.dart';

void run(List<String> args) async {
  final pod = Serverpod(
    args,
    Protocol(),
    Endpoints(),
  );

  // ClickHouse 초기화 (passwords.yaml에서 설정 읽기)
  await ClickHouseService.initialize(pod);

  // 또는 환경 변수에서 읽기
  // await ClickHouseService.initialize(pod, useEnvFallback: true);

  // 스키마 초기화 (첫 실행 시에만)
  // await ClickHouseService.instance.schema.initializeSchema();

  await pod.start();
}

// 서버 종료 시
Future<void> shutdown() async {
  await ClickHouseService.shutdown();
}
*/

// ============================================================================
// 3. 제공되는 Endpoints 사용하기
// ============================================================================

/*
모듈이 등록되면 다음 Endpoints가 자동으로 사용 가능합니다:

## 이벤트 수집 (client.ch.events.xxx)
- track(eventName, properties)       // 단일 이벤트
- trackBatch(events)                 // 배치 이벤트
- trackScreenView(screenName)        // 화면 조회
- trackButtonClick(buttonName)       // 버튼 클릭
- trackConversion(type, value)       // 전환 이벤트
- flush()                            // 버퍼 즉시 전송

## 분석 API (client.ch.analytics.xxx) - 로그인 필요
- getDau(days)                       // DAU 조회
- getWau(weeks)                      // WAU 조회
- getMau(months)                     // MAU 조회
- getFunnel(steps, days)             // 퍼널 분석
- getRetention(cohortEvent, days)    // 리텐션 분석
- getDailyRevenue(days)              // 일별 매출
- getArpu(months)                    // ARPU
- getEventCounts(eventNames, days)   // 이벤트 카운트
- customQuery(queryName, params)     // 커스텀 쿼리
*/

// ============================================================================
// 4. Endpoint 확장하기
// ============================================================================

/*
import 'package:serverpod/serverpod.dart';
import 'package:serverpod_clickhouse/serverpod_clickhouse.dart';

/// 커스텀 분석 Endpoint
class MyAnalyticsEndpoint extends ClickHouseAnalyticsEndpoint {

  /// 추가 커스텀 쿼리 정의
  @override
  Map<String, String> getAllowedQueries() {
    return {
      ...super.getAllowedQueries(),
      'my_custom_metric': '''
        SELECT
          toDate(timestamp) AS date,
          count() AS events
        FROM events
        WHERE event_name = {event_name:String}
          AND timestamp >= now() - INTERVAL {days:Int32} DAY
        GROUP BY date
        ORDER BY date
      ''',
    };
  }

  /// 완전히 새로운 분석 메서드 추가
  Future<Map<String, dynamic>> getMyCustomDashboard(
    Session session, {
    int days = 30,
  }) async {
    final dau = await getDau(session, days: days);
    final revenue = await getDailyRevenue(session, days: days);

    return {
      'dau': dau,
      'revenue': revenue,
      'summary': {
        'totalUsers': dau.fold(0, (sum, row) => sum + (row['value'] as num).toInt()),
        'totalRevenue': revenue.fold(0.0, (sum, row) => sum + (row['value'] as num)),
      },
    };
  }
}
*/

// ============================================================================
// 5. PostgreSQL → ClickHouse 동기화
// ============================================================================

/*
import 'package:serverpod/serverpod.dart';
import 'package:serverpod_clickhouse/serverpod_clickhouse.dart';
import 'dart:async';

/// 주문 데이터 동기화
class OrderSyncer extends ClickHouseSyncer {
  @override
  List<SyncTask> getSyncTasks() {
    return [
      SyncTask(
        tableName: 'orders',
        syncFunction: _syncOrders,
        priority: 10,
      ),
      SyncTask(
        tableName: 'order_items',
        syncFunction: _syncOrderItems,
        priority: 20,
      ),
    ];
  }

  Future<int> _syncOrders(Session session) async {
    // 마지막 동기화 이후 변경된 주문 조회
    final lastSync = await _getLastSyncTime(session, 'orders');

    final orders = await session.db.unsafeQuery('''
      SELECT * FROM orders
      WHERE updated_at > @lastSync
      ORDER BY updated_at
      LIMIT 10000
    ''', parameters: {'lastSync': lastSync});

    if (orders.isEmpty) return 0;

    // ClickHouse에 배치 삽입
    final rows = orders.map((row) => {
      'order_id': row['id'].toString(),
      'user_id': row['user_id'].toString(),
      'total_amount': row['total_amount'],
      'status': row['status'],
      'created_at': (row['created_at'] as DateTime).toIso8601String(),
    }).toList();

    await ClickHouseService.instance.client.insertBatch('orders', rows);

    return orders.length;
  }

  Future<int> _syncOrderItems(Session session) async {
    // 구현...
    return 0;
  }

  Future<DateTime> _getLastSyncTime(Session session, String tableName) async {
    final result = await session.db.unsafeQuery('''
      SELECT last_synced_at FROM serverpod_clickhouse_sync_log
      WHERE table_name = @tableName AND status = 'completed'
      ORDER BY last_synced_at DESC LIMIT 1
    ''', parameters: {'tableName': tableName});

    if (result.isNotEmpty) {
      return result.first['last_synced_at'] as DateTime;
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

// 동기화 스케줄링 (server.dart에서)
void setupSyncSchedule(Serverpod pod) {
  Timer.periodic(const Duration(hours: 1), (_) async {
    final session = await pod.createSession();
    try {
      final syncer = OrderSyncer();
      await syncer.runSync(session);
    } finally {
      await session.close();
    }
  });
}
*/

// ============================================================================
// 6. Flutter 클라이언트 사용
// ============================================================================

/*
// Flutter 앱에서

import 'package:my_project_client/my_project_client.dart';

class AnalyticsService {
  final Client client;

  AnalyticsService(this.client);

  // 이벤트 추적
  Future<void> track(String eventName, {Map<String, dynamic>? properties}) async {
    await client.ch.events.track(
      eventName: eventName,
      properties: properties,
    );
  }

  // 화면 조회 추적
  Future<void> trackScreen(String screenName) async {
    await client.ch.events.trackScreenView(screenName);
  }

  // 버튼 클릭 추적
  Future<void> trackButton(String buttonName, {String? screenName}) async {
    await client.ch.events.trackButtonClick(
      buttonName,
      screenName: screenName,
    );
  }

  // 구매 전환 추적
  Future<void> trackPurchase(double amount, {String? currency}) async {
    await client.ch.events.trackConversion(
      'purchase',
      value: amount,
      currency: currency ?? 'KRW',
    );
  }

  // 대시보드 데이터 조회 (로그인 필요)
  Future<DashboardData> getDashboard() async {
    final dau = await client.ch.analytics.getDau(days: 30);
    final revenue = await client.ch.analytics.getDailyRevenue(days: 30);

    return DashboardData(dau: dau, revenue: revenue);
  }

  // 퍼널 분석
  Future<Map<String, dynamic>> analyzeFunnel(List<String> steps) async {
    return await client.ch.analytics.getFunnel(
      steps: steps,
      days: 7,
    );
  }
}

// 자동 화면 추적 (Navigator Observer)
class AnalyticsNavigatorObserver extends NavigatorObserver {
  final AnalyticsService analytics;

  AnalyticsNavigatorObserver(this.analytics);

  @override
  void didPush(Route route, Route? previousRoute) {
    final name = route.settings.name;
    if (name != null) {
      analytics.trackScreen(name);
    }
  }
}

// MaterialApp에서 사용
MaterialApp(
  navigatorObservers: [
    AnalyticsNavigatorObserver(analyticsService),
  ],
  // ...
)
*/

// ============================================================================
// 7. 직접 ClickHouse 쿼리 실행 (서버 측)
// ============================================================================

/*
import 'package:serverpod_clickhouse/serverpod_clickhouse.dart';

Future<void> runCustomAnalytics() async {
  final client = ClickHouseService.instance.client;

  // 직접 쿼리 실행
  final result = await client.query('''
    SELECT
      toDate(timestamp) AS date,
      event_name,
      count() AS count
    FROM events
    WHERE timestamp >= now() - INTERVAL 7 DAY
    GROUP BY date, event_name
    ORDER BY date, count DESC
  ''');

  for (final row in result.rows) {
    print('${row['date']}: ${row['event_name']} = ${row['count']}');
  }

  // AnalyticsQueryBuilder 사용
  final analytics = ClickHouseService.instance.analytics;

  // DAU
  final dau = await analytics.dau(days: 30);

  // 퍼널
  final funnel = await analytics.funnel(
    steps: ['signup', 'profile_complete', 'first_purchase'],
    days: 7,
  );

  print('Overall conversion: ${funnel.overallConversionRate}%');
}
*/

void main() {
  // 이 파일은 예시 코드입니다.
  // 실제 Serverpod 프로젝트에서 위의 패턴을 참고하세요.
}
