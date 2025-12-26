# BI Events Guide

앱에서 측정해야 하는 표준 BI 이벤트 가이드입니다.

## 목차

1. [이벤트 카테고리](#이벤트-카테고리)
2. [필수 이벤트](#필수-이벤트)
3. [권장 이벤트](#권장-이벤트)
4. [커머스 이벤트](#커머스-이벤트)
5. [경로 분석 (Sankey Diagram)](#경로-분석-sankey-diagram)
6. [Flutter 통합 가이드](#flutter-통합-가이드)
7. [분석 활용 방법](#분석-활용-방법)

---

## 이벤트 카테고리

| 카테고리 | 설명 | 우선순위 |
|---------|------|---------|
| 앱 라이프사이클 | 앱 시작/종료/백그라운드 | 🔴 필수 |
| 경로 분석 | 화면 이동, 플로우 추적 | 🔴 필수 |
| 사용자 식별 | 로그인, 속성 업데이트 | 🔴 필수 |
| 에러 추적 | 앱/API 에러 | 🔴 필수 |
| 퍼포먼스 | 타이밍, API 성능 | 🟡 권장 |
| 검색 | 검색어, 결과 수 | 🟡 권장 |
| 커머스 | 상품 조회, 장바구니, 구매 | 🟡 권장 |
| 콘텐츠 | 콘텐츠 조회, 공유 | 🟢 선택 |
| 푸시 알림 | 수신, 클릭 | 🟢 선택 |

---

## 필수 이벤트

### 1. 앱 라이프사이클

#### app_opened
앱이 시작될 때 기록합니다.

```dart
await client.ch.events.trackAppOpened(
  source: 'deep_link',     // organic, deep_link, push, widget, shortcut
  campaign: 'summer_sale', // UTM 캠페인 ID
  referrer: 'instagram',   // 유입 출처
);
```

| 속성 | 타입 | 설명 |
|------|------|------|
| source | String? | 진입 경로 |
| campaign | String? | UTM 캠페인 ID |
| referrer | String? | 유입 출처 |

#### app_closed
앱이 종료되거나 백그라운드로 이동할 때 기록합니다.

```dart
await client.ch.events.trackAppClosed(
  sessionDurationMs: 300000,  // 5분
  lastScreen: 'ProductDetail',
  screenCount: 12,
);
```

| 속성 | 타입 | 설명 |
|------|------|------|
| sessionDurationMs | int? | 세션 지속 시간 (ms) |
| lastScreen | String? | 마지막 화면 (이탈점) |
| screenCount | int? | 본 화면 수 |

#### app_resumed
백그라운드에서 포그라운드로 복귀할 때 기록합니다.

```dart
await client.ch.events.trackAppResumed(
  backgroundDurationMs: 60000,  // 1분
);
```

---

### 2. 사용자 식별

#### user_identified
로그인 시 사용자를 식별합니다.

```dart
await client.ch.events.identify(
  'user_123',
  traits: {
    'plan': 'premium',
    'company': 'Acme Corp',
    'signup_date': '2024-01-15',
  },
);
```

#### user_logout
로그아웃 시 기록합니다.

```dart
await client.ch.events.trackLogout();
```

#### user_properties_updated
사용자 속성을 업데이트할 때 기록합니다.

```dart
await client.ch.events.setUserProperties({
  'notification_enabled': true,
  'language': 'ko',
  'theme': 'dark',
});
```

---

### 3. 에러 추적

#### error
앱에서 발생한 에러를 기록합니다.

```dart
await client.ch.events.trackError(
  errorType: 'NetworkError',
  message: 'Connection timeout',
  stackTrace: stackTrace.toString(),
  screenName: 'ProductList',
);
```

| 속성 | 타입 | 설명 |
|------|------|------|
| errorType | String | 에러 유형 |
| message | String | 에러 메시지 |
| stackTrace | String? | 스택 트레이스 |
| screenName | String? | 발생 화면 |

#### api_error
API 호출 실패를 기록합니다.

```dart
await client.ch.events.trackApiError(
  endpoint: '/api/v1/products',
  statusCode: 500,
  errorMessage: 'Internal Server Error',
  durationMs: 5000,
);
```

---

## 권장 이벤트

### 1. 화면 조회

```dart
await client.ch.events.trackScreenView('ProductDetail');
```

### 2. 버튼 클릭

```dart
await client.ch.events.trackButtonClick(
  'add_to_cart',
  screenName: 'ProductDetail',
);
```

### 3. 기능 사용

```dart
await client.ch.events.trackFeatureUsed(
  featureName: 'dark_mode',
  screenName: 'Settings',
);
```

### 4. 검색

```dart
await client.ch.events.trackSearch(
  query: 'bluetooth headphones',
  resultCount: 42,
  category: 'electronics',
);
```

### 5. 퍼포먼스

```dart
// 타이밍 측정
await client.ch.events.trackTiming(
  category: 'page_load',
  variable: 'home_screen',
  durationMs: 1200,
);

// API 성능
await client.ch.events.trackApiCall(
  endpoint: '/api/v1/products',
  method: 'GET',
  durationMs: 350,
  statusCode: 200,
  success: true,
);
```

---

## 커머스 이벤트

### 상품 조회

```dart
await client.ch.events.trackProductView(
  productId: 'SKU-12345',
  productName: 'Wireless Headphones',
  price: 99.99,
  category: 'Electronics',
);
```

### 장바구니 추가

```dart
await client.ch.events.trackAddToCart(
  productId: 'SKU-12345',
  quantity: 2,
  price: 99.99,
  productName: 'Wireless Headphones',
);
```

### 장바구니 제거

```dart
await client.ch.events.trackRemoveFromCart(
  productId: 'SKU-12345',
  quantity: 1,
);
```

### 체크아웃 시작

```dart
await client.ch.events.trackCheckoutStarted(
  totalAmount: 299.97,
  itemCount: 3,
  currency: 'USD',
);
```

### 구매 완료

```dart
await client.ch.events.trackPurchase(
  orderId: 'ORD-2024-001',
  amount: 299.97,
  currency: 'USD',
  items: [
    {'product_id': 'SKU-12345', 'quantity': 2, 'price': 99.99},
    {'product_id': 'SKU-67890', 'quantity': 1, 'price': 99.99},
  ],
);
```

---

## 경로 분석 (Sankey Diagram)

Sankey Diagram을 통해 사용자 경로를 시각화하려면 다음 이벤트들을 사용합니다.

### 화면 이동 추적 (navigation)

가장 중요한 이벤트입니다. 모든 화면 이동에서 이전 화면과 다음 화면을 기록합니다.

```dart
await client.ch.events.trackNavigation(
  toScreen: 'ProductDetail',
  fromScreen: 'ProductList',
  trigger: 'button',  // button, tab, back, deep_link, swipe
);
```

| 속성 | 타입 | 설명 |
|------|------|------|
| toScreen | String | 이동할 화면 |
| fromScreen | String? | 이전 화면 (null이면 진입점) |
| trigger | String? | 이동 트리거 |
| stepIndex | int? | 플로우 단계 인덱스 |
| flowName | String? | 플로우 이름 |

### 플로우 추적

특정 사용자 여정(온보딩, 체크아웃 등)을 추적합니다.

```dart
// 플로우 시작
await client.ch.events.trackFlowStarted(
  flowName: 'checkout',
  entryPoint: 'Cart',
);

// 각 단계에서 navigation 이벤트와 함께 flowName, stepIndex 포함
await client.ch.events.trackNavigation(
  toScreen: 'ShippingAddress',
  fromScreen: 'Cart',
  flowName: 'checkout',
  stepIndex: 1,
);

await client.ch.events.trackNavigation(
  toScreen: 'PaymentMethod',
  fromScreen: 'ShippingAddress',
  flowName: 'checkout',
  stepIndex: 2,
);

// 플로우 완료
await client.ch.events.trackFlowCompleted(
  flowName: 'checkout',
  totalSteps: 4,
  durationMs: 180000,  // 3분
  success: true,
);

// 또는 플로우 이탈
await client.ch.events.trackFlowAbandoned(
  flowName: 'checkout',
  abandonedAt: 'PaymentMethod',
  stepIndex: 2,
  reason: 'payment_failed',
);
```

### Sankey Diagram 데이터 조회

```dart
// 화면 이동 경로 데이터 (Sankey용)
final paths = await client.ch.analytics.getNavigationPaths(
  days: 7,
  minCount: 10,  // 최소 10회 이상 이동만 포함
);
// 결과:
// [
//   {"from_screen": "Home", "to_screen": "ProductList", "transitions": 1500, "unique_users": 800},
//   {"from_screen": "ProductList", "to_screen": "ProductDetail", "transitions": 1200, "unique_users": 650},
//   ...
// ]

// 이탈 지점 분석
final dropOffs = await client.ch.analytics.getDropOffPoints(
  flowName: 'checkout',
  days: 7,
);
// 결과:
// [
//   {"abandoned_at": "PaymentMethod", "step_index": 2, "abandon_count": 150},
//   {"abandoned_at": "ShippingAddress", "step_index": 1, "abandon_count": 80},
// ]

// 플로우 완료율
final completionRates = await client.ch.analytics.getFlowCompletionRates(
  days: 7,
);

// 개별 사용자 여정
final journey = await client.ch.analytics.getUserJourney(
  userId: 'user_123',
  days: 7,
);
```

---

## Flutter 통합 가이드

### 1. GoRouter Navigator Observer (화면 이동 자동 추적)

GoRouter를 사용하는 앱에서 화면 이동을 자동으로 추적합니다.

```dart
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// GoRouter용 ClickHouse Navigator Observer
///
/// 화면 이동을 자동으로 추적하여 Sankey Diagram 분석에 필요한 데이터를 수집합니다.
class ClickHouseNavigatorObserver extends NavigatorObserver {
  ClickHouseNavigatorObserver(this._navigatorLocation);

  final String _navigatorLocation;
  String? _previousScreen;

  @override
  void didPush(Route<void> route, Route<void>? previousRoute) {
    final currentLocation = _getCurrentLocation();
    if (currentLocation != null) {
      unawaited(
        client.ch.events.trackNavigation(
          toScreen: _sanitizeScreenName(currentLocation),
          fromScreen: _previousScreen,
          trigger: 'push',
        ),
      );
      _previousScreen = _sanitizeScreenName(currentLocation);
    }
  }

  @override
  void didPop(Route<void> route, Route<void>? previousRoute) {
    final currentLocation = _getCurrentLocation();
    if (currentLocation != null) {
      unawaited(
        client.ch.events.trackNavigation(
          toScreen: _sanitizeScreenName(currentLocation),
          fromScreen: _previousScreen,
          trigger: 'back',
        ),
      );
      _previousScreen = _sanitizeScreenName(currentLocation);
    }
  }

  @override
  void didRemove(Route<void> route, Route<void>? previousRoute) {
    final currentLocation = _getCurrentLocation();
    if (currentLocation != null) {
      unawaited(
        client.ch.events.trackNavigation(
          toScreen: _sanitizeScreenName(currentLocation),
          fromScreen: _previousScreen,
          trigger: 'remove',
        ),
      );
      _previousScreen = _sanitizeScreenName(currentLocation);
    }
  }

  @override
  void didReplace({Route<void>? newRoute, Route<void>? oldRoute}) {
    final currentLocation = _getCurrentLocation();
    if (currentLocation != null) {
      unawaited(
        client.ch.events.trackNavigation(
          toScreen: _sanitizeScreenName(currentLocation),
          fromScreen: _previousScreen,
          trigger: 'replace',
        ),
      );
      _previousScreen = _sanitizeScreenName(currentLocation);
    }
  }

  /// GoRouter에서 현재 경로 추출
  String? _getCurrentLocation() {
    try {
      final nav = navigator;
      if (nav != null && nav.context.mounted) {
        final router = GoRouter.of(nav.context);
        final path = router.routerDelegate.currentConfiguration.uri.path;
        if (path.isNotEmpty && path != '/') {
          return path;
        }
        if (path == '/') {
          return '/home';
        }
      }
    } catch (_) {}
    return null;
  }

  /// 화면 이름 정규화 (경로 → snake_case)
  ///
  /// 예: '/home/profile' → 'home_profile'
  ///     '/product/123' → 'product_123'
  String _sanitizeScreenName(String screenName) {
    if (screenName == '/') return 'home';
    return screenName
        .replaceAll('/', '_')
        .replaceAll(RegExp('^_'), '')
        .replaceAll(RegExp('[^a-z0-9_]'), '_')
        .replaceAll(RegExp('_+'), '_')
        .replaceAll(RegExp(r'_$'), '')
        .toLowerCase();
  }
}

// GoRouter에서 사용
final router = GoRouter(
  observers: [ClickHouseNavigatorObserver('root')],
  routes: [
    // ... routes
  ],
);
```

### 2. BLoC Observer (상태 변경 자동 추적)

BLoC 패턴을 사용하는 앱에서 상태 변경과 에러를 자동으로 추적합니다.

```dart
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';

/// BLoC 상태 변경 및 에러 자동 추적
class ClickHouseBlocObserver extends BlocObserver {
  const ClickHouseBlocObserver();

  @override
  void onTransition(
    Bloc<Object?, Object?> bloc,
    Transition<Object?, Object?> transition,
  ) {
    super.onTransition(bloc, transition);

    final eventName = _sanitizeEventName(transition.event.runtimeType.toString());
    unawaited(
      client.ch.events.track(
        eventName,
        properties: {
          'bloc_name': bloc.runtimeType.toString(),
          'current_state': transition.currentState.runtimeType.toString(),
          'next_state': transition.nextState.runtimeType.toString(),
        },
      ),
    );
  }

  @override
  void onError(BlocBase<Object?> bloc, Object error, StackTrace stackTrace) {
    unawaited(
      client.ch.events.trackError(
        errorType: 'BlocError',
        message: error.toString(),
        stackTrace: stackTrace.toString(),
        context: {'bloc_name': bloc.runtimeType.toString()},
      ),
    );
    super.onError(bloc, error, stackTrace);
  }

  /// BLoC 이벤트 이름 정규화 (CamelCase → snake_case)
  ///
  /// 예: 'LoginStartedEvent' → 'login_start'
  ///     'UserDataLoadedEvent' → 'user_data_load'
  String _sanitizeEventName(String eventName) {
    var sanitized = eventName
        .replaceAll('Event', '')
        .replaceAll('Started', 'Start')
        .replaceAll('Success', 'OK')
        .replaceAll('Failure', 'Fail')
        .replaceAll('Changed', 'Change')
        .replaceAll('Loaded', 'Load')
        .replaceAll('Updated', 'Update');

    sanitized = sanitized
        .replaceAllMapped(
          RegExp('[A-Z]'),
          (match) => '_${match.group(0)!.toLowerCase()}',
        )
        .replaceAll(RegExp('^_'), '')
        .replaceAll(RegExp('_+'), '_')
        .replaceAll(RegExp(r'_$'), '');

    // 40자 제한
    return sanitized.length > 40 ? sanitized.substring(0, 40) : sanitized;
  }
}

// main.dart에서 설정
void main() {
  Bloc.observer = const ClickHouseBlocObserver();
  runApp(const MyApp());
}
```

### 3. 앱 라이프사이클 Observer

앱 시작/종료/백그라운드 전환을 자동으로 추적합니다.

```dart
import 'dart:async';
import 'package:flutter/widgets.dart';

/// 앱 라이프사이클 자동 추적
class ClickHouseLifecycleObserver extends WidgetsBindingObserver {
  DateTime? _backgroundTime;
  final Stopwatch _sessionStopwatch = Stopwatch();
  String? _currentScreen;
  int _screenCount = 0;

  /// 초기화 - 앱 시작 시 호출
  void init() {
    WidgetsBinding.instance.addObserver(this);
    _sessionStopwatch.start();
    unawaited(client.ch.events.trackAppOpened());
  }

  /// 정리 - 앱 종료 시 호출
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  /// 현재 화면 업데이트 (NavigatorObserver와 연동)
  void setCurrentScreen(String screen) {
    _currentScreen = screen;
    _screenCount++;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _backgroundTime = DateTime.now();
        unawaited(
          client.ch.events.trackAppClosed(
            sessionDurationMs: _sessionStopwatch.elapsedMilliseconds,
            lastScreen: _currentScreen,
            screenCount: _screenCount,
          ),
        );
        break;

      case AppLifecycleState.resumed:
        final bgDuration = _backgroundTime != null
            ? DateTime.now().difference(_backgroundTime!).inMilliseconds
            : null;
        unawaited(
          client.ch.events.trackAppResumed(backgroundDurationMs: bgDuration),
        );
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }
}
```

### 4. Dio API Interceptor

API 호출 성능과 에러를 자동으로 추적합니다.

```dart
import 'dart:async';
import 'package:dio/dio.dart';

/// API 호출 자동 추적 Interceptor
class ClickHouseDioInterceptor extends Interceptor {
  final Map<RequestOptions, DateTime> _requestTimes = {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _requestTimes[options] = DateTime.now();
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _trackApiCall(response.requestOptions, response.statusCode!, true);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _trackApiCall(err.requestOptions, err.response?.statusCode ?? 0, false);

    unawaited(
      client.ch.events.trackApiError(
        endpoint: err.requestOptions.path,
        statusCode: err.response?.statusCode ?? 0,
        errorMessage: err.message,
      ),
    );
    handler.next(err);
  }

  void _trackApiCall(RequestOptions options, int statusCode, bool success) {
    final startTime = _requestTimes.remove(options);
    final duration = startTime != null
        ? DateTime.now().difference(startTime).inMilliseconds
        : 0;

    unawaited(
      client.ch.events.trackApiCall(
        endpoint: options.path,
        method: options.method,
        durationMs: duration,
        statusCode: statusCode,
        success: success,
      ),
    );
  }
}

// Dio에 추가
final dio = Dio();
dio.interceptors.add(ClickHouseDioInterceptor());
```

### 5. 에러 핸들러 (전역 설정)

앱 전체의 에러를 추적합니다.

```dart
import 'dart:async';
import 'package:flutter/material.dart';

void main() {
  // Flutter 프레임워크 에러 추적
  FlutterError.onError = (details) {
    client.ch.events.trackError(
      errorType: 'FlutterError',
      message: details.exceptionAsString(),
      stackTrace: details.stack?.toString(),
    );
    FlutterError.presentError(details);
  };

  // Dart 비동기 에러 추적
  runZonedGuarded(() {
    runApp(const MyApp());
  }, (error, stack) {
    client.ch.events.trackError(
      errorType: error.runtimeType.toString(),
      message: error.toString(),
      stackTrace: stack.toString(),
    );
  });
}
```

### 6. 전체 통합 예시 (main.dart)

위의 모든 Observer를 통합한 완전한 설정 예시입니다.

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

void main() {
  // 1. BLoC Observer 설정
  Bloc.observer = const ClickHouseBlocObserver();

  // 2. Flutter 에러 핸들링
  FlutterError.onError = (details) {
    client.ch.events.trackError(
      errorType: 'FlutterError',
      message: details.exceptionAsString(),
      stackTrace: details.stack?.toString(),
    );
    FlutterError.presentError(details);
  };

  // 3. Dart Zone 에러 핸들링
  runZonedGuarded(() {
    runApp(const MyApp());
  }, (error, stack) {
    client.ch.events.trackError(
      errorType: error.runtimeType.toString(),
      message: error.toString(),
      stackTrace: stack.toString(),
    );
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final ClickHouseLifecycleObserver _lifecycleObserver;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();

    // 4. Lifecycle Observer 초기화
    _lifecycleObserver = ClickHouseLifecycleObserver()..init();

    // 5. GoRouter 설정 (Navigator Observer 포함)
    _router = GoRouter(
      observers: [ClickHouseNavigatorObserver('root')],
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomePage()),
        GoRoute(path: '/products', builder: (_, __) => const ProductListPage()),
        GoRoute(path: '/product/:id', builder: (_, state) => ProductDetailPage(id: state.pathParameters['id']!)),
        // ... more routes
      ],
    );
  }

  @override
  void dispose() {
    _lifecycleObserver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      title: 'My App',
    );
  }
}
```

### 7. 경로 분석 데이터 활용 (Sankey Diagram)

수집된 화면 이동 데이터를 시각화에 활용하는 예시입니다.

```dart
/// 경로 분석 데이터 조회 서비스
class NavigationAnalyticsService {
  /// 화면 이동 경로 데이터 조회 (Sankey Diagram용)
  ///
  /// 반환 형식:
  /// ```json
  /// [
  ///   {"from_screen": "home", "to_screen": "product_list", "transitions": 1500, "unique_users": 800},
  ///   {"from_screen": "product_list", "to_screen": "product_detail", "transitions": 1200, "unique_users": 650}
  /// ]
  /// ```
  Future<List<Map<String, dynamic>>> getNavigationPaths({
    int days = 7,
    int minCount = 10,
  }) async {
    return await client.ch.analytics.getNavigationPaths(
      days: days,
      minCount: minCount,
    );
  }

  /// 이탈 지점 분석
  Future<List<Map<String, dynamic>>> getDropOffPoints({
    String? flowName,
    int days = 7,
  }) async {
    return await client.ch.analytics.getDropOffPoints(
      flowName: flowName,
      days: days,
    );
  }

  /// 플로우 완료율 분석
  Future<List<Map<String, dynamic>>> getFlowCompletionRates({
    int days = 7,
  }) async {
    return await client.ch.analytics.getFlowCompletionRates(days: days);
  }

  /// 개별 사용자 여정 조회
  Future<List<Map<String, dynamic>>> getUserJourney({
    required String userId,
    int days = 7,
  }) async {
    return await client.ch.analytics.getUserJourney(
      userId: userId,
      days: days,
    );
  }
}

// 사용 예시
void example() async {
  final analyticsService = NavigationAnalyticsService();

  // 화면 이동 경로 데이터
  final paths = await analyticsService.getNavigationPaths(days: 7);
  // [
  //   {"from_screen": "home", "to_screen": "product_list", "transitions": 1500, "unique_users": 800},
  //   {"from_screen": "product_list", "to_screen": "product_detail", "transitions": 1200, "unique_users": 650},
  // ]

  // sankey_flutter 등 시각화 라이브러리에서 활용:
  // - from_screen → source 노드
  // - to_screen → target 노드
  // - transitions → 링크 value (플로우 두께)

  // 이탈 지점 분석
  final dropOffs = await analyticsService.getDropOffPoints(flowName: 'checkout');
  // [
  //   {"flow_name": "checkout", "abandoned_at": "payment", "step_index": 3, "abandon_count": 150},
  //   {"flow_name": "checkout", "abandoned_at": "shipping", "step_index": 2, "abandon_count": 80},
  // ]
}
```

---

## 분석 활용 방법

### DAU/WAU/MAU
이벤트를 기록하면 자동으로 DAU/WAU/MAU를 계산할 수 있습니다.

```dart
final dau = await client.ch.analytics.getDau(days: 30);
final wau = await client.ch.analytics.getWau(weeks: 12);
final mau = await client.ch.analytics.getMau(months: 12);
```

### 퍼널 분석
특정 이벤트 시퀀스의 전환율을 분석합니다.

```dart
final funnel = await client.ch.analytics.getFunnel(
  steps: ['signup_started', 'email_entered', 'password_set', 'signup_completed'],
  days: 7,
);
```

### 리텐션 분석
N일 리텐션을 분석합니다.

```dart
final retention = await client.ch.analytics.getRetention(
  cohortEvent: 'signup_completed',
  returnEvent: 'app_opened',
  days: [1, 7, 30],
);
```

### 매출 분석

```dart
final revenue = await client.ch.analytics.getDailyRevenue(days: 30);
final arpu = await client.ch.analytics.getArpu(months: 6);
```

---

## 이벤트 상수 사용

코드에서 이벤트 이름을 직접 문자열로 사용하지 말고 상수를 사용하세요.

```dart
import 'package:serverpod_clickhouse/serverpod_clickhouse.dart';

// 이벤트 이름 상수
BiEvents.appOpened       // 'app_opened'
BiEvents.navigation      // 'navigation'
BiEvents.purchase        // 'purchase'

// 속성 키 상수
BiEventProperties.screenName     // 'screen_name'
BiEventProperties.fromScreen     // 'from_screen'
BiEventProperties.productId      // 'product_id'

// 트리거 타입 상수
NavigationTrigger.button    // 'button'
NavigationTrigger.back      // 'back'
NavigationTrigger.deepLink  // 'deep_link'

// 앱 오픈 소스 상수
AppOpenSource.organic    // 'organic'
AppOpenSource.push       // 'push'
AppOpenSource.deepLink   // 'deep_link'
```

---

## 베스트 프랙티스

1. **일관된 화면 이름 사용**: 화면 이름은 코드에서 상수로 정의하여 일관성 유지
2. **fromScreen 항상 포함**: 경로 분석을 위해 이전 화면 정보 포함
3. **플로우 시작/종료 명시**: 중요한 사용자 여정은 flow 이벤트로 추적
4. **에러 컨텍스트 포함**: 에러 발생 시 화면 이름, 사용자 행동 컨텍스트 포함
5. **성능 측정**: 중요한 화면 로딩, API 호출 시간 측정
6. **배치 전송 활용**: 오프라인 이벤트는 배치로 전송

---

## 체크리스트

### 필수 구현 (Day 1)
- [ ] 앱 시작/종료 이벤트 (`app_opened`, `app_closed`, `app_resumed`)
- [ ] 화면 이동 추적 (`navigation`)
- [ ] 사용자 식별 (`identify`, `logout`)
- [ ] 에러 추적 (`error`, `api_error`)

### 권장 구현 (Week 1)
- [ ] 버튼 클릭 추적 (`button_click`)
- [ ] 검색 추적 (`search`)
- [ ] API 성능 측정 (`api_call`)
- [ ] 플로우 추적 (`flow_started`, `flow_completed`, `flow_abandoned`)

### 커머스 앱 추가 (Week 2)
- [ ] 상품 조회 (`product_view`)
- [ ] 장바구니 이벤트 (`add_to_cart`, `remove_from_cart`)
- [ ] 체크아웃/구매 (`checkout_started`, `purchase`)

### 고급 기능 (Week 3+)
- [ ] 콘텐츠 추적 (`content_view`, `share`)
- [ ] 푸시 알림 추적 (`push_received`, `push_clicked`)
- [ ] A/B 테스트 이벤트
