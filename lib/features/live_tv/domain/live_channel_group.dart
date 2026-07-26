import 'live_channel.dart';

enum LiveChannelQualityTier {
  low,
  standard,
  hd,
  fullHd,
  ultraHd,
}

class LiveChannelVariant {
  const LiveChannelVariant({
    required this.channel,
    required this.tier,
  });

  final LiveChannel channel;
  final LiveChannelQualityTier tier;

  String get qualityLabel {
    switch (tier) {
      case LiveChannelQualityTier.low:
        return 'SD';
      case LiveChannelQualityTier.standard:
        return 'Estándar';
      case LiveChannelQualityTier.hd:
        return 'HD';
      case LiveChannelQualityTier.fullHd:
        return 'FHD';
      case LiveChannelQualityTier.ultraHd:
        return '4K';
    }
  }

  bool get isBackup => liveChannelIsBackup(channel);

  List<String> get labels => liveChannelVariantLabels(channel);

  String get description => liveChannelVariantDescription(channel);
}

class LiveChannelGroup {
  const LiveChannelGroup({
    required this.key,
    required this.displayName,
    required this.variants,
  });

  final String key;
  final String displayName;
  final List<LiveChannelVariant> variants;

  LiveChannelVariant get preferredVariant => variants.first;

  LiveChannel get representative {
    for (final variant in variants) {
      if (!variant.isBackup && variant.channel.iconUrl.trim().isNotEmpty) {
        return variant.channel;
      }
    }

    for (final variant in variants) {
      if (!variant.isBackup) {
        return variant.channel;
      }
    }

    for (final variant in variants) {
      if (variant.channel.iconUrl.trim().isNotEmpty) {
        return variant.channel;
      }
    }

    return variants.first.channel;
  }

  String get categoryId => representative.categoryId;

  String get iconUrl {
    for (final variant in variants) {
      if (variant.channel.iconUrl.trim().isNotEmpty) {
        return variant.channel.iconUrl;
      }
    }

    return '';
  }

  int get variantCount => variants.length;

  Set<int> get streamIds {
    return variants.map((variant) => variant.channel.streamId).toSet();
  }

  List<String> get qualityLabels {
    final labels = <String>[];

    for (final variant in variants) {
      final label = variant.qualityLabel;

      if (!labels.contains(label)) {
        labels.add(label);
      }
    }

    return labels;
  }
}

/// Convierte las señales crudas del proveedor en una sola entrada visual por
/// canal. Ninguna URL se elimina: todas permanecen disponibles como variantes.
List<LiveChannelGroup> groupLiveChannels(
  Iterable<LiveChannel> channels,
) {
  final source = channels.where((channel) => channel.isValid).toList(
        growable: false,
      );

  if (source.isEmpty) {
    return const [];
  }

  final disjointSet = _DisjointSet(source.length);
  final nameOwners = <String, int>{};
  final epgOwners = <String, int>{};

  for (var index = 0; index < source.length; index++) {
    final channel = source[index];
    final nameKey = liveChannelGroupKey(channel);
    final previousNameIndex = nameOwners[nameKey];

    if (previousNameIndex != null) {
      disjointSet.union(index, previousNameIndex);
    } else {
      nameOwners[nameKey] = index;
    }

    final epgKey = _liveChannelEpgKey(channel);

    if (epgKey != null) {
      final previousEpgIndex = epgOwners[epgKey];

      if (previousEpgIndex != null) {
        disjointSet.union(index, previousEpgIndex);
      } else {
        epgOwners[epgKey] = index;
      }
    }
  }

  final grouped = <int, Map<int, LiveChannelVariant>>{};

  for (var index = 0; index < source.length; index++) {
    final channel = source[index];
    final root = disjointSet.find(index);

    grouped.putIfAbsent(root, () => <int, LiveChannelVariant>{})[
          channel.streamId
        ] = LiveChannelVariant(
      channel: channel,
      tier: detectLiveChannelQuality(channel.name),
    );
  }

  final groups = <LiveChannelGroup>[];

  for (final entry in grouped.entries) {
    final variants = entry.value.values.toList()..sort(_compareVariants);
    final representative = _representativeVariant(variants);
    final displayName = _bestDisplayName(variants, representative.channel.name);

    groups.add(
      LiveChannelGroup(
        key: liveChannelGroupKey(representative.channel),
        displayName: displayName,
        variants: List<LiveChannelVariant>.unmodifiable(variants),
      ),
    );
  }

  // El proveedor suele enviar un orden inconsistente. La lista visible queda
  // organizada alfabéticamente y conserva números reales como ESPN 2 o HBO 3.
  groups.sort((a, b) => _naturalCompare(a.displayName, b.displayName));

  return List<LiveChannelGroup>.unmodifiable(groups);
}

String liveChannelGroupKey(LiveChannel channel) {
  final category = _normalizeCategory(channel.categoryId);
  final baseName = _normalize(liveChannelBaseName(channel.name));

  return '$category|name:$baseName';
}

String? _liveChannelEpgKey(LiveChannel channel) {
  final category = _normalizeCategory(channel.categoryId);
  final epg = _normalizeEpg(channel.epgChannelId);

  if (epg.isEmpty || epg == '-' || epg == 'null') {
    return null;
  }

  return '$category|epg:$epg';
}

String liveChannelBaseName(String name) {
  var value = name
      .replaceAll('\u00A0', ' ')
      .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
      .trim();

  // Etiquetas que suelen aparecer como prefijo antes del nombre real.
  value = value.replaceFirst(
    RegExp(
      r'^\s*[\[(]?(?:mx|mex|mexico|lat|latam|latino|usa|us|uk|esp|es|co|col|arg|ar|cl|chi|pe|peru|vip|premium)[\])]?\s*[|:/_-]+\s*',
      caseSensitive: false,
    ),
    '',
  );

  final technicalToken = RegExp(
    r'(^|[\s\-_|:/()\[\]{}.,+])(?:4k|uhd|fhd|full\s*hd|1080(?:p|i)?|720(?:p|i)?|576(?:p|i)?|540(?:p|i)?|480(?:p|i)?|360(?:p|i)?|hd|sd|low|hevc|avc|h\.?265|h\.?264|x265|x264|60\s*fps|50\s*fps)(?:\+)?(?=$|[\s\-_|:/()\[\]{}.,+])',
    caseSensitive: false,
  );

  final signalToken = RegExp(
    r'(^|[\s\-_|:/()\[\]{}.,+])(?:backup|back\s*up|bk|respaldo|alternativ[oa]|alt|mirror|vip|premium|latino|latam|lat|espanol|español|castellano|english|ingles|inglés|eng|dual|source\s*\d+|fuente\s*\d+|server\s*\d+|servidor\s*\d+|srv\s*\d+|linea\s*\d+|línea\s*\d+|opcion\s*\d+|opción\s*\d+)(?=$|[\s\-_|:/()\[\]{}.,+])',
    caseSensitive: false,
  );

  while (technicalToken.hasMatch(value) || signalToken.hasMatch(value)) {
    value = value.replaceAll(technicalToken, ' ');
    value = value.replaceAll(signalToken, ' ');
  }

  value = value.replaceAll(RegExp(r'[\[\](){}]'), ' ');
  value = value.replaceAll(RegExp(r'(^|\s)[|:/+_-]+(?=\s|$)'), ' ');
  value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  value = value.replaceAll(RegExp(r'^[\-_|:/.+]+|[\-_|:/.+]+$'), '').trim();

  return value.isEmpty ? name.trim() : value;
}

LiveChannelQualityTier detectLiveChannelQuality(String name) {
  final value = _normalize(name);

  if (RegExp(r'\b(4k|uhd|2160p?)\b').hasMatch(value)) {
    return LiveChannelQualityTier.ultraHd;
  }

  if (RegExp(r'\b(fhd|full\s*hd|1080p?|1080i)\b').hasMatch(value)) {
    return LiveChannelQualityTier.fullHd;
  }

  if (RegExp(r'\b(hd|720p?|720i)\b').hasMatch(value)) {
    return LiveChannelQualityTier.hd;
  }

  if (RegExp(r'\b(sd|576p?|540p?|480p?|360p?|low)\b').hasMatch(value)) {
    return LiveChannelQualityTier.low;
  }

  return LiveChannelQualityTier.standard;
}

String liveChannelQualityLabel(LiveChannel channel) {
  return LiveChannelVariant(
    channel: channel,
    tier: detectLiveChannelQuality(channel.name),
  ).qualityLabel;
}

bool liveChannelIsBackup(LiveChannel channel) {
  final value = _normalize(channel.name);

  return RegExp(
    r'\b(backup|back\s*up|bk|respaldo|alternativ[oa]|alt|mirror|source\s*\d+|fuente\s*\d+|server\s*\d+|servidor\s*\d+|srv\s*\d+|linea\s*\d+|opcion\s*\d+)\b',
  ).hasMatch(value);
}

List<String> liveChannelVariantLabels(LiveChannel channel) {
  final value = _normalize(channel.name);
  final labels = <String>[liveChannelQualityLabel(channel)];

  void addLabel(String label) {
    if (!labels.contains(label)) {
      labels.add(label);
    }
  }

  if (RegExp(r'\b(hevc|h\s*265|x265)\b').hasMatch(value)) {
    addLabel('HEVC');
  }

  if (RegExp(r'\b(latino|latam|lat)\b').hasMatch(value)) {
    addLabel('Latino');
  } else if (RegExp(r'\b(espanol|castellano|esp)\b').hasMatch(value)) {
    addLabel('Español');
  } else if (RegExp(r'\b(english|ingles|eng)\b').hasMatch(value)) {
    addLabel('Inglés');
  }

  if (RegExp(r'\b(dual)\b').hasMatch(value)) {
    addLabel('Dual');
  }

  if (RegExp(r'\b(vip|premium)\b').hasMatch(value)) {
    addLabel('Premium');
  }

  if (liveChannelIsBackup(channel)) {
    addLabel('Respaldo');
  }

  return List<String>.unmodifiable(labels);
}

String liveChannelVariantDescription(LiveChannel channel) {
  return liveChannelVariantLabels(channel).join(' · ');
}

int _compareVariants(LiveChannelVariant a, LiveChannelVariant b) {
  if (a.isBackup != b.isBackup) {
    return a.isBackup ? 1 : -1;
  }

  final qualityComparison = _qualityRank(b.tier).compareTo(
    _qualityRank(a.tier),
  );

  if (qualityComparison != 0) {
    return qualityComparison;
  }

  final orderComparison = a.channel.order.compareTo(b.channel.order);

  if (orderComparison != 0) {
    return orderComparison;
  }

  return _naturalCompare(a.channel.name, b.channel.name);
}

int _qualityRank(LiveChannelQualityTier tier) {
  switch (tier) {
    case LiveChannelQualityTier.low:
      return 0;
    case LiveChannelQualityTier.standard:
      return 1;
    case LiveChannelQualityTier.hd:
      return 2;
    case LiveChannelQualityTier.fullHd:
      return 3;
    case LiveChannelQualityTier.ultraHd:
      return 4;
  }
}

LiveChannelVariant _representativeVariant(
  List<LiveChannelVariant> variants,
) {
  for (final variant in variants) {
    if (!variant.isBackup && variant.channel.iconUrl.trim().isNotEmpty) {
      return variant;
    }
  }

  for (final variant in variants) {
    if (!variant.isBackup) {
      return variant;
    }
  }

  return variants.first;
}

String _bestDisplayName(
  List<LiveChannelVariant> variants,
  String fallback,
) {
  final names = variants
      .map((variant) => liveChannelBaseName(variant.channel.name))
      .where((name) => name.trim().isNotEmpty)
      .toSet()
      .toList();

  if (names.isEmpty) {
    return liveChannelBaseName(fallback);
  }

  names.sort((a, b) {
    final wordComparison =
        a.split(RegExp(r'\s+')).length.compareTo(b.split(RegExp(r'\s+')).length);

    if (wordComparison != 0) {
      return wordComparison;
    }

    final lengthComparison = a.length.compareTo(b.length);

    if (lengthComparison != 0) {
      return lengthComparison;
    }

    return _naturalCompare(a, b);
  });

  return names.first;
}

int _naturalCompare(String first, String second) {
  final firstParts = _naturalParts(first);
  final secondParts = _naturalParts(second);
  final length = firstParts.length < secondParts.length
      ? firstParts.length
      : secondParts.length;

  for (var index = 0; index < length; index++) {
    final firstPart = firstParts[index];
    final secondPart = secondParts[index];
    final firstNumber = int.tryParse(firstPart);
    final secondNumber = int.tryParse(secondPart);

    final comparison = firstNumber != null && secondNumber != null
        ? firstNumber.compareTo(secondNumber)
        : firstPart.compareTo(secondPart);

    if (comparison != 0) {
      return comparison;
    }
  }

  return firstParts.length.compareTo(secondParts.length);
}

List<String> _naturalParts(String value) {
  return RegExp(r'\d+|\D+')
      .allMatches(_normalize(value))
      .map((match) => match.group(0) ?? '')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
}

String _normalizeCategory(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized.isEmpty ? 'sin-categoria' : normalized;
}

String _normalizeEpg(String value) {
  return value
      .replaceAll('\u00A0', ' ')
      .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
      .trim()
      .toLowerCase();
}

String _normalize(String value) {
  var normalized = value
      .replaceAll('\u00A0', ' ')
      .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
      .toLowerCase()
      .trim();

  const replacements = <String, String>{
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };

  for (final entry in replacements.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }

  normalized = normalized.replaceAll(
    RegExp(r'[\[\](){}:_\-./|,+]+'),
    ' ',
  );
  normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

  return normalized;
}

class _DisjointSet {
  _DisjointSet(int length)
      : _parent = List<int>.generate(length, (index) => index),
        _rank = List<int>.filled(length, 0);

  final List<int> _parent;
  final List<int> _rank;

  int find(int value) {
    final parent = _parent[value];

    if (parent == value) {
      return value;
    }

    _parent[value] = find(parent);
    return _parent[value];
  }

  void union(int first, int second) {
    final firstRoot = find(first);
    final secondRoot = find(second);

    if (firstRoot == secondRoot) {
      return;
    }

    if (_rank[firstRoot] < _rank[secondRoot]) {
      _parent[firstRoot] = secondRoot;
      return;
    }

    if (_rank[firstRoot] > _rank[secondRoot]) {
      _parent[secondRoot] = firstRoot;
      return;
    }

    _parent[secondRoot] = firstRoot;
    _rank[firstRoot]++;
  }
}
