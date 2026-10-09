// lib/features/home/presentation/widgets/top_bar_profile_avatar_button.dart
//
// AppBar action showing the signed-in user's own avatar. Tapping opens
// their public profile (PublicTeamProfileScreen via the /profile/:userId
// route — the same screen other users see). Gets a colored ring, matching
// the treatment PublicTeamProfileScreen's own avatar already uses, when
// StatusRepository reports the user has an active status.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/cloudinary_media_utils.dart';
import '../../../status/data/status_repository.dart';
import '../../../verification/logic/badge_providers.dart';

class TopBarProfileAvatarButton extends ConsumerWidget {
  const TopBarProfileAvatarButton({super.key});

  static const double _size = 34;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();

    final brightness = Theme.of(context).brightness;

    // Shares the app-wide currentUserProfileProvider listener instead of
    // opening another live users/{uid} Firestore subscription just for
    // this always-mounted app-bar button.
    final profileAsync = ref.watch(currentUserProfileProvider);
    final avatarUrl = profileAsync.value?.effectivePhotoUrl ?? '';
    final thumbUrl = avatarUrl.isEmpty
        ? ''
        : CloudinaryMediaUtils.imageThumbnail(avatarUrl, maxWidth: 96);

    return StreamBuilder<bool>(
      stream: StatusRepository().watchHasActiveStatus(uid),
      builder: (context, statusSnap) {
        final hasActiveStatus = statusSnap.data ?? false;

        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: IconButton(
            padding: EdgeInsets.zero,
            onPressed: () => context.push('/profile/$uid'),
            icon: Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: hasActiveStatus
                      ? AppTheme.limeAccent
                      : AppTheme.cardBorder(brightness),
                  width: hasActiveStatus ? 2.5 : 1,
                ),
                color: AppTheme.iconCircleBackground(brightness),
                image: thumbUrl.isNotEmpty
                    ? DecorationImage(
                        image: NetworkImage(thumbUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: thumbUrl.isEmpty
                  ? Icon(
                      Icons.person_rounded,
                      size: 18,
                      color: AppTheme.secondaryText(brightness),
                    )
                  : null,
            ),
          ),
        );
      },
    );
  }
}
