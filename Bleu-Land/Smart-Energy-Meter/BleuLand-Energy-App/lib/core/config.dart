// Cloud connection. The publishable key is meant to ship inside the app:
// every table is protected by row-level security on the server.
abstract final class AppConfig {
  static const appName = 'BleuLand Energy';
  static const supabaseUrl = 'https://rmgzpxwpowwzqewmiyaw.supabase.co';
  static const supabaseKey = 'sb_publishable_2_MDRTqxogkVNA97djRs3Q_J3PrFZ7_';

  /// Bluetooth name prefix of an SEM-1 waiting for WiFi setup.
  static const blePrefix = 'SEM1_';

  /// A meter that hasn't reported for this long is shown as offline.
  static const offlineAfter = Duration(seconds: 45);
}
