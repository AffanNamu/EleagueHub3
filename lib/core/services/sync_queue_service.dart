/// ONLINE-ONLY MIGRATION (Facebook/X style)
///
/// This project previously used a local sync queue (stored in SharedPreferences)
/// to support offline changes and later background sync.
///
/// Online-only rules:
/// - No local persistence
/// - No background sync
/// - No durable queues
///
/// This file remains ONLY to keep backward compatibility during migration.
/// Any calls to enqueue items become no-ops, and reads always return empty.
///
/// Important:
/// - Do not rely on this queue for correctness.
/// - All writes must go directly to Firestore and surface failures to the user.

class SyncQueueItem {
  final String id;
  final String entityType; // 'league', 'announcement', 'space', ...
  final String entityId;
  final String action; // 'create' | 'update' | 'delete'
  final int lastModified; // ms since epoch
  final Map<String, dynamic>? payload;

  SyncQueueItem({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.lastModified,
    required this.payload,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'entityType': entityType,
        'entityId': entityId,
        'action': action,
        'lastModified': lastModified,
        'payload': payload,
      };

  factory SyncQueueItem.fromMap(Map<String, dynamic> map) {
    return SyncQueueItem(
      id: map['id'] as String,
      entityType: map['entityType'] as String,
      entityId: map['entityId'] as String,
      action: map['action'] as String,
      lastModified: map['lastModified'] as int,
      payload: (map['payload'] as Map?)?.cast<String, dynamic>(),
    );
  }
}

class SyncQueueService {
  SyncQueueService._internal();

  static SyncQueueService? _instance;

  /// Legacy init signature preserved. Argument is ignored in online-only mode.
  static SyncQueueService init(dynamic _unusedPrefs) {
    _instance ??= SyncQueueService._internal();
    return _instance!;
  }

  /// Never throw in online-only mode; always provide a usable (no-op) instance.
  static SyncQueueService get instance {
    _instance ??= SyncQueueService._internal();
    return _instance!;
  }

  Future<void> enqueueItem(SyncQueueItem item) async {
    // No-op (online-only).
  }

  Future<void> enqueue({
    required String id,
    required String entityType,
    required String entityId,
    required String action,
    required int lastModified,
    required Map<String, dynamic>? payload,
  }) async {
    // No-op (online-only).
  }

  Future<List<SyncQueueItem>> getPending() async {
    return const <SyncQueueItem>[];
  }

  Future<void> markDone(String id) async {
    // No-op (online-only).
  }

  Future<bool> hasPendingForEntity(String entityType, String entityId) async {
    return false;
  }

  Future<void> clearAll() async {
    // No-op (online-only).
  }
}
