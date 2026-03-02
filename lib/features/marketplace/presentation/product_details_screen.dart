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
    final onSurface = cs.onSurface;

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
                    color: onSurface.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        cs.primary.withOpacity(0.25),
                        cs.primary.withOpacity(0.08)
                      ],
                    ),
                  ),
                  child: Icon(Icons.open_in_new_rounded,
                      color: cs.primary, size: 24),
                ),
                const SizedBox(height: 14),
                Text(
                  'Continue to Partner Store?',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You will be redirected to an external store to complete your purchase.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: onSurface.withOpacity(0.60),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            Navigator.of(ctx).pop(true),
                        icon: const Icon(
                            Icons.open_in_new_rounded,
                            size: 18),
                        label: const Text('Continue'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cs.primary,
                          foregroundColor: Colors.white,
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
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
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
    final onSurface = cs.onSurface;
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
            child: Icon(Icons.arrow_back_ios_new_rounded,
                size: 18, color: onSurface),
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: StreamBuilder<MarketplaceProduct?>(
        stream: repo.watchProductById(productId),
        initialData: initialProduct,
        builder: (context, snap) {
          if (!snap.hasData) {
            return Center(
              child: CircularProgressIndicator(
                  color: cs.primary),
            );
          }

          final p = snap.data!;
          final img = p.imageUrl.trim();
          final hasImg =
              img.isNotEmpty && _looksLikeHttpUrl(img);

          return ListView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding:
                const EdgeInsets.fromLTRB(16, 4, 16, 100),
            children: [
              Glass(
                borderRadius: 22,
                padding: const EdgeInsets.all(10),
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 1.1,
                    child: hasImg
                        ? CachedNetworkImage(
                            imageUrl: img,
                            fit: BoxFit.cover,
                            placeholder:
                                (context, _) =>
                                    Container(
                              color: onSurface
                                  .withOpacity(
                                      0.04),
                              child: Center(
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color:
                                      cs.primary,
                                ),
                              ),
                            ),
                            errorWidget:
                                (context, _, __) =>
                                    Container(
                              color: onSurface
                                  .withOpacity(
                                      0.04),
                              child: Icon(
                                Icons
                                    .image_not_supported_outlined,
                                color: onSurface
                                    .withOpacity(
                                        0.35),
                              ),
                            ),
                          )
                        : Container(
                            color: onSurface
                                .withOpacity(
                                    0.04),
                            child: Icon(
                              Icons.image_outlined,
                              size: 48,
                              color: onSurface
                                  .withOpacity(
                                      0.35),
                            ),
                          ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              Glass(
                borderRadius: 20,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name.trim().isEmpty
                          ? 'Untitled product'
                          : p.name.trim(),
                      style: theme
                          .textTheme.titleLarge
                          ?.copyWith(
                        fontWeight:
                            FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      p.price.trim().isEmpty
                          ? '—'
                          : p.price.trim(),
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight:
                            FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Divider(
                        color: onSurface
                            .withOpacity(0.08)),
                    const SizedBox(height: 12),
                    Text(
                      'Description',
                      style: TextStyle(
                        color: onSurface
                            .withOpacity(0.55),
                        fontWeight:
                            FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      p.description.trim().isEmpty
                          ? 'No description.'
                          : p.description.trim(),
                      style: TextStyle(
                        color: onSurface
                            .withOpacity(0.70),
                        fontWeight:
                            FontWeight.w600,
                        height: 1.45,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      _buyNow(context, p),
                  icon: const Icon(
                      Icons.shopping_cart_rounded),
                  label: const Text(
                    'BUY NOW',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                              18),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
