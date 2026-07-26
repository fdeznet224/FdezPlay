enum CategorySection {
  liveTv,
  movies,
  series,
}

class CategoryNameLocalizer {
  const CategoryNameLocalizer._();

  static String toSpanish(
    String rawName, {
    CategorySection section = CategorySection.movies,
  }) {
    final original = rawName.trim();

    if (original.isEmpty) {
      return 'Sin categoría';
    }

    final cleaned = _cleanup(original);
    final normalized = _normalize(cleaned);
    final special = _specialCategory(normalized, section);

    if (special != null) {
      return special;
    }

    final words = normalized
        .split(' ')
        .where((word) => word.trim().isNotEmpty)
        .toList(growable: false);

    final translated = <String>[];

    for (final word in words) {
      if (_ignoredWords.contains(word)) {
        continue;
      }

      translated.add(_wordTranslations[word] ?? _titleWord(word));
    }

    if (translated.isEmpty) {
      return cleaned.isEmpty ? original : _titleCase(cleaned);
    }

    final result = translated
        .join(' ')
        .replaceAll(RegExp(r'\bPelículas Películas\b'), 'Películas')
        .replaceAll(RegExp(r'\bSeries Series\b'), 'Series')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return result.isEmpty ? _titleCase(cleaned) : result;
  }

  static String _cleanup(String value) {
    var text = value
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
        .replaceAll(RegExp(r'[\[\](){}]'), ' ')
        .replaceAll(RegExp(r'[|_/\\]+'), ' ')
        .replaceAll(RegExp(r'\s*-\s*'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    text = text.replaceAll(
      RegExp(
        r'^(?:mx|mex|méxico|mexico|lat|latino|usa|us|uk|esp|es|en|vod|live|iptv|tv|canales?|channels?|movies?|pel[ií]culas?|series?)\s+',
        caseSensitive: false,
      ),
      '',
    );

    text = text.replaceAll(
      RegExp(
        r'\s+(?:hd|fhd|uhd|4k|1080p|720p|sd|hevc|h264|h265)$',
        caseSensitive: false,
      ),
      '',
    );

    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String? _specialCategory(
    String value,
    CategorySection section,
  ) {
    if (value.isEmpty) {
      return null;
    }

    final direct = _directTranslations[value];

    if (direct != null) {
      return direct;
    }

    if (RegExp(r'\bnew\s+release').hasMatch(value) ||
        RegExp(r'\bnew\s+releases').hasMatch(value) ||
        RegExp(r'\bpremiere').hasMatch(value)) {
      final genre = _genreFromText(value);

      if (genre != null) {
        return 'Estrenos de $genre';
      }

      return section == CategorySection.series
          ? 'Series de Estreno'
          : 'Estrenos';
    }

    if (RegExp(r'\bkids?\b|\bchildren\b|\bfamily\b').hasMatch(value)) {
      return 'Infantil y Familiar';
    }

    if (RegExp(r'\bsports?\b|\bfutbol\b|\bfootball\b|\bsoccer\b')
        .hasMatch(value)) {
      return 'Deportes';
    }

    if (RegExp(r'\bnews\b|\bnoticias\b').hasMatch(value)) {
      return 'Noticias';
    }

    if (RegExp(r'\bdocumentary\b|\bdocumentaries\b|\bdocumental').hasMatch(value)) {
      return 'Documentales';
    }

    if (RegExp(r'\b24\s*7\b|\b24/7\b').hasMatch(value)) {
      final genre = _genreFromText(value);
      return genre == null ? '24/7' : '24/7 $genre';
    }

    return null;
  }

  static String? _genreFromText(String value) {
    for (final entry in _genreTranslations.entries) {
      if (RegExp('\\b${entry.key}\\b').hasMatch(value)) {
        return entry.value;
      }
    }

    return null;
  }

  static String _normalize(String value) {
    var text = value.toLowerCase().trim();

    const accents = <String, String>{
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };

    accents.forEach((from, to) {
      text = text.replaceAll(from, to);
    });

    return text
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _titleWord(String value) {
    if (value.isEmpty) {
      return value;
    }

    return value.substring(0, 1).toUpperCase() + value.substring(1);
  }

  static String _titleCase(String value) {
    return value
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) => _titleWord(word.toLowerCase()))
        .join(' ');
  }

  static const Set<String> _ignoredWords = {
    'mx',
    'mex',
    'mexico',
    'lat',
    'latino',
    'usa',
    'us',
    'uk',
    'esp',
    'es',
    'en',
    'vod',
    'live',
    'iptv',
    'hd',
    'fhd',
    'uhd',
    '4k',
    '1080p',
    '720p',
    'sd',
  };

  static const Map<String, String> _directTranslations = {
    'action': 'Acción',
    'action movies': 'Películas de Acción',
    'adventure': 'Aventura',
    'animation': 'Animación',
    'anime': 'Anime',
    'comedy': 'Comedia',
    'crime': 'Crimen',
    'documentary': 'Documentales',
    'documentaries': 'Documentales',
    'drama': 'Drama',
    'family': 'Familiar',
    'fantasy': 'Fantasía',
    'horror': 'Terror',
    'kids': 'Infantil',
    'movies': 'Películas',
    'music': 'Música',
    'news': 'Noticias',
    'romance': 'Romance',
    'sci fi': 'Ciencia Ficción',
    'science fiction': 'Ciencia Ficción',
    'series': 'Series',
    'sports': 'Deportes',
    'thriller': 'Suspenso',
    'western': 'Western',
    'new release': 'Estrenos',
    'new releases': 'Estrenos',
    'new release action': 'Estrenos de Acción',
    'new release comedy': 'Estrenos de Comedia',
    'new release drama': 'Estrenos de Drama',
    'new release horror': 'Estrenos de Terror',
    'new release family': 'Estrenos Familiares',
    'new release romance': 'Estrenos de Romance',
    'new release thriller': 'Estrenos de Suspenso',
    'new release animation': 'Estrenos de Animación',
    'new release adventure': 'Estrenos de Aventura',
    'new release sci fi': 'Estrenos de Ciencia Ficción',
    'new release science fiction': 'Estrenos de Ciencia Ficción',
  };

  static const Map<String, String> _genreTranslations = {
    'action': 'Acción',
    'adventure': 'Aventura',
    'animation': 'Animación',
    'anime': 'Anime',
    'comedy': 'Comedia',
    'crime': 'Crimen',
    'documentary': 'Documentales',
    'documentaries': 'Documentales',
    'drama': 'Drama',
    'family': 'Familiares',
    'fantasy': 'Fantasía',
    'horror': 'Terror',
    'kids': 'Infantil',
    'music': 'Música',
    'romance': 'Romance',
    'sci': 'Ciencia Ficción',
    'scifi': 'Ciencia Ficción',
    'science': 'Ciencia Ficción',
    'thriller': 'Suspenso',
    'western': 'Western',
  };

  static const Map<String, String> _wordTranslations = {
    'action': 'Acción',
    'adventure': 'Aventura',
    'animation': 'Animación',
    'anime': 'Anime',
    'classic': 'Clásicas',
    'classics': 'Clásicas',
    'comedy': 'Comedia',
    'crime': 'Crimen',
    'documentary': 'Documentales',
    'documentaries': 'Documentales',
    'drama': 'Drama',
    'entertainment': 'Entretenimiento',
    'family': 'Familiar',
    'fantasy': 'Fantasía',
    'horror': 'Terror',
    'kids': 'Infantil',
    'movie': 'Película',
    'movies': 'Películas',
    'music': 'Música',
    'new': 'Nuevo',
    'news': 'Noticias',
    'premiere': 'Estreno',
    'premieres': 'Estrenos',
    'release': 'Estreno',
    'releases': 'Estrenos',
    'romance': 'Romance',
    'sci': 'Ciencia',
    'science': 'Ciencia',
    'fiction': 'Ficción',
    'series': 'Series',
    'shows': 'Programas',
    'sports': 'Deportes',
    'thriller': 'Suspenso',
    'tv': 'TV',
    'western': 'Western',
  };
}
