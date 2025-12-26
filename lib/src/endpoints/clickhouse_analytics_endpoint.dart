import 'package:serverpod/serverpod.dart';

import '../service/clickhouse_service.dart';

/// 분석 API Endpoint
///
/// 클라이언트에서 `client.ch.analytics.xxx`로 접근합니다.
/// 기본적으로 로그인이 필요합니다.
///
/// ## 사용 예시
/// ```dart
/// // Flutter 앱에서
/// final dau = await client.ch.analytics.getDau(days: 30);
/// final funnel = await client.ch.analytics.getFunnel(
///   steps: ['signup', 'add_to_cart', 'purchase'],
/// );
/// ```
///
/// ## 반환 타입
/// `serverpod generate` 실행 후에는 generated/protocol.dart의
/// 타입 세이프한 모델을 사용할 수 있습니다.
class ClickHouseAnalyticsEndpoint extends Endpoint {
  @override
  bool get requireLogin => true;

  /// DAU (Daily Active Users) 조회
  ///
  /// 지정된 기간 동안의 일별 활성 사용자 수를 반환합니다.
  ///
  /// - [days]: 조회 기간 (일), 기본값 30일
  ///
  /// 반환 형식:
  /// ```json
  /// [{"date": "2024-01-01", "name": "dau", "value": 1234.0}]
  /// ```
  Future<List<Map<String, dynamic>>> getDau(
    Session session, {
    int days = 30,
  }) async {
    final result = await ClickHouseService.instance.analytics.dau(days: days);
    return result.rows
        .map((row) => {
              'date': row['date'] as String,
              'name': 'dau',
              'value': (row['dau'] as num).toDouble(),
            })
        .toList();
  }

  /// WAU (Weekly Active Users) 조회
  ///
  /// 지정된 기간 동안의 주별 활성 사용자 수를 반환합니다.
  ///
  /// - [weeks]: 조회 기간 (주), 기본값 12주
  Future<List<Map<String, dynamic>>> getWau(
    Session session, {
    int weeks = 12,
  }) async {
    final result = await ClickHouseService.instance.analytics.wau(weeks: weeks);
    return result.rows
        .map((row) => {
              'date': row['week'] as String,
              'name': 'wau',
              'value': (row['wau'] as num).toDouble(),
            })
        .toList();
  }

  /// MAU (Monthly Active Users) 조회
  ///
  /// 지정된 기간 동안의 월별 활성 사용자 수를 반환합니다.
  ///
  /// - [months]: 조회 기간 (월), 기본값 12개월
  Future<List<Map<String, dynamic>>> getMau(
    Session session, {
    int months = 12,
  }) async {
    final result =
        await ClickHouseService.instance.analytics.mau(months: months);
    return result.rows
        .map((row) => {
              'date': row['month'] as String,
              'name': 'mau',
              'value': (row['mau'] as num).toDouble(),
            })
        .toList();
  }

  /// 퍼널 분석
  ///
  /// 지정된 단계들의 전환율을 분석합니다.
  ///
  /// - [steps]: 퍼널 단계 이벤트 이름 목록 (예: ['signup', 'add_to_cart', 'purchase'])
  /// - [days]: 분석 기간 (일), 기본값 7일
  ///
  /// 반환 형식:
  /// ```json
  /// {
  ///   "steps": [
  ///     {"stepName": "signup", "users": 1000, "conversionRate": 100.0, "dropoffRate": 0.0},
  ///     {"stepName": "purchase", "users": 100, "conversionRate": 10.0, "dropoffRate": 90.0}
  ///   ],
  ///   "overallConversionRate": 10.0,
  ///   "periodDays": 7
  /// }
  /// ```
  Future<Map<String, dynamic>> getFunnel(
    Session session, {
    required List<String> steps,
    int days = 7,
  }) async {
    final result = await ClickHouseService.instance.analytics.funnel(
      steps: steps,
      days: days,
    );

    return {
      'steps': result.stepResults
          .map((s) => {
                'stepName': s.name,
                'users': s.users,
                'conversionRate': s.conversionRate,
                'dropoffRate': s.dropoffRate,
              })
          .toList(),
      'overallConversionRate': result.overallConversionRate,
      'periodDays': days,
    };
  }

  /// N-Day 리텐션 분석
  ///
  /// 특정 이벤트 후 N일 차 복귀율을 분석합니다.
  ///
  /// - [cohortEvent]: 코호트 정의 이벤트 (예: 'signup')
  /// - [returnEvent]: 복귀 판단 이벤트 (예: 'app_opened')
  /// - [days]: 분석할 N일 목록 (예: [1, 7, 30])
  Future<List<Map<String, dynamic>>> getRetention(
    Session session, {
    required String cohortEvent,
    String returnEvent = 'app_opened',
    List<int> days = const [1, 7, 30],
  }) async {
    final result = await ClickHouseService.instance.analytics.nDayRetention(
      cohortEvent: cohortEvent,
      returnEvent: returnEvent,
      days: days,
    );
    return result.rows;
  }

  /// 일별 매출 조회
  ///
  /// 지정된 기간 동안의 일별 매출을 반환합니다.
  ///
  /// - [days]: 조회 기간 (일), 기본값 30일
  Future<List<Map<String, dynamic>>> getDailyRevenue(
    Session session, {
    int days = 30,
  }) async {
    final result =
        await ClickHouseService.instance.analytics.dailyRevenue(days: days);
    return result.rows
        .map((row) => {
              'date': row['date'] as String,
              'name': 'revenue',
              'value': (row['revenue'] as num).toDouble(),
            })
        .toList();
  }

  /// ARPU (Average Revenue Per User) 조회
  ///
  /// 지정된 기간 동안의 월별 사용자당 평균 매출을 반환합니다.
  ///
  /// - [months]: 조회 기간 (월), 기본값 6개월
  Future<List<Map<String, dynamic>>> getArpu(
    Session session, {
    int months = 6,
  }) async {
    final result =
        await ClickHouseService.instance.analytics.arpu(months: months);
    return result.rows
        .map((row) => {
              'date': row['month'] as String,
              'name': 'arpu',
              'value': (row['arpu'] as num).toDouble(),
            })
        .toList();
  }

  /// 이벤트 카운트 조회
  ///
  /// 지정된 이벤트들의 발생 횟수를 조회합니다.
  ///
  /// - [eventNames]: 조회할 이벤트 이름 목록
  /// - [days]: 조회 기간 (일), 기본값 7일
  Future<List<Map<String, dynamic>>> getEventCounts(
    Session session, {
    required List<String> eventNames,
    int days = 7,
  }) async {
    final result = await ClickHouseService.instance.analytics.eventCounts(
      eventNames: eventNames,
      days: days,
    );
    return result.rows;
  }

  /// 커스텀 쿼리 실행
  ///
  /// 사전 정의된 쿼리만 허용됩니다 (SQL Injection 방지).
  /// 허용된 쿼리 목록: 'top_screens', 'user_activity'
  ///
  /// - [queryName]: 쿼리 이름
  /// - [params]: 쿼리 파라미터
  Future<List<Map<String, dynamic>>> customQuery(
    Session session,
    String queryName,
    Map<String, dynamic> params,
  ) async {
    final allowedQueries = getAllowedQueries();

    final sql = allowedQueries[queryName];
    if (sql == null) {
      throw ArgumentError(
        'Unknown query: $queryName. '
        'Allowed queries: ${allowedQueries.keys.join(", ")}',
      );
    }

    final result = await ClickHouseService.instance.analytics.custom(
      sql,
      params: params,
    );
    return result.rows;
  }

  /// 허용된 커스텀 쿼리 목록
  ///
  /// 상속 클래스에서 오버라이드하여 확장할 수 있습니다.
  Map<String, String> getAllowedQueries() {
    return {
      'top_screens': '''
        SELECT
          JSONExtractString(properties, 'screen_name') AS screen,
          count() AS views,
          uniqExact(user_id) AS unique_users
        FROM events
        WHERE event_name = 'screen_view'
          AND timestamp >= now() - INTERVAL {days:Int32} DAY
        GROUP BY screen
        ORDER BY views DESC
        LIMIT {limit:Int32}
      ''',
      'user_activity': '''
        SELECT
          toDate(timestamp) AS date,
          count() AS events,
          uniqExact(event_name) AS unique_events
        FROM events
        WHERE user_id = {user_id:String}
          AND timestamp >= now() - INTERVAL {days:Int32} DAY
        GROUP BY date
        ORDER BY date
      ''',
    };
  }

  // ==========================================================================
  // 경로 분석 (Sankey Diagram)
  // ==========================================================================

  /// 화면 이동 경로 분석 (Sankey Diagram용)
  ///
  /// 화면 간 이동 패턴을 분석하여 Sankey Diagram 시각화에 필요한 데이터를 반환합니다.
  ///
  /// 반환 형식:
  /// ```json
  /// [
  ///   {"from_screen": "Home", "to_screen": "ProductList", "transitions": 1500, "unique_users": 800},
  ///   {"from_screen": "ProductList", "to_screen": "ProductDetail", "transitions": 1200, "unique_users": 650}
  /// ]
  /// ```
  Future<List<Map<String, dynamic>>> getNavigationPaths(
    Session session, {
    int days = 7,
    int minCount = 10,
    String? flowName,
  }) async {
    final result = await ClickHouseService.instance.analytics.navigationPaths(
      days: days,
      minCount: minCount,
      flowName: flowName,
    );
    return result.rows;
  }

  /// 플로우별 단계 전환율
  ///
  /// 특정 플로우의 각 단계별 사용자 수와 전환율을 분석합니다.
  Future<List<Map<String, dynamic>>> getFlowStepConversion(
    Session session, {
    required String flowName,
    int days = 7,
  }) async {
    final result = await ClickHouseService.instance.analytics.flowStepConversion(
      flowName: flowName,
      days: days,
    );
    return result.rows;
  }

  /// 이탈 지점 분석
  ///
  /// 사용자가 플로우를 이탈하는 주요 지점을 분석합니다.
  ///
  /// 반환 형식:
  /// ```json
  /// [
  ///   {"flow_name": "checkout", "abandoned_at": "Payment", "step_index": 3, "abandon_count": 150},
  ///   {"flow_name": "checkout", "abandoned_at": "Shipping", "step_index": 2, "abandon_count": 80}
  /// ]
  /// ```
  Future<List<Map<String, dynamic>>> getDropOffPoints(
    Session session, {
    String? flowName,
    int days = 7,
    int limit = 20,
  }) async {
    final result = await ClickHouseService.instance.analytics.dropOffPoints(
      flowName: flowName,
      days: days,
      limit: limit,
    );
    return result.rows;
  }

  /// 진입점 분석
  ///
  /// 앱 진입 경로 및 첫 화면을 분석합니다.
  Future<List<Map<String, dynamic>>> getEntryPoints(
    Session session, {
    int days = 7,
  }) async {
    final result = await ClickHouseService.instance.analytics.entryPoints(
      days: days,
    );
    return result.rows;
  }

  /// 사용자 경로 시퀀스 (개별 사용자)
  ///
  /// 특정 사용자의 화면 이동 시퀀스를 조회합니다.
  Future<List<Map<String, dynamic>>> getUserJourney(
    Session session, {
    required String userId,
    int days = 7,
    String? sessionId,
  }) async {
    final result = await ClickHouseService.instance.analytics.userJourney(
      userId: userId,
      days: days,
      sessionId: sessionId,
    );
    return result.rows;
  }

  /// 플로우 완료율
  ///
  /// 각 플로우의 시작/완료/이탈 비율을 분석합니다.
  Future<List<Map<String, dynamic>>> getFlowCompletionRates(
    Session session, {
    int days = 7,
  }) async {
    final result = await ClickHouseService.instance.analytics.flowCompletionRates(
      days: days,
    );
    return result.rows;
  }

  /// 세션별 화면 수
  ///
  /// 세션당 평균 화면 조회 수를 분석합니다.
  Future<List<Map<String, dynamic>>> getScreensPerSession(
    Session session, {
    int days = 7,
  }) async {
    final result = await ClickHouseService.instance.analytics.screensPerSession(
      days: days,
    );
    return result.rows;
  }
}
