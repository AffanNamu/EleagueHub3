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
  static const String _superAdminUid =
      'a0JDUelQW3TEyoXTm4ESuGi7ndq1';
  static const int _maxImageBytes =
      8 * 1024 * 1024;

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

  String? _requireText(String? v,
      {required String label}) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return '$label is required';
    return null;
  }

  bool _looksLikeHttpUrl(String s) {
    final u = s.trim().toLowerCase();
    return u.startsWith('https://') ||
        u.startsWith('http://');
  }

  Future<void> _pickImage() async {
    if (_uploading) return;

    try {
      await ConnectivityService.instance.requireOnline(
          timeout: const Duration(seconds: 6));

      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
        requestFullMetadata: false,
      );

      if (!mounted || xfile == null) return;

      final bytes = await xfile.readAsBytes();

      if (bytes.isEmpty) {
        _snack('Could not read image.');
        return;
      }

      if (bytes.lengthInBytes >
          _maxImageBytes) {
        _snack('Image too large. Max 8MB.');
        return;
      }

      setState(() {
        _pickedImage = _PickedImage(
          bytes: bytes,
          filename: xfile.name,
          filePath: xfile.path,
        );
      });
    } catch (e) {
      if (!mounted) return;
      _snack(UserFriendlyError.toMessage(
          e is Object
              ? e
              : Exception('unknown')));
    }
  }

  Future<void> _upload() async {
    if (_uploading) return;

    final uid =
        (FirebaseAuth.instance.currentUser?.uid ??
                '')
            .trim();

    if (uid != _superAdminUid) {
      _snack('Access denied.');
      return;
    }

    final ok =
        _formKey.currentState?.validate() ??
            false;
    if (!ok) return;

    final picked = _pickedImage;
    if (picked == null) {
      _snack('Please select an image.');
      return;
    }

    final affiliate =
        _affiliateCtrl.text.trim();
    if (!_looksLikeHttpUrl(affiliate)) {
      _snack(
          'Affiliate link must start with http/https.');
      return;
    }

    setState(() => _uploading = true);

    try {
      await ConnectivityService.instance.requireOnline(
          timeout: const Duration(seconds: 6));

      final cloud =
          CloudinaryUploadService();

      final secureUrl =
          await cloud
              .uploadMarketplaceProductImageFile(
                  filePath: picked.filePath);

      final repo =
          MarketplaceRepository();

      await repo.createProduct(
        name: _nameCtrl.text.trim(),
        price: _priceCtrl.text.trim(),
        description:
            _descCtrl.text.trim(),
        imageUrl: secureUrl,
        affiliateUrl: affiliate,
        category: _category.trim(),
        sellerName:
            _sellerCtrl.text.trim(),
        createdBy: uid,
      );

      if (!mounted) return;

      _snack('Uploaded successfully.');

      setState(() {
        _pickedImage = null;
        _nameCtrl.clear();
        _priceCtrl.clear();
        _descCtrl.clear();
        _affiliateCtrl.clear();
        _sellerCtrl.clear();
        _category =
            _categories.first;
      });
    } catch (e) {
      if (!mounted) return;
      _snack(UserFriendlyError.toMessage(
          e is Object
              ? e
              : Exception('unknown')));
    } finally {
      if (mounted)
        setState(
            () => _uploading = false);
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
    final theme =
        Theme.of(context);
    final cs =
        theme.colorScheme;
    final onSurface =
        cs.onSurface;

    final uid =
        (FirebaseAuth.instance.currentUser?.uid ??
                '')
            .trim();

    final isAllowed =
        uid == _superAdminUid;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text(''),
        backgroundColor:
            Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Glass(
            padding:
                const EdgeInsets.all(8),
            borderRadius: 12,
            child: Icon(
                Icons
                    .arrow_back_ios_new_rounded,
                size: 18,
                color: onSurface),
          ),
          onPressed: () =>
              Navigator.of(context)
                  .maybePop(),
        ),
      ),
      body: ListView(
        physics:
            const BouncingScrollPhysics(
                parent:
                    AlwaysScrollableScrollPhysics()),
        padding:
            const EdgeInsets.fromLTRB(
                16, 4, 16, 100),
        children: [
          Glass(
            borderRadius: 22,
            padding:
                const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration:
                      BoxDecoration(
                    shape:
                        BoxShape.circle,
                    gradient:
                        LinearGradient(
                      colors: [
                        cs.primary
                            .withOpacity(
                                0.25),
                        cs.primary
                            .withOpacity(
                                0.08),
                      ],
                    ),
                  ),
                  child: Icon(
                      Icons
                          .cloud_upload_rounded,
                      color:
                          cs.primary,
                      size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,
                    children: [
                      Text(
                        'Upload Product',
                        style: theme
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                fontWeight:
                                    FontWeight
                                        .w900),
                      ),
                      const SizedBox(
                          height: 2),
                      Text(
                        'Admin only',
                        style:
                            TextStyle(
                          color:
                              onSurface
                                  .withOpacity(
                                      0.60),
                          fontSize:
                              12,
                          fontWeight:
                              FontWeight
                                  .w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          if (!isAllowed)
            Glass(
              borderRadius: 22,
              padding:
                  const EdgeInsets.all(
                      24),
              child: Column(
                children: [
                  Icon(
                      Icons
                          .block_rounded,
                      color:
                          cs.error,
                      size: 40),
                  const SizedBox(
                      height: 14),
                  Text(
                    'Access Denied',
                    style: theme
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                            fontWeight:
                                FontWeight
                                    .w900),
                  ),
                ],
              ),
            )
          else ...[
            Glass(
              borderRadius: 20,
              padding:
                  const EdgeInsets.all(
                      16),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Text(
                    'Product Image',
                    style:
                        TextStyle(
                      fontWeight:
                          FontWeight
                              .w900,
                      fontSize:
                          14,
                      color:
                          onSurface
                              .withOpacity(
                                  0.70),
                    ),
                  ),
                  const SizedBox(
                      height: 12),
                  _ImagePreview(
                      bytes:
                          _pickedImage
                              ?.bytes),
                  const SizedBox(
                      height: 12),
                  SizedBox(
                    width:
                        double.infinity,
                    child:
                        ElevatedButton.icon(
                      onPressed:
                          _uploading
                              ? null
                              : _pickImage,
                      icon: const Icon(
                          Icons
                              .image_rounded),
                      label: const Text(
                          'Select Image'),
                      style:
                          ElevatedButton.styleFrom(
                        backgroundColor:
                            cs.primary,
                        foregroundColor:
                            Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Glass(
              borderRadius: 20,
              padding:
                  const EdgeInsets.all(
                      16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller:
                          _nameCtrl,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Product Name',
                        prefixIcon: Icon(
                            Icons
                                .sell_outlined),
                      ),
                      validator: (v) =>
                          _requireText(v,
                              label:
                                  'Product name'),
                    ),
                    const SizedBox(
                        height: 12),
                    TextFormField(
                      controller:
                          _priceCtrl,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Price',
                        prefixIcon: Icon(
                            Icons
                                .payments_outlined),
                      ),
                      validator: (v) =>
                          _requireText(v,
                              label:
                                  'Price'),
                    ),
                    const SizedBox(
                        height: 12),
                    TextFormField(
                      controller:
                          _sellerCtrl,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Seller Name',
                        prefixIcon: Icon(
                            Icons
                                .storefront_outlined),
                      ),
                      validator: (v) =>
                          _requireText(v,
                              label:
                                  'Seller name'),
                    ),
                    const SizedBox(
                        height: 12),
                    DropdownButtonFormField<
                        String>(
                      value:
                          _category,
                      items: _categories
                          .map((c) =>
                              DropdownMenuItem<
                                  String>(
                                value:
                                    c,
                                child:
                                    Text(
                                        c),
                              ))
                          .toList(),
                      onChanged:
                          (v) {
                        if (v !=
                            null)
                          setState(() =>
                              _category =
                                  v);
                      },
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Category',
                        prefixIcon: Icon(
                            Icons
                                .category_outlined),
                      ),
                    ),
                    const SizedBox(
                        height: 12),
                    TextFormField(
                      controller:
                          _affiliateCtrl,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Affiliate Link',
                        prefixIcon:
                            Icon(
                                Icons
                                    .link),
                      ),
                      validator: (v) =>
                          _requireText(v,
                              label:
                                  'Affiliate link'),
                    ),
                    const SizedBox(
                        height: 12),
                    TextFormField(
                      controller:
                          _descCtrl,
                      minLines: 3,
                      maxLines: 8,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Description',
                        prefixIcon: Icon(
                            Icons
                                .notes_outlined),
                      ),
                      validator: (v) =>
                          _requireText(v,
                              label:
                                  'Description'),
                    ),
                    const SizedBox(
                        height: 18),
                    SizedBox(
                      width:
                          double.infinity,
                      height:
                          50,
                      child:
                          ElevatedButton(
                        onPressed:
                            _uploading
                                ? null
                                : _upload,
                        style:
                            ElevatedButton.styleFrom(
                          backgroundColor:
                              cs.primary,
                          foregroundColor:
                              Colors.white,
                        ),
                        child: _uploading
                            ? const CircularProgressIndicator(
                                color:
                                    Colors.white)
                            : const Text(
                                'Upload Product'),
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
  const _ImagePreview(
      {required this.bytes});

  final Uint8List? bytes;

  @override
  Widget build(
      BuildContext context) {
    final cs =
        Theme.of(context)
            .colorScheme;
    final onSurface =
        cs.onSurface;

    final b = bytes;

    Widget child;
    if (b != null &&
        b.isNotEmpty) {
      child = ClipRRect(
        borderRadius:
            BorderRadius.circular(
                14),
        child: Image.memory(
          b,
          width:
              double.infinity,
          height:
              180,
          fit: BoxFit.cover,
        ),
      );
    } else {
      child = SizedBox(
        height: 180,
        child: Center(
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              Icon(
                Icons.image_outlined,
                size: 34,
                color: onSurface
                    .withOpacity(
                        0.35),
              ),
              const SizedBox(
                  height: 8),
              Text(
                'No image selected',
                style: TextStyle(
                  color: onSurface
                      .withOpacity(
                          0.50),
                  fontWeight:
                      FontWeight.w600,
                  fontSize:
                      12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration:
          const Duration(
              milliseconds:
                  180),
      child: Container(
        key: ValueKey(
            (b?.lengthInBytes ??
                    0)
                .toString()),
        decoration:
            BoxDecoration(
          borderRadius:
              BorderRadius.circular(
                  14),
          border: Border.all(
              color: onSurface
                  .withOpacity(
                      0.08)),
          color: onSurface
              .withOpacity(
                  0.03),
        ),
        child: child,
      ),
    );
  }
}
