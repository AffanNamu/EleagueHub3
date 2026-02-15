import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/cloudinary_upload_service.dart';
import '../data/marketplace_repository.dart';

class AdminMarketplaceUploadScreen extends StatefulWidget {
  const AdminMarketplaceUploadScreen({super.key});

  @override
  State<AdminMarketplaceUploadScreen> createState() =>
      _AdminMarketplaceUploadScreenState();
}

class _AdminMarketplaceUploadScreenState
    extends State<AdminMarketplaceUploadScreen> {
  // IMPORTANT: must match your Firestore rules super admin UID.
  static const String _superAdminUid = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';

  // Conservative limit for mobile memory safety.
  static const int _maxImageBytes = 8 * 1024 * 1024;

  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _affiliateCtrl = TextEditingController();
  final _sellerCtrl = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  bool _uploading = false;

  _PickedImage? _pickedImage;

  String _category = 'Gamepads';

  static const List<String> _categories = <String>[
    'Gamepads',
    'Jerseys',
    'Boots',
    'Accessories',
  ];

  void _snack(String msg) {
    final trimmed = msg.trim();
    if (trimmed.isEmpty) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        content: Text(trimmed),
      ),
    );
  }

  String? _requireText(String? v, {required String label}) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '$label is required';
    return null;
  }

  bool _looksLikeHttpUrl(String s) {
    final u = s.trim().toLowerCase();
    return u.startsWith('https://') || u.startsWith('http://');
  }

  Future<void> _pickImage() async {
    if (_uploading) return;

    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 6));

      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
        requestFullMetadata: false,
      );

      if (!mounted) return;
      if (xfile == null) return;

      final bytes = await xfile.readAsBytes();
      if (!mounted) return;

      if (bytes.isEmpty) {
        _snack('Could not read image bytes. Please try another image.');
        return;
      }

      if (bytes.lengthInBytes > _maxImageBytes) {
        _snack(
          'Image is too large (${(bytes.lengthInBytes / (1024 * 1024)).toStringAsFixed(1)}MB). '
          'Please choose an image under 8MB.',
        );
        return;
      }

      final filePath = xfile.path.trim();
      if (filePath.isEmpty) {
        _snack('Selected image path is not available. Please try again.');
        return;
      }

      final fileName = _deriveFilename(xfile);

      setState(() {
        _pickedImage = _PickedImage(
          bytes: bytes,
          filename: fileName,
          filePath: filePath,
        );
      });
    } catch (e) {
      if (!mounted) return;
      _snack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    }
  }

  String _deriveFilename(XFile xfile) {
    final n = (xfile.name).trim();
    if (n.isNotEmpty) return n;

    final p = xfile.path.trim();
    if (p.isEmpty) return 'image.jpg';

    final slash = p.lastIndexOf('/');
    final backslash = p.lastIndexOf('\\');
    final idx = slash > backslash ? slash : backslash;
    final base = (idx >= 0 && idx + 1 < p.length) ? p.substring(idx + 1) : p;

    return base.trim().isEmpty ? 'image.jpg' : base.trim();
  }

  Future<void> _upload() async {
    if (_uploading) return;

    final user = FirebaseAuth.instance.currentUser;
    final uid = (user?.uid ?? '').trim();

    if (uid != _superAdminUid) {
      _snack('Access denied.');
      return;
    }

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    final picked = _pickedImage;
    if (picked == null) {
      _snack('Please select an image.');
      return;
    }

    final affiliate = _affiliateCtrl.text.trim();
    if (!_looksLikeHttpUrl(affiliate)) {
      _snack('Affiliate link must start with http:// or https://');
      return;
    }

    setState(() => _uploading = true);

    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 6));

      final cloud = CloudinaryUploadService();
      final secureUrl = await cloud.uploadMarketplaceProductImageFile(
        filePath: picked.filePath,
      );

      final repo = MarketplaceRepository();
      await repo.createProduct(
        name: _nameCtrl.text.trim(),
        price: _priceCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        imageUrl: secureUrl,
        affiliateUrl: affiliate,
        category: _category.trim(),
        sellerName: _sellerCtrl.text.trim(),
        createdBy: uid,
      );

      if (!mounted) return;
      _snack('Uploaded.');
      setState(() {
        _pickedImage = null;
        _nameCtrl.clear();
        _priceCtrl.clear();
        _descCtrl.clear();
        _affiliateCtrl.clear();
        _sellerCtrl.clear();
        _category = _categories.first;
      });
    } catch (e) {
      if (!mounted) return;
      _snack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    } finally {
      if (!mounted) return;
      setState(() => _uploading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    _affiliateCtrl.dispose();
    _sellerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final user = FirebaseAuth.instance.currentUser;
    final uid = (user?.uid ?? '').trim();
    final isAllowed = uid == _superAdminUid;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Marketplace Upload'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (!isAllowed) ...[
            const SizedBox(height: 10),
            Glass(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.block, color: cs.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Access Denied',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Glass(
              padding: const EdgeInsets.all(14),
              child: Text(
                'You do not have permission to upload marketplace products.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withOpacity(0.72),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 6),
            Glass(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Product Image',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ImagePreview(bytes: _pickedImage?.bytes),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _uploading ? null : _pickImage,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Select Image'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Glass(
              padding: const EdgeInsets.all(14),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Product Info',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameCtrl,
                      enabled: !_uploading,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Product Name',
                        prefixIcon: Icon(Icons.sell_outlined),
                      ),
                      validator: (v) => _requireText(v, label: 'Product name'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _priceCtrl,
                      enabled: !_uploading,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Price',
                        prefixIcon: Icon(Icons.payments_outlined),
                        hintText: 'e.g. ₦12,499 or \$19.99',
                      ),
                      validator: (v) => _requireText(v, label: 'Price'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _sellerCtrl,
                      enabled: !_uploading,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Seller Name',
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                      validator: (v) => _requireText(v, label: 'Seller name'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _category,
                      items: _categories
                          .map((c) => DropdownMenuItem<String>(
                                value: c,
                                child: Text(c),
                              ))
                          .toList(),
                      onChanged: _uploading
                          ? null
                          : (v) {
                              if (v == null) return;
                              setState(() => _category = v);
                            },
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _affiliateCtrl,
                      enabled: !_uploading,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Affiliate Link',
                        prefixIcon: Icon(Icons.link),
                        hintText: 'https://...',
                      ),
                      validator: (v) => _requireText(v, label: 'Affiliate link'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _descCtrl,
                      enabled: !_uploading,
                      textInputAction: TextInputAction.newline,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                      validator: (v) => _requireText(v, label: 'Description'),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _uploading ? null : _upload,
                        icon: _uploading
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.onPrimary,
                                ),
                              )
                            : const Icon(Icons.cloud_upload_outlined),
                        label: Text(_uploading ? 'Uploading…' : 'Upload Product'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Uploads are restricted to super admins. Products use Cloudinary for images.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.65),
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PickedImage {
  const _PickedImage({
    required this.bytes,
    required this.filename,
    required this.filePath,
  });

  final Uint8List bytes;
  final String filename;
  final String filePath;
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.bytes});

  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final b = bytes;

    Widget child;
    if (b != null && b.isNotEmpty) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(
          b,
          width: double.infinity,
          height: 180,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
        ),
      );
    } else {
      child = SizedBox(
        height: 180,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_outlined,
                  size: 34, color: cs.onSurface.withOpacity(0.55)),
              const SizedBox(height: 8),
              Text(
                'No image selected',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.65),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Container(
        key: ValueKey((b?.lengthInBytes ?? 0).toString()),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.onSurface.withOpacity(0.12)),
        ),
        child: child,
      ),
    );
  }
}
