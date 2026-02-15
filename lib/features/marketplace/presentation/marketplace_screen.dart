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

    final repo = MarketplaceRepository();

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Marketplace'),
      ),
      body: StreamBuilder<List<MarketplaceProduct>>(
        stream: repo.watchProducts(
          category: _selectedCategory == 'All' ? null : _selectedCategory,
          limit: 120,
        ),
        builder: (context, snap) {
          final hasError = snap.hasError;
          final isLoading =
              snap.connectionState == ConnectionState.waiting && !snap.hasData;
          final products = snap.data ?? const <MarketplaceProduct>[];

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                sliver: SliverToBoxAdapter(
                  child: _HeroBanner(
                    title: 'Affiliate Product\nMarketplace',
                    subtitle:
                        'Explore great deals on gaming\nand sports gear.',
                    badgeText: 'Affiliate Products',
                    trailing: _HeroTrailingWidget(),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                sliver: SliverToBoxAdapter(
                  child: Glass(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.headset_mic_outlined,
                            color: cs.onSurface.withOpacity(0.70)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Purchases made through these links may earn us a small commission at no extra cost you.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.70),
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                sliver: SliverToBoxAdapter(
                  child: _CategoryRow(
                    categories: _categories,
                    selected: _selectedCategory,
                    onSelect: (c) => setState(() => _selectedCategory = c),
                  ),
                ),
              ),
              if (hasError)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: Glass(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: cs.error),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Could not load marketplace products.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (isLoading)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  sliver: SliverToBoxAdapter(
                    child: Center(
                      child: CircularProgressIndicator(color: cs.primary),
                    ),
                  ),
                )
              else if (products.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  sliver: SliverToBoxAdapter(
                    child: Glass(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              color: cs.onSurface.withOpacity(0.72)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _selectedCategory == 'All'
                                  ? 'No products yet.'
                                  : 'No products in $_selectedCategory yet.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurface.withOpacity(0.78),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final p = products[i];
                        return _ProductCard(
                          product: p,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ProductDetailsScreen(
                                  productId: p.productId,
                                  initialProduct: p,
                                ),
                              ),
                            );
                          },
                        );
                      },
                      childCount: products.length,
                    ),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.72,
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
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

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.title,
    required this.subtitle,
    required this.badgeText,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final String badgeText;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF2D6CDF).withOpacity(0.85),
                  const Color(0xFF65C7FF).withOpacity(0.70),
                ],
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
              ),
            ),
            child: const SizedBox(height: 150, width: double.infinity),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withOpacity(0.06),
                    Colors.transparent,
                  ],
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 150,
            top: 16,
            bottom: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withOpacity(0.92),
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.20),
                    borderRadius: BorderRadius.circular(999),
                    border:
                        Border.all(color: Colors.white.withOpacity(0.24)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_offer_outlined,
                          size: 16, color: Colors.white.withOpacity(0.95)),
                      const SizedBox(width: 6),
                      Text(
                        badgeText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withOpacity(0.95),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 10,
            top: 10,
            bottom: 10,
            child: SizedBox(
              width: 130,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    border: Border.all(color: Colors.white.withOpacity(0.18)),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Center(child: trailing),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 1,
              color: cs.onSurface.withOpacity(0.08),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroTrailingWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Align(
          alignment: AlignmentDirectional.topEnd,
          child: Icon(
            Icons.sports_esports_rounded,
            size: 74,
            color: Colors.white.withOpacity(0.90),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.bottomStart,
          child: Icon(
            Icons.sports_soccer_rounded,
            size: 54,
            color: Colors.white.withOpacity(0.70),
          ),
        ),
      ],
    );
  }
}

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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final c = categories[i];
          final isSel = c == selected;

          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => onSelect(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSel ? cs.primary.withOpacity(0.16) : cs.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSel ? cs.primary.withOpacity(0.55) : cs.onSurface.withOpacity(0.10),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _categoryIcon(c),
                    size: 18,
                    color: isSel ? cs.primary : cs.onSurface.withOpacity(0.70),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    c,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isSel ? cs.primary : cs.onSurface.withOpacity(0.82),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _categoryIcon(String c) {
    switch (c.toLowerCase()) {
      case 'gamepads':
        return Icons.sports_esports_outlined;
      case 'jerseys':
        return Icons.checkroom_outlined;
      case 'boots':
        return Icons.hiking_outlined;
      case 'accessories':
        return Icons.watch_outlined;
      default:
        return Icons.apps_outlined;
    }
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.onTap,
  });

  final MarketplaceProduct product;
  final VoidCallback onTap;

  bool _looksLikeHttpUrl(String s) {
    final u = s.trim().toLowerCase();
    return u.startsWith('https://') || u.startsWith('http://');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final img = product.imageUrl.trim();
    final hasImg = img.isNotEmpty && _looksLikeHttpUrl(img);

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Glass(
        borderRadius: 22,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 1.25,
                child: hasImg
                    ? CachedNetworkImage(
                        imageUrl: img,
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 150),
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
            const SizedBox(height: 10),
            Text(
              product.name.trim().isEmpty ? 'Untitled product' : product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w900,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              product.price.trim().isEmpty ? '—' : product.price.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Icon(Icons.storefront_outlined,
                    size: 16, color: cs.onSurface.withOpacity(0.65)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    product.sellerName.trim().isEmpty
                        ? 'Seller'
                        : product.sellerName.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.72),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AffiliateDisclosureCard extends StatelessWidget {
  const _AffiliateDisclosureCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Glass(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.primary.withOpacity(0.30)),
            ),
            child: Icon(Icons.lightbulb_outline, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Affiliate Disclosure',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This marketplace contains affiliate products. We may earn commission from purchases.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.70),
                    fontWeight: FontWeight.w600,
                    height: 1.25,
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
