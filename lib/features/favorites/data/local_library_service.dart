import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/domain/auth_session.dart';
import '../../live_tv/domain/live_channel.dart';
import '../../live_tv/domain/live_channel_group.dart';
import '../../movies/domain/movie.dart';
import '../../series/domain/tv_series.dart';

class LocalLibrarySnapshot {
  const LocalLibrarySnapshot({
    required this.favorites,
    required this.progress,
  });

  final List<FavoriteEntry> favorites;
  final List<WatchProgressEntry> progress;
}

class FavoriteEntry {
  const FavoriteEntry({
    required this.type,
    required this.updatedAt,
    this.movie,
    this.series,
    this.channel,
    this.channelVariants = const [],
  });

  final String type;
  final int updatedAt;
  final Movie? movie;
  final TvSeries? series;
  final LiveChannel? channel;
  final List<LiveChannel> channelVariants;

  String get key {
    if (movie != null) {
      return 'movie:${movie!.streamId}';
    }

    if (series != null) {
      return 'series:${series!.seriesId}';
    }

    return 'channel:${channel?.streamId ?? 0}';
  }

  String get title {
    return movie?.name ??
        series?.name ??
        (channel == null ? '' : liveChannelBaseName(channel!.name));
  }

  String get imageUrl {
    return movie?.posterUrl ??
        series?.coverUrl ??
        channel?.iconUrl ??
        '';
  }

  String get subtitle {
    switch (type) {
      case 'movie':
        return 'Película';
      case 'series':
        return 'Serie';
      case 'channel':
        return 'Canal en vivo';
      default:
        return '';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'updated_at': updatedAt,
      if (movie != null) 'movie': _movieToJson(movie!),
      if (series != null) 'series': _seriesToJson(series!),
      if (channel != null) 'channel': _channelToJson(channel!),
      if (channelVariants.isNotEmpty)
        'channel_variants': channelVariants.map(_channelToJson).toList(),
    };
  }

  factory FavoriteEntry.fromJson(Map<String, dynamic> json) {
    final type = _text(json['type']);

    return FavoriteEntry(
      type: type,
      updatedAt: _toInt(json['updated_at']),
      movie: type == 'movie'
          ? _movieFromJson(_map(json['movie']))
          : null,
      series: type == 'series'
          ? _seriesFromJson(_map(json['series']))
          : null,
      channel: type == 'channel'
          ? _channelFromJson(_map(json['channel']))
          : null,
      channelVariants: type == 'channel'
          ? _channelList(json['channel_variants'])
          : const [],
    );
  }
}

class WatchProgressEntry {
  const WatchProgressEntry({
    required this.type,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
    this.movie,
    this.series,
    this.episode,
    this.seasonName = '',
    this.episodes = const [],
    this.currentIndex = 0,
  });

  final String type;
  final int positionMs;
  final int durationMs;
  final int updatedAt;
  final Movie? movie;
  final TvSeries? series;
  final SeriesEpisode? episode;
  final String seasonName;
  final List<SeriesEpisode> episodes;
  final int currentIndex;

  String get key {
    if (movie != null) {
      return 'movie:${movie!.streamId}';
    }

    return 'episode:${episode?.episodeId ?? 0}';
  }

  String get title {
    if (movie != null) {
      return movie!.name;
    }

    return series?.name ?? episode?.displayTitle ?? '';
  }

  String get subtitle {
    if (movie != null) {
      return 'Película';
    }

    final currentEpisode = episode;

    if (currentEpisode == null) {
      return seasonName;
    }

    final episodeLabel = currentEpisode.episodeNumber > 0
        ? 'Episodio ${currentEpisode.episodeNumber}'
        : currentEpisode.displayTitle;

    if (seasonName.isEmpty) {
      return episodeLabel;
    }

    return '$seasonName • $episodeLabel';
  }

  String get imageUrl {
    if (movie != null) {
      return movie!.posterUrl;
    }

    if (episode?.imageUrl.isNotEmpty == true) {
      return episode!.imageUrl;
    }

    return series?.coverUrl ?? '';
  }

  double get progress {
    if (durationMs <= 0) {
      return 0;
    }

    return (positionMs / durationMs).clamp(0.0, 1.0).toDouble();
  }

  Duration get position => Duration(milliseconds: positionMs);

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'position_ms': positionMs,
      'duration_ms': durationMs,
      'updated_at': updatedAt,
      'season_name': seasonName,
      'current_index': currentIndex,
      if (movie != null) 'movie': _movieToJson(movie!),
      if (series != null) 'series': _seriesToJson(series!),
      if (episode != null) 'episode': _episodeToJson(episode!),
      if (episodes.isNotEmpty)
        'episodes': episodes.map(_episodeToJson).toList(),
    };
  }

  factory WatchProgressEntry.fromJson(Map<String, dynamic> json) {
    final type = _text(json['type']);
    final rawEpisodes = json['episodes'];
    final episodes = <SeriesEpisode>[];

    if (rawEpisodes is List) {
      for (final item in rawEpisodes.whereType<Map>()) {
        episodes.add(
          _episodeFromJson(Map<String, dynamic>.from(item)),
        );
      }
    }

    return WatchProgressEntry(
      type: type,
      positionMs: _toInt(json['position_ms']),
      durationMs: _toInt(json['duration_ms']),
      updatedAt: _toInt(json['updated_at']),
      movie: type == 'movie' ? _movieFromJson(_map(json['movie'])) : null,
      series: type == 'episode' ? _seriesFromJson(_map(json['series'])) : null,
      episode: type == 'episode' ? _episodeFromJson(_map(json['episode'])) : null,
      seasonName: _text(json['season_name']),
      episodes: episodes,
      currentIndex: _toInt(json['current_index']),
    );
  }
}

class LocalLibraryService {
  LocalLibraryService._();

  static final LocalLibraryService instance = LocalLibraryService._();

  static const int _maxProgressItems = 30;
  static const Duration _minimumProgress = Duration(seconds: 15);
  static const Duration _finishedThreshold = Duration(seconds: 45);

  Future<LocalLibrarySnapshot> load(AuthSession session) async {
    final data = await _read(session);
    final favorites = _favoriteList(data)..sort(_sortNewestFavorite);
    final progress = _progressList(data)..sort(_sortNewestProgress);

    return LocalLibrarySnapshot(
      favorites: favorites,
      progress: progress,
    );
  }

  Future<bool> isMovieFavorite(
    AuthSession session,
    int streamId,
  ) async {
    final snapshot = await load(session);

    return snapshot.favorites.any(
      (item) => item.movie?.streamId == streamId,
    );
  }

  Future<bool> isSeriesFavorite(
    AuthSession session,
    int seriesId,
  ) async {
    final snapshot = await load(session);

    return snapshot.favorites.any(
      (item) => item.series?.seriesId == seriesId,
    );
  }

  Future<bool> isChannelFavorite(
    AuthSession session,
    int streamId,
  ) async {
    final snapshot = await load(session);

    return snapshot.favorites.any((item) {
      if (item.channel?.streamId == streamId) {
        return true;
      }

      return item.channelVariants.any(
        (variant) => variant.streamId == streamId,
      );
    });
  }

  Future<bool> toggleMovieFavorite(
    AuthSession session,
    Movie movie,
  ) async {
    final data = await _read(session);
    final favorites = _favoriteList(data);
    final key = 'movie:${movie.streamId}';
    final alreadyFavorite = favorites.any((item) => item.key == key);

    favorites.removeWhere((item) => item.key == key);

    if (!alreadyFavorite) {
      favorites.add(
        FavoriteEntry(
          type: 'movie',
          movie: movie,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    data['favorites'] = favorites.map((item) => item.toJson()).toList();
    await _write(session, data);

    return !alreadyFavorite;
  }

  Future<bool> toggleSeriesFavorite(
    AuthSession session,
    TvSeries series,
  ) async {
    final data = await _read(session);
    final favorites = _favoriteList(data);
    final key = 'series:${series.seriesId}';
    final alreadyFavorite = favorites.any((item) => item.key == key);

    favorites.removeWhere((item) => item.key == key);

    if (!alreadyFavorite) {
      favorites.add(
        FavoriteEntry(
          type: 'series',
          series: series,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    data['favorites'] = favorites.map((item) => item.toJson()).toList();
    await _write(session, data);

    return !alreadyFavorite;
  }

  Future<bool> toggleChannelFavorite(
    AuthSession session,
    LiveChannel channel,
  ) {
    return toggleChannelFavoriteGroup(
      session,
      channel: channel,
      variants: [channel],
    );
  }

  Future<bool> toggleChannelFavoriteGroup(
    AuthSession session, {
    required LiveChannel channel,
    required List<LiveChannel> variants,
  }) async {
    final data = await _read(session);
    final favorites = _favoriteList(data);
    final safeVariants = variants.isEmpty ? [channel] : variants;
    final groupIds = safeVariants
        .map((item) => item.streamId)
        .toSet()
      ..add(channel.streamId);

    final alreadyFavorite = favorites.any((item) {
      final savedChannel = item.channel;

      if (savedChannel != null && groupIds.contains(savedChannel.streamId)) {
        return true;
      }

      return item.channelVariants.any(
        (variant) => groupIds.contains(variant.streamId),
      );
    });

    favorites.removeWhere((item) {
      final savedChannel = item.channel;

      if (savedChannel != null && groupIds.contains(savedChannel.streamId)) {
        return true;
      }

      return item.channelVariants.any(
        (variant) => groupIds.contains(variant.streamId),
      );
    });

    if (!alreadyFavorite) {
      favorites.add(
        FavoriteEntry(
          type: 'channel',
          channel: channel,
          channelVariants: List<LiveChannel>.unmodifiable(safeVariants),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    data['favorites'] = favorites.map((item) => item.toJson()).toList();
    await _write(session, data);

    return !alreadyFavorite;
  }

  Future<WatchProgressEntry?> movieProgress(
    AuthSession session,
    int streamId,
  ) async {
    final snapshot = await load(session);

    for (final item in snapshot.progress) {
      if (item.movie?.streamId == streamId) {
        return item;
      }
    }

    return null;
  }

  Future<WatchProgressEntry?> episodeProgress(
    AuthSession session,
    int episodeId,
  ) async {
    final snapshot = await load(session);

    for (final item in snapshot.progress) {
      if (item.episode?.episodeId == episodeId) {
        return item;
      }
    }

    return null;
  }

  Future<void> saveMovieProgress({
    required AuthSession session,
    required Movie movie,
    required Duration position,
    required Duration duration,
  }) async {
    final key = 'movie:${movie.streamId}';

    await _saveProgress(
      session: session,
      key: key,
      position: position,
      duration: duration,
      entryBuilder: () {
        return WatchProgressEntry(
          type: 'movie',
          movie: movie,
          positionMs: position.inMilliseconds,
          durationMs: duration.inMilliseconds,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      },
    );
  }

  Future<void> saveEpisodeProgress({
    required AuthSession session,
    required TvSeries series,
    required String seasonName,
    required List<SeriesEpisode> episodes,
    required int currentIndex,
    required Duration position,
    required Duration duration,
  }) async {
    if (episodes.isEmpty ||
        currentIndex < 0 ||
        currentIndex >= episodes.length) {
      return;
    }

    final episode = episodes[currentIndex];
    final key = 'episode:${episode.episodeId}';

    await _saveProgress(
      session: session,
      key: key,
      position: position,
      duration: duration,
      replaceWhere: (item) =>
          item.series?.seriesId == series.seriesId,
      entryBuilder: () {
        return WatchProgressEntry(
          type: 'episode',
          series: series,
          episode: episode,
          seasonName: seasonName,
          episodes: episodes,
          currentIndex: currentIndex,
          positionMs: position.inMilliseconds,
          durationMs: duration.inMilliseconds,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
      },
    );
  }

  Future<void> removeMovieProgress(
    AuthSession session,
    int streamId,
  ) {
    return _removeProgress(session, 'movie:$streamId');
  }

  Future<void> removeEpisodeProgress(
    AuthSession session,
    int episodeId,
  ) {
    return _removeProgress(session, 'episode:$episodeId');
  }

  Future<void> clearProgress(AuthSession session) async {
    final data = await _read(session);
    data['progress'] = <Object?>[];
    await _write(session, data);
  }

  Future<void> clearFavorites(AuthSession session) async {
    final data = await _read(session);
    data['favorites'] = <Object?>[];
    await _write(session, data);
  }

  Future<void> clearAll(AuthSession session) async {
    await _write(
      session,
      <String, dynamic>{
        'favorites': <Object?>[],
        'progress': <Object?>[],
      },
    );
  }

  Future<void> _saveProgress({
    required AuthSession session,
    required String key,
    required Duration position,
    required Duration duration,
    required WatchProgressEntry Function() entryBuilder,
    bool Function(WatchProgressEntry item)? replaceWhere,
  }) async {
    final data = await _read(session);
    final progress = _progressList(data)
      ..removeWhere(
        (item) =>
            item.key == key ||
            (replaceWhere != null && replaceWhere(item)),
      );

    final validDuration = duration > Duration.zero;
    final nearlyFinished = validDuration &&
        duration - position <= _finishedThreshold;
    final completedPercentage = validDuration &&
        position.inMilliseconds / duration.inMilliseconds >= 0.95;

    if (position >= _minimumProgress &&
        validDuration &&
        !nearlyFinished &&
        !completedPercentage) {
      progress.add(entryBuilder());
    }

    progress.sort(_sortNewestProgress);

    data['progress'] = progress
        .take(_maxProgressItems)
        .map((item) => item.toJson())
        .toList();

    await _write(session, data);
  }

  Future<void> _removeProgress(
    AuthSession session,
    String key,
  ) async {
    final data = await _read(session);
    final progress = _progressList(data)
      ..removeWhere((item) => item.key == key);

    data['progress'] = progress.map((item) => item.toJson()).toList();
    await _write(session, data);
  }

  Future<Map<String, dynamic>> _read(AuthSession session) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey(session));

    if (raw == null || raw.trim().isEmpty) {
      return <String, dynamic>{
        'favorites': <Object?>[],
        'progress': <Object?>[],
      };
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Si el almacenamiento quedó corrupto, se recrea limpio.
    }

    return <String, dynamic>{
      'favorites': <Object?>[],
      'progress': <Object?>[],
    };
  }

  Future<void> _write(
    AuthSession session,
    Map<String, dynamic> data,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey(session),
      jsonEncode(data),
    );
  }

  String _storageKey(AuthSession session) {
    final encodedUser = base64Url.encode(
      utf8.encode(session.username.trim().toLowerCase()),
    );

    return 'fdezplay.local_library.$encodedUser';
  }

  List<FavoriteEntry> _favoriteList(Map<String, dynamic> data) {
    final raw = data['favorites'];

    if (raw is! List) {
      return <FavoriteEntry>[];
    }

    final items = <FavoriteEntry>[];

    for (final item in raw.whereType<Map>()) {
      try {
        final favorite = FavoriteEntry.fromJson(
          Map<String, dynamic>.from(item),
        );

        if (favorite.title.isNotEmpty) {
          items.add(favorite);
        }
      } catch (_) {
        // Se omite únicamente el elemento inválido.
      }
    }

    return _mergeChannelFavorites(items);
  }

  List<FavoriteEntry> _mergeChannelFavorites(
    List<FavoriteEntry> items,
  ) {
    final nonChannelFavorites = items
        .where((item) => item.channel == null)
        .toList(growable: true);
    final channelFavorites = items
        .where((item) => item.channel != null)
        .toList(growable: false);

    if (channelFavorites.isEmpty) {
      return items;
    }

    final allChannels = <LiveChannel>[];
    final updatedAtByStreamId = <int, int>{};

    for (final favorite in channelFavorites) {
      final channels = <LiveChannel>[
        if (favorite.channel != null) favorite.channel!,
        ...favorite.channelVariants,
      ];

      for (final channel in channels) {
        if (!allChannels.any((item) => item.streamId == channel.streamId)) {
          allChannels.add(channel);
        }

        final previousUpdatedAt = updatedAtByStreamId[channel.streamId] ?? 0;

        if (favorite.updatedAt > previousUpdatedAt) {
          updatedAtByStreamId[channel.streamId] = favorite.updatedAt;
        }
      }
    }

    for (final group in groupLiveChannels(allChannels)) {
      final variants = group.variants
          .map((variant) => variant.channel)
          .toList(growable: false);
      var updatedAt = 0;

      for (final variant in variants) {
        final variantUpdatedAt = updatedAtByStreamId[variant.streamId] ?? 0;

        if (variantUpdatedAt > updatedAt) {
          updatedAt = variantUpdatedAt;
        }
      }

      nonChannelFavorites.add(
        FavoriteEntry(
          type: 'channel',
          channel: group.representative,
          channelVariants: variants,
          updatedAt: updatedAt,
        ),
      );
    }

    return nonChannelFavorites;
  }

  List<WatchProgressEntry> _progressList(Map<String, dynamic> data) {
    final raw = data['progress'];

    if (raw is! List) {
      return <WatchProgressEntry>[];
    }

    final items = <WatchProgressEntry>[];

    for (final item in raw.whereType<Map>()) {
      try {
        final progress = WatchProgressEntry.fromJson(
          Map<String, dynamic>.from(item),
        );

        if (progress.title.isNotEmpty && progress.durationMs > 0) {
          items.add(progress);
        }
      } catch (_) {
        // Se omite únicamente el elemento inválido.
      }
    }

    return items;
  }

  static int _sortNewestFavorite(
    FavoriteEntry a,
    FavoriteEntry b,
  ) {
    return b.updatedAt.compareTo(a.updatedAt);
  }

  static int _sortNewestProgress(
    WatchProgressEntry a,
    WatchProgressEntry b,
  ) {
    return b.updatedAt.compareTo(a.updatedAt);
  }
}


List<LiveChannel> _channelList(Object? raw) {
  if (raw is! List) {
    return const [];
  }

  final channels = <LiveChannel>[];

  for (final item in raw.whereType<Map>()) {
    try {
      channels.add(
        _channelFromJson(Map<String, dynamic>.from(item)),
      );
    } catch (_) {
      // Se omite únicamente la variante inválida.
    }
  }

  return channels;
}

Map<String, dynamic> _channelToJson(LiveChannel channel) {
  return {
    'stream_id': channel.streamId,
    'name': channel.name,
    'icon_url': channel.iconUrl,
    'category_id': channel.categoryId,
    'epg_channel_id': channel.epgChannelId,
    'order': channel.order,
    'has_archive': channel.hasArchive,
    'archive_duration': channel.archiveDuration,
  };
}

LiveChannel _channelFromJson(Map<String, dynamic> json) {
  return LiveChannel(
    streamId: _toInt(json['stream_id']),
    name: _text(json['name']),
    iconUrl: _text(json['icon_url']),
    categoryId: _text(json['category_id']),
    epgChannelId: _text(json['epg_channel_id']),
    order: _toInt(json['order']),
    hasArchive: json['has_archive'] == true ||
        _text(json['has_archive']) == '1',
    archiveDuration: _toInt(json['archive_duration']),
  );
}

Map<String, dynamic> _movieToJson(Movie movie) {
  return {
    'stream_id': movie.streamId,
    'name': movie.name,
    'poster_url': movie.posterUrl,
    'category_id': movie.categoryId,
    'container_extension': movie.containerExtension,
    'rating': movie.rating,
    'year': movie.year,
    'plot': movie.plot,
    'duration': movie.duration,
    'genre': movie.genre,
    'director': movie.director,
    'cast': movie.cast,
    'release_date': movie.releaseDate,
    'backdrop_url': movie.backdropUrl,
    'direct_source': movie.directSource,
  };
}

Movie _movieFromJson(Map<String, dynamic> json) {
  return Movie(
    streamId: _toInt(json['stream_id']),
    name: _text(json['name']),
    posterUrl: _text(json['poster_url']),
    categoryId: _text(json['category_id']),
    containerExtension: _text(json['container_extension']),
    rating: _text(json['rating']),
    year: _text(json['year']),
    plot: _text(json['plot']),
    duration: _text(json['duration']),
    genre: _text(json['genre']),
    director: _text(json['director']),
    cast: _text(json['cast']),
    releaseDate: _text(json['release_date']),
    backdropUrl: _text(json['backdrop_url']),
    directSource: _text(json['direct_source']),
  );
}

Map<String, dynamic> _seriesToJson(TvSeries series) {
  return {
    'series_id': series.seriesId,
    'name': series.name,
    'cover_url': series.coverUrl,
    'category_id': series.categoryId,
    'plot': series.plot,
    'cast': series.cast,
    'director': series.director,
    'genre': series.genre,
    'release_date': series.releaseDate,
    'rating': series.rating,
    'backdrop_url': series.backdropUrl,
    'youtube_trailer': series.youtubeTrailer,
    'episode_run_time': series.episodeRunTime,
  };
}

TvSeries _seriesFromJson(Map<String, dynamic> json) {
  return TvSeries(
    seriesId: _toInt(json['series_id']),
    name: _text(json['name']),
    coverUrl: _text(json['cover_url']),
    categoryId: _text(json['category_id']),
    plot: _text(json['plot']),
    cast: _text(json['cast']),
    director: _text(json['director']),
    genre: _text(json['genre']),
    releaseDate: _text(json['release_date']),
    rating: _text(json['rating']),
    backdropUrl: _text(json['backdrop_url']),
    youtubeTrailer: _text(json['youtube_trailer']),
    episodeRunTime: _text(json['episode_run_time']),
  );
}

Map<String, dynamic> _episodeToJson(SeriesEpisode episode) {
  return {
    'episode_id': episode.episodeId,
    'episode_number': episode.episodeNumber,
    'season_number': episode.seasonNumber,
    'title': episode.title,
    'container_extension': episode.containerExtension,
    'plot': episode.plot,
    'duration': episode.duration,
    'release_date': episode.releaseDate,
    'rating': episode.rating,
    'image_url': episode.imageUrl,
    'direct_source': episode.directSource,
  };
}

SeriesEpisode _episodeFromJson(Map<String, dynamic> json) {
  return SeriesEpisode(
    episodeId: _toInt(json['episode_id']),
    episodeNumber: _toInt(json['episode_number']),
    seasonNumber: _toInt(json['season_number']),
    title: _text(json['title']),
    containerExtension: _text(json['container_extension']),
    plot: _text(json['plot']),
    duration: _text(json['duration']),
    releaseDate: _text(json['release_date']),
    rating: _text(json['rating']),
    imageUrl: _text(json['image_url']),
    directSource: _text(json['direct_source']),
  );
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }

  return const <String, dynamic>{};
}

String _text(Object? value) {
  if (value == null) {
    return '';
  }

  return value.toString().trim();
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
