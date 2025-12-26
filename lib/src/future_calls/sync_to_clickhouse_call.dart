import 'package:serverpod/serverpod.dart';

/// PostgreSQL → ClickHouse 동기화 유틸리티
///
/// 정기적으로 PostgreSQL 데이터를 ClickHouse로 동기화합니다.
/// 사용자 프로젝트에서 상속하여 커스텀 동기화 로직을 구현할 수 있습니다.
///
/// ## 사용 예시
/// ```dart
/// // 직접 호출
/// final syncer = ClickHouseSyncer();
/// await syncer.runSync(session);
///
/// // 또는 상속하여 확장
/// class MySyncer extends ClickHouseSyncer {
///   @override
///   List<SyncTask> getSyncTasks() {
///     return [
///       ...super.getSyncTasks(),
///       SyncTask(
///         tableName: 'custom_orders',
///         syncFunction: _syncCustomOrders,
///       ),
///     ];
///   }
/// }
/// ```
///
/// ## 스케줄링 (Serverpod에서 직접 설정)
/// ```dart
/// // 방법 1: Cron 스타일 (권장)
/// // server.dart에서:
/// Timer.periodic(Duration(hours: 1), (_) async {
///   final session = await pod.createSession();
///   try {
///     await ClickHouseSyncer().runSync(session);
///   } finally {
///     await session.close();
///   }
/// });
///
/// // 방법 2: Endpoint에서 수동 호출
/// class AdminEndpoint extends Endpoint {
///   Future<void> triggerSync(Session session) async {
///     await ClickHouseSyncer().runSync(session);
///   }
/// }
/// ```
class ClickHouseSyncer {
  /// 동기화 실행
  ///
  /// 모든 등록된 동기화 작업을 순차적으로 실행합니다.
  Future<List<SyncResult>> runSync(Session session) async {
    session.log('Starting ClickHouse sync...');

    final tasks = getSyncTasks().where((t) => t.enabled).toList();
    tasks.sort((a, b) => a.priority.compareTo(b.priority));

    final results = <SyncResult>[];

    for (final task in tasks) {
      final result = await _executeTask(session, task);
      results.add(result);

      // 결과 로깅
      if (result.success) {
        session.log(
          'Synced ${task.tableName}: ${result.rowsSynced} rows in ${result.durationMs}ms',
        );
      } else {
        session.log(
          'Failed to sync ${task.tableName}: ${result.errorMessage}',
          level: LogLevel.error,
        );
      }
    }

    // 동기화 결과 저장 (sync_log 테이블에)
    await _saveSyncResults(session, results);

    final successCount = results.where((r) => r.success).length;
    session.log(
      'ClickHouse sync completed: $successCount/${results.length} successful',
    );

    return results;
  }

  /// 동기화할 테이블 목록 반환
  ///
  /// 상속 클래스에서 오버라이드하여 커스텀 동기화 작업을 추가할 수 있습니다.
  List<SyncTask> getSyncTasks() {
    return [
      // 기본 제공 동기화 작업들
      // 사용자가 필요에 따라 오버라이드하여 추가
    ];
  }

  /// 개별 동기화 작업 실행
  Future<SyncResult> _executeTask(Session session, SyncTask task) async {
    final startTime = DateTime.now();

    try {
      final rowsSynced = await task.syncFunction(session);

      return SyncResult(
        tableName: task.tableName,
        success: true,
        rowsSynced: rowsSynced,
        durationMs: DateTime.now().difference(startTime).inMilliseconds,
      );
    } catch (e, stackTrace) {
      session.log(
        'Sync error for ${task.tableName}: $e\n$stackTrace',
        level: LogLevel.error,
      );

      return SyncResult(
        tableName: task.tableName,
        success: false,
        rowsSynced: 0,
        durationMs: DateTime.now().difference(startTime).inMilliseconds,
        errorMessage: e.toString(),
      );
    }
  }

  /// 동기화 결과를 PostgreSQL에 저장
  Future<void> _saveSyncResults(
    Session session,
    List<SyncResult> results,
  ) async {
    for (final result in results) {
      try {
        // SQL Injection 방지를 위해 parameterized query 사용
        final status = result.success ? 'completed' : 'failed';
        final errorMsg = result.errorMessage?.replaceAll("'", "''");

        await session.db.unsafeExecute('''
          INSERT INTO serverpod_clickhouse_sync_log
            (table_name, last_synced_at, rows_synced, status, error_message, duration_ms)
          VALUES
            ('${result.tableName.replaceAll("'", "''")}',
             NOW(),
             ${result.rowsSynced},
             '$status',
             ${errorMsg != null ? "'$errorMsg'" : 'NULL'},
             ${result.durationMs})
        ''');
      } catch (e) {
        session.log(
          'Failed to save sync result for ${result.tableName}: $e',
          level: LogLevel.warning,
        );
      }
    }
  }
}

/// 동기화 작업 정의
class SyncTask {
  /// 테이블 이름 (로깅 및 추적용)
  final String tableName;

  /// 동기화 함수 - 동기화된 행 수를 반환
  final Future<int> Function(Session session) syncFunction;

  /// 동기화 우선순위 (낮을수록 먼저 실행)
  final int priority;

  /// 활성화 여부
  final bool enabled;

  const SyncTask({
    required this.tableName,
    required this.syncFunction,
    this.priority = 100,
    this.enabled = true,
  });
}

/// 동기화 결과
class SyncResult {
  final String tableName;
  final bool success;
  final int rowsSynced;
  final int durationMs;
  final String? errorMessage;
  final DateTime syncedAt;

  SyncResult({
    required this.tableName,
    required this.success,
    required this.rowsSynced,
    required this.durationMs,
    this.errorMessage,
    DateTime? syncedAt,
  }) : syncedAt = syncedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'tableName': tableName,
        'success': success,
        'rowsSynced': rowsSynced,
        'durationMs': durationMs,
        'errorMessage': errorMessage,
        'syncedAt': syncedAt.toIso8601String(),
      };
}

/// 사용자 동기화 구현 예시
///
/// 사용자가 자신의 프로젝트에서 이 패턴을 참고하여 구현합니다.
/// ```dart
/// import 'package:serverpod_clickhouse/serverpod_clickhouse.dart';
///
/// class MyOrderSyncer extends ClickHouseSyncer {
///   @override
///   List<SyncTask> getSyncTasks() {
///     return [
///       ...super.getSyncTasks(),
///       SyncTask(
///         tableName: 'orders',
///         syncFunction: _syncOrders,
///         priority: 10,
///       ),
///       SyncTask(
///         tableName: 'order_items',
///         syncFunction: _syncOrderItems,
///         priority: 20,
///       ),
///     ];
///   }
///
///   Future<int> _syncOrders(Session session) async {
///     // 마지막 동기화 이후 변경된 주문 조회
///     final lastSync = await _getLastSyncTime(session, 'orders');
///
///     final orders = await session.db.find<Order>(
///       where: (t) => t.updatedAt > lastSync,
///       orderBy: (t) => t.updatedAt,
///       limit: 10000,
///     );
///
///     if (orders.isEmpty) return 0;
///
///     // ClickHouse에 배치 삽입
///     final rows = orders.map((o) => {
///       'order_id': o.id.toString(),
///       'user_id': o.userId.toString(),
///       'total_amount': o.totalAmount,
///       'status': o.status,
///       'created_at': o.createdAt.toIso8601String(),
///     }).toList();
///
///     await ClickHouseService.instance.client.insertBatch('orders', rows);
///
///     return orders.length;
///   }
///
///   Future<DateTime> _getLastSyncTime(Session session, String tableName) async {
///     final result = await session.db.unsafeQuery('''
///       SELECT last_synced_at FROM serverpod_clickhouse_sync_log
///       WHERE table_name = '$tableName' AND status = 'completed'
///       ORDER BY last_synced_at DESC LIMIT 1
///     ''');
///     if (result.isNotEmpty) {
///       return result.first['last_synced_at'] as DateTime;
///     }
///     return DateTime.fromMillisecondsSinceEpoch(0);
///   }
/// }
/// ```
