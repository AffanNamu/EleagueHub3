import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/color_compat.dart';
import '../../../../core/widgets/glass.dart';
import '../../../../core/widgets/glass_scaffold.dart';
import '../../data/models/reward_model.dart';
import '../../data/services/reward_firestore_service.dart';
import '../../../marketplace/data/cloudinary_upload_service.dart';
import '../widgets/reward_card.dart';

class EditLeagueRewardsScreen extends StatefulWidget {
  const EditLeagueRewardsScreen({
    super.key,
    required this.leagueId,
  });

  final String leagueId;

  @override
  State<EditLeagueRewardsScreen> createState() => _EditLeagueRewardsScreenState();
}

class _EditLeagueRewardsScreenState extends State<EditLeagueRewardsScreen> {
  final RewardFirestoreService _service = RewardFirestoreService();

  Future<bool> _isOrganizer() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return false;

    final leagueSnap = await FirebaseFirestore.instance
        .collection('leagues')
        .doc(widget.leagueId)
        .get();
    final data = leagueSnap.data();
    if (data == null) return false;

    final organizerUid =
        (data['organizerUid'] ?? data['createdBy'] ?? data['ownerUid'] ?? '')
            .toString();
    return organizerUid.isNotEmpty && organizerUid == uid;
  }

  Future<void> _createReward() async {
    if (!mounted) return;
    final created = await showModalBottomSheet<RewardModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RewardEditorSheet(
        leagueId: widget.leagueId,
        title: 'Add Reward',
      ),
    );

    if (!mounted || created == null) return;
    await _service.createReward(leagueId: widget.leagueId, reward: created);
  }

  Future<void> _editReward(RewardModel reward) async {
    if (!mounted) return;
    final updated = await showModalBottomSheet<RewardModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RewardEditorSheet(
        leagueId: widget.leagueId,
        title: 'Edit Reward',
        initialReward: reward,
      ),
    );

    if (!mounted || updated == null) return;
    await _service.updateReward(
      leagueId: widget.leagueId,
      rewardId: reward.id,
      reward: updated.copyWith(id: reward.id),
    );
  }

  Future<void> _deleteReward(RewardModel reward) async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dialogBg =
        theme.brightness == Brightness.light ? Colors.white.withOpacity(0.92) : cs.surface;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: dialogBg,
          title: const Text('Delete reward?'),
          content: Text('This will permanently remove "${reward.rewardName}".'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;
    await _service.deleteReward(leagueId: widget.leagueId, rewardId: reward.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;

    final pageBody = FutureBuilder<bool>(
      future: _isOrganizer(),
      builder: (context, permSnap) {
        if (permSnap.connectionState != ConnectionState.done) {
          return Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: cs.primary,
              ),
            ),
          );
        }

        final isOrganizer = permSnap.data == true;
        if (!isOrganizer) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                'You do not have permission to manage rewards for this league.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withOpacity(0.80),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          );
        }

        return StreamBuilder<List<RewardModel>>(
          stream: _service.streamRewards(leagueId: widget.leagueId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text(
                    snapshot.error.toString(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.error.withOpacity(0.95),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              );
            }

            if (!snapshot.hasData) {
              return Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: cs.primary,
                  ),
                ),
              );
            }

            final rewards = snapshot.data ?? const <RewardModel>[];
            if (rewards.isEmpty) {
              return Center(
                child: Text(
                  'No rewards yet. Tap "Add Reward" to create one.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withOpacity(0.78),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: rewards.length,
              itemBuilder: (context, index) {
                final reward = rewards[index];
                return RewardCard(
                  reward: reward,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        tooltip: 'Edit',
                        onPressed: () => _editReward(reward),
                        icon: Icon(
                          Icons.edit_outlined,
                          color: cs.onSurface.withOpacity(0.85),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        onPressed: () => _deleteReward(reward),
                        icon: Icon(
                          Icons.delete_outline,
                          color: cs.error.withOpacity(0.95),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );

    final fab = FutureBuilder<bool>(
      future: _isOrganizer(),
      builder: (context, snapshot) {
        final canManage = snapshot.data == true;
        if (!canManage) return const SizedBox.shrink();

        return FloatingActionButton.extended(
          onPressed: _createReward,
          icon: const Icon(Icons.add),
          label: const Text('Add Reward'),
        );
      },
    );

    // Light mode: premium glass scaffold background.
    if (isLight) {
      return GlassScaffold(
        appBar: AppBar(
          title: const Text('Manage Rewards'),
        ),
        floatingActionButton: fab,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(top: kToolbarHeight),
            child: pageBody,
          ),
        ),
      );
    }

    // Dark mode: keep previous dark styling unchanged.
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.2),
        elevation: 0,
        title: const Text('Manage Rewards'),
      ),
      floatingActionButton: fab,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFF0B0F1A),
              Color(0xFF0A1222),
              Color(0xFF071425),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: pageBody,
      ),
    );
  }
}

class RewardEditorSheet extends StatefulWidget {
  const RewardEditorSheet({
    super.key,
    required this.leagueId,
    required this.title,
    this.initialReward,
  });

  final String leagueId;
  final String title;
  final RewardModel? initialReward;

  @override
  State<RewardEditorSheet> createState() => _RewardEditorSheetState();
}

class _RewardEditorSheetState extends State<RewardEditorSheet> {
  final _formKey = GlobalKey<FormState>();

  late int _position;
  late String _rewardName;
  late String _description;
  late String _rewardType;

  XFile? _pickedXFile;
  PlatformFile? _pickedPlatformFile;

  String _existingImageUrl = '';

  bool _busy = false;

  @override
  void initState() {
    super.initState();

    final initial = widget.initialReward;
    _position = initial?.position ?? 1;
    _rewardName = initial?.rewardName ?? '';
    _description = initial?.description ?? '';
    _rewardType = initial?.rewardType ?? 'physical';
    _existingImageUrl = initial?.imageUrl ?? '';
  }

  String _fallbackNameFromPath(String path) {
    final p = path.trim();
    if (p.isEmpty) return 'image.jpg';
    final idx = p.lastIndexOf(RegExp(r'[\/\\]'));
    if (idx < 0) return p;
    final n = p.substring(idx + 1);
    return n.trim().isEmpty ? 'image.jpg' : n.trim();
  }

  Future<void> _pickImage() async {
    if (!kIsWeb) {
      try {
        final picker = ImagePicker();
        final x = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
        );

        if (x != null) {
          setState(() {
            _pickedXFile = x;
            _pickedPlatformFile = null;
          });
          return;
        }
      } catch (_) {}
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() {
        _pickedPlatformFile = result.files.first;
        _pickedXFile = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<PlatformFile> _platformFileFromXFile(XFile x) async {
    final name = (x.name).trim().isNotEmpty ? x.name.trim() : _fallbackNameFromPath(x.path);

    final p = x.path.trim();
    if (p.isNotEmpty) {
      int size = 0;
      try {
        size = await x.length();
      } catch (_) {
        try {
          size = await File(p).length();
        } catch (_) {
          size = 0;
        }
      }
      return PlatformFile(
        name: name,
        size: size,
        path: p,
      );
    }

    final bytes = await x.readAsBytes();
    return PlatformFile(
      name: name,
      size: bytes.length,
      bytes: bytes,
    );
  }

  Future<String> _uploadToCloudinary(PlatformFile file) async {
    final cloudinary = CloudinaryUploadService();
    final folder = 'eleaguehub/league_rewards/${widget.leagueId}';

    final url = await cloudinary.uploadImagePlatformFile(
      file: file,
      folder: folder,
    );

    final secure = url.trim();
    if (secure.isEmpty) {
      throw StateError('Upload failed: empty secure URL.');
    }
    return secure;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    _formKey.currentState?.save();

    setState(() => _busy = true);
    try {
      String imageUrl = _existingImageUrl;

      if (_pickedXFile != null) {
        final pf = await _platformFileFromXFile(_pickedXFile!);
        imageUrl = await _uploadToCloudinary(pf);
      } else if (_pickedPlatformFile != null) {
        imageUrl = await _uploadToCloudinary(_pickedPlatformFile!);
      }

      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

      final model = RewardModel(
        id: widget.initialReward?.id ?? '',
        position: _position,
        rewardName: _rewardName.trim(),
        rewardType: RewardModel.normalizeRewardType(_rewardType),
        description: _description.trim(),
        imageUrl: imageUrl.trim(),
        createdAt: widget.initialReward?.createdAt,
        createdBy: widget.initialReward?.createdBy ?? uid,
      );

      if (!mounted) return;
      Navigator.of(context).pop(model);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;
    final isLight = theme.brightness == Brightness.light;

    final dropdownBg = isLight ? Colors.white : const Color(0xFF0E1628);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Glass(
              borderRadius: 24,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: onSurface.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            widget.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: onSurface,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _busy ? null : () => Navigator.of(context).pop(),
                          icon: Icon(Icons.close, color: onSurface.withOpacity(0.85)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  value: _position,
                                  decoration: const InputDecoration(
                                    labelText: 'Position',
                                  ),
                                  dropdownColor: dropdownBg,
                                  items: List<DropdownMenuItem<int>>.generate(
                                    50,
                                    (i) => DropdownMenuItem<int>(
                                      value: i + 1,
                                      child: Text('${i + 1}'),
                                    ),
                                  ),
                                  onChanged: _busy
                                      ? null
                                      : (v) {
                                          if (v == null) return;
                                          setState(() => _position = v);
                                        },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: RewardModel.normalizeRewardType(_rewardType),
                                  decoration: const InputDecoration(
                                    labelText: 'Reward Type',
                                  ),
                                  dropdownColor: dropdownBg,
                                  items: const <DropdownMenuItem<String>>[
                                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                                    DropdownMenuItem(value: 'physical', child: Text('Physical')),
                                    DropdownMenuItem(value: 'digital', child: Text('Digital')),
                                    DropdownMenuItem(value: 'trophy', child: Text('Trophy')),
                                    DropdownMenuItem(value: 'other', child: Text('Other')),
                                  ],
                                  onChanged: _busy
                                      ? null
                                      : (v) {
                                          if (v == null) return;
                                          setState(() => _rewardType = v);
                                        },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            initialValue: _rewardName,
                            enabled: !_busy,
                            decoration: const InputDecoration(
                              labelText: 'Reward Name',
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Reward name is required';
                              if (v.trim().length < 2) return 'Too short';
                              return null;
                            },
                            onSaved: (v) => _rewardName = v ?? '',
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            initialValue: _description,
                            enabled: !_busy,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                            ),
                            maxLines: 4,
                            onSaved: (v) => _description = v ?? '',
                          ),
                          const SizedBox(height: 12),
                          _ImagePickerRow(
                            existingUrl: _existingImageUrl,
                            pickedXFile: _pickedXFile,
                            pickedPlatformFile: _pickedPlatformFile,
                            onPick: _busy ? null : _pickImage,
                            onClear: _busy
                                ? null
                                : () {
                                    setState(() {
                                      _pickedXFile = null;
                                      _pickedPlatformFile = null;
                                      _existingImageUrl = '';
                                    });
                                  },
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: cs.onPrimary,
                                      ),
                                    )
                                  : const Text('Save'),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImagePickerRow extends StatelessWidget {
  const _ImagePickerRow({
    required this.existingUrl,
    required this.pickedXFile,
    required this.pickedPlatformFile,
    required this.onPick,
    required this.onClear,
  });

  final String existingUrl;
  final XFile? pickedXFile;
  final PlatformFile? pickedPlatformFile;
  final VoidCallback? onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final Widget preview = _buildPreview(context);

    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Reward Image (Cloudinary)',
      ),
      child: Row(
        children: <Widget>[
          ClipRRect(borderRadius: BorderRadius.circular(12), child: preview),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              pickedXFile != null || pickedPlatformFile != null
                  ? 'Selected image'
                  : (existingUrl.trim().isNotEmpty ? 'Using existing image' : 'No image selected'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface.withOpacity(0.82),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Pick'),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Clear',
            onPressed: onClear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    if (pickedXFile != null) {
      final p = pickedXFile!.path.trim();
      if (p.isNotEmpty) {
        return Image.file(
          File(p),
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(context),
        );
      }
    }

    if (pickedPlatformFile != null) {
      return _platformPreview(context, pickedPlatformFile!);
    }

    if (existingUrl.trim().isNotEmpty) {
      return Image.network(
        existingUrl,
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(context),
      );
    }

    return _fallback(context);
  }

  Widget _platformPreview(BuildContext context, PlatformFile f) {
    if (f.bytes != null && f.bytes!.isNotEmpty) {
      return Image.memory(
        f.bytes!,
        width: 64,
        height: 64,
        fit: BoxFit.cover,
      );
    }
    final p = (f.path ?? '').trim();
    if (p.isNotEmpty) {
      return Image.file(
        File(p),
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(context),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 64,
      height: 64,
      color: cs.onSurface.withOpacity(0.06),
      alignment: Alignment.center,
      child: Icon(
        Icons.image_outlined,
        color: cs.onSurface.withOpacity(0.55),
      ),
    );
  }
}
