import 'package:bleuland_energy/widgets/number_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TextEditingValue typed(String text, {int? cursor}) =>
      TextEditingValue(text: text, selection: TextSelection.collapsed(offset: cursor ?? text.length));
  String fmt(String text, {int decimals = 0}) =>
      GroupedNumberFormatter(decimals: decimals).formatEditUpdate(TextEditingValue.empty, typed(text)).text;

  test('commas every three digits', () {
    expect(fmt('1020359584'), '1,020,359,584');
    expect(fmt('106469'), '106,469');
    expect(fmt('999'), '999');
    expect(fmt(''), '');
  });
  test('typing into an already grouped number regroups it', () => expect(fmt('106,4691'), '1,064,691'));
  test('decimals only where allowed, at most that many', () {
    expect(fmt('1431.69', decimals: 2), '1,431.69');
    expect(fmt('1431.699', decimals: 2), '1,431.69');
    expect(fmt('1431.69'), '143,169');
    expect(fmt('.5', decimals: 2), '0.5');
  });
  test('no leading zeros, letters dropped', () {
    expect(fmt('007'), '7');
    expect(fmt('12a3'), '123');
  });
  test('the cursor stays after the same digit', () {
    // "106469" with the cursor after "1064" → after "1064" in "106,469"
    final v = const GroupedNumberFormatter().formatEditUpdate(TextEditingValue.empty, typed('106469', cursor: 4));
    expect(v.text.substring(0, v.selection.baseOffset), '106,4');
  });
}
