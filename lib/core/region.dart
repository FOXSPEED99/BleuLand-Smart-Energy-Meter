/// Where the user's homes are. Picked after signing up / in, changeable in
/// Settings; it decides the flag on the bill (and, later, local defaults
/// such as the electricity price). Add a country here to support it.
class Region {
  const Region({required this.id, required this.name, required this.currency, this.billMatch = false});
  final String id; // ISO 3166 code, lower case
  final String name;
  final String currency;
  // "Match your bill" with the house meter's readings: for countries whose
  // bills come from fixed calendar cycles read off the utility meter
  final bool billMatch;
}

const regions = [
  // 2-month cycles from the 1st of odd months, billed from meter readings
  Region(id: 'sy', name: 'Syria', currency: 'SYP', billMatch: true),
];

Region? regionById(String? id) {
  for (final r in regions) {
    if (r.id == id) return r;
  }
  return null;
}
