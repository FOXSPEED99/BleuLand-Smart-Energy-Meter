import 'package:flutter/services.dart';

/// Puts thousands commas in a number while it's typed: "1020359584" shows as
/// "1,020,359,584". With [decimals] > 0 a "." and that many digits after it
/// are allowed ("1,431.69"). The cursor stays after the same digit.
class GroupedNumberFormatter extends TextInputFormatter {
  const GroupedNumberFormatter({this.decimals = 0});
  final int decimals;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue value) {
    final raw = value.text;
    // keep digits (and one "." when decimals are allowed)
    final b = StringBuffer();
    var dot = false;
    var fraction = 0;
    for (final ch in raw.split('')) {
      if (_isDigit(ch)) {
        if (dot) {
          if (fraction >= decimals) continue;
          fraction++;
        }
        b.write(ch);
      } else if (ch == '.' && decimals > 0 && !dot) {
        dot = true;
        b.write('.');
      }
    }
    var clean = b.toString();
    if (clean.startsWith('.')) clean = '0$clean';
    final parts = clean.split('.');
    // no leading zeros ("007" → "7"), but "0" and "0.5" stay
    var whole = parts[0].replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final text = parts.length > 1 ? '${_group(whole)}.${parts[1]}' : _group(whole);

    // put the cursor after as many digits (and dot) as it had before it
    final cursor = value.selection.baseOffset < 0 ? raw.length : value.selection.baseOffset;
    final kept = raw.substring(0, cursor.clamp(0, raw.length)).split('').where((c) => _isDigit(c) || c == '.').length;
    var pos = 0, seen = 0;
    while (pos < text.length && seen < kept) {
      if (text[pos] != ',') seen++;
      pos++;
    }
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: pos));
  }

  static bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  static String _group(String digits) {
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
}
