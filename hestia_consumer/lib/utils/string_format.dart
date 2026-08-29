/// Display helpers for person names (professionals and users).

/// Title-cases each word so names always start with a capital letter.
/// Example: `prakash kumar` → `Prakash Kumar`.
String capitalizeWords(String? input) {
  final trimmed = input?.trim() ?? '';
  if (trimmed.isEmpty) return '';

  return trimmed.split(RegExp(r'\s+')).map((word) {
    if (word.isEmpty) return word;
    return word.split('-').map((part) {
      if (part.isEmpty) return part;
      final lower = part.toLowerCase();
      return '${lower[0].toUpperCase()}${lower.substring(1)}';
    }).join('-');
  }).join(' ');
}

/// Capitalized full name for UI, with optional fallback when empty.
String displayPersonName(String? name, {String fallback = ''}) {
  final formatted = capitalizeWords(name);
  return formatted.isEmpty ? fallback : formatted;
}
