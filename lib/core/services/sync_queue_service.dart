import 'dart:convert';
import 'package:uuid/uuid.dart';

import '../persistence/prefs_service.dart';

/// Represents a single pending sync action
class SyncQueueItem {
  final String id;
  final String entityType; // league, announcement, space
  final String entityId;
  final String action; // create | update | delete
  final int lastModified;

  SyncQueueItem({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.lastModified,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'entityType': entityType,
        'entityId': entityId,
        'action': action,
        'lastModified': lastModified,
      };

  factory SyncQueueItem.fromMap(Map<String, dynamic> map) {
    return SyncQueueItem(
      id: map['id'],
      entityType: map['entityType'],
      entityId: map['entityId'],
      action: map['action'],
      lastModified: map['lastModified'],
    );
  }
}

/// Local-only sync queue using SharedPreferences
/// Safe, simple, backend-agnostic
class SyncQueueService {
  SyncQueueService._internal(this._prefs);

  static SyncQueueService? _instance;

  static SyncQueueService init(PreferencesService prefs) {
    _instance ??= SyncQueueService._internal(prefs);
    return _instance!;
  }

  static SyncQueueService get instance {
    if (_instance == null) {
      throw StateError(
        'SyncQueueService not initialized. Call init() first.',
      );
    }
    return _instance!;
  }

  static const _storageKey = 'sync_queue_items';

  final PreferencesService _prefs;
  final Uuid _uuid = const Uuid();

  /// Add a new pending sync action
  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required String action,
    required int lastModified,
  }) async {
    final items = await _loadAll();

    items.add(
      SyncQueueItem(
        id: _uuid.v4(),
        entityType: entityType,
        entityId: entityId,
        action: action,
        lastModified: lastModified,
      ),
    );

    await _saveAll(items);
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
  Future<bool> hasPendingForEntity(
    String entityType,
    String entityId,
  ) async {
    final items = await _loadAll();
    return items.any(
      (e) => e.entityType == entityType && e.entityId == entityId,
    );
  }

  /// Clear everything (debug / logout / full reset)
  Future<void> clearAll() async {
    await _prefs.remove(_storageKey);
  }

  // -----------------
  // Internal helpers
  // -----------------

  Future<List<SyncQueueItem>> _loadAll() async {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => SyncQueueItem.fromMap(e))
        .toList();
  }

  Future<void> _saveAll(List<SyncQueueItem> items) async {
    final encoded =
        jsonEncode(items.map((e) => e.toMap()).toList());
    await _prefs.setString(_storageKey, encoded);
  }
}
