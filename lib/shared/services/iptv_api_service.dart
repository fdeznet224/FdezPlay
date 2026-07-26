import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/config/app_config.dart';
import '../../features/auth/domain/auth_session.dart';
import '../../features/movies/domain/movie.dart';
import '../../features/series/domain/tv_series.dart';
import '../models/catalog_overview.dart';
import '../models/iptv_category.dart';

class IptvApiService {
  static const Duration _categoryCacheDuration = Duration(minutes: 15);
  static const Duration _catalogCacheDuration = Duration(minutes: 5);
  static const Duration _detailsCacheDuration = Duration(minutes: 10);

  static final Map<String, _TimedCacheEntry> _memoryCache =
      <String, _TimedCacheEntry>{};
  static final Map<String, Future<dynamic>> _pendingRequests =
      <String, Future<dynamic>>{};

  Future<CatalogOverview> loadOverview(
    AuthSession session, {
    bool forceRefresh = false,
  }) {
    return _cached<CatalogOverview>(
      key: _cacheKey(session, 'overview'),
      duration: _categoryCacheDuration,
      forceRefresh: forceRefresh,
      loader: () {
        return _withServerFallback(
          session: session,
          errorMessage: 'No fue posible cargar el contenido.',
          loader: (server) async {
            final results = await Future.wait<List<IptvCategory>>([
              _loadCategories(
                server: server,
                session: session,
                action: 'get_live_categories',
              ),
              _loadCategories(
                server: server,
                session: session,
                action: 'get_vod_categories',
              ),
              _loadCategories(
                server: server,
                session: session,
                action: 'get_series_categories',
              ),
            ]);

            return CatalogOverview(
              liveCategories: results[0],
              movieCategories: results[1],
              seriesCategories: results[2],
            );
          },
        );
      },
    );
  }

  Future<List<IptvCategory>> loadMovieCategories(
    AuthSession session, {
    bool forceRefresh = false,
  }) {
    return _cached<List<IptvCategory>>(
      key: _cacheKey(session, 'movie_categories'),
      duration: _categoryCacheDuration,
      forceRefresh: forceRefresh,
      loader: () {
        return _withServerFallback(
          session: session,
          errorMessage:
              'No fue posible cargar las categorías de películas.',
          loader: (server) {
            return _loadCategories(
              server: server,
              session: session,
              action: 'get_vod_categories',
            );
          },
        );
      },
    );
  }

  Future<List<Movie>> loadMovies(
    AuthSession session, {
    String? categoryId,
    bool forceRefresh = false,
  }) {
    final normalizedCategory = categoryId?.trim() ?? '';

    return _cached<List<Movie>>(
      key: _cacheKey(
        session,
        'movies',
        normalizedCategory.isEmpty ? 'all' : normalizedCategory,
      ),
      duration: _catalogCacheDuration,
      forceRefresh: forceRefresh,
      loader: () {
        return _withServerFallback(
          session: session,
          errorMessage: 'No fue posible cargar las películas.',
          loader: (server) {
            return _loadMoviesFromServer(
              server: server,
              session: session,
              categoryId: categoryId,
            );
          },
        );
      },
    );
  }

  Future<Movie> loadMovieDetails(
    AuthSession session, {
    required Movie movie,
    bool forceRefresh = false,
  }) {
    return _cached<Movie>(
      key: _cacheKey(
        session,
        'movie_details',
        movie.streamId.toString(),
      ),
      duration: _detailsCacheDuration,
      forceRefresh: forceRefresh,
      loader: () {
        return _withServerFallback(
          session: session,
          errorMessage:
              'No fue posible cargar los detalles de la película.',
          loader: (server) async {
            final decoded = await _requestJson(
              server: server,
              session: session,
              queryParameters: {
                'action': 'get_vod_info',
                'vod_id': movie.streamId.toString(),
              },
            );

            if (decoded is! Map) {
              throw const FormatException(
                'La respuesta de detalles no es válida.',
              );
            }

            return Movie.fromVodInfo(
              Map<String, dynamic>.from(decoded),
              fallback: movie,
            );
          },
        );
      },
    );
  }

  Future<List<IptvCategory>> loadSeriesCategories(
    AuthSession session, {
    bool forceRefresh = false,
  }) {
    return _cached<List<IptvCategory>>(
      key: _cacheKey(session, 'series_categories'),
      duration: _categoryCacheDuration,
      forceRefresh: forceRefresh,
      loader: () {
        return _withServerFallback(
          session: session,
          errorMessage:
              'No fue posible cargar las categorías de series.',
          loader: (server) {
            return _loadCategories(
              server: server,
              session: session,
              action: 'get_series_categories',
            );
          },
        );
      },
    );
  }

  Future<List<TvSeries>> loadSeries(
    AuthSession session, {
    String? categoryId,
    bool forceRefresh = false,
  }) {
    final normalizedCategory = categoryId?.trim() ?? '';

    return _cached<List<TvSeries>>(
      key: _cacheKey(
        session,
        'series',
        normalizedCategory.isEmpty ? 'all' : normalizedCategory,
      ),
      duration: _catalogCacheDuration,
      forceRefresh: forceRefresh,
      loader: () {
        return _withServerFallback(
          session: session,
          errorMessage: 'No fue posible cargar las series.',
          loader: (server) {
            return _loadSeriesFromServer(
              server: server,
              session: session,
              categoryId: categoryId,
            );
          },
        );
      },
    );
  }

  Future<SeriesDetails> loadSeriesDetails(
    AuthSession session, {
    required TvSeries series,
    bool forceRefresh = false,
  }) {
    return _cached<SeriesDetails>(
      key: _cacheKey(
        session,
        'series_details',
        series.seriesId.toString(),
      ),
      duration: _detailsCacheDuration,
      forceRefresh: forceRefresh,
      loader: () {
        return _withServerFallback(
          session: session,
          errorMessage:
              'No fue posible cargar temporadas y episodios.',
          loader: (server) async {
            final decoded = await _requestJson(
              server: server,
              session: session,
              queryParameters: {
                'action': 'get_series_info',
                'series_id': series.seriesId.toString(),
              },
            );

            if (decoded is! Map) {
              throw const FormatException(
                'La respuesta de detalles de la serie no es válida.',
              );
            }

            return SeriesDetails.fromResponse(
              Map<String, dynamic>.from(decoded),
              fallback: series,
            );
          },
        );
      },
    );
  }

  void clearMemoryCache({AuthSession? session}) {
    if (session == null) {
      _memoryCache.clear();
      _pendingRequests.clear();
      return;
    }

    final prefix = '${session.username.trim()}|';
    _memoryCache.removeWhere((key, _) => key.startsWith(prefix));
    _pendingRequests.removeWhere((key, _) => key.startsWith(prefix));
  }

  Future<T> _cached<T>({
    required String key,
    required Duration duration,
    required bool forceRefresh,
    required Future<T> Function() loader,
  }) async {
    final now = DateTime.now();

    if (!forceRefresh) {
      final cached = _memoryCache[key];

      if (cached != null && cached.expiresAt.isAfter(now)) {
        return cached.value as T;
      }

      final pending = _pendingRequests[key];

      if (pending != null) {
        return (await pending) as T;
      }
    } else {
      _memoryCache.remove(key);
    }

    final future = loader();
    _pendingRequests[key] = future;

    try {
      final value = await future;

      _memoryCache[key] = _TimedCacheEntry(
        value: value,
        expiresAt: DateTime.now().add(duration),
      );

      return value;
    } finally {
      if (identical(_pendingRequests[key], future)) {
        _pendingRequests.remove(key);
      }
    }
  }

  String _cacheKey(
    AuthSession session,
    String resource, [
    String qualifier = '',
  ]) {
    return <String>[
      session.username.trim(),
      resource,
      qualifier,
    ].join('|');
  }

  Future<T> _withServerFallback<T>({
    required AuthSession session,
    required String errorMessage,
    required Future<T> Function(String server) loader,
  }) async {
    Object? lastError;

    for (final server in _serverOrder(session.server)) {
      try {
        final result = await loader(server);

        session.updateServer(server);

        return result;
      } catch (error) {
        lastError = error;
      }
    }

    throw Exception('$errorMessage $lastError');
  }

  List<String> _serverOrder(String activeServer) {
    return <String>{
      activeServer,
      ...AppConfig.servers,
    }
        .map(_normalizeServer)
        .where((server) => server.isNotEmpty)
        .toList();
  }

  String _normalizeServer(String server) {
    return server.trim().replaceFirst(RegExp(r'/+$'), '');
  }

  Future<List<IptvCategory>> _loadCategories({
    required String server,
    required AuthSession session,
    required String action,
  }) async {
    final decoded = await _requestJson(
      server: server,
      session: session,
      queryParameters: {'action': action},
    );

    if (decoded is! List) {
      throw const FormatException(
        'La respuesta de categorías no es válida.',
      );
    }

    return decoded
        .whereType<Map>()
        .map(
          (item) => IptvCategory.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .where((category) => category.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<Movie>> _loadMoviesFromServer({
    required String server,
    required AuthSession session,
    String? categoryId,
  }) async {
    final query = <String, String>{'action': 'get_vod_streams'};
    final normalizedCategory = categoryId?.trim() ?? '';

    if (normalizedCategory.isNotEmpty) {
      query['category_id'] = normalizedCategory;
    }

    final decoded = await _requestJson(
      server: server,
      session: session,
      queryParameters: query,
    );

    if (decoded is! List) {
      throw const FormatException(
        'La respuesta de películas no es válida.',
      );
    }

    return decoded
        .whereType<Map>()
        .map(
          (item) => Movie.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .where((movie) => movie.streamId > 0 && movie.name.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<TvSeries>> _loadSeriesFromServer({
    required String server,
    required AuthSession session,
    String? categoryId,
  }) async {
    final query = <String, String>{'action': 'get_series'};
    final normalizedCategory = categoryId?.trim() ?? '';

    if (normalizedCategory.isNotEmpty) {
      query['category_id'] = normalizedCategory;
    }

    final decoded = await _requestJson(
      server: server,
      session: session,
      queryParameters: query,
    );

    if (decoded is! List) {
      throw const FormatException(
        'La respuesta de series no es válida.',
      );
    }

    return decoded
        .whereType<Map>()
        .map(
          (item) => TvSeries.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .where((series) => series.seriesId > 0 && series.name.isNotEmpty)
        .toList(growable: false);
  }

  Future<Object?> _requestJson({
    required String server,
    required AuthSession session,
    required Map<String, String> queryParameters,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = AppConfig.connectionTimeout
      ..autoUncompress = true;

    try {
      final uri = Uri.parse('$server/player_api.php').replace(
        queryParameters: {
          'username': session.username,
          'password': session.password,
          ...queryParameters,
        },
      );

      final request = await client
          .getUrl(uri)
          .timeout(AppConfig.connectionTimeout);

      request.followRedirects = true;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'FdezPlay/1.0');

      final response = await request
          .close()
          .timeout(AppConfig.connectionTimeout);

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(AppConfig.connectionTimeout);

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Respuesta HTTP ${response.statusCode}');
      }

      if (body.trim().isEmpty) {
        throw const FormatException(
          'El servidor devolvió una respuesta vacía.',
        );
      }

      return jsonDecode(body);
    } finally {
      client.close(force: true);
    }
  }
}

class _TimedCacheEntry {
  const _TimedCacheEntry({
    required this.value,
    required this.expiresAt,
  });

  final Object? value;
  final DateTime expiresAt;
}
