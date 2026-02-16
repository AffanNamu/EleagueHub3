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
  State<AdminMarketplaceUploadScreen> createState() => _AdminMarketplaceUploadScreenState();
}

class _AdminMarketplaceUploadScreenState extends State<AdminMarketplaceUploadScreen> {
  static const String _superAdminUid = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';
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

  static const List<String> _categories = <String>['Gamepads', 'Jerseys', 'Boots', 'Accessories'];

  void _snack(String msg) {
    final trimmed = msg.trim();
    if (trimmed.isEmpty) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.all(12), content: Text(trimmed)),
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
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 6));
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 2048, maxHeight: 2048, imageQuality: 90, requestFullMetadata: false,
      );
      if (!mounted || xfile == null) return;
      final bytes = await xfile.readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty) { _snack('Could not read image.'); return; }
      if (bytes.lengthInBytes > _maxImageBytes) {
        _snack('Image too large (${(bytes.lengthInBytes / (1024 * 1024)).toStringAsFixed(1)}MB). Max 8MB.');
        return;
      }
      final filePath = xfile.path.trim();
      if (filePath.isEmpty) { _snack('Image path unavailable.'); return; }
      final fileName = _deriveFilename(xfile);
      setState(() => _pickedImage = _PickedImage(bytes: bytes, filename: fileName, filePath: filePath));
    } catch (e) {
      if (!mounted) return;
      _snack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    }
  }

  String _deriveFilename(XFile xfile) {
    final n = xfile.name.trim();
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
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (uid != _superAdminUid) { _snack('Access denied.'); return; }
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;
    final picked = _pickedImage;
    if (picked == null) { _snack('Please select an image.'); return; }
    final affiliate = _affiliateCtrl.text.trim();
    if (!_looksLikeHttpUrl(affiliate)) { _snack('Affiliate link must start with http/https.'); return; }

    setState(() => _uploading = true);
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 6));
      final cloud = CloudinaryUploadService();
      final secureUrl = await cloud.uploadMarketplaceProductImageFile(filePath: picked.filePath);
      final repo = MarketplaceRepository();
      await repo.createProduct(
        name: _nameCtrl.text.trim(), price: _priceCtrl.text.trim(), description: _descCtrl.text.trim(),
        imageUrl: secureUrl, affiliateUrl: affiliate, category: _category.trim(),
        sellerName: _sellerCtrl.text.trim(), createdBy: uid,
      );
      if (!mounted) return;
      _snack('Uploaded successfully.');
      setState(() {
        _pickedImage = null;
        _nameCtrl.clear(); _priceCtrl.clear(); _descCtrl.clear(); _affiliateCtrl.clear(); _sellerCtrl.clear();
        _category = _categories.first;
      });
    } catch (e) {
      if (!mounted) return;
      _snack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _priceCtrl.dispose(); _descCtrl.dispose(); _affiliateCtrl.dispose(); _sellerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    final isAllowed = uid == _superAdminUid;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Glass(
            padding: const EdgeInsets.all(8),
            borderRadius: 12,
            child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white.withOpacity(0.9)),
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          // ── Header ──
          Glass(
            borderRadius: 22,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [cs.primary.withOpacity(0.30), cs.primary.withOpacity(0.08)]),
                  ),
                  child: Icon(Icons.cloud_upload_rounded, color: cs.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Upload Product', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, fontSize: 18)),
                      const SizedBox(height: 2),
                      Text('Admin only', style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          if (!isAllowed) ...[
            Glass(
              borderRadius: 22,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: cs.error.withOpacity(0.12)),
                    child: Icon(Icons.block_rounded, color: cs.error, size: 28),
                  ),
                  const SizedBox(height: 14),
                  Text('Access Denied', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(
                    'You do not have permission to upload marketplace products.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.50), fontWeight: FontWeight.w600, height: 1.4),
                  ),
                ],
              ),
            ),
          ] else ...[
            // ── Image picker ──
            Glass(
              borderRadius: 20,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Product Image', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white.withOpacity(0.7))),
                  const SizedBox(height: 12),
                  _ImagePreview(bytes: _pickedImage?.bytes),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _uploading ? null : _pickImage,
                        borderRadius: BorderRadius.circular(14),
                        child: Ink(
                          height: 44,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: cs.primary.withOpacity(0.12),
                            border: Border.all(color: cs.primary.withOpacity(0.25)),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.image_rounded, size: 18, color: cs.primary),
                                const SizedBox(width: 8),
                                Text('Select Image', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800, fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Form ──
            Glass(
              borderRadius: 20,
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Product Info', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white.withOpacity(0.7))),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _nameCtrl, enabled: !_uploading, textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Product Name', prefixIcon: Icon(Icons.sell_outlined)),
                      validator: (v) => _requireText(v, label: 'Product name'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _priceCtrl, enabled: !_uploading, textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Price', prefixIcon: Icon(Icons.payments_outlined), hintText: 'e.g. ₦12,499'),
                      validator: (v) => _requireText(v, label: 'Price'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _sellerCtrl, enabled: !_uploading, textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Seller Name', prefixIcon: Icon(Icons.storefront_outlined)),
                      validator: (v) => _requireText(v, label: 'Seller name'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _category,
                      items: _categories.map((c) => DropdownMenuItem<String>(value: c, child: Text(c))).toList(),
                      onChanged: _uploading ? null : (v) { if (v != null) setState(() => _category = v); },
                      decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category_outlined)),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _affiliateCtrl, enabled: !_uploading, textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Affiliate Link', prefixIcon: Icon(Icons.link), hintText: 'https://...'),
                      validator: (v) => _requireText(v, label: 'Affiliate link'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descCtrl, enabled: !_uploading, textInputAction: TextInputAction.newline,
                      minLines: 3, maxLines: 8,
                      decoration: const InputDecoration(labelText: 'Description', prefixIcon: Icon(Icons.notes_outlined)),
                      validator: (v) => _requireText(v, label: 'Description'),
                    ),
                    const SizedBox(height: 18),

                    // Upload button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _uploading ? null : _upload,
                          borderRadius: BorderRadius.circular(16),
                          child: Ink(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: _uploading
                                  ? null
                                  : LinearGradient(colors: [cs.primary, cs.primary.withOpacity(0.75)]),
                              color: _uploading ? Colors.white.withOpacity(0.06) : null,
                              border: Border.all(color: _uploading ? Colors.white.withOpacity(0.08) : cs.primary.withOpacity(0.40)),
                            ),
                            child: Center(
                              child: _uploading
                                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.cloud_upload_rounded, size: 20, color: Colors.white),
                                        const SizedBox(width: 10),
                                        const Text('Upload Product', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    Text(
                      'Uploads are restricted to super admins. Products use Cloudinary for images.',
                      style: TextStyle(color: Colors.white.withOpacity(0.40), fontWeight: FontWeight.w600, fontSize: 11, height: 1.3),
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
  const _PickedImage({required this.bytes, required this.filename, required this.filePath});
  final Uint8List bytes;
  final String filename;
  final String filePath;
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.bytes});
  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final b = bytes;

    Widget child;
    if (b != null && b.isNotEmpty) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.memory(b, width: double.infinity, height: 180, fit: BoxFit.cover, filterQuality: FilterQuality.low),
      );
    } else {
      child = SizedBox(
        height: 180,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_outlined, size: 34, color: Colors.white.withOpacity(0.3)),
              const SizedBox(height: 8),
              Text('No image selected', style: TextStyle(color: Colors.white.withOpacity(0.40), fontWeight: FontWeight.w600, fontSize: 12)),
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
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          color: Colors.white.withOpacity(0.03),
        ),
        child: child,
      ),
    );
  }
}
