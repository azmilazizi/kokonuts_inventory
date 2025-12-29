import 'package:flutter/material.dart';

class ReadOnlyFieldStyle {
  static Color _fadedTextColor(ThemeData theme) {
    return theme.colorScheme.onSurface.withOpacity(0.5);
  }

  static Color _borderColor(ThemeData theme) {
    return theme.colorScheme.outline.withOpacity(0.4);
  }

  static TextStyle? textStyle(ThemeData theme) {
    return theme.textTheme.bodyMedium?.copyWith(
      color: _fadedTextColor(theme),
    );
  }

  static InputDecoration decoration(
    ThemeData theme, {
    required String labelText,
    String? hintText,
  }) {
    final border = UnderlineInputBorder(
      borderSide: BorderSide(color: _borderColor(theme)),
    );
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: _fadedTextColor(theme),
    );
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      filled: false,
      fillColor: Colors.transparent,
      enabledBorder: border,
      focusedBorder: border,
      disabledBorder: border,
      labelStyle: labelStyle,
      floatingLabelStyle: labelStyle,
    );
  }
}
