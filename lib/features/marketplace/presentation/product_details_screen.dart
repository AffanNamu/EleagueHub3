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
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        content: Text(trimmed),
      ),
    );
  }

  Future<void> _buyNow(BuildContext context, MarketplaceProduct p) async {
    final affiliate = p.affiliateUrl.trim();
    if (!_looksLikeHttpUrl(affiliate)) {
      _snack(context, 'Invalid affiliate link.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;

        return AlertDialog(
          backgroundColor: cs.surface,
          title: const Text('Continue?'),
          content: const Text('You are being redirected to partner store'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    final uri = Uri.tryParse(affiliate);
    if (uri == null) {
      _snack(context, 'Invalid link URL.');
      return;
    }

    final ok = await canLaunchUrl(uri);
    if (!ok) {
      _snack(context, 'Could not open partner store.');
      return;
    }

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && context.mounted) {
        _snack(context, 'Could not open partner store.');
      }
    } catch (_) {
      if (context.mounted) {
        _snack(context, 'Could not open partner store.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final repo = MarketplaceRepository();

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Product'),
      ),
      body: StreamBuilder<MarketplaceProduct?>(
        stream: repo.watchProductById(productId),
        initialData: initialProduct,
        builder: (context, snap) {
          if (snap.hasError) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Glass(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: cs.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Could not load product.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          if (!snap.hasData) {
            return Center(
              child: CircularProgressIndicator(color: cs.primary),
            );
          }

          final p = snap.data;
          if (p == null) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Glass(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          color: cs.onSurface.withOpacity(0.72)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Product not found.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface.withOpacity(0.80),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          final img = p.imageUrl.trim();
          final hasImg = img.isNotEmpty && _looksLikeHttpUrl(img);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Glass(
                borderRadius: 22,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(
                        aspectRatio: 1.2,
                        child: hasImg
                            ? CachedNetworkImage(
                                imageUrl: img,
                                fit: BoxFit.cover,
                                fadeInDuration:
                                    const Duration(milliseconds: 150),
                                placeholder: (context, _) => DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: cs.onSurface.withOpacity(0.06),
                                  ),
                                  child: Center(
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                errorWidget: (context, _, __) => DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: cs.onSurface.withOpacity(0.06),
                                  ),
                                  child: Icon(
                                    Icons.image_not_supported_outlined,
                                    color: cs.onSurface.withOpacity(0.55),
                                  ),
                                ),
                              )
                            : DecoratedBox(
                                decoration: BoxDecoration(
                                  color: cs.onSurface.withOpacity(0.06),
                                ),
                                child: Icon(
                                  Icons.image_outlined,
                                  color: cs.onSurface.withOpacity(0.55),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      p.name.trim().isEmpty ? 'Untitled product' : p.name.trim(),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                        height: 1.12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      p.price.trim().isEmpty ? '—' : p.price.trim(),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.storefront_outlined,
                            size: 18, color: cs.onSurface.withOpacity(0.70)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            p.sellerName.trim().isEmpty
                                ? 'Seller'
                                : p.sellerName.trim(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface.withOpacity(0.80),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      p.description.trim().isEmpty
                          ? 'No description.'
                          : p.description.trim(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withOpacity(0.75),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => _buyNow(context, p),
                        child: const Text('BUY NOW'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Affiliate disclosure: purchases via this link may earn us a commission.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.65),
                        fontWeight: FontWeight.w600,
                        height: 1.25,
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
