import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'animated_bubble_background.dart';

class GlassScaffold extends StatelessWidget {
  const GlassScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.extendBody = true,
    this.resizeToAvoidBottomInset = true,
    this.useBubbles = true,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final bool extendBody;
  final bool resizeToAvoidBottomInset;
  final bool useBubbles;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      extendBody: extendBody,
      extendBodyBehindAppBar: appBar != null,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      backgroundColor: Colors.transparent,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppTheme.backgroundGradient(brightness),
              ),
            ),
          ),
          if (useBubbles) const Positioned.fill(child: AnimatedBubbleBackground()),
          if (brightness == Brightness.light)
            Positioned(
              top: -90,
              right: -70,
              child: IgnorePointer(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0x26B6FF00),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (brightness == Brightness.dark)
            Positioned(
              bottom: -120,
              left: -80,
              child: IgnorePointer(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color(0x18B6FF00),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          body,
        ],
      ),
    );
  }
}
