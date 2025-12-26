import 'clickhouse_client.dart';

/// 스키마 매니저 - 테이블 생성 및 마이그레이션
class SchemaManager {
  final ClickHouseClient _client;

  SchemaManager(this._client);

  /// 이벤트 테이블 생성
  Future<void> createEventsTable({
    String tableName = 'events',
    int ttlDays = 180,
  }) async {
    await _client.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        -- 이벤트 식별
        event_id UUID DEFAULT generateUUIDv4(),
        event_name LowCardinality(String),
        
        -- 사용자 식별
        user_id String,
        session_id String,
        anonymous_id String,
        
        -- 시간
        timestamp DateTime64(3) DEFAULT now64(3),
        server_time DateTime64(3) DEFAULT now64(3),
        
        -- 디바이스/환경
        device_type LowCardinality(String) DEFAULT '',
        os LowCardinality(String) DEFAULT '',
        os_version LowCardinality(String) DEFAULT '',
        app_version LowCardinality(String) DEFAULT '',
        
        -- 위치
        country LowCardinality(String) DEFAULT '',
        region LowCardinality(String) DEFAULT '',
        
        -- 이벤트 속성 (JSON)
        properties String DEFAULT '{}' CODEC(ZSTD(1)),
        
        -- 메타데이터
        _inserted_at DateTime64(3) DEFAULT now64(3)
      )
      ENGINE = MergeTree()
      PARTITION BY toYYYYMM(timestamp)
      ORDER BY (user_id, timestamp, event_id)
      TTL timestamp + INTERVAL $ttlDays DAY
      SETTINGS index_granularity = 8192
    ''');

    // 인덱스 추가
    await _client.execute('''
      ALTER TABLE $tableName 
      ADD INDEX IF NOT EXISTS idx_event_name event_name 
      TYPE bloom_filter GRANULARITY 4
    ''');

    await _client.execute('''
      ALTER TABLE $tableName 
      ADD INDEX IF NOT EXISTS idx_session session_id 
      TYPE bloom_filter GRANULARITY 4
    ''');
  }

  /// 주문 테이블 생성 (매출 분석용)
  Future<void> createOrdersTable({
    String tableName = 'orders',
    int ttlDays = 365 * 2, // 2년
  }) async {
    await _client.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        -- 주문 식별
        order_id String,
        external_order_id String DEFAULT '',
        
        -- 사용자
        user_id String,
        
        -- 금액
        total_amount Decimal64(2),
        discount_amount Decimal64(2) DEFAULT 0,
        tax_amount Decimal64(2) DEFAULT 0,
        currency LowCardinality(String) DEFAULT 'KRW',
        
        -- 상태
        status LowCardinality(String), -- pending, completed, cancelled, refunded
        
        -- 결제
        payment_method LowCardinality(String) DEFAULT '',
        payment_provider LowCardinality(String) DEFAULT '',
        
        -- 시간
        created_at DateTime64(3),
        completed_at Nullable(DateTime64(3)),
        
        -- 메타데이터
        _synced_at DateTime64(3) DEFAULT now64(3)
      )
      ENGINE = ReplacingMergeTree(_synced_at)
      PARTITION BY toYYYYMM(created_at)
      ORDER BY (user_id, created_at, order_id)
      TTL created_at + INTERVAL $ttlDays DAY
    ''');
  }

  /// 주문 상품 테이블 생성
  Future<void> createOrderItemsTable({
    String tableName = 'order_items',
    int ttlDays = 365 * 2,
  }) async {
    await _client.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        -- 식별
        order_id String,
        item_id String,
        
        -- 상품
        product_id String,
        product_name String,
        category LowCardinality(String) DEFAULT '',
        
        -- 금액
        price Decimal64(2),
        quantity UInt32,
        discount Decimal64(2) DEFAULT 0,
        
        -- 시간
        created_at DateTime64(3),
        
        -- 메타데이터
        _synced_at DateTime64(3) DEFAULT now64(3)
      )
      ENGINE = ReplacingMergeTree(_synced_at)
      PARTITION BY toYYYYMM(created_at)
      ORDER BY (order_id, item_id)
      TTL created_at + INTERVAL $ttlDays DAY
    ''');
  }

  /// 사용자 프로필 테이블 (차원 테이블)
  Future<void> createUsersTable({
    String tableName = 'users',
  }) async {
    await _client.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        user_id String,
        
        -- 기본 정보
        email String DEFAULT '',
        name String DEFAULT '',
        
        -- 세그먼트
        plan LowCardinality(String) DEFAULT 'free',
        user_type LowCardinality(String) DEFAULT '',
        
        -- 시간
        created_at DateTime64(3),
        first_seen_at DateTime64(3),
        last_seen_at DateTime64(3),
        
        -- 메타데이터
        properties String DEFAULT '{}' CODEC(ZSTD(1)),
        _synced_at DateTime64(3) DEFAULT now64(3)
      )
      ENGINE = ReplacingMergeTree(_synced_at)
      ORDER BY user_id
    ''');
  }

  /// 일일 집계 Materialized View 생성
  Future<void> createDailyAggregationMV({
    String sourceTable = 'events',
    String mvName = 'events_daily_mv',
  }) async {
    await _client.execute('''
      CREATE MATERIALIZED VIEW IF NOT EXISTS $mvName
      ENGINE = SummingMergeTree()
      PARTITION BY toYYYYMM(date)
      ORDER BY (date, event_name, user_id)
      AS SELECT
        toDate(timestamp) AS date,
        event_name,
        user_id,
        count() AS event_count
      FROM $sourceTable
      GROUP BY date, event_name, user_id
    ''');
  }

  /// 모든 기본 테이블 생성
  Future<void> initializeSchema() async {
    await createEventsTable();
    await createOrdersTable();
    await createOrderItemsTable();
    await createUsersTable();
    await createDailyAggregationMV();
  }

  /// 테이블 삭제 (주의!)
  Future<void> dropTable(String tableName) async {
    await _client.execute('DROP TABLE IF EXISTS $tableName');
  }

  /// 테이블 목록 조회
  Future<List<String>> listTables() async {
    final result = await _client.query(
      'SELECT name FROM system.tables WHERE database = {db}',
      params: {'db': _client.config.database},
    );
    return result.rows.map((r) => r['name'] as String).toList();
  }

  /// 테이블 스키마 조회
  Future<ClickHouseResult> describeTable(String tableName) async {
    return _client.query(
      'DESCRIBE TABLE $tableName',
    );
  }
}

/// PostgreSQL → ClickHouse 동기화 유틸리티
/// 
/// 실제 사용 시에는 ClickPipes, Debezium, 또는 배치 ETL을 권장합니다.
/// 이 클래스는 간단한 배치 동기화를 위한 헬퍼입니다.
class SyncUtility {
  final ClickHouseClient _clickhouse;

  SyncUtility(this._clickhouse);

  /// 주문 데이터 동기화 (Serverpod/PostgreSQL → ClickHouse)
  /// 
  /// Serverpod에서 호출하는 예시:
  /// ```dart
  /// final orders = await Order.db.find(
  ///   session,
  ///   where: (t) => t.updatedAt > lastSyncTime,
  /// );
  /// await syncUtility.syncOrders(orders.map((o) => o.toMap()).toList());
  /// ```
  Future<void> syncOrders(
    List<Map<String, dynamic>> orders, {
    String tableName = 'orders',
  }) async {
    if (orders.isEmpty) return;

    final rows = orders.map((order) => {
      'order_id': order['id']?.toString() ?? '',
      'external_order_id': order['externalId']?.toString() ?? '',
      'user_id': order['userId']?.toString() ?? '',
      'total_amount': order['totalAmount'] ?? 0,
      'discount_amount': order['discountAmount'] ?? 0,
      'tax_amount': order['taxAmount'] ?? 0,
      'currency': order['currency'] ?? 'KRW',
      'status': order['status'] ?? 'pending',
      'payment_method': order['paymentMethod'] ?? '',
      'payment_provider': order['paymentProvider'] ?? '',
      'created_at': _formatDateTime(order['createdAt']),
      'completed_at': order['completedAt'] != null 
          ? _formatDateTime(order['completedAt']) 
          : null,
    }).toList();

    await _clickhouse.insertBatch(tableName, rows);
  }

  /// 사용자 데이터 동기화
  Future<void> syncUsers(
    List<Map<String, dynamic>> users, {
    String tableName = 'users',
  }) async {
    if (users.isEmpty) return;

    final rows = users.map((user) => {
      'user_id': user['id']?.toString() ?? '',
      'email': user['email'] ?? '',
      'name': user['name'] ?? '',
      'plan': user['plan'] ?? 'free',
      'user_type': user['userType'] ?? '',
      'created_at': _formatDateTime(user['createdAt']),
      'first_seen_at': _formatDateTime(user['firstSeenAt'] ?? user['createdAt']),
      'last_seen_at': _formatDateTime(user['lastSeenAt'] ?? DateTime.now()),
    }).toList();

    await _clickhouse.insertBatch(tableName, rows);
  }

  String _formatDateTime(dynamic value) {
    if (value == null) return DateTime.now().toUtc().toIso8601String();
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is String) return value;
    return DateTime.now().toUtc().toIso8601String();
  }
}
