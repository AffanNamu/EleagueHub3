import 'dart:convert';

import '../persistence/prefs_service.dart';

/// One queued local change to be synced to cloud later.
///
/// payload:
/// - for create/update: JSON map of the entity (Firestore-ready)
/// - for delete: null
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

/// Local-only sync queue using SharedPreferences.
/// Safe, simple, backend-agnostic.
class SyncQueueService {
  SyncQueueService._internal(this._prefs);

  static SyncQueueService? _instance;

  static SyncQueueService init(PreferencesService prefs) {
    _instance ??= SyncQueueService._internal(prefs);
    return _instance!;
  }

  static SyncQueueService get instance {
    final inst = _instance;
    if (inst == null) {
      throw StateError('SyncQueueService not initialized. Call init() first.');
    }
    return inst;
  }

  static const _storageKey = 'sync_queue_items';

  final PreferencesService _prefs;

  /// Add a new pending sync action.
  ///
  /// You generate the queue item id outside OR just pass something stable.
  /// (We keep your "id" field in the queue item so markDone works.)
  Future<void> enqueueItem(SyncQueueItem item) async {
    final items = await _loadAll();
    items.add(item);
    await _saveAll(items);
  }

  /// Convenience API (if you don't want to build SyncQueueItem manually)
  Future<void> enqueue({
    required String id,
    required String entityType,
    required String entityId,
    required String action,
    required int lastModified,
    required Map<String, dynamic>? payload,
  }) async {
    await enqueueItem(
      SyncQueueItem(
        id: id,
        entityType: entityType,
        entityId: entityId,
        action: action,
        lastModified: lastModified,
        payload: payload,
      ),
    );
  }

  /// Get all pending items (ordered oldest → newest)
  Future<List<SyncQueueItem>> getPending() async {
    final items = await _loadAll();
    items.sort((a, b) => a.lastModified.compareTo(b.lastModified));
    return items;
  }

  /// Remove item after successful sync
  Future<void> markDone(String id) async {
    final items = await _loadAll();
    items.removeWhere((e) => e.id == id);
    await _saveAll(items);
  }

  /// Check if a specific entity has pending changes
  Future<bool> hasPendingForEntity(String entityType, String entityId) async {
    final items = await _loadAll();
    return items.any((e) => e.entityType == entityType && e.entityId == entityId);
  }

  /// Clear everything (debug / logout / full reset)
  Future<void> clearAll() async {
    // PreferencesService does not expose remove(); store empty value instead.
    await _prefs.setString(_storageKey, '');
  }

  // -----------------
  // Internal helpers
  // -----------------

  Future<List<SyncQueueItem>> _loadAll() async {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => SyncQueueItem.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> _saveAll(List<SyncQueueItem> items) async {
    final encoded = jsonEncode(items.map((e) => e.toMap()).toList());
    await _prefs.setString(_storageKey, encoded);
  }
}
