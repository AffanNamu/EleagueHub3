import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'glass.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.enabled = true,
    this.textInputAction,
    this.autofillHints,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final textColor = AppTheme.primaryText(brightness);
    final secondaryText = AppTheme.secondaryText(brightness);

    return Glass(
      padding: EdgeInsets.zero,
      borderRadius: 18,
      fill: AppTheme.searchBackground(brightness),
      borderColor: AppTheme.searchOutline(brightness),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        obscureText: obscureText,
        onChanged: onChanged,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        onSubmitted: onSubmitted,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
          floatingLabelBehavior: FloatingLabelBehavior.auto,
          labelStyle: theme.textTheme.labelMedium?.copyWith(
            color: secondaryText,
            fontWeight: FontWeight.w600,
          ),
          hintStyle: theme.textTheme.bodySmall?.copyWith(
            color: secondaryText,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
