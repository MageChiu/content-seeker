List<String> buildMediaSearchQueries(
  String query, {
  int maxVariants = 5,
}) {
  final normalized = _normalizeWhitespace(query);
  if (normalized.isEmpty) {
    return const [];
  }

  final variants = <String>[];
  final seen = <String>{};

  void add(String value) {
    final candidate = _normalizeWhitespace(value);
    if (candidate.isEmpty) return;
    final key = candidate.toLowerCase();
    if (seen.add(key)) {
      variants.add(candidate);
    }
  }

  add(normalized);

  final stripped = _stripCommonDecorations(normalized);
  add(stripped);

  final simplified = _simplifySeparators(stripped);
  add(simplified);

  final parts = _splitCompoundQuery(stripped);
  if (parts.length == 2) {
    final left = _stripCommonDecorations(parts[0]);
    final right = _stripCommonDecorations(parts[1]);
    add('$left $right');
    add('$right $left');
    add(left);
    add(right);
  }

  if (variants.length <= maxVariants) {
    return List<String>.unmodifiable(variants);
  }
  return List<String>.unmodifiable(variants.take(maxVariants));
}

String _normalizeWhitespace(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _stripCommonDecorations(String value) {
  var current = value.trim();
  current = current.replaceAll(
    RegExp(r'\[(official|mv|m/v|music video|lyrics?|lyric video|audio|hd)\]',
        caseSensitive: false),
    ' ',
  );
  current = current.replaceAll(
    RegExp(r'\((official|mv|m/v|music video|lyrics?|lyric video|audio|hd)\)',
        caseSensitive: false),
    ' ',
  );
  current = current.replaceAll(
    RegExp(r'【(official|mv|m/v|music video|lyrics?|lyric video|audio|hd)】',
        caseSensitive: false),
    ' ',
  );
  return _normalizeWhitespace(current);
}

String _simplifySeparators(String value) {
  return _normalizeWhitespace(
    value.replaceAll(RegExp(r'[·•_/|]+'), ' ').replaceAll(RegExp(r'\s*-\s*'), ' '),
  );
}

List<String> _splitCompoundQuery(String value) {
  final separators = <RegExp>[
    RegExp(r'\s+-\s+'),
    RegExp(r'\s+by\s+', caseSensitive: false),
    RegExp(r'\s*[|/]\s*'),
    RegExp(r'\s*[·•]\s*'),
  ];

  for (final separator in separators) {
    final parts = value
        .split(separator)
        .map(_normalizeWhitespace)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (parts.length == 2) {
      return parts;
    }
  }
  return const [];
}
