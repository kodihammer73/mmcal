import 'package:flutter/services.dart';

/// Forces text to upper case as it is typed.
///
/// `TextCapitalization.characters` is only a keyboard hint and isn't honoured
/// on every platform, so stock codes and names are normalised here as well as
/// on save (`PortfolioTxn.canonical`).
class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final upper = newValue.text.toUpperCase();
    if (upper == newValue.text) return newValue;
    // Upper-casing preserves length for the characters used in tickers, so the
    // existing selection stays valid.
    return TextEditingValue(
      text: upper,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}
