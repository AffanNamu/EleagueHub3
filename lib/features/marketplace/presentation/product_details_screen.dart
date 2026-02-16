import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/marketplace_repository.dart';
import '../domain/marketplace_product_model.dart';

class ProductDetailsScreen extends StatelessWidget {
  const ProductDetailsScreen({
    super.key,
    required this.productId,
    this.initialProduct,
  });

  final String productId;
  final MarketplaceProduct? initialProduct;

  bool _looksLikeHttpUrl(String s) {
    final u = s.trim().toLowerCase();
    return u.startsWith('https://') || u.startsWith('http://');
  }

  void _snack(BuildContext context, String msg) {
    final trimmed = msg.trim();
    if (trimmed.isEmpty) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, margin: const EdgeInsets.all(12), content: Text(trimmed)),
    );
  }

  Uri? _parseAffiliateUri(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final direct = Uri.tryParse(s);
    if (direct != null && direct.hasScheme) return direct;
    final encoded = Uri.tryParse(Uri.encodeFull(s));
    if (encoded != null && encoded.hasScheme) return encoded;
    return null;
  }

  Future<void> _buyNow(BuildContext context, MarketplaceProduct p) async {
    final affiliate = p.affiliateUrl.trim();
    if (!_looksLikeHttpUrl(affiliate)) {
      _snack(context, 'Invalid affiliate link.');
      return;
    }

    final cs = Theme.of(context).colorScheme;

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Glass(
            borderRadius: 24,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [cs.primary.withOpacity(0.30), cs.primary.withOpacity(0.08)],
                    ),
                  ),
                  child: Icon(Icons.open_in_new_rounded, color: cs.primary, size: 24),
                ),
                const SizedBox(height: 14),
                Text(
                  'Continue to Partner Store?',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'You will be redirected to an external store to complete your purchase.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.50), fontSize: 13, fontWeight: FontWeight.w600, height: 1.4),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.of(ctx).pop(false),
                          borderRadius: BorderRadius.circular(14),
                          child: Ink(
                            height: 46,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withOpacity(0.12)),
                            ),
                            child: Center(
                              child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.of(ctx).pop(true),
                          borderRadius: BorderRadius.circular(14),
                          child: Ink(
                            height: 46,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(colors: [cs.primary, cs.primary.withOpacity(0.75)]),
                            ),
                            child: const Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.open_in_new_rounded, size: 18, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text('Continue', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirm != true) return;

    final uri = _parseAffiliateUri(affiliate);
    if (uri == null) {
      _snack(context, 'Invalid link URL.');
      return;
    }

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) _snack(context, 'Could not open partner store.');
    } catch (_) {
      if (context.mounted) _snack(context, 'Could not open partner store.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final repo = MarketplaceRepository();

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
      body: StreamBuilder<MarketplaceProduct?>(
        stream: repo.watchProductById(productId),
        initialData: initialProduct,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Glass(
                  borderRadius: 22,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: cs.error.withOpacity(0.12)),
                        child: Icon(Icons.error_outline_rounded, color: cs.error, size: 26),
                      ),
                      const SizedBox(height: 14),
                      Text('Could not load product.', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ),
            );
          }

          if (!snap.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: cs.primary),
                  const SizedBox(height: 14),
                  Text('Loading product...', style: TextStyle(color: Colors.white.withOpacity(0.45), fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }

          final p = snap.data;
          if (p == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Glass(
                  borderRadius: 22,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined, color: Colors.white.withOpacity(0.4), size: 40),
                      const SizedBox(height: 14),
                      Text('Product not found.', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ),
            );
          }

          final img = p.imageUrl.trim();
          final hasImg = img.isNotEmpty && _looksLikeHttpUrl(img);

          return ListView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            children: [
              // ── Product Image ──
              Glass(
                borderRadius: 22,
                padding: const EdgeInsets.all(10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 1.1,
                    child: hasImg
                        ? CachedNetworkImage(
                            imageUrl: img,
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 150),
                            placeholder: (context, _) => Container(
                              color: Colors.white.withOpacity(0.04),
                              child: Center(
                                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
                              ),
                            ),
                            errorWidget: (context, _, __) => Container(
                              color: Colors.white.withOpacity(0.04),
                              child: Icon(Icons.image_not_supported_outlined, color: Colors.white.withOpacity(0.3)),
                            ),
                          )
                        : Container(
                            color: Colors.white.withOpacity(0.04),
                            child: Icon(Icons.image_outlined, color: Colors.white.withOpacity(0.3), size: 48),
                          ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // ── Product Info ──
              Glass(
                borderRadius: 20,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name.trim().isEmpty ? 'Untitled product' : p.name.trim(),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        letterSpacing: -0.5,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Price
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.primary.withOpacity(0.20)),
                      ),
                      child: Text(
                        p.price.trim().isEmpty ? '—' : p.price.trim(),
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Seller
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.06),
                          ),
                          child: Icon(Icons.storefront_rounded, size: 16, color: Colors.white.withOpacity(0.5)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            p.sellerName.trim().isEmpty ? 'Seller' : p.sellerName.trim(),
                            style: TextStyle(color: Colors.white.withOpacity(0.60), fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    Divider(color: Colors.white.withOpacity(0.06)),
                    const SizedBox(height: 12),

                    // Description
                    Text(
                      'Description',
                      style: TextStyle(color: Colors.white.withOpacity(0.45), fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      p.description.trim().isEmpty ? 'No description.' : p.description.trim(),
                      style: TextStyle(color: Colors.white.withOpacity(0.60), fontWeight: FontWeight.w600, height: 1.45, fontSize: 14),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── Buy Button ──
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _buyNow(context, p),
                  borderRadius: BorderRadius.circular(18),
                  child: Ink(
                    height: 54,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        colors: [cs.primary, cs.primary.withOpacity(0.75)],
                      ),
                      border: Border.all(color: cs.primary.withOpacity(0.40)),
                      boxShadow: [
                        BoxShadow(color: cs.primary.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: const Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shopping_cart_rounded, size: 20, color: Colors.white),
                          SizedBox(width: 10),
                          Text('BUY NOW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Affiliate Disclosure ──
              Glass(
                borderRadius: 14,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.white.withOpacity(0.35), size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Affiliate disclosure: purchases via this link may earn us a commission.',
                        style: TextStyle(color: Colors.white.withOpacity(0.40), fontWeight: FontWeight.w600, fontSize: 11, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
