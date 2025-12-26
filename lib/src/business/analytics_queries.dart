import 'clickhouse_client.dart';

/// 분석 쿼리 빌더
class AnalyticsQueryBuilder {
  final ClickHouseClient _client;
  final String _eventsTable;

  AnalyticsQueryBuilder(
    this._client, {
    String eventsTable = 'events',
  }) : _eventsTable = eventsTable;

  // ============================================================================
  // 기본 메트릭
  // ============================================================================

  /// DAU (Daily Active Users)
  Future<ClickHouseResult> dau({
    DateTime? date,
    int days = 30,
  }) async {
    final targetDate = date ?? DateTime.now();
    return _client.query('''
      SELECT 
        toDate(timestamp) AS date,
        uniqExact(user_id) AS dau
      FROM $_eventsTable
      WHERE timestamp >= toDate({start_date}) 
        AND timestamp < toDate({end_date})
        AND user_id != ''
      GROUP BY date
      ORDER BY date
    ''', params: {
      'start_date': targetDate.subtract(Duration(days: days)),
      'end_date': targetDate.add(const Duration(days: 1)),
    });
  }

  /// WAU (Weekly Active Users)
  Future<ClickHouseResult> wau({int weeks = 12}) async {
    return _client.query('''
      SELECT 
        toStartOfWeek(timestamp) AS week,
        uniqExact(user_id) AS wau
      FROM $_eventsTable
      WHERE timestamp >= now() - INTERVAL {weeks} WEEK
        AND user_id != ''
      GROUP BY week
      ORDER BY week
    ''', params: {'weeks': weeks});
  }

  /// MAU (Monthly Active Users)
  Future<ClickHouseResult> mau({int months = 12}) async {
    return _client.query('''
      SELECT 
        toStartOfMonth(timestamp) AS month,
        uniqExact(user_id) AS mau
      FROM $_eventsTable
      WHERE timestamp >= now() - INTERVAL {months} MONTH
        AND user_id != ''
      GROUP BY month
      ORDER BY month
    ''', params: {'months': months});
  }

  /// 이벤트 카운트
  Future<ClickHouseResult> eventCounts({
    required List<String> eventNames,
    int days = 7,
  }) async {
    return _client.query('''
      SELECT 
        event_name,
        count() AS event_count,
        uniqExact(user_id) AS unique_users
      FROM $_eventsTable
      WHERE timestamp >= now() - INTERVAL {days} DAY
        AND event_name IN ({events})
      GROUP BY event_name
      ORDER BY event_count DESC
    ''', params: {
      'days': days,
      'events': eventNames,
    });
  }

  // ============================================================================
  // 퍼널 분석
  // ============================================================================

  /// 퍼널 분석
  /// 
  /// 예시:
  /// ```dart
  /// await analytics.funnel(
  ///   steps: ['sign_up_started', 'email_entered', 'password_set', 'sign_up_completed'],
  ///   days: 7,
  /// );
  /// ```
  Future<FunnelResult> funnel({
    required List<String> steps,
    int days = 7,
    Duration? windowDuration,
  }) async {
    if (steps.isEmpty) {
      throw ArgumentError('At least one step is required');
    }

    final window = windowDuration ?? const Duration(days: 1);
    final windowSeconds = window.inSeconds;

    // ClickHouse windowFunnel 함수 사용
    final stepConditions = steps
        .asMap()
        .entries
        .map((e) => "event_name = '${e.value}'")
        .join(', ');

    final result = await _client.query('''
      SELECT
        level,
        count() AS users
      FROM (
        SELECT 
          user_id,
          windowFunnel($windowSeconds)(timestamp, $stepConditions) AS level
        FROM $_eventsTable
        WHERE timestamp >= now() - INTERVAL {days} DAY
          AND event_name IN ({steps})
          AND user_id != ''
        GROUP BY user_id
      )
      GROUP BY level
      ORDER BY level
    ''', params: {
      'days': days,
      'steps': steps,
    });

    return FunnelResult.fromClickHouse(steps, result.rows);
  }

  // ============================================================================
  // 리텐션 분석
  // ============================================================================

  /// 코호트 리텐션
  /// 
  /// 예시:
  /// ```dart
  /// await analytics.cohortRetention(
  ///   cohortEvent: 'sign_up_completed',
  ///   returnEvent: 'app_opened',
  ///   weeks: 8,
  /// );
  /// ```
  Future<ClickHouseResult> cohortRetention({
    required String cohortEvent,
    String returnEvent = 'app_opened',
    int weeks = 8,
  }) async {
    return _client.query('''
      WITH cohort AS (
        SELECT 
          user_id,
          toStartOfWeek(min(timestamp)) AS cohort_week
        FROM $_eventsTable
        WHERE event_name = {cohort_event}
          AND timestamp >= now() - INTERVAL {weeks} WEEK
        GROUP BY user_id
      ),
      activity AS (
        SELECT 
          user_id,
          toStartOfWeek(timestamp) AS activity_week
        FROM $_eventsTable
        WHERE event_name = {return_event}
          AND timestamp >= now() - INTERVAL {weeks} WEEK
        GROUP BY user_id, activity_week
      )
      SELECT
        cohort_week,
        dateDiff('week', cohort_week, activity_week) AS week_number,
        uniqExact(c.user_id) AS users
      FROM cohort c
      JOIN activity a ON c.user_id = a.user_id
      WHERE activity_week >= cohort_week
      GROUP BY cohort_week, week_number
      ORDER BY cohort_week, week_number
    ''', params: {
      'cohort_event': cohortEvent,
      'return_event': returnEvent,
      'weeks': weeks,
    });
  }

  /// N일 리텐션 (Day 1, Day 7, Day 30)
  Future<ClickHouseResult> nDayRetention({
    required String cohortEvent,
    String returnEvent = 'app_opened',
    List<int> days = const [1, 7, 30],
    int lookbackDays = 60,
  }) async {
    final daysCases = days.map((d) => '''
      countIf(dateDiff('day', first_date, return_date) = $d) > 0 AS retained_day_$d
    ''').join(',\n      ');

    return _client.query('''
      WITH first_events AS (
        SELECT 
          user_id,
          toDate(min(timestamp)) AS first_date
        FROM $_eventsTable
        WHERE event_name = {cohort_event}
          AND timestamp >= now() - INTERVAL {lookback} DAY
        GROUP BY user_id
      ),
      return_events AS (
        SELECT 
          user_id,
          toDate(timestamp) AS return_date
        FROM $_eventsTable
        WHERE event_name = {return_event}
          AND timestamp >= now() - INTERVAL {lookback} DAY
        GROUP BY user_id, return_date
      ),
      user_retention AS (
        SELECT 
          f.user_id,
          f.first_date,
          $daysCases
        FROM first_events f
        LEFT JOIN return_events r ON f.user_id = r.user_id
        GROUP BY f.user_id, f.first_date
      )
      SELECT
        first_date AS cohort_date,
        count() AS cohort_size,
        ${days.map((d) => 'sum(retained_day_$d) AS day_${d}_retained').join(',\n        ')}
      FROM user_retention
      GROUP BY first_date
      ORDER BY first_date DESC
      LIMIT 30
    ''', params: {
      'cohort_event': cohortEvent,
      'return_event': returnEvent,
      'lookback': lookbackDays,
    });
  }

  // ============================================================================
  // 매출 분석
  // ============================================================================

  /// 일별 매출
  Future<ClickHouseResult> dailyRevenue({
    String revenueTable = 'orders',
    int days = 30,
  }) async {
    return _client.query('''
      SELECT 
        toDate(created_at) AS date,
        sum(total_amount) AS revenue,
        count() AS order_count,
        uniqExact(user_id) AS unique_customers
      FROM $revenueTable
      WHERE created_at >= now() - INTERVAL {days} DAY
        AND status = 'completed'
      GROUP BY date
      ORDER BY date
    ''', params: {'days': days});
  }

  /// 상품별 매출 TOP N
  Future<ClickHouseResult> topProductsByRevenue({
    String revenueTable = 'order_items',
    int limit = 10,
    int days = 30,
  }) async {
    return _client.query('''
      SELECT 
        product_id,
        product_name,
        sum(price * quantity) AS revenue,
        sum(quantity) AS units_sold,
        uniqExact(order_id) AS order_count
      FROM $revenueTable
      WHERE created_at >= now() - INTERVAL {days} DAY
      GROUP BY product_id, product_name
      ORDER BY revenue DESC
      LIMIT {limit}
    ''', params: {
      'days': days,
      'limit': limit,
    });
  }

  /// ARPU (Average Revenue Per User)
  Future<ClickHouseResult> arpu({
    String revenueTable = 'orders',
    int months = 6,
  }) async {
    return _client.query('''
      SELECT 
        toStartOfMonth(created_at) AS month,
        sum(total_amount) / uniqExact(user_id) AS arpu,
        sum(total_amount) AS total_revenue,
        uniqExact(user_id) AS paying_users
      FROM $revenueTable
      WHERE created_at >= now() - INTERVAL {months} MONTH
        AND status = 'completed'
      GROUP BY month
      ORDER BY month
    ''', params: {'months': months});
  }

  // ============================================================================
  // 경로 분석 (Sankey Diagram 지원)
  // ============================================================================

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
  ///
  /// - [days]: 분석 기간 (일)
  /// - [minCount]: 최소 이동 횟수 (노이즈 제거용)
  /// - [flowName]: 특정 플로우만 분석 (선택)
  Future<ClickHouseResult> navigationPaths({
    int days = 7,
    int minCount = 10,
    String? flowName,
  }) async {
    final flowCondition =
        flowName != null ? "AND JSONExtractString(properties, 'flow_name') = {flow_name}" : '';

    return _client.query('''
      SELECT
        JSONExtractString(properties, 'from_screen') AS from_screen,
        JSONExtractString(properties, 'to_screen') AS to_screen,
        count() AS transitions,
        uniqExact(user_id) AS unique_users
      FROM $_eventsTable
      WHERE event_name = 'navigation'
        AND timestamp >= now() - INTERVAL {days} DAY
        AND JSONExtractString(properties, 'from_screen') != ''
        $flowCondition
      GROUP BY from_screen, to_screen
      HAVING transitions >= {min_count}
      ORDER BY transitions DESC
    ''', params: {
      'days': days,
      'min_count': minCount,
      if (flowName != null) 'flow_name': flowName,
    });
  }

  /// 플로우별 단계 전환율
  ///
  /// 특정 플로우의 각 단계별 사용자 수와 전환율을 분석합니다.
  ///
  /// - [flowName]: 플로우 이름 (예: checkout, onboarding)
  /// - [days]: 분석 기간 (일)
  Future<ClickHouseResult> flowStepConversion({
    required String flowName,
    int days = 7,
  }) async {
    return _client.query('''
      WITH flow_users AS (
        SELECT DISTINCT user_id
        FROM $_eventsTable
        WHERE event_name = 'flow_started'
          AND JSONExtractString(properties, 'flow_name') = {flow_name}
          AND timestamp >= now() - INTERVAL {days} DAY
          AND user_id != ''
      ),
      step_counts AS (
        SELECT
          JSONExtractInt(properties, 'step_index') AS step_index,
          JSONExtractString(properties, 'to_screen') AS screen_name,
          count() AS step_count,
          uniqExact(user_id) AS users_at_step
        FROM $_eventsTable
        WHERE event_name = 'navigation'
          AND JSONExtractString(properties, 'flow_name') = {flow_name}
          AND timestamp >= now() - INTERVAL {days} DAY
          AND user_id IN (SELECT user_id FROM flow_users)
        GROUP BY step_index, screen_name
      )
      SELECT
        step_index,
        screen_name,
        step_count,
        users_at_step,
        users_at_step * 100.0 / (SELECT count() FROM flow_users) AS conversion_rate
      FROM step_counts
      ORDER BY step_index
    ''', params: {
      'flow_name': flowName,
      'days': days,
    });
  }

  /// 이탈 지점 분석
  ///
  /// 사용자가 플로우를 이탈하는 주요 지점을 분석합니다.
  ///
  /// - [flowName]: 특정 플로우만 분석 (선택)
  /// - [days]: 분석 기간 (일)
  /// - [limit]: 반환할 최대 결과 수
  Future<ClickHouseResult> dropOffPoints({
    String? flowName,
    int days = 7,
    int limit = 20,
  }) async {
    final flowCondition =
        flowName != null ? "AND JSONExtractString(properties, 'flow_name') = {flow_name}" : '';

    return _client.query('''
      SELECT
        JSONExtractString(properties, 'flow_name') AS flow_name,
        JSONExtractString(properties, 'abandoned_at') AS abandoned_at,
        JSONExtractInt(properties, 'step_index') AS step_index,
        count() AS abandon_count,
        uniqExact(user_id) AS unique_users
      FROM $_eventsTable
      WHERE event_name = 'flow_abandoned'
        AND timestamp >= now() - INTERVAL {days} DAY
        $flowCondition
      GROUP BY flow_name, abandoned_at, step_index
      ORDER BY abandon_count DESC
      LIMIT {limit}
    ''', params: {
      'days': days,
      'limit': limit,
      if (flowName != null) 'flow_name': flowName,
    });
  }

  /// 진입점 분석
  ///
  /// 앱 진입 경로 및 첫 화면을 분석합니다.
  ///
  /// - [days]: 분석 기간 (일)
  Future<ClickHouseResult> entryPoints({int days = 7}) async {
    return _client.query('''
      WITH app_opens AS (
        SELECT
          user_id,
          session_id,
          JSONExtractString(properties, 'source') AS source,
          timestamp
        FROM $_eventsTable
        WHERE event_name = 'app_opened'
          AND timestamp >= now() - INTERVAL {days} DAY
      ),
      first_screens AS (
        SELECT
          ao.user_id,
          ao.session_id,
          ao.source,
          first_value(JSONExtractString(e.properties, 'to_screen')) AS first_screen
        FROM app_opens ao
        LEFT JOIN $_eventsTable e ON ao.user_id = e.user_id
          AND ao.session_id = e.session_id
          AND e.event_name = 'navigation'
          AND e.timestamp > ao.timestamp
          AND e.timestamp < ao.timestamp + INTERVAL 5 MINUTE
        GROUP BY ao.user_id, ao.session_id, ao.source
      )
      SELECT
        source,
        first_screen,
        count() AS session_count,
        uniqExact(user_id) AS unique_users
      FROM first_screens
      GROUP BY source, first_screen
      ORDER BY session_count DESC
    ''', params: {'days': days});
  }

  /// 사용자 경로 시퀀스 (개별 사용자)
  ///
  /// 특정 사용자의 화면 이동 시퀀스를 조회합니다.
  ///
  /// - [userId]: 사용자 ID
  /// - [days]: 조회 기간 (일)
  /// - [sessionId]: 특정 세션만 조회 (선택)
  Future<ClickHouseResult> userJourney({
    required String userId,
    int days = 7,
    String? sessionId,
  }) async {
    final sessionCondition = sessionId != null ? "AND session_id = {session_id}" : '';

    return _client.query('''
      SELECT
        session_id,
        timestamp,
        event_name,
        JSONExtractString(properties, 'from_screen') AS from_screen,
        JSONExtractString(properties, 'to_screen') AS to_screen,
        JSONExtractString(properties, 'screen_name') AS screen_name,
        JSONExtractString(properties, 'flow_name') AS flow_name,
        JSONExtractInt(properties, 'step_index') AS step_index
      FROM $_eventsTable
      WHERE user_id = {user_id}
        AND timestamp >= now() - INTERVAL {days} DAY
        AND event_name IN ('navigation', 'screen_view', 'flow_started', 'flow_completed', 'flow_abandoned')
        $sessionCondition
      ORDER BY timestamp
      LIMIT 1000
    ''', params: {
      'user_id': userId,
      'days': days,
      if (sessionId != null) 'session_id': sessionId,
    });
  }

  /// 플로우 완료율
  ///
  /// 각 플로우의 시작/완료/이탈 비율을 분석합니다.
  ///
  /// - [days]: 분석 기간 (일)
  Future<ClickHouseResult> flowCompletionRates({int days = 7}) async {
    return _client.query('''
      SELECT
        flow_name,
        sum(started) AS started_count,
        sum(completed) AS completed_count,
        sum(abandoned) AS abandoned_count,
        completed_count * 100.0 / started_count AS completion_rate,
        abandoned_count * 100.0 / started_count AS abandon_rate
      FROM (
        SELECT
          JSONExtractString(properties, 'flow_name') AS flow_name,
          countIf(event_name = 'flow_started') AS started,
          countIf(event_name = 'flow_completed') AS completed,
          countIf(event_name = 'flow_abandoned') AS abandoned
        FROM $_eventsTable
        WHERE event_name IN ('flow_started', 'flow_completed', 'flow_abandoned')
          AND timestamp >= now() - INTERVAL {days} DAY
        GROUP BY flow_name, user_id
      )
      GROUP BY flow_name
      ORDER BY started_count DESC
    ''', params: {'days': days});
  }

  /// 세션별 화면 수
  ///
  /// 세션당 평균 화면 조회 수를 분석합니다.
  ///
  /// - [days]: 분석 기간 (일)
  Future<ClickHouseResult> screensPerSession({int days = 7}) async {
    return _client.query('''
      SELECT
        toDate(timestamp) AS date,
        avg(screen_count) AS avg_screens_per_session,
        median(screen_count) AS median_screens_per_session,
        max(screen_count) AS max_screens_per_session
      FROM (
        SELECT
          session_id,
          min(timestamp) AS timestamp,
          count() AS screen_count
        FROM $_eventsTable
        WHERE event_name IN ('screen_view', 'navigation')
          AND timestamp >= now() - INTERVAL {days} DAY
          AND session_id != ''
        GROUP BY session_id
      )
      GROUP BY date
      ORDER BY date
    ''', params: {'days': days});
  }

  // ============================================================================
  // 커스텀 쿼리
  // ============================================================================

  /// 커스텀 SQL 실행
  Future<ClickHouseResult> custom(
    String sql, {
    Map<String, dynamic>? params,
  }) {
    return _client.query(sql, params: params);
  }
}

/// 퍼널 분석 결과
class FunnelResult {
  final List<String> steps;
  final List<FunnelStep> stepResults;

  FunnelResult({required this.steps, required this.stepResults});

  factory FunnelResult.fromClickHouse(
    List<String> steps,
    List<Map<String, dynamic>> rows,
  ) {
    // level -> count 맵핑
    final levelCounts = <int, int>{};
    for (final row in rows) {
      final level = row['level'] as int;
      final users = row['users'] as int;
      levelCounts[level] = users;
    }

    // 총 사용자 (level 1 이상)
    int totalUsers = 0;
    for (var i = 1; i <= steps.length; i++) {
      totalUsers += levelCounts[i] ?? 0;
    }

    // 각 단계별 결과 생성
    final stepResults = <FunnelStep>[];
    int remainingUsers = totalUsers;

    for (var i = 0; i < steps.length; i++) {
      final stepIndex = i + 1;
      
      // 이 단계에 도달한 사용자 (이 단계 이상의 모든 사용자)
      int usersAtStep = 0;
      for (var j = stepIndex; j <= steps.length; j++) {
        usersAtStep += levelCounts[j] ?? 0;
      }

      final conversionRate = totalUsers > 0 ? usersAtStep / totalUsers : 0.0;
      final dropoffRate = i > 0 && stepResults[i - 1].users > 0
          ? 1 - (usersAtStep / stepResults[i - 1].users)
          : 0.0;

      stepResults.add(FunnelStep(
        name: steps[i],
        users: usersAtStep,
        conversionRate: conversionRate,
        dropoffRate: dropoffRate,
      ));
    }

    return FunnelResult(steps: steps, stepResults: stepResults);
  }

  /// 전체 전환율 (첫 단계 → 마지막 단계)
  double get overallConversionRate {
    if (stepResults.isEmpty) return 0;
    final first = stepResults.first.users;
    final last = stepResults.last.users;
    return first > 0 ? last / first : 0;
  }

  @override
  String toString() {
    final buffer = StringBuffer('Funnel Analysis:\n');
    for (final step in stepResults) {
      buffer.writeln('  ${step.name}: ${step.users} users '
          '(${(step.conversionRate * 100).toStringAsFixed(1)}% conversion, '
          '${(step.dropoffRate * 100).toStringAsFixed(1)}% dropoff)');
    }
    buffer.writeln('Overall conversion: ${(overallConversionRate * 100).toStringAsFixed(1)}%');
    return buffer.toString();
  }
}

/// 퍼널 단계
class FunnelStep {
  final String name;
  final int users;
  final double conversionRate;
  final double dropoffRate;

  FunnelStep({
    required this.name,
    required this.users,
    required this.conversionRate,
    required this.dropoffRate,
  });
}
