import 'package:flutter/foundation.dart';

// Discover (index 2) is the landing tab: HomeShell reads this value once,
// in initState, the first time it mounts in a given app process -- which
// is exactly cold app launch and immediately after a fresh login/
// onboarding completes, since HomeShell isn't in the widget tree at all
// before that point. Any later in-app tab switch (openHomeShellTab) still
// updates this same notifier, so navigating back to Home explicitly is
// unaffected -- only the very first landing changes.
final ValueNotifier<int> homeShellTabIndexNotifier = ValueNotifier<int>(2);

void openHomeShellTab(int index) {
  if (index < 0) {
    homeShellTabIndexNotifier.value = 0;
    return;
  }
  if (index > 4) {
    homeShellTabIndexNotifier.value = 4;
    return;
  }
  homeShellTabIndexNotifier.value = index;
}
