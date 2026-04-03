import 'package:flutter/foundation.dart';

final ValueNotifier<int> homeShellTabIndexNotifier = ValueNotifier<int>(0);

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
