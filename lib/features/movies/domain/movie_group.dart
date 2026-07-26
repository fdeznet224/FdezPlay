import 'movie.dart';

class MovieGroup {
  const MovieGroup({
    required this.key,
    required this.displayTitle,
    required this.year,
    required this.variants,
  });

  final String key;
  final String displayTitle;
  final String year;
  final List<Movie> variants;

  Movie get primary => variants.first;

  int get versionCount => variants.length;

  bool matches(
    String query, {
    Map<String, String> categoryNames = const {},
  }) {
    final normalizedQuery = _normalizeText(query);

    if (normalizedQuery.isEmpty) {
      return true;
    }

    if (_normalizeText(displayTitle).contains(normalizedQuery) ||
        _normalizeText(year).contains(normalizedQuery)) {
      return true;
    }

    for (final movie in variants) {
      final category = categoryNames[movie.categoryId] ?? '';

      final searchable = [
        movie.name,
        movie.genre,
        movie.director,
        movie.cast,
        movie.plot,
        category,
        movie.displayYear,
      ].map(_normalizeText).join(' ');

      if (searchable.contains(normalizedQuery)) {
        return true;
      }
    }

    return false;
  }
}

List<MovieGroup> groupMovies(Iterable<Movie> movies) {
  final grouped = <String, List<Movie>>{};
  final displayTitles = <String, String>{};
  final years = <String, String>{};

  for (final movie in movies) {
    final year = _movieYear(movie);
    final cleanTitle = cleanMovieTitle(movie.name);
    final normalizedTitle = _normalizeText(cleanTitle);

    final fallbackTitle = normalizedTitle.isEmpty
        ? _normalizeText(movie.name)
        : normalizedTitle;

    final key = '$fallbackTitle|$year';

    grouped.putIfAbsent(key, () => <Movie>[]).add(movie);
    displayTitles.putIfAbsent(
      key,
      () => cleanTitle.isEmpty ? movie.name.trim() : cleanTitle,
    );
    years.putIfAbsent(key, () => year);
  }

  final result = <MovieGroup>[];

  for (final entry in grouped.entries) {
    final variants = List<Movie>.from(entry.value)
      ..sort(_compareMovieVariants);

    result.add(
      MovieGroup(
        key: entry.key,
        displayTitle: displayTitles[entry.key] ?? variants.first.name,
        year: years[entry.key] ?? '',
        variants: List<Movie>.unmodifiable(variants),
      ),
    );
  }

  return result;
}

String cleanMovieTitle(String value) {
  var title = value.trim();

  title = title.replaceAll(
    RegExp(
      r'[\[\(\{][^\]\)\}]*'
      r'(?:esp|español|castellano|latino|lat|eng|english|ingl[eé]s|'
      r'sub|subs|subtitulado|subtitulada|dual|multi|audio|'
      r'4k|uhd|fhd|hd|1080p|720p|2160p|hdr|bluray|blu-ray|'
      r'web[- ]?dl|webrip|x264|x265|h264|h265|hevc)'
      r'[^\]\)\}]*[\]\)\}]',
      caseSensitive: false,
    ),
    ' ',
  );

  title = title.replaceAll(
    RegExp(
      r'\b'
      r'(?:esp|español|castellano|latino|lat|eng|english|ingl[eé]s|'
      r'sub|subs|subtitulado|subtitulada|dual|multi(?:audio)?|'
      r'4k|uhd|fhd|hd|1080p|720p|2160p|hdr|bluray|blu-ray|'
      r'web[- ]?dl|webrip|x264|x265|h264|h265|hevc)'
      r'\b',
      caseSensitive: false,
    ),
    ' ',
  );

  title = title.replaceAll(
    RegExp(r'\b(?:19|20)\d{2}\b'),
    ' ',
  );

  title = title
      .replaceAll(RegExp(r'[_|]+'), ' ')
      .replaceAll(RegExp(r'\s*[-–—]\s*$'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  return title;
}

String movieVariantLabel(Movie movie) {
  final text = _normalizeText(movie.name);

  final labels = <String>[];

  if (_containsAny(text, const [
    'latino',
    'lat',
  ])) {
    labels.add('Español latino');
  } else if (_containsAny(text, const [
    'espanol',
    'castellano',
    'esp',
  ])) {
    labels.add('Español');
  }

  if (_containsAny(text, const [
    'english',
    'ingles',
    'eng',
  ])) {
    labels.add('Inglés');
  }

  if (_containsAny(text, const [
    'subtitulado',
    'subtitulada',
    'subs',
    'sub',
  ])) {
    labels.add('Subtitulada');
  }

  if (_containsAny(text, const ['dual'])) {
    labels.add('Audio dual');
  }

  if (_containsAny(text, const [
    'multiaudio',
    'multi audio',
    'multi',
  ])) {
    labels.add('Multi audio');
  }

  if (_containsAny(text, const [
    '2160p',
    'uhd',
    '4k',
  ])) {
    labels.add('4K');
  } else if (_containsAny(text, const [
    '1080p',
    'fhd',
  ])) {
    labels.add('Full HD');
  } else if (_containsAny(text, const [
    '720p',
    'hd',
  ])) {
    labels.add('HD');
  }

  if (labels.isEmpty) {
    final extension = movie.safeExtension.toUpperCase();

    if (extension.isNotEmpty) {
      labels.add(extension);
    } else {
      labels.add('Versión disponible');
    }
  }

  return labels.toSet().join(' • ');
}

int _compareMovieVariants(Movie a, Movie b) {
  final language = _variantPriority(a).compareTo(_variantPriority(b));

  if (language != 0) {
    return language;
  }

  final quality = _qualityPriority(a).compareTo(_qualityPriority(b));

  if (quality != 0) {
    return quality;
  }

  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

int _variantPriority(Movie movie) {
  final text = _normalizeText(movie.name);

  if (_containsAny(text, const [
    'latino',
    'lat',
    'espanol',
    'castellano',
    'esp',
  ])) {
    return 0;
  }

  if (_containsAny(text, const [
    'dual',
    'multiaudio',
    'multi audio',
    'multi',
  ])) {
    return 1;
  }

  if (_containsAny(text, const [
    'subtitulado',
    'subtitulada',
    'subs',
    'sub',
  ])) {
    return 2;
  }

  if (_containsAny(text, const [
    'english',
    'ingles',
    'eng',
  ])) {
    return 3;
  }

  return 4;
}

int _qualityPriority(Movie movie) {
  final text = _normalizeText(movie.name);

  if (_containsAny(text, const [
    '2160p',
    'uhd',
    '4k',
  ])) {
    return 0;
  }

  if (_containsAny(text, const [
    '1080p',
    'fhd',
  ])) {
    return 1;
  }

  if (_containsAny(text, const [
    '720p',
    'hd',
  ])) {
    return 2;
  }

  return 3;
}

String _movieYear(Movie movie) {
  final year = movie.displayYear.trim();

  if (RegExp(r'^(?:19|20)\d{2}$').hasMatch(year)) {
    return year;
  }

  final match = RegExp(r'\b(?:19|20)\d{2}\b').firstMatch(movie.name);

  return match?.group(0) ?? '';
}

bool _containsAny(String source, List<String> terms) {
  for (final term in terms) {
    final normalizedTerm = _normalizeText(term);

    final pattern =
        '(^|[^a-z0-9])${RegExp.escape(normalizedTerm)}'
        r'([^a-z0-9]|$)';

    if (RegExp(pattern).hasMatch(source)) {
      return true;
    }
  }

  return false;
}

String _normalizeText(String value) {
  var text = value.toLowerCase().trim();

  const replacements = <String, String>{
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ñ': 'n',
  };

  replacements.forEach((from, to) {
    text = text.replaceAll(from, to);
  });

  return text
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
