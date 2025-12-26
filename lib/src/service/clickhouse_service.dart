import 'dart:io';

import 'package:serverpod/serverpod.dart';

import '../business/clickhouse_client.dart';
import '../business/event_tracker.dart';
import '../business/analytics_queries.dart';
import '../business/schema_manager.dart';

/// ClickHouse 서비스 싱글톤
///
/// Serverpod 서버에서 초기화하여 전역적으로 사용합니다.
///
/// ## 사용 예시
/// ```dart
/// // server.dart에서 초기화
/// await ClickHouseService.initialize(pod);
///
/// // Endpoint에서 사용
/// final dau = await ClickHouseService.instance.analytics.dau(days: 30);
/// ```
class ClickHouseService {
  static ClickHouseService? _instance;

  /// 싱글톤 인스턴스 접근
  ///
  /// [initialize]가 호출되지 않았으면 [StateError]를 던집니다.
  static ClickHouseService get instance {
    if (_instance == null) {
      throw StateError(
        'ClickHouseService not initialized. '
        'Call ClickHouseService.initialize() in your server.dart',
      );
    }
    return _instance!;
  }

  /// 초기화 여부 확인
  static bool get isInitialized => _instance != null;

  /// ClickHouse HTTP 클라이언트
  final ClickHouseClient client;

  /// 이벤트 트래커 (배치 전송)
  final EventTracker tracker;

  /// 분석 쿼리 빌더
  final AnalyticsQueryBuilder analytics;

  /// 스키마 관리자
  final SchemaManager schema;

  /// 동기화 유틸리티
  final SyncUtility sync;

  ClickHouseService._({
    required this.client,
    required this.tracker,
    required this.analytics,
    required this.schema,
    required this.sync,
  });

  /// Serverpod 서버에서 초기화
  ///
  /// passwords.yaml에서 설정을 읽어옵니다. 환경변수를 fallback으로 사용합니다.
  ///
  /// ### passwords.yaml 설정 예시
  /// ```yaml
  /// development:
  ///   clickhouse_host: 'xxx.clickhouse.cloud'
  ///   clickhouse_database: 'analytics'
  ///   clickhouse_username: 'default'
  ///   clickhouse_password: 'your-password'
  ///   clickhouse_use_ssl: 'true'
  ///   clickhouse_port: '8443'  # 선택사항
  /// ```
  ///
  /// ### 환경변수 fallback
  /// - `CLICKHOUSE_HOST` (필수)
  /// - `CLICKHOUSE_DATABASE` (기본값: 'analytics')
  /// - `CLICKHOUSE_USERNAME` (기본값: 'default')
  /// - `CLICKHOUSE_PASSWORD` (기본값: '')
  /// - `CLICKHOUSE_USE_SSL` (기본값: 'true')
  /// - `CLICKHOUSE_PORT` (기본값: SSL 사용 시 8443, 미사용 시 8123)
  static Future<ClickHouseService> initialize(
    Serverpod pod, {
    String? eventsTable,
    EventTrackerConfig? trackerConfig,
  }) async {
    // 1. passwords.yaml에서 설정 읽기 (우선)
    final host =
        pod.getPassword('clickhouse_host') ?? _getEnvOrThrow('CLICKHOUSE_HOST');
    final database = pod.getPassword('clickhouse_database') ??
        _getEnv('CLICKHOUSE_DATABASE', 'analytics');
    final username = pod.getPassword('clickhouse_username') ??
        _getEnv('CLICKHOUSE_USERNAME', 'default');
    final password = pod.getPassword('clickhouse_password') ??
        _getEnv('CLICKHOUSE_PASSWORD', '');
    final useSsl =
        (pod.getPassword('clickhouse_use_ssl') ?? _getEnv('CLICKHOUSE_USE_SSL', 'true')) ==
            'true';
    final port =
        int.tryParse(pod.getPassword('clickhouse_port') ?? _getEnv('CLICKHOUSE_PORT', '')) ??
            (useSsl ? 8443 : 8123);

    // 2. 클라이언트 생성
    final config = useSsl
        ? ClickHouseConfig.cloud(
            host: host,
            database: database,
            username: username,
            password: password,
          )
        : ClickHouseConfig(
            host: host,
            port: port,
            database: database,
            username: username,
            password: password,
            useSsl: false,
          );

    final client = ClickHouseClient(config);

    // 3. 연결 테스트
    final connected = await client.ping();
    if (!connected) {
      throw Exception(
        'Failed to connect to ClickHouse at ${config.host}:${config.port}',
      );
    }

    // 4. 서비스 구성
    _instance = ClickHouseService._(
      client: client,
      tracker: EventTracker(client, config: trackerConfig),
      analytics:
          AnalyticsQueryBuilder(client, eventsTable: eventsTable ?? 'events'),
      schema: SchemaManager(client),
      sync: SyncUtility(client),
    );

    return _instance!;
  }

  /// 수동 설정으로 초기화 (테스트용)
  ///
  /// Serverpod 없이 직접 [ClickHouseConfig]를 전달하여 초기화합니다.
  static Future<ClickHouseService> initializeWithConfig(
    ClickHouseConfig config, {
    String? eventsTable,
    EventTrackerConfig? trackerConfig,
  }) async {
    final client = ClickHouseClient(config);

    final connected = await client.ping();
    if (!connected) {
      throw Exception(
        'Failed to connect to ClickHouse at ${config.host}:${config.port}',
      );
    }

    _instance = ClickHouseService._(
      client: client,
      tracker: EventTracker(client, config: trackerConfig),
      analytics:
          AnalyticsQueryBuilder(client, eventsTable: eventsTable ?? 'events'),
      schema: SchemaManager(client),
      sync: SyncUtility(client),
    );

    return _instance!;
  }

  /// 서버 종료 시 호출
  ///
  /// 버퍼에 남은 이벤트를 모두 전송하고 클라이언트를 정리합니다.
  Future<void> shutdown() async {
    await tracker.shutdown();
    client.close();
    _instance = null;
  }

  /// 인스턴스 리셋 (테스트용)
  static void reset() {
    _instance = null;
  }

  static String _getEnvOrThrow(String key) {
    final value = Platform.environment[key];
    if (value == null || value.isEmpty) {
      throw ArgumentError(
        'Environment variable $key is required. '
        'Set it in passwords.yaml or as an environment variable.',
      );
    }
    return value;
  }

  static String _getEnv(String key, String defaultValue) {
    final value = Platform.environment[key];
    return (value != null && value.isNotEmpty) ? value : defaultValue;
  }
}
