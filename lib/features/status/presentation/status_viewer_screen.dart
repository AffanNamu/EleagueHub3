// lib/features/status/presentation/status_viewer_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../auth/data/user_profile_repository.dart';
import '../data/status_repository.dart';
import '../models/user_status.dart';

/// Full-screen status viewer (Feature 2). Displays every active
/// status for a single user, auto-advancing like a story, with a
/// progress bar per item, tap-to-advance/back, and a close control.
class StatusViewerScreen extends StatefulWidget {
  const StatusViewerScreen({super.key, required this.userId});

  final String userId;

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _perStatusDuration = Duration(seconds: 6);

  final StatusRepository _repo = StatusRepository();
  final UserProfileRepository _userRepo = UserProfileRepository();

  bool _loading = true;
  String? _error;
  List<UserStatus> _items = const [];
  String _displayName = 'User';

  int _index = 0;
  late final AnimationController _progress;

  String get _selfUid => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
  bool get _isOwner => _selfUid.isNotEmpty && _selfUid == widget.userId.trim();

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: _perStatusDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _goNext();
      });
    _load();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repo.fetchActiveStatuses(widget.userId);
      final name = await _userRepo.fetchDisplayNameByUserId(widget.userId);

      if (!mounted) return;

      setState(() {
        _loading = false;
        _items = items;
        _displayName = name;
        _index = 0;
      });

      if (items.isNotEmpty) {
        _progress
          ..reset()
          ..forward();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));
      });
    }
  }

  void _goNext() {
    if (_index >= _items.length - 1) {
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    setState(() => _index++);
    _progress
      ..reset()
      ..forward();
  }

  void _goPrevious() {
    if (_index <= 0) {
      _progress
        ..reset()
        ..forward();
      return;
    }
    setState(() => _index--);
    _progress
      ..reset()
      ..forward();
  }

  Future<void> _confirmDelete() async {
    _progress.stop();
    final current = _items[_index];
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this status?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) {
      _progress.forward();
      return;
    }
    try {
      await _repo.deleteStatus(userId: widget.userId, statusId: current.statusId);
      if (!mounted) return;
      final remaining = List<UserStatus>.from(_items)..removeAt(_index);
      if (remaining.isEmpty) {
        Navigator.of(context).maybePop();
        return;
      }
      setState(() {
        _items = remaining;
        if (_index >= _items.length) _index = _items.length - 1;
      });
      _progress
        ..reset()
        ..forward();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')))),
      );
      _progress.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : _error != null
                ? _MessageState(message: _error!, onClose: () => Navigator.of(context).maybePop())
                : _items.isEmpty
                    ? _MessageState(
                        message: 'No active status right now.',
                        onClose: () => Navigator.of(context).maybePop(),
                      )
                    : _buildViewer(),
      ),
    );
  }

  Widget _buildViewer() {
    final current = _items[_index];

    return GestureDetector(
      onTapUp: (details) {
        final width = MediaQuery.of(context).size.width;
        if (details.globalPosition.dx < width / 3) {
          _goPrevious();
        } else {
          _goNext();
        }
      },
      onLongPressStart: (_) => _progress.stop(),
      onLongPressEnd: (_) => _progress.forward(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            current.imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
            ),
            loadingBuilder: (context, child, event) {
              if (event == null) return child;
              return const Center(child: CircularProgressIndicator(color: Colors.white));
            },
          ),
          Positioned(
            left: 8,
            right: 8,
            top: 8,
            child: Row(
              children: List.generate(_items.length, (i) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AnimatedBuilder(
                      animation: _progress,
                      builder: (context, _) {
                        double value;
                        if (i < _index) {
                          value = 1;
                        } else if (i == _index) {
                          value = _progress.value;
                        } else {
                          value = 0;
                        }
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: 3,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation(Colors.white),
                          ),
                        );
                      },
                    ),
                  ),
                );
              }),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 20,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_isOwner)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                    onPressed: _confirmDelete,
                  ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          if (current.caption.trim().isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 32,
              child: Text(
                current.caption,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, required this.onClose});
  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: onClose,
          ),
        ),
      ],
    );
  }
}
