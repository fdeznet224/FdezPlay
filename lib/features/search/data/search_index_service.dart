import '../../auth/domain/auth_session.dart';
import '../../live_tv/data/live_tv_service.dart';
import '../../live_tv/domain/live_channel_group.dart';
import '../../movies/domain/movie.dart';
import '../../movies/domain/movie_group.dart';
import '../../series/domain/series_group.dart';
import '../../series/domain/tv_series.dart';
import '../../../shared/services/iptv_api_service.dart';

class IndexedLiveChannelGroup {
  const IndexedLiveChannelGroup({
    required this.group,
    required this.searchText,
  });

  final LiveChannelGroup group;
  final String searchText;
}

class IndexedMovieGroup {
  const IndexedMovieGroup({
    required this.group,
    required this.searchText,
  });

  final MovieGroup group;
  final String searchText;
}

class IndexedSeriesGroup {
  const IndexedSeriesGroup({
    required this.group,
    required this.searchText,
  });

  final SeriesGroup group;
  final String searchText;
}

class FdezSearchIndexService {
  FdezSearchIndexService._();

  static final FdezSearchIndexService instance = FdezSearchIndexService._();

  factory FdezSearchIndexService() => instance;

  final IptvApiService _apiService = IptvApiService();
  final LiveTvService _liveTvService = LiveTvService();

  String? _sessionKey;
  Future<void>? _prepareFuture;

  List<IndexedLiveChannelGroup>? _channelIndex;
  List<IndexedMovieGroup>? _movieIndex;
  List<IndexedSeriesGroup>? _seriesIndex;

  Future<List<IndexedLiveChannelGroup>>? _channelIndexFuture;
  Future<List<IndexedMovieGroup>>? _movieIndexFuture;
  Future<List<IndexedSeriesGroup>>? _seriesIndexFuture;

  static List<IndexedLiveChannelGroup> buildChannelIndex(
    Iterable<LiveChannelGroup> groups,
  ) {
    return groups
        .map(
          (group) => IndexedLiveChannelGroup(
            group: group,
            searchText: _channelSearchText(group),
          ),
        )
        .toList(growable: false);
  }

  static List<IndexedMovieGroup> buildMovieIndex(
    Iterable<Movie> movies, {
    Map<String, String> categoryNames = const {},
  }) {
    return groupMovies(movies)
        .map(
          (group) => IndexedMovieGroup(
            group: group,
            searchText: _movieSearchText(
              group,
              categoryNames: categoryNames,
            ),
          ),
        )
        .toList(growable: false);
  }

  static List<IndexedSeriesGroup> buildSeriesIndex(
    Iterable<TvSeries> series, {
    Map<String, String> categoryNames = const {},
  }) {
    return groupSeries(series)
        .map(
          (group) => IndexedSeriesGroup(
            group: group,
            searchText: _seriesSearchText(
              group,
              categoryNames: categoryNames,
            ),
          ),
        )
        .toList(growable: false);
  }

  static List<LiveChannelGroup> filterChannels(
    Iterable<IndexedLiveChannelGroup> index,
    String query, {
    int limit = 24,
  }) {
    final tokens = _queryTokens(query);

    if (tokens.isEmpty) {
      return const [];
    }

    final results = <LiveChannelGroup>[];

    for (final entry in index) {
      if (_matchesTokens(entry.searchText, tokens)) {
        results.add(entry.group);

        if (results.length >= limit) {
          break;
        }
      }
    }

    return results;
  }

  static List<MovieGroup> filterMovies(
    Iterable<IndexedMovieGroup> index,
    String query, {
    int limit = 40,
  }) {
    final tokens = _queryTokens(query);

    if (tokens.isEmpty) {
      return const [];
    }

    final results = <MovieGroup>[];

    for (final entry in index) {
      if (_matchesTokens(entry.searchText, tokens)) {
        results.add(entry.group);

        if (results.length >= limit) {
          break;
        }
      }
    }

    return results;
  }

  static List<SeriesGroup> filterSeries(
    Iterable<IndexedSeriesGroup> index,
    String query, {
    int limit = 40,
  }) {
    final tokens = _queryTokens(query);

    if (tokens.isEmpty) {
      return const [];
    }

    final results = <SeriesGroup>[];

    for (final entry in index) {
      if (_matchesTokens(entry.searchText, tokens)) {
        results.add(entry.group);

        if (results.length >= limit) {
          break;
        }
      }
    }

    return results;
  }

  List<LiveChannelGroup>? get cachedChannelGroups {
    final index = _channelIndex;
    if (index == null) {
      return null;
    }

    return index.map((entry) => entry.group).toList(growable: false);
  }

  List<MovieGroup>? get cachedMovieGroups {
    final index = _movieIndex;
    if (index == null) {
      return null;
    }

    return index.map((entry) => entry.group).toList(growable: false);
  }

  List<SeriesGroup>? get cachedSeriesGroups {
    final index = _seriesIndex;
    if (index == null) {
      return null;
    }

    return index.map((entry) => entry.group).toList(growable: false);
  }

  Future<void> prepare(AuthSession session) {
    _ensureSession(session);

    return _prepareFuture ??= _prepareSequential(session);
  }

  Future<void> _prepareSequential(AuthSession session) async {
    await ensureChannelIndex(session);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await ensureMovieIndex(session);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await ensureSeriesIndex(session);
  }

  Future<List<IndexedLiveChannelGroup>> ensureChannelIndex(
    AuthSession session,
  ) async {
    _ensureSession(session);

    final cached = _channelIndex;
    if (cached != null) {
      return cached;
    }

    final pending = _channelIndexFuture;
    if (pending != null) {
      return pending;
    }

    final future = _loadChannelIndex(session);
    _channelIndexFuture = future;
    return future;
  }

  Future<List<IndexedLiveChannelGroup>> _loadChannelIndex(
    AuthSession session,
  ) async {
    try {
      final channels = await _liveTvService.loadAllChannels(session: session);
      final groups = groupLiveChannels(channels);
      final index = buildChannelIndex(groups);
      _channelIndex = index;
      return index;
    } finally {
      _channelIndexFuture = null;
    }
  }

  Future<List<IndexedMovieGroup>> ensureMovieIndex(
    AuthSession session, {
    Map<String, String> categoryNames = const {},
  }) async {
    _ensureSession(session);

    final cached = _movieIndex;
    if (cached != null) {
      return cached;
    }

    final pending = _movieIndexFuture;
    if (pending != null) {
      return pending;
    }

    final future = _loadMovieIndex(
      session,
      categoryNames: categoryNames,
    );
    _movieIndexFuture = future;
    return future;
  }

  Future<List<IndexedMovieGroup>> _loadMovieIndex(
    AuthSession session, {
    Map<String, String> categoryNames = const {},
  }) async {
    try {
      final movies = await _apiService.loadMovies(session);
      final index = buildMovieIndex(
        movies,
        categoryNames: categoryNames,
      );
      _movieIndex = index;
      return index;
    } finally {
      _movieIndexFuture = null;
    }
  }

  Future<List<IndexedSeriesGroup>> ensureSeriesIndex(
    AuthSession session, {
    Map<String, String> categoryNames = const {},
  }) async {
    _ensureSession(session);

    final cached = _seriesIndex;
    if (cached != null) {
      return cached;
    }

    final pending = _seriesIndexFuture;
    if (pending != null) {
      return pending;
    }

    final future = _loadSeriesIndex(
      session,
      categoryNames: categoryNames,
    );
    _seriesIndexFuture = future;
    return future;
  }

  Future<List<IndexedSeriesGroup>> _loadSeriesIndex(
    AuthSession session, {
    Map<String, String> categoryNames = const {},
  }) async {
    try {
      final series = await _apiService.loadSeries(session);
      final index = buildSeriesIndex(
        series,
        categoryNames: categoryNames,
      );
      _seriesIndex = index;
      return index;
    } finally {
      _seriesIndexFuture = null;
    }
  }

  Future<List<LiveChannelGroup>> searchChannels(
    AuthSession session,
    String query, {
    int limit = 24,
  }) async {
    final index = await ensureChannelIndex(session);
    return filterChannels(index, query, limit: limit);
  }

  Future<List<MovieGroup>> searchMovies(
    AuthSession session,
    String query, {
    int limit = 40,
  }) async {
    final index = await ensureMovieIndex(session);
    return filterMovies(index, query, limit: limit);
  }

  Future<List<SeriesGroup>> searchSeries(
    AuthSession session,
    String query, {
    int limit = 40,
  }) async {
    final index = await ensureSeriesIndex(session);
    return filterSeries(index, query, limit: limit);
  }

  void _ensureSession(AuthSession session) {
    final key = '${session.server}|${session.username}';

    if (_sessionKey == key) {
      return;
    }

    _sessionKey = key;
    _prepareFuture = null;
    _channelIndex = null;
    _movieIndex = null;
    _seriesIndex = null;
    _channelIndexFuture = null;
    _movieIndexFuture = null;
    _seriesIndexFuture = null;
  }

  static String _channelSearchText(LiveChannelGroup group) {
    return _normalize(
      <String>[
        group.displayName,
        group.categoryId,
        for (final variant in group.variants) ...[
          variant.channel.name,
          variant.channel.epgChannelId,
          variant.qualityLabel,
          ...variant.labels,
        ],
      ].join(' '),
    );
  }

  static String _movieSearchText(
    MovieGroup group, {
    Map<String, String> categoryNames = const {},
  }) {
    return _normalize(
      <String>[
        group.displayTitle,
        group.year,
        for (final movie in group.variants) ...[
          movie.name,
          movie.displayYear,
          movie.genre,
          movie.containerExtension,
          categoryNames[movie.categoryId] ?? '',
        ],
      ].join(' '),
    );
  }

  static String _seriesSearchText(
    SeriesGroup group, {
    Map<String, String> categoryNames = const {},
  }) {
    return _normalize(
      <String>[
        group.displayTitle,
        group.year,
        for (final series in group.variants) ...[
          series.name,
          series.displayYear,
          series.genre,
          categoryNames[series.categoryId] ?? '',
        ],
      ].join(' '),
    );
  }

  static List<String> _queryTokens(String query) {
    final normalized = _normalize(query);

    if (normalized.isEmpty) {
      return const [];
    }

    return normalized
        .split(' ')
        .where((token) => token.trim().isNotEmpty)
        .toList(growable: false);
  }

  static bool _matchesTokens(String searchText, List<String> tokens) {
    for (final token in tokens) {
      if (!searchText.contains(token)) {
        return false;
      }
    }

    return true;
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
