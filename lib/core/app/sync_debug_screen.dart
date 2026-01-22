import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import '../services/sync_queue_service.dart';
import '../services/sync_service.dart';

class SyncDebugScreen extends StatefulWidget {
  const SyncDebugScreen({super.key});

  @override
  State<SyncDebugScreen> createState() => _SyncDebugScreenState();
}

class _SyncDebugScreenState extends State<SyncDebugScreen> {
  bool _syncing = false;
  int _queueCount = 0;
  String _log = 'Ready';
  List<String> _queuePreview = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final pending = await SyncQueueService.instance.getPending();
    if (!mounted) return;
    setState(() {
      _queueCount = pending.length;
      _queuePreview = pending
          .take(12)
          .map((q) => 'type=${q.entityType} action=${q.action} id=${q.entityId}')
          .toList();
    });
  }

  Future<void> _runSync() async {
    setState(() {
      _syncing = true;
      _log = 'Running sync...';
    });

    try {
      await SyncService.instance.syncAll();
      await _refresh();
      if (!mounted) return;
      setState(() {
        _log = 'Sync finished. Pending queue: $_queueCount';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _log = 'Sync ERROR: $e';
      });
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = ConnectivityService.instance.isConnected.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Debug'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            ListTile(
              title: const Text('Connectivity'),
              subtitle: Text(online ? 'ONLINE' : 'OFFLINE'),
            ),
            ListTile(
              title: const Text('Queue items'),
              subtitle: Text('$_queueCount'),
            ),
            ElevatedButton.icon(
              onPressed: _syncing ? null : _runSync,
              icon: _syncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload),
              label: Text(_syncing ? 'Syncing...' : 'Run Sync Now'),
            ),
            const SizedBox(height: 16),
            const Text('Queue preview (first 12):', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._queuePreview.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(line),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_log),
            ),
          ],
        ),
      ),
    );
  }
}
