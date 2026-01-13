import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// ClickHouse HTTP 클라이언트 설정
class ClickHouseConfig {
  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
  final bool useSsl;
  final Duration timeout;

  const ClickHouseConfig({
    required this.host,
    this.port = 8443,
    required this.database,
    this.username = 'default',
    this.password = '',
    this.useSsl = true,
    this.timeout = const Duration(seconds: 30),
  });

  /// ClickHouse Cloud 연결용
  factory ClickHouseConfig.cloud({
    required String host,
    required String database,
    required String username,
    required String password,
  }) {
    return ClickHouseConfig(
      host: host,
      port: 8443,
      database: database,
      username: username,
      password: password,
      useSsl: true,
    );
  }

  /// 로컬 개발용
  factory ClickHouseConfig.local({
    String host = 'localhost',
    int port = 8123,
    String database = 'default',
  }) {
    return ClickHouseConfig(
      host: host,
      port: port,
      database: database,
      useSsl: false,
    );
  }

  String get baseUrl {
    final scheme = useSsl ? 'https' : 'http';
    return '$scheme://$host:$port';
  }
}

/// 쿼리 결과 포맷
enum ClickHouseFormat {
  json('JSON'),
  jsonEachRow('JSONEachRow'),
  jsonCompact('JSONCompact'),
  csv('CSV'),
  tabSeparated('TabSeparated');

  final String value;
  const ClickHouseFormat(this.value);
}

/// ClickHouse 쿼리 결과
class ClickHouseResult {
  final List<Map<String, dynamic>> rows;
  final int rowsRead;
  final int bytesRead;
  final Duration elapsed;
  final Map<String, dynamic>? meta;

  ClickHouseResult({
    required this.rows,
    this.rowsRead = 0,
    this.bytesRead = 0,
    this.elapsed = Duration.zero,
    this.meta,
  });

  bool get isEmpty => rows.isEmpty;
  bool get isNotEmpty => rows.isNotEmpty;
  int get length => rows.length;

  /// 첫 번째 행 반환
  Map<String, dynamic>? get firstOrNull => rows.isEmpty ? null : rows.first;

  /// 단일 값 반환 (COUNT, SUM 등)
  T? scalar<T>() {
    if (rows.isEmpty) return null;
    final first = rows.first;
    if (first.isEmpty) return null;
    return first.values.first as T?;
  }
}

/// ClickHouse HTTP 클라이언트
class ClickHouseClient {
  final ClickHouseConfig config;
  final http.Client _httpClient;

  ClickHouseClient(this.config) : _httpClient = http.Client();

  /// SELECT 쿼리 실행
  Future<ClickHouseResult> query(
    String sql, {
    Map<String, dynamic>? params,
    ClickHouseFormat format = ClickHouseFormat.jsonEachRow,
  }) async {
    final stopwatch = Stopwatch()..start();

    // 파라미터 바인딩
    var processedSql = sql;
    if (params != null) {
      params.forEach((key, value) {
        final escaped = _escapeValue(value);
        processedSql = processedSql.replaceAll('{$key}', escaped);
      });
    }

    final uri = Uri.parse(config.baseUrl).replace(
      queryParameters: {
        'database': config.database,
        'default_format': format.value,
      },
    );

    final response = await _httpClient
        .post(
          uri,
          headers: _headers,
          body: processedSql,
        )
        .timeout(config.timeout);

    stopwatch.stop();

    if (response.statusCode != 200) {
      throw ClickHouseException(
        'Query failed: ${response.statusCode}',
        response.body,
      );
    }

    return _parseResponse(response.body, format, stopwatch.elapsed);
  }

  /// INSERT 쿼리 실행 (단일 행)
  Future<void> insert(
    String table,
    Map<String, dynamic> row,
  ) async {
    await insertBatch(table, [row]);
  }

  /// INSERT 쿼리 실행 (배치)
  Future<void> insertBatch(
    String table,
    List<Map<String, dynamic>> rows, {
    ClickHouseFormat format = ClickHouseFormat.jsonEachRow,
  }) async {
    if (rows.isEmpty) return;

    final uri = Uri.parse(config.baseUrl).replace(
      queryParameters: {
        'database': config.database,
        'query': 'INSERT INTO $table FORMAT ${format.value}',
      },
    );

    final body = rows.map((row) => jsonEncode(row)).join('\n');

    final response = await _httpClient
        .post(
          uri,
          headers: _headers,
          body: body,
        )
        .timeout(config.timeout);

    if (response.statusCode != 200) {
      throw ClickHouseException(
        'Insert failed: ${response.statusCode}',
        response.body,
      );
    }
  }

  /// DDL 실행 (CREATE TABLE 등)
  Future<void> execute(String sql) async {
    final uri = Uri.parse(config.baseUrl).replace(
      queryParameters: {
        'database': config.database,
      },
    );

    final response = await _httpClient
        .post(
          uri,
          headers: _headers,
          body: sql,
        )
        .timeout(config.timeout);

    if (response.statusCode != 200) {
      throw ClickHouseException(
        'Execute failed: ${response.statusCode}',
        response.body,
      );
    }
  }

  /// 연결 테스트
  Future<bool> ping() async {
    try {
      final result = await query('SELECT 1');
      return result.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ============================================================================
  // 세션 설정 (25.9+ 성능 최적화)
  // ============================================================================

  /// ClickHouse 서버 버전 조회
  ///
  /// 반환 형식: "25.9.1.123" 등
  Future<String> getServerVersion() async {
    final result = await query('SELECT version() AS version');
    return result.firstOrNull?['version'] as String? ?? '';
  }

  /// 최소 버전 요구사항 확인
  ///
  /// [requiredVersion]은 "25.9" 또는 "25.9.1" 형식입니다.
  /// 서버 버전이 요구 버전 이상이면 true를 반환합니다.
  Future<bool> meetsMinimumVersion(String requiredVersion) async {
    try {
      final serverVersion = await getServerVersion();
      return _compareVersions(serverVersion, requiredVersion) >= 0;
    } catch (_) {
      return false;
    }
  }

  /// 버전 비교 (-1: a < b, 0: a == b, 1: a > b)
  int _compareVersions(String a, String b) {
    final aParts = a.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final bParts = b.split('.').map((p) => int.tryParse(p) ?? 0).toList();

    final maxLength =
        aParts.length > bParts.length ? aParts.length : bParts.length;

    for (var i = 0; i < maxLength; i++) {
      final aVal = i < aParts.length ? aParts[i] : 0;
      final bVal = i < bParts.length ? bParts[i] : 0;

      if (aVal < bVal) return -1;
      if (aVal > bVal) return 1;
    }

    return 0;
  }

  /// Streaming Secondary Indices 활성화
  ///
  /// ClickHouse 25.9+에서 인덱스 평가를 데이터 읽기와 동시에 수행하여
  /// 4배 이상 성능 향상, 50% 메모리 절감, LIMIT 쿼리 조기 종료를 지원합니다.
  ///
  /// 25.9 미만 버전에서는 설정이 무시됩니다 (에러 없이 진행).
  ///
  /// 참고: https://clickhouse.com/blog/streaming-secondary-indices
  Future<bool> enableStreamingIndices() async {
    try {
      await execute('SET use_skip_indexes_on_data_read = 1');
      return true;
    } on ClickHouseException catch (e) {
      // 설정이 지원되지 않는 버전에서는 무시
      if (e.details?.contains('Unknown setting') ?? false) {
        return false;
      }
      rethrow;
    }
  }

  /// 세션 설정 일괄 적용
  ///
  /// 지원되지 않는 설정은 건너뜁니다.
  /// 반환값: 성공적으로 적용된 설정 목록
  Future<List<String>> applySettings(
    Map<String, dynamic> settings, {
    bool throwOnError = false,
  }) async {
    final applied = <String>[];

    for (final entry in settings.entries) {
      try {
        await execute('SET ${entry.key} = ${_escapeValue(entry.value)}');
        applied.add(entry.key);
      } on ClickHouseException catch (e) {
        if (throwOnError) rethrow;
        // Unknown setting 에러는 무시 (버전 호환성)
        if (!(e.details?.contains('Unknown setting') ?? false)) {
          rethrow;
        }
      }
    }

    return applied;
  }

  /// 권장 성능 설정 적용 (대시보드/분석 워크로드용)
  ///
  /// - streaming indices: 인덱스 성능 최적화 (25.9+)
  /// - optimize_read_in_order: ORDER BY 최적화
  ///
  /// 반환값: 성공적으로 적용된 설정 목록
  Future<List<String>> applyRecommendedSettings() async {
    return applySettings({
      'use_skip_indexes_on_data_read': 1,
      'optimize_read_in_order': 1,
    });
  }

  /// 테이블 존재 여부 확인
  Future<bool> tableExists(String table) async {
    final result = await query(
      "SELECT 1 FROM system.tables WHERE database = {db} AND name = {table}",
      params: {'db': config.database, 'table': table},
    );
    return result.isNotEmpty;
  }

  Map<String, String> get _headers => {
        HttpHeaders.contentTypeHeader: 'text/plain; charset=utf-8',
        HttpHeaders.authorizationHeader:
            'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
      };

  String _escapeValue(dynamic value) {
    if (value == null) return 'NULL';
    if (value is num) return value.toString();
    if (value is bool) return value ? '1' : '0';
    if (value is DateTime) return "'${value.toUtc().toIso8601String()}'";
    if (value is List) {
      final items = value.map(_escapeValue).join(', ');
      return '[$items]';
    }
    // String
    final escaped = value.toString().replaceAll("'", "\\'");
    return "'$escaped'";
  }

  ClickHouseResult _parseResponse(
    String body,
    ClickHouseFormat format,
    Duration elapsed,
  ) {
    switch (format) {
      case ClickHouseFormat.jsonEachRow:
        final lines = body.trim().split('\n').where((l) => l.isNotEmpty);
        final rows = lines.map((l) => jsonDecode(l) as Map<String, dynamic>).toList();
        return ClickHouseResult(rows: rows, elapsed: elapsed);

      case ClickHouseFormat.json:
        final json = jsonDecode(body) as Map<String, dynamic>;
        final data = json['data'] as List? ?? [];
        return ClickHouseResult(
          rows: data.cast<Map<String, dynamic>>(),
          rowsRead: json['rows_read'] as int? ?? 0,
          bytesRead: json['bytes_read'] as int? ?? 0,
          elapsed: elapsed,
          meta: json['meta'] as Map<String, dynamic>?,
        );

      default:
        // CSV, TabSeparated 등은 raw로 반환
        return ClickHouseResult(
          rows: [
            {'raw': body}
          ],
          elapsed: elapsed,
        );
    }
  }

  void close() {
    _httpClient.close();
  }
}

/// ClickHouse 예외
class ClickHouseException implements Exception {
  final String message;
  final String? details;

  ClickHouseException(this.message, [this.details]);

  @override
  String toString() => 'ClickHouseException: $message${details != null ? '\n$details' : ''}';
}
