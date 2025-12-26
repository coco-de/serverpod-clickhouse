import 'dart:async';
import 'dart:collection';

import 'package:uuid/uuid.dart';

import 'bi_events.dart';
import 'clickhouse_client.dart';

/// 분석 이벤트
class AnalyticsEvent {
  final String eventId;
  final String eventName;
  final String? userId;
  final String? sessionId;
  final String? anonymousId;
  final DateTime timestamp;
  final Map<String, dynamic> properties;
  final Map<String, dynamic>? context;

  AnalyticsEvent({
    String? eventId,
    required this.eventName,
    this.userId,
    this.sessionId,
    this.anonymousId,
    DateTime? timestamp,
    this.properties = const {},
    this.context,
  })  : eventId = eventId ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toClickHouseRow() {
    return {
      'event_id': eventId,
      'event_name': eventName,
      'user_id': userId ?? '',
      'session_id': sessionId ?? '',
      'anonymous_id': anonymousId ?? '',
      'timestamp': timestamp.toUtc().toIso8601String(),
      'properties': properties,
      // Context 필드들 (옵션)
      if (context != null) ...{
        'device_type': context!['device_type'] ?? '',
        'os': context!['os'] ?? '',
        'os_version': context!['os_version'] ?? '',
        'app_version': context!['app_version'] ?? '',
        'country': context!['country'] ?? '',
        'region': context!['region'] ?? '',
      },
    };
  }
}

/// 이벤트 트래커 설정
class EventTrackerConfig {
  /// 배치 크기 (몇 개 모이면 전송)
  final int batchSize;

  /// 최대 대기 시간 (이 시간 지나면 배치 크기와 관계없이 전송)
  final Duration flushInterval;

  /// 이벤트 테이블 이름
  final String tableName;

  /// 재시도 횟수
  final int maxRetries;

  /// 재시도 간격
  final Duration retryDelay;

  const EventTrackerConfig({
    this.batchSize = 100,
    this.flushInterval = const Duration(seconds: 10),
    this.tableName = 'events',
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 1),
  });
}

/// 이벤트 트래커 - 배치로 ClickHouse에 이벤트 전송
class EventTracker {
  final ClickHouseClient _client;
  final EventTrackerConfig _config;

  final Queue<AnalyticsEvent> _buffer = Queue();
  Timer? _flushTimer;
  bool _isFlushing = false;

  /// 공통 컨텍스트 (모든 이벤트에 추가)
  Map<String, dynamic> commonContext = {};

  EventTracker(
    this._client, {
    EventTrackerConfig? config,
  }) : _config = config ?? const EventTrackerConfig() {
    _startFlushTimer();
  }

  /// 이벤트 추적
  void track(
    String eventName, {
    String? userId,
    String? sessionId,
    String? anonymousId,
    Map<String, dynamic> properties = const {},
    Map<String, dynamic>? context,
  }) {
    final mergedContext = {...commonContext, ...?context};

    final event = AnalyticsEvent(
      eventName: eventName,
      userId: userId,
      sessionId: sessionId,
      anonymousId: anonymousId,
      properties: properties,
      context: mergedContext.isNotEmpty ? mergedContext : null,
    );

    _buffer.add(event);

    // 배치 크기 도달 시 즉시 전송
    if (_buffer.length >= _config.batchSize) {
      flush();
    }
  }

  /// 화면 조회 이벤트
  void trackScreenView(
    String screenName, {
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.screenView,
      userId: userId,
      sessionId: sessionId,
      properties: {BiEventProperties.screenName: screenName, ...properties},
    );
  }

  /// 버튼 클릭 이벤트
  void trackButtonClick(
    String buttonName, {
    String? screenName,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.buttonClick,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.buttonName: buttonName,
        if (screenName != null) BiEventProperties.screenName: screenName,
        ...properties,
      },
    );
  }

  /// 전환 이벤트 (가입, 구매 등)
  void trackConversion(
    String conversionType, {
    String? userId,
    String? sessionId,
    double? value,
    String? currency,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.conversion,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.conversionType: conversionType,
        if (value != null) BiEventProperties.value: value,
        if (currency != null) BiEventProperties.currency: currency,
        ...properties,
      },
    );
  }

  // ==========================================================================
  // 앱 라이프사이클 이벤트
  // ==========================================================================

  /// 앱 시작 이벤트
  ///
  /// 앱이 콜드 스타트되거나 딥링크/푸시로 열릴 때 호출합니다.
  ///
  /// - [source]: 진입 경로 (organic, deep_link, push, widget, shortcut)
  /// - [campaign]: UTM 캠페인 ID
  /// - [referrer]: 유입 출처
  void trackAppOpened({
    String? userId,
    String? sessionId,
    String? source,
    String? campaign,
    String? referrer,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.appOpened,
      userId: userId,
      sessionId: sessionId,
      properties: {
        if (source != null) BiEventProperties.source: source,
        if (campaign != null) BiEventProperties.campaign: campaign,
        if (referrer != null) BiEventProperties.referrer: referrer,
        ...properties,
      },
    );
  }

  /// 앱 종료/백그라운드 이벤트
  ///
  /// 앱이 종료되거나 백그라운드로 이동할 때 호출합니다.
  ///
  /// - [sessionDurationMs]: 세션 지속 시간 (밀리초)
  /// - [lastScreen]: 마지막으로 본 화면 (이탈점 분석용)
  /// - [screenCount]: 세션 동안 본 화면 수
  void trackAppClosed({
    String? userId,
    String? sessionId,
    int? sessionDurationMs,
    String? lastScreen,
    int? screenCount,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.appClosed,
      userId: userId,
      sessionId: sessionId,
      properties: {
        if (sessionDurationMs != null)
          BiEventProperties.sessionDurationMs: sessionDurationMs,
        if (lastScreen != null) BiEventProperties.lastScreen: lastScreen,
        if (screenCount != null) BiEventProperties.screenCount: screenCount,
        ...properties,
      },
    );
  }

  /// 앱 포그라운드 복귀 이벤트
  ///
  /// 백그라운드에서 포그라운드로 돌아올 때 호출합니다.
  ///
  /// - [backgroundDurationMs]: 백그라운드에 있던 시간 (밀리초)
  void trackAppResumed({
    String? userId,
    String? sessionId,
    int? backgroundDurationMs,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.appResumed,
      userId: userId,
      sessionId: sessionId,
      properties: {
        if (backgroundDurationMs != null)
          BiEventProperties.backgroundDurationMs: backgroundDurationMs,
        ...properties,
      },
    );
  }

  // ==========================================================================
  // 경로 분석 이벤트 (Sankey Diagram 지원)
  // ==========================================================================

  /// 화면 이동 추적 (Sankey Diagram용)
  ///
  /// 화면 간 이동을 추적하여 사용자 경로를 분석합니다.
  ///
  /// - [toScreen]: 이동할 화면 이름
  /// - [fromScreen]: 이전 화면 이름 (null이면 진입점)
  /// - [trigger]: 이동 트리거 (button, tab, back, deep_link 등)
  /// - [stepIndex]: 퍼널 단계 인덱스 (선택)
  /// - [flowName]: 플로우 이름 (예: checkout, onboarding)
  void trackNavigation({
    required String toScreen,
    String? fromScreen,
    String? trigger,
    int? stepIndex,
    String? flowName,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.navigation,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.toScreen: toScreen,
        if (fromScreen != null) BiEventProperties.fromScreen: fromScreen,
        if (trigger != null) BiEventProperties.trigger: trigger,
        if (stepIndex != null) BiEventProperties.stepIndex: stepIndex,
        if (flowName != null) BiEventProperties.flowName: flowName,
        ...properties,
      },
    );
  }

  /// 플로우 시작 이벤트
  ///
  /// 명시적 퍼널/플로우가 시작될 때 호출합니다.
  ///
  /// - [flowName]: 플로우 이름 (예: onboarding, checkout, registration)
  /// - [entryPoint]: 진입 화면
  void trackFlowStarted({
    required String flowName,
    String? entryPoint,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.flowStarted,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.flowName: flowName,
        if (entryPoint != null) BiEventProperties.entryPoint: entryPoint,
        ...properties,
      },
    );
  }

  /// 플로우 완료 이벤트
  ///
  /// 플로우가 성공적으로 완료되었을 때 호출합니다.
  ///
  /// - [flowName]: 플로우 이름
  /// - [totalSteps]: 총 단계 수
  /// - [durationMs]: 플로우 완료까지 걸린 시간 (밀리초)
  /// - [success]: 성공 여부
  void trackFlowCompleted({
    required String flowName,
    int? totalSteps,
    int? durationMs,
    bool? success,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.flowCompleted,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.flowName: flowName,
        if (totalSteps != null) BiEventProperties.totalSteps: totalSteps,
        if (durationMs != null) BiEventProperties.durationMs: durationMs,
        if (success != null) BiEventProperties.success: success,
        ...properties,
      },
    );
  }

  /// 플로우 이탈 이벤트
  ///
  /// 사용자가 플로우를 중간에 이탈했을 때 호출합니다.
  ///
  /// - [flowName]: 플로우 이름
  /// - [abandonedAt]: 이탈 지점 화면
  /// - [stepIndex]: 이탈한 단계 인덱스
  /// - [reason]: 이탈 사유 (선택)
  void trackFlowAbandoned({
    required String flowName,
    required String abandonedAt,
    required int stepIndex,
    String? reason,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.flowAbandoned,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.flowName: flowName,
        BiEventProperties.abandonedAt: abandonedAt,
        BiEventProperties.stepIndex: stepIndex,
        if (reason != null) BiEventProperties.reason: reason,
        ...properties,
      },
    );
  }

  // ==========================================================================
  // 에러 추적
  // ==========================================================================

  /// 에러 이벤트
  ///
  /// 앱에서 발생한 에러를 추적합니다.
  ///
  /// - [errorType]: 에러 유형 (예: NetworkError, ValidationError)
  /// - [message]: 에러 메시지
  /// - [stackTrace]: 스택 트레이스 (선택)
  /// - [screenName]: 에러 발생 화면
  void trackError({
    required String errorType,
    required String message,
    String? stackTrace,
    String? screenName,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.error,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.errorType: errorType,
        BiEventProperties.errorMessage: message,
        if (stackTrace != null) BiEventProperties.stackTrace: stackTrace,
        if (screenName != null) BiEventProperties.screenName: screenName,
        ...properties,
      },
    );
  }

  /// API 에러 이벤트
  ///
  /// API 호출 실패를 추적합니다.
  ///
  /// - [endpoint]: API 엔드포인트
  /// - [statusCode]: HTTP 상태 코드
  /// - [errorMessage]: 에러 메시지
  /// - [durationMs]: 요청 시간 (밀리초)
  void trackApiError({
    required String endpoint,
    required int statusCode,
    String? errorMessage,
    int? durationMs,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.apiError,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.endpoint: endpoint,
        BiEventProperties.statusCode: statusCode,
        if (errorMessage != null) BiEventProperties.errorMessage: errorMessage,
        if (durationMs != null) BiEventProperties.durationMs: durationMs,
        ...properties,
      },
    );
  }

  // ==========================================================================
  // 사용자 식별 및 속성
  // ==========================================================================

  /// 사용자 속성 설정
  ///
  /// 사용자 프로필 속성을 업데이트합니다.
  void setUserProperties(
    Map<String, dynamic> userProperties, {
    String? userId,
    String? sessionId,
  }) {
    track(
      BiEvents.userPropertiesUpdated,
      userId: userId,
      sessionId: sessionId,
      properties: userProperties,
    );
  }

  /// 사용자 식별 (로그인)
  ///
  /// 익명 사용자를 로그인 사용자로 연결합니다.
  ///
  /// - [userId]: 사용자 ID
  /// - [traits]: 사용자 속성 (예: plan, company, email)
  void identify(
    String userId, {
    String? sessionId,
    Map<String, dynamic> traits = const {},
  }) {
    track(
      BiEvents.userIdentified,
      userId: userId,
      sessionId: sessionId,
      properties: traits,
    );
  }

  /// 로그아웃 이벤트
  void trackLogout({
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.userLogout,
      userId: userId,
      sessionId: sessionId,
      properties: properties,
    );
  }

  // ==========================================================================
  // 퍼포먼스/타이밍
  // ==========================================================================

  /// 타이밍 이벤트
  ///
  /// 특정 작업의 수행 시간을 측정합니다.
  ///
  /// - [category]: 카테고리 (예: page_load, api, render)
  /// - [variable]: 변수명 (예: home_screen, user_list)
  /// - [durationMs]: 소요 시간 (밀리초)
  /// - [label]: 추가 라벨 (선택)
  void trackTiming({
    required String category,
    required String variable,
    required int durationMs,
    String? label,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.timing,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.category: category,
        BiEventProperties.variable: variable,
        BiEventProperties.durationMs: durationMs,
        if (label != null) BiEventProperties.label: label,
        ...properties,
      },
    );
  }

  /// API 호출 성능 측정
  ///
  /// API 호출의 성능을 추적합니다.
  ///
  /// - [endpoint]: API 엔드포인트
  /// - [method]: HTTP 메서드 (GET, POST 등)
  /// - [durationMs]: 소요 시간 (밀리초)
  /// - [statusCode]: HTTP 상태 코드
  /// - [success]: 성공 여부
  void trackApiCall({
    required String endpoint,
    required String method,
    required int durationMs,
    int? statusCode,
    bool? success,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.apiCall,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.endpoint: endpoint,
        BiEventProperties.method: method,
        BiEventProperties.durationMs: durationMs,
        if (statusCode != null) BiEventProperties.statusCode: statusCode,
        if (success != null) BiEventProperties.success: success,
        ...properties,
      },
    );
  }

  // ==========================================================================
  // 검색
  // ==========================================================================

  /// 검색 이벤트
  ///
  /// 검색 실행을 추적합니다.
  ///
  /// - [query]: 검색어
  /// - [resultCount]: 검색 결과 수
  /// - [category]: 검색 카테고리 (선택)
  void trackSearch({
    required String query,
    int? resultCount,
    String? category,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.search,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.query: query,
        if (resultCount != null) BiEventProperties.resultCount: resultCount,
        if (category != null) BiEventProperties.category: category,
        ...properties,
      },
    );
  }

  // ==========================================================================
  // 커머스 이벤트
  // ==========================================================================

  /// 상품 조회 이벤트
  void trackProductView({
    required String productId,
    String? productName,
    double? price,
    String? category,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.productView,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.productId: productId,
        if (productName != null) BiEventProperties.productName: productName,
        if (price != null) BiEventProperties.price: price,
        if (category != null) BiEventProperties.category: category,
        ...properties,
      },
    );
  }

  /// 장바구니 추가 이벤트
  void trackAddToCart({
    required String productId,
    int quantity = 1,
    double? price,
    String? productName,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.addToCart,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.productId: productId,
        BiEventProperties.quantity: quantity,
        if (price != null) BiEventProperties.price: price,
        if (productName != null) BiEventProperties.productName: productName,
        ...properties,
      },
    );
  }

  /// 장바구니 제거 이벤트
  void trackRemoveFromCart({
    required String productId,
    int quantity = 1,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.removeFromCart,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.productId: productId,
        BiEventProperties.quantity: quantity,
        ...properties,
      },
    );
  }

  /// 체크아웃 시작 이벤트
  void trackCheckoutStarted({
    double? totalAmount,
    int? itemCount,
    String? currency,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.checkoutStarted,
      userId: userId,
      sessionId: sessionId,
      properties: {
        if (totalAmount != null) BiEventProperties.totalAmount: totalAmount,
        if (itemCount != null) BiEventProperties.itemCount: itemCount,
        if (currency != null) BiEventProperties.currency: currency,
        ...properties,
      },
    );
  }

  /// 구매 완료 이벤트
  ///
  /// - [orderId]: 주문 ID
  /// - [amount]: 결제 금액
  /// - [currency]: 통화 코드 (예: USD, KRW)
  /// - [items]: 구매 상품 목록
  void trackPurchase({
    required String orderId,
    required double amount,
    String? currency,
    List<Map<String, dynamic>>? items,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.purchase,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.orderId: orderId,
        BiEventProperties.totalAmount: amount,
        if (currency != null) BiEventProperties.currency: currency,
        if (items != null) BiEventProperties.items: items,
        ...properties,
      },
    );
  }

  // ==========================================================================
  // 콘텐츠 상호작용
  // ==========================================================================

  /// 콘텐츠 조회 이벤트
  void trackContentView({
    required String contentId,
    required String contentType,
    String? contentName,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.contentView,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.contentId: contentId,
        BiEventProperties.contentType: contentType,
        if (contentName != null) BiEventProperties.contentName: contentName,
        ...properties,
      },
    );
  }

  /// 공유 이벤트
  void trackShare({
    required String contentType,
    required String method,
    String? contentId,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.share,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.contentType: contentType,
        BiEventProperties.shareMethod: method,
        if (contentId != null) BiEventProperties.contentId: contentId,
        ...properties,
      },
    );
  }

  // ==========================================================================
  // 푸시 알림
  // ==========================================================================

  /// 푸시 알림 수신 이벤트
  void trackPushReceived({
    required String campaignId,
    String? title,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.pushReceived,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.campaignId: campaignId,
        if (title != null) BiEventProperties.title: title,
        ...properties,
      },
    );
  }

  /// 푸시 알림 클릭 이벤트
  void trackPushClicked({
    required String campaignId,
    String? action,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.pushClicked,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.campaignId: campaignId,
        if (action != null) BiEventProperties.action: action,
        ...properties,
      },
    );
  }

  // ==========================================================================
  // 기능 사용
  // ==========================================================================

  /// 기능 사용 이벤트
  void trackFeatureUsed({
    required String featureName,
    String? screenName,
    String? userId,
    String? sessionId,
    Map<String, dynamic> properties = const {},
  }) {
    track(
      BiEvents.featureUsed,
      userId: userId,
      sessionId: sessionId,
      properties: {
        BiEventProperties.featureName: featureName,
        if (screenName != null) BiEventProperties.screenName: screenName,
        ...properties,
      },
    );
  }

  // ==========================================================================
  // 버퍼 관리
  // ==========================================================================

  /// 즉시 전송
  Future<void> flush() async {
    if (_isFlushing || _buffer.isEmpty) return;
    _isFlushing = true;

    try {
      // 버퍼에서 배치 추출
      final batch = <AnalyticsEvent>[];
      while (batch.length < _config.batchSize && _buffer.isNotEmpty) {
        batch.add(_buffer.removeFirst());
      }

      if (batch.isNotEmpty) {
        await _sendBatch(batch);
      }
    } finally {
      _isFlushing = false;
    }

    // 남은 이벤트가 있으면 계속 전송
    if (_buffer.isNotEmpty) {
      flush();
    }
  }

  Future<void> _sendBatch(List<AnalyticsEvent> batch) async {
    final rows = batch.map((e) => e.toClickHouseRow()).toList();

    for (var attempt = 0; attempt < _config.maxRetries; attempt++) {
      try {
        await _client.insertBatch(_config.tableName, rows);
        return; // 성공
      } catch (e) {
        if (attempt == _config.maxRetries - 1) {
          // 최종 실패 - 로그 또는 Dead Letter Queue로
          print('EventTracker: Failed to send batch after ${_config.maxRetries} attempts: $e');
          // TODO: DLQ 구현 또는 로컬 파일로 저장
          rethrow;
        }
        await Future.delayed(_config.retryDelay * (attempt + 1));
      }
    }
  }

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_config.flushInterval, (_) {
      flush();
    });
  }

  /// 종료 시 호출 - 남은 이벤트 모두 전송
  Future<void> shutdown() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await flush();
  }

  /// 버퍼 크기
  int get bufferSize => _buffer.length;
}

/// 세션 관리
class SessionManager {
  static final _uuid = Uuid();

  String? _currentSessionId;
  DateTime? _sessionStartTime;
  final Duration sessionTimeout;

  SessionManager({this.sessionTimeout = const Duration(minutes: 30)});

  /// 현재 세션 ID (없으면 생성)
  String get sessionId {
    final now = DateTime.now();

    // 세션 타임아웃 체크
    if (_currentSessionId != null && _sessionStartTime != null) {
      if (now.difference(_sessionStartTime!) > sessionTimeout) {
        _currentSessionId = null;
      }
    }

    // 새 세션 생성
    _currentSessionId ??= _uuid.v4();
    _sessionStartTime = now;

    return _currentSessionId!;
  }

  /// 세션 리셋 (로그아웃 등)
  void resetSession() {
    _currentSessionId = null;
    _sessionStartTime = null;
  }

  /// 세션 활동 갱신
  void touch() {
    _sessionStartTime = DateTime.now();
  }
}
