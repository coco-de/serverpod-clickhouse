/// BI 이벤트 이름 상수
///
/// 앱에서 측정해야 하는 표준 BI 이벤트 이름을 정의합니다.
/// 이벤트 이름은 snake_case를 사용합니다.
///
/// ## 사용 예시
/// ```dart
/// tracker.track(BiEvents.appOpened, properties: {...});
/// tracker.track(BiEvents.screenView, properties: {'screen_name': 'Home'});
/// ```
class BiEvents {
  BiEvents._();

  // ==========================================================================
  // 앱 라이프사이클
  // ==========================================================================

  /// 앱이 시작됨 (콜드 스타트)
  static const appOpened = 'app_opened';

  /// 앱이 종료됨 또는 백그라운드로 이동
  static const appClosed = 'app_closed';

  /// 앱이 포그라운드로 복귀
  static const appResumed = 'app_resumed';

  /// 세션 시작 (자동 감지)
  static const sessionStart = 'session_start';

  /// 세션 종료 (자동 감지)
  static const sessionEnd = 'session_end';

  // ==========================================================================
  // 경로 분석 (Sankey Diagram 지원)
  // ==========================================================================

  /// 화면 이동 (from → to 정보 포함)
  static const navigation = 'navigation';

  /// 플로우/퍼널 시작 (예: checkout, onboarding)
  static const flowStarted = 'flow_started';

  /// 플로우/퍼널 완료
  static const flowCompleted = 'flow_completed';

  /// 플로우/퍼널 이탈
  static const flowAbandoned = 'flow_abandoned';

  // ==========================================================================
  // 화면 및 UI 상호작용
  // ==========================================================================

  /// 화면 조회
  static const screenView = 'screen_view';

  /// 버튼 클릭
  static const buttonClick = 'button_click';

  /// 기능 사용
  static const featureUsed = 'feature_used';

  // ==========================================================================
  // 사용자 식별 및 속성
  // ==========================================================================

  /// 사용자 식별 (로그인)
  static const userIdentified = 'user_identified';

  /// 사용자 로그아웃
  static const userLogout = 'user_logout';

  /// 사용자 속성 업데이트
  static const userPropertiesUpdated = 'user_properties_updated';

  // ==========================================================================
  // 에러 및 예외
  // ==========================================================================

  /// 일반 에러
  static const error = 'error';

  /// API 에러
  static const apiError = 'api_error';

  // ==========================================================================
  // 퍼포먼스 및 타이밍
  // ==========================================================================

  /// 타이밍 측정
  static const timing = 'timing';

  /// API 호출 성능
  static const apiCall = 'api_call';

  // ==========================================================================
  // 검색
  // ==========================================================================

  /// 검색 실행
  static const search = 'search';

  // ==========================================================================
  // 커머스 이벤트
  // ==========================================================================

  /// 상품 조회
  static const productView = 'product_view';

  /// 장바구니 추가
  static const addToCart = 'add_to_cart';

  /// 장바구니 제거
  static const removeFromCart = 'remove_from_cart';

  /// 체크아웃 시작
  static const checkoutStarted = 'checkout_started';

  /// 구매 완료
  static const purchase = 'purchase';

  /// 범용 전환 이벤트
  static const conversion = 'conversion';

  // ==========================================================================
  // 콘텐츠 상호작용
  // ==========================================================================

  /// 콘텐츠 조회
  static const contentView = 'content_view';

  /// 콘텐츠 공유
  static const share = 'share';

  // ==========================================================================
  // 푸시 알림
  // ==========================================================================

  /// 푸시 알림 수신
  static const pushReceived = 'push_received';

  /// 푸시 알림 클릭
  static const pushClicked = 'push_clicked';
}

/// 이벤트 속성 키 상수
///
/// 이벤트 properties에 사용되는 표준 키 이름을 정의합니다.
class BiEventProperties {
  BiEventProperties._();

  // 공통
  static const screenName = 'screen_name';
  static const userId = 'user_id';
  static const sessionId = 'session_id';
  static const timestamp = 'timestamp';

  // 경로 분석
  static const fromScreen = 'from_screen';
  static const toScreen = 'to_screen';
  static const trigger = 'trigger';
  static const stepIndex = 'step_index';
  static const flowName = 'flow_name';
  static const entryPoint = 'entry_point';
  static const abandonedAt = 'abandoned_at';
  static const totalSteps = 'total_steps';
  static const durationMs = 'duration_ms';
  static const reason = 'reason';
  static const success = 'success';

  // 라이프사이클
  static const source = 'source';
  static const campaign = 'campaign';
  static const referrer = 'referrer';
  static const lastScreen = 'last_screen';
  static const screenCount = 'screen_count';
  static const sessionDurationMs = 'session_duration_ms';
  static const backgroundDurationMs = 'background_duration_ms';

  // 에러
  static const errorType = 'error_type';
  static const errorMessage = 'error_message';
  static const stackTrace = 'stack_trace';
  static const endpoint = 'endpoint';
  static const statusCode = 'status_code';

  // 퍼포먼스
  static const category = 'category';
  static const variable = 'variable';
  static const label = 'label';
  static const method = 'method';

  // 검색
  static const query = 'query';
  static const resultCount = 'result_count';

  // 커머스
  static const productId = 'product_id';
  static const productName = 'product_name';
  static const price = 'price';
  static const quantity = 'quantity';
  static const currency = 'currency';
  static const value = 'value';
  static const orderId = 'order_id';
  static const totalAmount = 'total_amount';
  static const itemCount = 'item_count';
  static const items = 'items';
  static const conversionType = 'conversion_type';

  // 콘텐츠
  static const contentId = 'content_id';
  static const contentType = 'content_type';
  static const contentName = 'content_name';
  static const shareMethod = 'share_method';

  // 푸시
  static const campaignId = 'campaign_id';
  static const title = 'title';
  static const action = 'action';

  // 버튼/UI
  static const buttonName = 'button_name';
  static const featureName = 'feature_name';
}

/// 경로 분석 트리거 타입
class NavigationTrigger {
  NavigationTrigger._();

  static const button = 'button';
  static const tab = 'tab';
  static const back = 'back';
  static const deepLink = 'deep_link';
  static const push = 'push';
  static const swipe = 'swipe';
  static const auto = 'auto';
}

/// 앱 오픈 소스 타입
class AppOpenSource {
  AppOpenSource._();

  static const organic = 'organic';
  static const deepLink = 'deep_link';
  static const push = 'push';
  static const widget = 'widget';
  static const shortcut = 'shortcut';
}
