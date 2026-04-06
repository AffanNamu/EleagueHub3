import 'package:flutter/material.dart';

import '../core/widgets/glass.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Glass(
          borderRadius: 14,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          fill: const Color(0xFFEF4444).withOpacity(0.94),
          border: false,
          boxShadow: const [],
          child: const Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "You're offline. Please check your connection and try again.",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
