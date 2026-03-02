import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/marketplace_repository.dart';
import '../domain/marketplace_product_model.dart';
import 'product_details_screen.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  static const List<String> _categories = <String>[
    'All',
    'Gamepads',
    'Jerseys',
    'Boots',
    'Accessories',
  ];

  String _selectedCategory = 'All';

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
      ),
      body: StreamBuilder<List<MarketplaceProduct>>(
        stream: repo.watchProducts(
          category: _selectedCategory == 'All' ? null : _selectedCategory,
          limit: 120,
        ),
        builder: (context, snap) {
          final hasError = snap.hasError;
          final isLoading =
              snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData;
          final products = snap.data ?? const <MarketplaceProduct>[];

          return CustomScrollView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              // ── Header ──
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Glass(
                    borderRadius: 22,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                cs.primary.withOpacity(0.25),
                                cs.primary.withOpacity(0.08)
                              ],
                            ),
                          ),
                          child: Icon(Icons.storefront_rounded,
                              color: cs.primary, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Marketplace',
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 22,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Gaming & sports gear',
                                style: TextStyle(
                                  color:
                                      onSurface.withOpacity(0.60),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Categories ──
              SliverPadding(
                padding:
                    const EdgeInsets.fromLTRB(16, 16, 16, 10),
                sliver: SliverToBoxAdapter(
                  child: _CategoryRow(
                    categories: _categories,
                    selected: _selectedCategory,
                    onSelect: (c) =>
                        setState(() => _selectedCategory = c),
                  ),
                ),
              ),

              // ── Content ──
              if (hasError)
                SliverPadding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: Glass(
                      borderRadius: 18,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  cs.error.withOpacity(0.12),
                            ),
                            child: Icon(
                                Icons.error_outline_rounded,
                                color: cs.error,
                                size: 24),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Could not load products.',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(
                                    fontWeight:
                                        FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (isLoading)
                SliverPadding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 20, 16, 20),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                              color: cs.primary),
                          const SizedBox(height: 14),
                          Text(
                            'Loading products...',
                            style: TextStyle(
                              color: onSurface
                                  .withOpacity(0.55),
                              fontWeight:
                                  FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (products.isEmpty)
                SliverPadding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: Glass(
                      borderRadius: 18,
                      padding:
                          const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            color: onSurface
                                .withOpacity(0.35),
                            size: 40,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _selectedCategory == 'All'
                                ? 'No products yet.'
                                : 'No products in $_selectedCategory yet.',
                            style: TextStyle(
                              color: onSurface
                                  .withOpacity(0.65),
                              fontWeight:
                                  FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding:
                      const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  sliver: SliverGrid(
                    delegate:
                        SliverChildBuilderDelegate(
                      (context, i) {
                        final p = products[i];
                        return _ProductCard(
                          product: p,
                          onTap: () {
                            Navigator.of(context)
                                .push(
                              MaterialPageRoute<
                                  void>(
                                builder: (_) =>
                                    ProductDetailsScreen(
                                  productId:
                                      p.productId,
                                  initialProduct:
                                      p,
                                ),
                              ),
                            );
                          },
                        );
                      },
                      childCount: products.length,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.68,
                    ),
                  ),
                ),

              SliverPadding(
                padding:
                    const EdgeInsets.fromLTRB(16, 2, 16, 100),
                sliver: SliverToBoxAdapter(
                  child: const _AffiliateDisclosureCard(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Category Row
// ─────────────────────────────────────────────

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = categories[i];
          final isSel = c == selected;

          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onSelect(c),
            child: AnimatedContainer(
              duration:
                  const Duration(milliseconds: 180),
              padding:
                  const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8),
              decoration: BoxDecoration(
                color: isSel
                    ? cs.primary.withOpacity(0.12)
                    : onSurface.withOpacity(0.04),
                borderRadius:
                    BorderRadius.circular(14),
                border: Border.all(
                  color: isSel
                      ? cs.primary.withOpacity(0.35)
                      : onSurface.withOpacity(0.08),
                ),
              ),
              child: Center(
                child: Text(
                  c,
                  style: TextStyle(
                    color: isSel
                        ? cs.primary
                        : onSurface
                            .withOpacity(0.65),
                    fontWeight: isSel
                        ? FontWeight.w900
                        : FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Product Card
// ─────────────────────────────────────────────

class _ProductCard extends StatefulWidget {
  const _ProductCard(
      {required this.product, required this.onTap});
  final MarketplaceProduct product;
  final VoidCallback onTap;

  @override
  State<_ProductCard> createState() =>
      _ProductCardState();
}

class _ProductCardState extends State<_ProductCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration:
          const Duration(milliseconds: 100),
      reverseDuration:
          const Duration(milliseconds: 180),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool _looksLikeHttpUrl(String s) {
    final u = s.trim().toLowerCase();
    return u.startsWith('https://') ||
        u.startsWith('http://');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;
    final p = widget.product;

    final img = p.imageUrl.trim();
    final hasImg =
        img.isNotEmpty && _looksLikeHttpUrl(img);

    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(
              scale: _scale.value, child: child),
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: Glass(
          borderRadius: 20,
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius:
                    BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 1.2,
                  child: hasImg
                      ? CachedNetworkImage(
                          imageUrl: img,
                          fit: BoxFit.cover,
                          placeholder:
                              (context, _) =>
                                  Container(
                            color: onSurface
                                .withOpacity(0.04),
                            child: Center(
                              child:
                                  SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth:
                                      2,
                                  color:
                                      cs.primary,
                                ),
                              ),
                            ),
                          ),
                          errorWidget:
                              (context, _, __) =>
                                  Container(
                            color: onSurface
                                .withOpacity(0.04),
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
                              .withOpacity(0.04),
                          child: Icon(
                            Icons.image_outlined,
                            color: onSurface
                                .withOpacity(0.35),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                p.name.trim().isEmpty
                    ? 'Untitled'
                    : p.name,
                maxLines: 2,
                overflow:
                    TextOverflow.ellipsis,
                style: theme
                    .textTheme.bodyMedium
                    ?.copyWith(
                  fontWeight:
                      FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                p.price.trim().isEmpty
                    ? '—'
                    : p.price.trim(),
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.primary,
                  fontWeight:
                      FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Icon(
                    Icons
                        .storefront_rounded,
                    size: 13,
                    color: onSurface
                        .withOpacity(0.45),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      p.sellerName
                              .trim()
                              .isEmpty
                          ? 'Seller'
                          : p.sellerName
                              .trim(),
                      maxLines: 1,
                      overflow:
                          TextOverflow
                              .ellipsis,
                      style: TextStyle(
                        color: onSurface
                            .withOpacity(
                                0.55),
                        fontWeight:
                            FontWeight
                                .w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Affiliate Disclosure
// ─────────────────────────────────────────────

class _AffiliateDisclosureCard
    extends StatelessWidget {
  const _AffiliateDisclosureCard();

  @override
  Widget build(BuildContext context) {
    final cs =
        Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;

    return Glass(
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  cs.primary.withOpacity(0.10),
            ),
            child: Icon(
                Icons.lightbulb_outline_rounded,
                color: cs.primary,
                size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'Affiliate Disclosure',
                  style: TextStyle(
                      fontWeight:
                          FontWeight.w900,
                      fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'This marketplace contains affiliate products. We may earn commission from purchases.',
                  style: TextStyle(
                    color: onSurface
                        .withOpacity(0.55),
                    fontWeight:
                        FontWeight.w600,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
