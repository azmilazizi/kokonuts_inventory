import 'package:flutter/services.dart';

/// A [TextInputFormatter] that keeps currency inputs fixed to two decimal places
/// and treats new digits as the least-significant (cents) values.
class CurrencyInputFormatter extends TextInputFormatter {
  const CurrencyInputFormatter();

  static final RegExp _nonDigitRegExp = RegExp(r'[^0-9]');
  static final RegExp _nonNumericRegExp = RegExp(r'[^0-9,.-]');

  /// Normalizes existing numeric strings (for example values loaded from the
  /// backend) to a standard two-decimal representation.
  static String normalizeExistingValue(String? value) {
    if (value == null) {
      return '0.00';
    }

    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '0.00';
    }

    final sanitized = trimmed.replaceAll(_nonNumericRegExp, '');
    if (sanitized.isEmpty) {
      return '0.00';
    }

    final parsed = _parseFlexibleDouble(sanitized);
    if (parsed == null) {
      return '0.00';
    }

    return parsed.toStringAsFixed(2);
  }

  static double? _parseFlexibleDouble(String value) {
    if (value.isEmpty) {
      return null;
    }

    final hasComma = value.contains(',');
    final hasDot = value.contains('.');

    String normalized = value;
    if (hasComma && hasDot) {
      final lastComma = value.lastIndexOf(',');
      final lastDot = value.lastIndexOf('.');
      if (lastComma > lastDot) {
        normalized = value.replaceAll('.', '').replaceFirst(',', '.');
      } else {
        normalized = value.replaceAll(',', '');
      }
    } else if (hasComma && !hasDot) {
      normalized = value.replaceFirst(',', '.');
    }

    return double.tryParse(normalized);
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(_nonDigitRegExp, '');
    final formatted = _formatDigitsAsCurrency(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _formatDigitsAsCurrency(String digits) {
    if (digits.isEmpty) {
      return '0.00';
    }

    final padded = digits.padLeft(3, '0');
    final integerPart = padded.substring(0, padded.length - 2);
    final decimalPart = padded.substring(padded.length - 2);
    final normalizedInteger = integerPart.replaceFirst(RegExp(r'^0+'), '');
    final safeInteger = normalizedInteger.isEmpty ? '0' : normalizedInteger;
    return '$safeInteger.$decimalPart';
  }
}
