/// Where the user's homes are. Picked after signing up / in, changeable in
/// Settings; it decides the flag on the bill (and, later, local defaults
/// such as the electricity price). Add a country here to support it.
class Region {
  const Region({required this.id, required this.name, required this.currency});
  final String id; // ISO 3166 code, lower case
  final String name;
  final String currency;
}

const regions = [
  Region(id: 'sy', name: 'Syria', currency: 'SYP'),
];

Region? regionById(String? id) {
  for (final r in regions) {
    if (r.id == id) return r;
  }
  return null;
}
