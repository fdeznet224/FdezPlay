class TvSeries {
  const TvSeries({
    required this.seriesId,
    required this.name,
    required this.coverUrl,
    required this.categoryId,
    required this.plot,
    required this.cast,
    required this.director,
    required this.genre,
    required this.releaseDate,
    required this.rating,
    required this.backdropUrl,
    required this.youtubeTrailer,
    required this.episodeRunTime,
  });

  final int seriesId;
  final String name;
  final String coverUrl;
  final String categoryId;
  final String plot;
  final String cast;
  final String director;
  final String genre;
  final String releaseDate;
  final String rating;
  final String backdropUrl;
  final String youtubeTrailer;
  final String episodeRunTime;

  factory TvSeries.fromJson(Map<String, dynamic> json) {
    return TvSeries(
      seriesId: _toInt(
        _firstValue([
          json['series_id'],
          json['id'],
        ]),
      ),
      name: _firstText([
        json['name'],
        json['title'],
      ]),
      coverUrl: _firstImage([
        json['cover'],
        json['cover_big'],
        json['stream_icon'],
        json['movie_image'],
      ]),
      categoryId: _text(json['category_id']),
      plot: _firstText([
        json['plot'],
        json['description'],
        json['overview'],
      ]),
      cast: _firstText([
        json['cast'],
        json['actors'],
      ]),
      director: _text(json['director']),
      genre: _text(json['genre']),
      releaseDate: _firstText([
        json['releaseDate'],
        json['release_date'],
      ]),
      rating: _firstText([
        json['rating'],
        json['rating_5based'],
      ]),
      backdropUrl: _firstImage([
        json['backdrop_path'],
        json['backdrop'],
      ]),
      youtubeTrailer: _firstText([
        json['youtube_trailer'],
        json['youtubeTrailer'],
      ]),
      episodeRunTime: _durationText(
        _firstValue([
          json['episode_run_time'],
          json['episodeRunTime'],
        ]),
      ),
    );
  }

  factory TvSeries.fromInfo(
    Map<String, dynamic> info, {
    required TvSeries fallback,
  }) {
    final releaseDate = _firstText([
      info['releaseDate'],
      info['release_date'],
      fallback.releaseDate,
    ]);

    return TvSeries(
      seriesId: _toInt(
        _firstValue([
          info['series_id'],
          info['id'],
          fallback.seriesId,
        ]),
      ),
      name: _firstText([
        info['name'],
        info['title'],
        fallback.name,
      ]),
      coverUrl: _firstImage([
        info['cover'],
        info['cover_big'],
        info['stream_icon'],
        fallback.coverUrl,
      ]),
      categoryId: _firstText([
        info['category_id'],
        fallback.categoryId,
      ]),
      plot: _firstText([
        info['plot'],
        info['description'],
        info['overview'],
        fallback.plot,
      ]),
      cast: _firstText([
        info['cast'],
        info['actors'],
        fallback.cast,
      ]),
      director: _firstText([
        info['director'],
        fallback.director,
      ]),
      genre: _firstText([
        info['genre'],
        fallback.genre,
      ]),
      releaseDate: releaseDate,
      rating: _firstText([
        info['rating'],
        info['rating_5based'],
        fallback.rating,
      ]),
      backdropUrl: _firstImage([
        info['backdrop_path'],
        info['backdrop'],
        fallback.backdropUrl,
        fallback.coverUrl,
      ]),
      youtubeTrailer: _firstText([
        info['youtube_trailer'],
        info['youtubeTrailer'],
        fallback.youtubeTrailer,
      ]),
      episodeRunTime: _firstText([
        _durationText(
          _firstValue([
            info['episode_run_time'],
            info['episodeRunTime'],
          ]),
        ),
        fallback.episodeRunTime,
      ]),
    );
  }

  String get displayYear {
    return _extractYear(releaseDate);
  }

  String get displayRating {
    if (rating.isEmpty) {
      return '';
    }

    final numeric = double.tryParse(rating.replaceAll(',', '.'));

    if (numeric == null) {
      return rating;
    }

    return numeric.toStringAsFixed(
      numeric == numeric.roundToDouble() ? 0 : 1,
    );
  }
}

class SeriesDetails {
  const SeriesDetails({
    required this.series,
    required this.seasons,
  });

  final TvSeries series;
  final List<SeriesSeason> seasons;

  factory SeriesDetails.fromResponse(
    Map<String, dynamic> response, {
    required TvSeries fallback,
  }) {
    final info = _map(response['info']);
    final updatedSeries = TvSeries.fromInfo(
      info,
      fallback: fallback,
    );

    final metadata = <int, _SeasonMetadata>{};
    final rawSeasons = response['seasons'];

    if (rawSeasons is List) {
      for (final item in rawSeasons.whereType<Map>()) {
        final data = Map<String, dynamic>.from(item);
        final seasonNumber = _toInt(
          _firstValue([
            data['season_number'],
            data['season'],
          ]),
        );

        metadata[seasonNumber] = _SeasonMetadata(
          name: _firstText([
            data['name'],
            data['title'],
          ]),
          coverUrl: _firstImage([
            data['cover'],
            data['cover_big'],
            data['poster_path'],
          ]),
        );
      }
    }

    final groupedEpisodes = <int, List<SeriesEpisode>>{};
    final rawEpisodes = response['episodes'];

    void addEpisode(
      Map<String, dynamic> json, {
      int? fallbackSeason,
    }) {
      final episode = SeriesEpisode.fromJson(
        json,
        fallbackSeason: fallbackSeason,
      );

      if (episode.episodeId <= 0) {
        return;
      }

      groupedEpisodes
          .putIfAbsent(episode.seasonNumber, () => <SeriesEpisode>[])
          .add(episode);
    }

    if (rawEpisodes is Map) {
      for (final entry in rawEpisodes.entries) {
        final seasonNumber = _toInt(entry.key);
        final value = entry.value;

        if (value is List) {
          for (final item in value.whereType<Map>()) {
            addEpisode(
              Map<String, dynamic>.from(item),
              fallbackSeason: seasonNumber,
            );
          }
        }
      }
    } else if (rawEpisodes is List) {
      for (final item in rawEpisodes.whereType<Map>()) {
        addEpisode(Map<String, dynamic>.from(item));
      }
    }

    final seasonNumbers = <int>{
      ...metadata.keys,
      ...groupedEpisodes.keys,
    }.toList()
      ..sort();

    final seasons = <SeriesSeason>[];

    for (final seasonNumber in seasonNumbers) {
      final episodes = List<SeriesEpisode>.from(
        groupedEpisodes[seasonNumber] ?? const <SeriesEpisode>[],
      )
        ..sort((a, b) {
          final byNumber = a.episodeNumber.compareTo(b.episodeNumber);

          if (byNumber != 0) {
            return byNumber;
          }

          return a.episodeId.compareTo(b.episodeId);
        });

      if (episodes.isEmpty) {
        continue;
      }

      final seasonMetadata = metadata[seasonNumber];
      final defaultName = seasonNumber == 0
          ? 'Especiales'
          : 'Temporada $seasonNumber';

      seasons.add(
        SeriesSeason(
          seasonNumber: seasonNumber,
          name: seasonMetadata?.name.isNotEmpty == true
              ? seasonMetadata!.name
              : defaultName,
          coverUrl: seasonMetadata?.coverUrl ?? '',
          episodes: episodes,
        ),
      );
    }

    return SeriesDetails(
      series: updatedSeries,
      seasons: seasons,
    );
  }

  int get episodeCount {
    return seasons.fold<int>(
      0,
      (total, season) => total + season.episodes.length,
    );
  }
}

class SeriesSeason {
  const SeriesSeason({
    required this.seasonNumber,
    required this.name,
    required this.coverUrl,
    required this.episodes,
  });

  final int seasonNumber;
  final String name;
  final String coverUrl;
  final List<SeriesEpisode> episodes;
}

class SeriesEpisode {
  const SeriesEpisode({
    required this.episodeId,
    required this.episodeNumber,
    required this.seasonNumber,
    required this.title,
    required this.containerExtension,
    required this.plot,
    required this.duration,
    required this.releaseDate,
    required this.rating,
    required this.imageUrl,
    required this.directSource,
  });

  final int episodeId;
  final int episodeNumber;
  final int seasonNumber;
  final String title;
  final String containerExtension;
  final String plot;
  final String duration;
  final String releaseDate;
  final String rating;
  final String imageUrl;
  final String directSource;

  factory SeriesEpisode.fromJson(
    Map<String, dynamic> json, {
    int? fallbackSeason,
  }) {
    final info = _map(json['info']);

    Object? pick(List<String> keys) {
      for (final key in keys) {
        final directValue = json[key];

        if (_hasValue(directValue)) {
          return directValue;
        }

        final infoValue = info[key];

        if (_hasValue(infoValue)) {
          return infoValue;
        }
      }

      return null;
    }

    final episodeNumber = _toInt(
      _firstValue([
        pick(['episode_num', 'episode_number']),
        0,
      ]),
    );

    final seasonNumber = _toInt(
      _firstValue([
        pick(['season', 'season_number']),
        fallbackSeason,
        0,
      ]),
    );

    return SeriesEpisode(
      episodeId: _toInt(
        _firstValue([
          pick(['id', 'stream_id', 'episode_id']),
          0,
        ]),
      ),
      episodeNumber: episodeNumber,
      seasonNumber: seasonNumber,
      title: _firstText([
        pick(['title', 'name']),
        episodeNumber > 0 ? 'Episodio $episodeNumber' : 'Episodio',
      ]),
      containerExtension: _normalizeExtension(
        _firstText([
          pick(['container_extension', 'extension']),
        ]),
      ),
      plot: _firstText([
        pick(['plot', 'description', 'overview']),
      ]),
      duration: _durationText(
        _firstValue([
          pick(['duration', 'duration_secs']),
        ]),
      ),
      releaseDate: _firstText([
        pick(['releaseDate', 'release_date', 'releasedate']),
      ]),
      rating: _firstText([
        pick(['rating', 'rating_5based']),
      ]),
      imageUrl: _firstImage([
        pick([
          'movie_image',
          'cover_big',
          'stream_icon',
          'cover',
        ]),
      ]),
      directSource: _firstText([
        pick(['direct_source']),
      ]),
    );
  }

  String get safeExtension {
    final value = _normalizeExtension(containerExtension);

    return value.isEmpty ? 'mp4' : value;
  }

  String get displayTitle {
    if (title.isNotEmpty) {
      return title;
    }

    return episodeNumber > 0 ? 'Episodio $episodeNumber' : 'Episodio';
  }

  String get displayRating {
    if (rating.isEmpty) {
      return '';
    }

    final numeric = double.tryParse(rating.replaceAll(',', '.'));

    if (numeric == null) {
      return rating;
    }

    return numeric.toStringAsFixed(
      numeric == numeric.roundToDouble() ? 0 : 1,
    );
  }
}

class _SeasonMetadata {
  const _SeasonMetadata({
    required this.name,
    required this.coverUrl,
  });

  final String name;
  final String coverUrl;
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
    final normalized = value.trim().toLowerCase();

    return normalized.isNotEmpty && normalized != 'null';
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

String _text(Object? value) {
  if (!_hasValue(value)) {
    return '';
  }

  return value.toString().trim();
}

String _firstText(List<Object?> values) {
  return _text(_firstValue(values));
}

int _toInt(Object? value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(_text(value)) ?? 0;
}

String _firstImage(List<Object?> values) {
  for (final value in values) {
    if (value is List) {
      for (final image in value) {
        final result = _text(image);

        if (_isHttpUrl(result)) {
          return result;
        }
      }

      continue;
    }

    final result = _text(value);

    if (_isHttpUrl(result)) {
      return result;
    }
  }

  return '';
}

bool _isHttpUrl(String value) {
  return value.startsWith('http://') || value.startsWith('https://');
}

String _normalizeExtension(String value) {
  return value.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');
}

String _extractYear(String value) {
  final match = RegExp(r'(19|20)\d{2}').firstMatch(value);

  return match?.group(0) ?? '';
}

String _durationText(Object? value) {
  if (!_hasValue(value)) {
    return '';
  }

  if (value is num) {
    return _formatSeconds(value.toInt());
  }

  final text = _text(value);
  final numeric = int.tryParse(text);

  if (numeric != null) {
    return _formatSeconds(numeric);
  }

  return text;
}

String _formatSeconds(int totalSeconds) {
  if (totalSeconds <= 0) {
    return '';
  }

  final duration = Duration(seconds: totalSeconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);

  if (hours > 0) {
    return '${hours}h ${minutes}min';
  }

  return '${duration.inMinutes} min';
}
