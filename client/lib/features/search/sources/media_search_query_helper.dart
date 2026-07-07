List<String> buildMediaSearchQueries(
  String query, {
  int maxVariants = 8,
}) {
  final normalized = _normalizeQuery(query);
  if (normalized.isEmpty) {
    return const [];
  }

  final variants = <String>[];
  final seen = <String>{};

  void add(String value) {
    final candidate = _normalizeQuery(value);
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

  final core = _stripMusicVersionTokens(simplified);
  add(core);

  final parts = _splitCompoundQuery(simplified);
  if (parts.length == 2) {
    final left = _stripMusicVersionTokens(_stripCommonDecorations(parts[0]));
    final right = _stripMusicVersionTokens(_stripCommonDecorations(parts[1]));
    add('$left $right');
    add('$right $left');
    add(left);
    add(right);
    add(_stripFeaturing('$left $right'));
    add(_stripFeaturing('$right $left'));
  }

  add(_stripFeaturing(core));
  add(_stripFeaturing(normalized));

  if (variants.length <= maxVariants) {
    return List<String>.unmodifiable(variants);
  }
  return List<String>.unmodifiable(variants.take(maxVariants));
}

String _normalizeQuery(String value) {
  return _normalizeWhitespace(
    value
        .replaceAll(RegExp(r'[“”]'), '"')
        .replaceAll(RegExp(r"[‘’]"), "'")
        .replaceAll(RegExp(r'[【\[]'), '(')
        .replaceAll(RegExp(r'[】\]]'), ')')
        .replaceAll(RegExp(r'[—–]+'), '-')
        .replaceAll(RegExp(r'[：]+'), ':')
        .replaceAll(RegExp(r'[，、]+'), ' '),
  );
}

String _normalizeWhitespace(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _stripCommonDecorations(String value) {
  var current = value.trim();
  current = current.replaceAll(
    RegExp(r'^\s*(song|track|music)\s*:\s*', caseSensitive: false),
    '',
  );
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

String _stripMusicVersionTokens(String value) {
  var current = value.trim();
  current = current.replaceAll(
    RegExp(
      r'\((live|remix|mix|ver\.?|version|cover|karaoke|instrumental|acoustic|demo|ost|theme|edit|performance|recording)[^)]*\)',
      caseSensitive: false,
    ),
    ' ',
  );
  current = current.replaceAll(
    RegExp(
      r'\[(live|remix|mix|ver\.?|version|cover|karaoke|instrumental|acoustic|demo|ost|theme|edit|performance|recording)[^\]]*\]',
      caseSensitive: false,
    ),
    ' ',
  );
  current = current.replaceAll(
    RegExp(
      r'\b(live|remix|mix|cover|karaoke|instrumental|acoustic|demo|ost|theme song|theme|edit|full version|official audio|official video)\b',
      caseSensitive: false,
    ),
    ' ',
  );
  return _normalizeWhitespace(current);
}

String _stripFeaturing(String value) {
  return _normalizeWhitespace(
    value.replaceAll(
      RegExp(r'\b(feat\.?|ft\.?|featuring|with)\b.*$', caseSensitive: false),
      ' ',
    ),
  );
}

String _simplifySeparators(String value) {
  return _normalizeWhitespace(
    value
        .replaceAll(RegExp(r'[·•_/|]+'), ' ')
        .replaceAll(RegExp(r'\s*-\s*'), ' ')
        .replaceAll(RegExp(r'\s*:\s*'), ' '),
  );
}

List<String> _splitCompoundQuery(String value) {
  final separators = <RegExp>[
    RegExp(r'\s+-\s+'),
    RegExp(r'\s*:\s*'),
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
