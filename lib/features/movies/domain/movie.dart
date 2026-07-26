class Movie {
  const Movie({
    required this.streamId,
    required this.name,
    required this.posterUrl,
    required this.categoryId,
    required this.containerExtension,
    required this.rating,
    required this.year,
    required this.plot,
    required this.duration,
    required this.genre,
    required this.director,
    required this.cast,
    required this.releaseDate,
    required this.backdropUrl,
    required this.directSource,
  });

  final int streamId;
  final String name;
  final String posterUrl;
  final String categoryId;
  final String containerExtension;
  final String rating;
  final String year;
  final String plot;
  final String duration;
  final String genre;
  final String director;
  final String cast;
  final String releaseDate;
  final String backdropUrl;
  final String directSource;

  factory Movie.fromJson(Map<String, dynamic> json) {
    final releaseDate = _firstText([
      json['releaseDate'],
      json['release_date'],
    ]);

    return Movie(
      streamId: _toInt(json['stream_id']),
      name: _firstText([
        json['name'],
        json['title'],
      ]),
      posterUrl: _firstImage([
        json['stream_icon'],
        json['movie_image'],
        json['cover_big'],
        json['cover'],
      ]),
      categoryId: _text(json['category_id']),
      containerExtension: _normalizeExtension(
        _firstText([
          json['container_extension'],
          json['extension'],
        ]),
      ),
      rating: _firstText([
        json['rating'],
        json['rating_5based'],
      ]),
      year: _firstText([
        json['year'],
        _extractYear(releaseDate),
      ]),
      plot: _firstText([
        json['plot'],
        json['description'],
        json['overview'],
      ]),
      duration: _durationText(
        _firstValue([
          json['duration'],
          json['duration_secs'],
        ]),
      ),
      genre: _text(json['genre']),
      director: _text(json['director']),
      cast: _text(json['cast']),
      releaseDate: releaseDate,
      backdropUrl: _firstImage([
        json['backdrop_path'],
        json['backdrop'],
      ]),
      directSource: _text(json['direct_source']),
    );
  }

  factory Movie.fromVodInfo(
    Map<String, dynamic> response, {
    required Movie fallback,
  }) {
    final info = _map(response['info']);
    final movieData = _map(response['movie_data']);

    Object? pick(List<String> keys) {
      for (final key in keys) {
        final infoValue = info[key];

        if (_hasValue(infoValue)) {
          return infoValue;
        }

        final movieValue = movieData[key];

        if (_hasValue(movieValue)) {
          return movieValue;
        }
      }

      return null;
    }

    final releaseDate = _firstText([
      pick(['releaseDate', 'release_date']),
      fallback.releaseDate,
    ]);

    return Movie(
      streamId: _toInt(
        _firstValue([
          pick(['stream_id', 'vod_id']),
          fallback.streamId,
        ]),
      ),
      name: _firstText([
        pick(['name', 'title']),
        fallback.name,
      ]),
      posterUrl: _firstImage([
        pick([
          'movie_image',
          'cover_big',
          'stream_icon',
          'cover',
        ]),
        fallback.posterUrl,
      ]),
      categoryId: _firstText([
        pick(['category_id']),
        fallback.categoryId,
      ]),
      containerExtension: _normalizeExtension(
        _firstText([
          pick(['container_extension', 'extension']),
          fallback.containerExtension,
        ]),
      ),
      rating: _firstText([
        pick(['rating', 'rating_5based']),
        fallback.rating,
      ]),
      year: _firstText([
        pick(['year']),
        _extractYear(releaseDate),
        fallback.year,
      ]),
      plot: _firstText([
        pick(['plot', 'description', 'overview']),
        fallback.plot,
      ]),
      duration: _firstText([
        _durationText(
          pick(['duration', 'duration_secs']),
        ),
        fallback.duration,
      ]),
      genre: _firstText([
        pick(['genre']),
        fallback.genre,
      ]),
      director: _firstText([
        pick(['director']),
        fallback.director,
      ]),
      cast: _firstText([
        pick(['cast', 'actors']),
        fallback.cast,
      ]),
      releaseDate: releaseDate,
      backdropUrl: _firstImage([
        pick(['backdrop_path', 'backdrop']),
        fallback.backdropUrl,
        fallback.posterUrl,
      ]),
      directSource: _firstText([
        pick(['direct_source']),
        fallback.directSource,
      ]),
    );
  }

  String get safeExtension {
    final value = _normalizeExtension(containerExtension);

    return value.isEmpty ? 'mp4' : value;
  }

  String get displayYear {
    if (year.isNotEmpty) {
      return year;
    }

    return _extractYear(releaseDate);
  }

  String get displayRating {
    if (rating.isEmpty) {
      return '';
    }

    final numeric = double.tryParse(rating);

    if (numeric == null) {
      return rating;
    }

    return numeric.toStringAsFixed(
      numeric == numeric.roundToDouble() ? 0 : 1,
    );
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }

  return const <String, dynamic>{};
}

bool _hasValue(Object? value) {
  if (value == null) {
    return false;
  }

  if (value is String) {
    return value.trim().isNotEmpty &&
        value.trim().toLowerCase() != 'null';
  }

  if (value is Iterable) {
    return value.isNotEmpty;
  }

  return true;
}

Object? _firstValue(List<Object?> values) {
  for (final value in values) {
    if (_hasValue(value)) {
      return value;
    }
  }

  return null;
}

String _firstText(List<Object?> values) {
  return _text(_firstValue(values));
}

String _text(Object? value) {
  if (!_hasValue(value)) {
    return '';
  }

  if (value is Iterable) {
    return value
        .where(_hasValue)
        .map(_text)
        .where((item) => item.isNotEmpty)
        .join(', ');
  }

  return value.toString().trim();
}

int _toInt(Object? value) {
  if (value is int) {
    return value;
  }

  return int.tryParse(_text(value)) ?? 0;
}

String _firstImage(List<Object?> values) {
  for (final value in values) {
    if (value is Iterable) {
      for (final item in value) {
        final image = _text(item);

        if (image.isNotEmpty) {
          return image;
        }
      }

      continue;
    }

    final image = _text(value);

    if (image.isNotEmpty) {
      return image;
    }
  }

  return '';
}

String _normalizeExtension(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'^\.'), '')
      .split('?')
      .first;
}

String _extractYear(String value) {
  final match = RegExp(r'(19|20)\d{2}').firstMatch(value);

  return match?.group(0) ?? '';
}

String _durationText(Object? value) {
  final text = _text(value);

  if (text.isEmpty) {
    return '';
  }

  if (text.contains(':')) {
    return text;
  }

  final seconds = int.tryParse(text);

  if (seconds == null || seconds <= 0) {
    return text;
  }

  final duration = Duration(seconds: seconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);

  if (hours > 0) {
    return '${hours}h ${minutes}min';
  }

  return '${minutes}min';
}
