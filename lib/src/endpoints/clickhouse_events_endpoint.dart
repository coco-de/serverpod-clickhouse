import 'package:serverpod/serverpod.dart';

import '../business/bi_events.dart';
import '../service/clickhouse_service.dart';

/// 이벤트 수집 Endpoint
///
/// 클라이언트에서 `client.ch.events.xxx`로 접근합니다.
///
/// ## 사용 예시
/// ```dart
/// // Flutter 앱에서
/// await client.ch.events.track(eventName: 'button_click');
/// await client.ch.events.trackScreenView(screenName: 'HomeScreen');
/// ```
class ClickHouseEventsEndpoint extends Endpoint {
  /// 단일 이벤트 추적
  ///
  /// 인증된 사용자 ID가 있으면 자동으로 추출하여 포함합니다.
  ///
  /// - [eventName]: 이벤트 이름 (예: 'button_click', 'purchase')
  /// - [properties]: 이벤트 속성 (예: {'button': 'buy', 'price': 100})
  Future<void> track(
    Session session, {
    required String eventName,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.track(
      eventName,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
      context: await _extractContext(session),
    );
  }

  /// 배치 이벤트 추적
  ///
  /// 여러 이벤트를 한 번에 전송합니다. 오프라인 캐시된 이벤트 등에 유용합니다.
  ///
  /// 각 이벤트는 다음 형태의 Map이어야 합니다:
  /// ```dart
  /// {
  ///   'name': 'event_name',
  ///   'properties': {'key': 'value'},
  ///   'timestamp': '2024-01-01T00:00:00Z', // 선택사항
  /// }
  /// ```
  Future<void> trackBatch(
    Session session,
    List<Map<String, dynamic>> events,
  ) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;
    final context = await _extractContext(session);

    for (final event in events) {
      ClickHouseService.instance.tracker.track(
        event['name'] as String,
        userId: userId?.toString(),
        sessionId: session.sessionId.toString(),
        properties: event['properties'] as Map<String, dynamic>? ?? {},
        context: context,
      );
    }
  }

  /// 화면 조회 추적
  ///
  /// 화면/페이지 조회 이벤트를 기록합니다.
  /// 이벤트 이름은 `screen_view`로 고정됩니다.
  Future<void> trackScreenView(
    Session session,
    String screenName, {
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackScreenView(
      screenName,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  /// 버튼 클릭 추적
  ///
  /// 버튼/UI 요소 클릭 이벤트를 기록합니다.
  /// 이벤트 이름은 `button_click`으로 고정됩니다.
  Future<void> trackButtonClick(
    Session session,
    String buttonName, {
    String? screenName,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackButtonClick(
      buttonName,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      screenName: screenName,
      properties: properties ?? {},
    );
  }

  /// 전환 이벤트 추적
  ///
  /// 가입, 구매 등 전환 이벤트를 기록합니다.
  /// 이벤트 이름은 `conversion`으로 고정됩니다.
  ///
  /// - [conversionType]: 전환 유형 (예: 'signup', 'purchase', 'subscription')
  /// - [value]: 전환 가치 (금액 등)
  /// - [currency]: 통화 (예: 'USD', 'KRW')
  Future<void> trackConversion(
    Session session,
    String conversionType, {
    double? value,
    String? currency,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackConversion(
      conversionType,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      value: value,
      currency: currency,
      properties: properties ?? {},
    );
  }

  /// 버퍼 즉시 전송
  ///
  /// 버퍼에 남은 이벤트를 즉시 ClickHouse로 전송합니다.
  /// 일반적으로 호출할 필요 없으며, 디버깅이나 관리 목적으로 사용합니다.
  Future<void> flush(Session session) async {
    await ClickHouseService.instance.tracker.flush();
  }

  // ==========================================================================
  // 앱 라이프사이클 이벤트
  // ==========================================================================

  /// 앱 시작 추적
  ///
  /// - [source]: 진입 경로 (organic, deep_link, push 등)
  /// - [campaign]: UTM 캠페인 ID
  /// - [referrer]: 유입 출처
  Future<void> trackAppOpened(
    Session session, {
    String? source,
    String? campaign,
    String? referrer,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackAppOpened(
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      source: source,
      campaign: campaign,
      referrer: referrer,
      properties: properties ?? {},
    );
  }

  /// 앱 종료/백그라운드 추적
  Future<void> trackAppClosed(
    Session session, {
    int? sessionDurationMs,
    String? lastScreen,
    int? screenCount,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackAppClosed(
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      sessionDurationMs: sessionDurationMs,
      lastScreen: lastScreen,
      screenCount: screenCount,
      properties: properties ?? {},
    );
  }

  /// 앱 포그라운드 복귀 추적
  Future<void> trackAppResumed(
    Session session, {
    int? backgroundDurationMs,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackAppResumed(
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      backgroundDurationMs: backgroundDurationMs,
      properties: properties ?? {},
    );
  }

  // ==========================================================================
  // 경로 분석 이벤트 (Sankey Diagram)
  // ==========================================================================

  /// 화면 이동 추적 (Sankey Diagram용)
  ///
  /// 화면 간 이동을 추적하여 사용자 경로를 분석합니다.
  Future<void> trackNavigation(
    Session session, {
    required String toScreen,
    String? fromScreen,
    String? trigger,
    int? stepIndex,
    String? flowName,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackNavigation(
      toScreen: toScreen,
      fromScreen: fromScreen,
      trigger: trigger,
      stepIndex: stepIndex,
      flowName: flowName,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  /// 플로우 시작 추적
  Future<void> trackFlowStarted(
    Session session, {
    required String flowName,
    String? entryPoint,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackFlowStarted(
      flowName: flowName,
      entryPoint: entryPoint,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  /// 플로우 완료 추적
  Future<void> trackFlowCompleted(
    Session session, {
    required String flowName,
    int? totalSteps,
    int? durationMs,
    bool? success,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackFlowCompleted(
      flowName: flowName,
      totalSteps: totalSteps,
      durationMs: durationMs,
      success: success,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  /// 플로우 이탈 추적
  Future<void> trackFlowAbandoned(
    Session session, {
    required String flowName,
    required String abandonedAt,
    required int stepIndex,
    String? reason,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackFlowAbandoned(
      flowName: flowName,
      abandonedAt: abandonedAt,
      stepIndex: stepIndex,
      reason: reason,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  // ==========================================================================
  // 에러 추적
  // ==========================================================================

  /// 에러 이벤트 추적
  Future<void> trackError(
    Session session, {
    required String errorType,
    required String message,
    String? stackTrace,
    String? screenName,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackError(
      errorType: errorType,
      message: message,
      stackTrace: stackTrace,
      screenName: screenName,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  /// API 에러 추적
  Future<void> trackApiError(
    Session session, {
    required String endpoint,
    required int statusCode,
    String? errorMessage,
    int? durationMs,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackApiError(
      endpoint: endpoint,
      statusCode: statusCode,
      errorMessage: errorMessage,
      durationMs: durationMs,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  // ==========================================================================
  // 사용자 식별
  // ==========================================================================

  /// 사용자 속성 설정
  Future<void> setUserProperties(
    Session session,
    Map<String, dynamic> userProperties,
  ) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.setUserProperties(
      userProperties,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
    );
  }

  /// 사용자 식별 (로그인)
  Future<void> identify(
    Session session,
    String userId, {
    Map<String, dynamic>? traits,
  }) async {
    ClickHouseService.instance.tracker.identify(
      userId,
      sessionId: session.sessionId.toString(),
      traits: traits ?? {},
    );
  }

  /// 로그아웃 추적
  Future<void> trackLogout(
    Session session, {
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackLogout(
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  // ==========================================================================
  // 퍼포먼스/타이밍
  // ==========================================================================

  /// 타이밍 이벤트 추적
  Future<void> trackTiming(
    Session session, {
    required String category,
    required String variable,
    required int durationMs,
    String? label,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackTiming(
      category: category,
      variable: variable,
      durationMs: durationMs,
      label: label,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  /// API 호출 성능 추적
  Future<void> trackApiCall(
    Session session, {
    required String endpoint,
    required String method,
    required int durationMs,
    int? statusCode,
    bool? success,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackApiCall(
      endpoint: endpoint,
      method: method,
      durationMs: durationMs,
      statusCode: statusCode,
      success: success,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  // ==========================================================================
  // 검색
  // ==========================================================================

  /// 검색 이벤트 추적
  Future<void> trackSearch(
    Session session, {
    required String query,
    int? resultCount,
    String? category,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackSearch(
      query: query,
      resultCount: resultCount,
      category: category,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  // ==========================================================================
  // 커머스 이벤트
  // ==========================================================================

  /// 상품 조회 추적
  Future<void> trackProductView(
    Session session, {
    required String productId,
    String? productName,
    double? price,
    String? category,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackProductView(
      productId: productId,
      productName: productName,
      price: price,
      category: category,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  /// 장바구니 추가 추적
  Future<void> trackAddToCart(
    Session session, {
    required String productId,
    int quantity = 1,
    double? price,
    String? productName,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackAddToCart(
      productId: productId,
      quantity: quantity,
      price: price,
      productName: productName,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  /// 장바구니 제거 추적
  Future<void> trackRemoveFromCart(
    Session session, {
    required String productId,
    int quantity = 1,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackRemoveFromCart(
      productId: productId,
      quantity: quantity,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  /// 체크아웃 시작 추적
  Future<void> trackCheckoutStarted(
    Session session, {
    double? totalAmount,
    int? itemCount,
    String? currency,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackCheckoutStarted(
      totalAmount: totalAmount,
      itemCount: itemCount,
      currency: currency,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  /// 구매 완료 추적
  Future<void> trackPurchase(
    Session session, {
    required String orderId,
    required double amount,
    String? currency,
    List<Map<String, dynamic>>? items,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackPurchase(
      orderId: orderId,
      amount: amount,
      currency: currency,
      items: items,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  // ==========================================================================
  // 콘텐츠 상호작용
  // ==========================================================================

  /// 콘텐츠 조회 추적
  Future<void> trackContentView(
    Session session, {
    required String contentId,
    required String contentType,
    String? contentName,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackContentView(
      contentId: contentId,
      contentType: contentType,
      contentName: contentName,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  /// 공유 추적
  Future<void> trackShare(
    Session session, {
    required String contentType,
    required String method,
    String? contentId,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackShare(
      contentType: contentType,
      method: method,
      contentId: contentId,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  // ==========================================================================
  // 푸시 알림
  // ==========================================================================

  /// 푸시 알림 수신 추적
  Future<void> trackPushReceived(
    Session session, {
    required String campaignId,
    String? title,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackPushReceived(
      campaignId: campaignId,
      title: title,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  /// 푸시 알림 클릭 추적
  Future<void> trackPushClicked(
    Session session, {
    required String campaignId,
    String? action,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackPushClicked(
      campaignId: campaignId,
      action: action,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  // ==========================================================================
  // 기능 사용
  // ==========================================================================

  /// 기능 사용 추적
  Future<void> trackFeatureUsed(
    Session session, {
    required String featureName,
    String? screenName,
    Map<String, dynamic>? properties,
  }) async {
    final authInfo = await session.authenticated;
    final userId = authInfo?.userId;

    ClickHouseService.instance.tracker.trackFeatureUsed(
      featureName: featureName,
      screenName: screenName,
      userId: userId?.toString(),
      sessionId: session.sessionId.toString(),
      properties: properties ?? {},
    );
  }

  /// HTTP 요청에서 컨텍스트 추출
  ///
  /// 클라이언트가 커스텀 헤더로 전달한 기기 정보를 추출합니다.
  /// 헤더 예시:
  /// - `x-device-type`: 'mobile', 'tablet', 'desktop'
  /// - `x-app-version`: '1.0.0'
  /// - `x-platform`: 'ios', 'android', 'web'
  /// - `x-os-version`: '17.0'
  Future<Map<String, dynamic>> _extractContext(Session session) async {
    // Serverpod 2.x에서는 httpRequest가 직접 노출되지 않음
    // 대신 메서드 정보나 다른 방식으로 컨텍스트를 전달받아야 함
    // 클라이언트에서 properties에 컨텍스트를 포함하도록 권장
    return {};
  }
}
