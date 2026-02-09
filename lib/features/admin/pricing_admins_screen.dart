import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PricingAdminsScreen extends StatefulWidget {
  const PricingAdminsScreen({super.key});

  @override
  State<PricingAdminsScreen> createState() => _PricingAdminsScreenState();
}

class _PricingAdminsScreenState extends State<PricingAdminsScreen> {
  final _doc = FirebaseFirestore.instance.collection('app').doc('admins');

  bool _saving = false;
  String? _error;

  final _newUidCtrl = TextEditingController();

  @override
  void dispose() {
    _newUidCtrl.dispose();
    super.dispose();
  }

  Future<void> _addUid() async {
    final uid = _newUidCtrl.text.trim();
    if (uid.isEmpty) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _doc.set({
        'pricingAdmins': FieldValue.arrayUnion([uid]),
      }, SetOptions(merge: true));

      _newUidCtrl.clear();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin added')),
      );
    } on FirebaseException catch (e) {
      setState(() => _error = 'Failed to add: ${e.message ?? e.code}');
    } catch (e) {
      setState(() => _error = 'Failed to add: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeUid(String uid) async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _doc.set({
        'pricingAdmins': FieldValue.arrayRemove([uid]),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin removed')),
      );
    } on FirebaseException catch (e) {
      setState(() => _error = 'Failed to remove: ${e.message ?? e.code}');
    } catch (e) {
      setState(() => _error = 'Failed to remove: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pricing Admins'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _doc.snapshots(),
        builder: (context, snap) {
          final theme = Theme.of(context);
          final cs = theme.colorScheme;

          if (snap.hasError) {
            return Center(
              child: Text(
                'Failed to load admins.',
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.error, fontWeight: FontWeight.w800),
              ),
            );
          }

          if (!snap.hasData) {
            return Center(child: CircularProgressIndicator(color: cs.primary));
          }

          final data = snap.data!.data() ?? <String, dynamic>{};
          final list = <String>[];
          final raw = data['pricingAdmins'];
          if (raw is List) {
            for (final v in raw) {
              if (v is String && v.trim().isNotEmpty) list.add(v.trim());
            }
          }
          list.sort();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.error.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.error.withOpacity(0.35)),
                        ),
                        child: Text(
                          _error!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.error,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      'Your UID: $me',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.75),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _newUidCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Add pricing admin UID',
                        prefixIcon: Icon(Icons.person_add_alt),
                        helperText: 'Paste Firebase Auth UID and tap Add',
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _saving ? null : _addUid,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Current pricing admins (dynamic)',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (list.isEmpty)
                      Text(
                        'No dynamic admins yet.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.65),
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else
                      ...list.map(
                        (u) => Card(
                          child: ListTile(
                            leading: const Icon(Icons.verified_user),
                            title: Text(
                              u,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: 'Remove',
                              icon: Icon(Icons.remove_circle_outline, color: cs.error),
                              onPressed: _saving ? null : () => _removeUid(u),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      'Note: Some admins may be whitelisted in the app build and are not editable here.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.60),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
