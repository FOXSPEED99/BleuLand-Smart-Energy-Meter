// Number formatting in one place, so every screen speaks the same way.
import 'package:intl/intl.dart';

final _int = NumberFormat('#,##0');
final _dec1 = NumberFormat('#,##0.0');
final _dec2 = NumberFormat('#,##0.00');

/// Power: "860 W", "3.42 kW".
({String value, String unit}) fmtPower(double w) {
  if (w.abs() >= 1000) return (value: _dec2.format(w / 1000), unit: 'kW');
  return (value: _int.format(w.round()), unit: 'W');
}

String fmtPowerText(double w) {
  final p = fmtPower(w);
  return '${p.value} ${p.unit}';
}

/// Energy: "0.84 kWh", "12.6 kWh", "1,284 kWh".
String fmtKwh(double kwh, {bool unit = true}) {
  final v = kwh.abs() >= 1000
      ? _int.format(kwh)
      : kwh.abs() >= 100
          ? _int.format(kwh)
          : kwh.abs() >= 10
              ? _dec1.format(kwh)
              : _dec2.format(kwh);
  return unit ? '$v kWh' : v;
}

/// Money: whole units once amounts are large, two decimals for small ones.
String fmtMoney(double amount, String currency) {
  final v = amount.abs() >= 100 ? _int.format(amount.round()) : _dec2.format(amount);
  return '$v $currency';
}

String fmtVolts(double v) => '${_dec1.format(v)} V';
String fmtAmps(double a) => '${_dec2.format(a)} A';
String fmtPf(double pf) => pf.toStringAsFixed(2);

/// "just now", "2 min ago", "3 h ago", "12 Oct".
String fmtAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inSeconds < 20) return 'just now';
  if (d.inMinutes < 1) return '${d.inSeconds} s ago';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return DateFormat('d MMM').format(t);
}

/// Spelled out, for places with room: "just now", "1 minute ago",
/// "5 hours ago", "yesterday", "3 days ago", "on 12 Oct".
String fmtAgoLong(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  String n(int v, String unit) => '$v $unit${v == 1 ? '' : 's'} ago';
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return n(d.inMinutes, 'minute');
  if (d.inDays < 1) return n(d.inHours, 'hour');
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 7) return n(d.inDays, 'day');
  return 'on ${DateFormat('d MMM').format(t)}';
}
