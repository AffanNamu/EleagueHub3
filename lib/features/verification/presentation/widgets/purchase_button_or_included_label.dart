// lib/features/verification/presentation/widgets/purchase_button_or_included_label.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/badge_model.dart';
import '../../logic/badge_providers.dart';
import '../../logic/badge_service.dart';

/// Drop-in widget that replaces a purchase button with an
/// "Included with your X subscription" label when appropriate.
///
/// Pass [userId], [isGreenProduct], [isOrganizerProduct],
/// and the [purchaseButton] that should be shown when the user
/// does NOT already own the badge via subscription.
///
/// The existing UI design is preserved — this widget simply
/// conditionally swaps the button for a label.
class PurchaseButtonOrIncludedLabel extends ConsumerWidget {
  final String userId;
  final bool isGreenProduct;
  final bool isOrganizerProduct;
  
  /// The original purchase button widget from the existing screen.
  final Widget purchaseButton;
  
  const PurchaseButtonOrIncludedLabel({
    super.key,
    required this.userId,
    required this.isGreenProduct,
    required this.isOrganizerProduct,
    required this.purchaseButton,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badgeAsync = ref.watch(badgeStreamProvider(userId));
    
    return badgeAsync.when(
      data: (badges) {
        final blockedReason = BadgeService.instance.purchaseBlockedReason(
          badges: badges,
          isGreenProduct: isGreenProduct,
          isOrganizerProduct: isOrganizerProduct,
        );
        
        if (blockedReason != null) {
          return _IncludedLabel(message: blockedReason);
        }
        
        return purchaseButton;
      },
      loading: () => purchaseButton,
      error: (_, __) => purchaseButton,
    );
  }
}

/// Replaces the purchase button with an "included" label.
/// Uses the existing app green accent color.
class _IncludedLabel extends StatelessWidget {
  final String message;
  
  const _IncludedLabel({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF00C853).withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00C853).withOpacity(0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF00C853),
            size: 18,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF00C853),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
