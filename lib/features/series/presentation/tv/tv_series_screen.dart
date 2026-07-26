import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/models/iptv_category.dart';
import '../../../../shared/services/iptv_api_service.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../auth/domain/auth_session.dart';
import '../../../favorites/data/local_library_service.dart';
import '../../../player/presentation/tv/tv_series_player_screen.dart';
import '../../../search/data/search_index_service.dart';
import '../../domain/series_group.dart';
import '../../domain/tv_series.dart';

class TvSeriesScreen extends StatefulWidget {
  const TvSeriesScreen({
    required this.session,
    super.key,
  });

  final AuthSession session;

  @override
  State<TvSeriesScreen> createState() => _TvSeriesScreenState();
}

class _TvSeriesScreenState extends State<TvSeriesScreen> {
  final IptvApiService _apiService = IptvApiService();
  final FdezSearchIndexService _searchIndexService = FdezSearchIndexService();
  final LocalLibraryService _libraryService = LocalLibraryService.instance;
  final TextEditingController _searchController = TextEditingController();

  Timer? _searchDebounce;

  List<IptvCategory> _categories = <IptvCategory>[];
  List<TvSeries> _categorySeries = <TvSeries>[];
  List<TvSeries> _allSeries = <TvSeries>[];

  String? _selectedCategoryId;
  SeriesGroup? _selectedGroup;
  SeriesDetails? _selectedDetails;
  int _selectedVersionIndex = 0;
  int _selectedSeasonIndex = 0;
  String _searchQuery = '';

  bool _loadingInitialData = true;
  bool _loadingSeries = false;
  bool _loadingGlobalSearch = false;
  bool _allSeriesLoaded = false;
  bool _loadingDetails = false;
  bool _favoriteActionLoading = false;
  bool _preparingPlayback = false;

  String? _errorMessage;
  String? _globalSearchError;
  String? _detailsError;

  int _seriesRequestId = 0;
  int _detailsRequestId = 0;

  final Map<int, SeriesDetails> _detailsCache = <int, SeriesDetails>{};
  Set<int> _favoriteSeriesIds = <int>{};
  Map<int, WatchProgressEntry> _episodeProgress =
      <int, WatchProgressEntry>{};
  Map<int, WatchProgressEntry> _seriesProgress =
      <int, WatchProgressEntry>{};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    unawaited(_loadInitialData());
    unawaited(_loadLibraryStateDeferred());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLibraryStateDeferred() async {
    await Future<void>.delayed(const Duration(milliseconds: 1400));

    if (!mounted) {
      return;
    }

    await _loadLibraryState();
  }

  bool get _isSearching => _searchQuery.trim().isNotEmpty;

  Map<String, String> get _categoryNames {
    return <String, String>{
      for (final category in _categories) category.id: category.name,
    };
  }

  String get _selectedCategoryName {
    final selectedId = _selectedCategoryId;

    if (selectedId == null) {
      return 'Series';
    }

    for (final category in _categories) {
      if (category.id == selectedId) {
        return category.name;
      }
    }

    return 'Series';
  }

  List<SeriesGroup> get _visibleGroups {
    final source = _isSearching ? _allSeries : _categorySeries;
    final groups = groupSeries(source);
    final query = _searchQuery.trim();

    if (query.isEmpty) {
      return groups;
    }

    return groups
        .where(
          (group) => group.matches(
            query,
            categoryNames: _categoryNames,
          ),
        )
        .toList(growable: false);
  }

  SeriesSeason? get _selectedSeason {
    final details = _selectedDetails;

    if (details == null || details.seasons.isEmpty) {
      return null;
    }

    final safeIndex = _selectedSeasonIndex
        .clamp(0, details.seasons.length - 1)
        .toInt();

    return details.seasons[safeIndex];
  }

  Future<void> _loadLibraryState() async {
    try {
      final snapshot = await _libraryService.load(widget.session);

      if (!mounted) {
        return;
      }

      final favoriteIds = <int>{};
      final progressByEpisode = <int, WatchProgressEntry>{};
      final progressBySeries = <int, WatchProgressEntry>{};

      for (final item in snapshot.favorites) {
        final series = item.series;

        if (series != null) {
          favoriteIds.add(series.seriesId);
        }
      }

      for (final item in snapshot.progress) {
        final episodeId = item.episode?.episodeId;
        final seriesId = item.series?.seriesId;

        if (episodeId != null && episodeId > 0) {
          progressByEpisode[episodeId] = item;
        }

        if (seriesId != null && seriesId > 0) {
          progressBySeries.putIfAbsent(seriesId, () => item);
        }
      }

      setState(() {
        _favoriteSeriesIds = favoriteIds;
        _episodeProgress = progressByEpisode;
        _seriesProgress = progressBySeries;
      });
    } catch (_) {
      // La pantalla puede seguir funcionando aunque falle la biblioteca local.
    }
  }

  List<TvSeries>? _cachedSeriesForCategory(String categoryId) {
    final cachedGroups = _searchIndexService.cachedSeriesGroups;
    if (cachedGroups == null || cachedGroups.isEmpty) {
      return null;
    }

    return cachedGroups
        .where(
          (group) => group.variants.any((series) => series.categoryId == categoryId),
        )
        .expand((group) => group.variants)
        .toList(growable: false);
  }

  List<TvSeries>? _cachedAllSeries() {
    final cachedGroups = _searchIndexService.cachedSeriesGroups;
    if (cachedGroups == null || cachedGroups.isEmpty) {
      return null;
    }

    return cachedGroups
        .expand((group) => group.variants)
        .toList(growable: false);
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loadingInitialData = true;
      _errorMessage = null;
    });

    try {
      final categories = await _apiService.loadSeriesCategories(widget.session);

      if (!mounted) {
        return;
      }

      if (categories.isEmpty) {
        setState(() {
          _categories = <IptvCategory>[];
          _categorySeries = <TvSeries>[];
          _selectedGroup = null;
          _selectedDetails = null;
          _loadingInitialData = false;
          _errorMessage = 'No se encontraron categorías de series.';
        });
        return;
      }

      final firstCategory = categories.first;

      setState(() {
        _categories = categories;
        _selectedCategoryId = firstCategory.id;
      });

      final series = _cachedSeriesForCategory(firstCategory.id) ??
          await _apiService.loadSeries(
            widget.session,
            categoryId: firstCategory.id,
          );

      if (!mounted) {
        return;
      }

      final groups = groupSeries(series);
      final firstGroup = groups.isEmpty ? null : groups.first;

      setState(() {
        _categorySeries = series;
        _selectedGroup = firstGroup;
        _selectedVersionIndex = 0;
        _selectedSeasonIndex = 0;
        _selectedDetails = firstGroup == null
            ? null
            : SeriesDetails(series: firstGroup.primary, seasons: const []);
        _loadingInitialData = false;
      });

      if (firstGroup != null) {
        unawaited(_loadSelectedDetails(firstGroup));
      }

    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingInitialData = false;
        _errorMessage = 'No fue posible cargar las series.';
      });
    }
  }

  Future<void> _selectCategory(IptvCategory category) async {
    if (_loadingSeries || category.id == _selectedCategoryId) {
      if (_isSearching) {
        _searchController.clear();
      }
      return;
    }

    _searchController.clear();
    final requestId = ++_seriesRequestId;

    setState(() {
      _selectedCategoryId = category.id;
      _loadingSeries = true;
      _errorMessage = null;
      _categorySeries = <TvSeries>[];
      _selectedGroup = null;
      _selectedDetails = null;
      _selectedVersionIndex = 0;
      _selectedSeasonIndex = 0;
      _detailsError = null;
    });

    try {
      final series = _cachedSeriesForCategory(category.id) ??
          await _apiService.loadSeries(
            widget.session,
            categoryId: category.id,
          );

      if (!mounted || requestId != _seriesRequestId) {
        return;
      }

      final groups = groupSeries(series);
      final firstGroup = groups.isEmpty ? null : groups.first;

      setState(() {
        _categorySeries = series;
        _selectedGroup = firstGroup;
        _selectedDetails = firstGroup == null
            ? null
            : SeriesDetails(series: firstGroup.primary, seasons: const []);
        _selectedVersionIndex = 0;
        _selectedSeasonIndex = 0;
        _loadingSeries = false;
      });

      if (firstGroup != null) {
        unawaited(_loadSelectedDetails(firstGroup));
      }

    } catch (_) {
      if (!mounted || requestId != _seriesRequestId) {
        return;
      }

      setState(() {
        _loadingSeries = false;
        _errorMessage = 'No fue posible cargar esta categoría.';
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _searchDebounce?.cancel();

    SeriesGroup? firstGroup;

    if (query.isEmpty) {
      final groups = groupSeries(_categorySeries);
      firstGroup = groups.isEmpty ? null : groups.first;
    } else if (_allSeriesLoaded) {
      final groups = _filterGroups(groupSeries(_allSeries), query);
      firstGroup = groups.isEmpty ? null : groups.first;
    }

    setState(() {
      _searchQuery = query;

      if (query.isEmpty || _allSeriesLoaded) {
        _globalSearchError = null;
        _selectedGroup = firstGroup;
        _selectedVersionIndex = 0;
        _selectedSeasonIndex = 0;
        _selectedDetails = firstGroup == null
            ? null
            : SeriesDetails(series: firstGroup.primary, seasons: const []);
        _detailsError = null;
      }
    });

    if (firstGroup != null && (query.isEmpty || _allSeriesLoaded)) {
      unawaited(_loadSelectedDetails(firstGroup));
    }

    if (query.isEmpty || _allSeriesLoaded || _loadingGlobalSearch) {
      return;
    }

    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      _loadAllSeriesForSearch,
    );
  }

  List<SeriesGroup> _filterGroups(
    List<SeriesGroup> groups,
    String query,
  ) {
    return groups
        .where(
          (group) => group.matches(
            query,
            categoryNames: _categoryNames,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _loadAllSeriesForSearch({bool force = false}) async {
    if (_loadingGlobalSearch || (_allSeriesLoaded && !force)) {
      return;
    }

    setState(() {
      _loadingGlobalSearch = true;
      _globalSearchError = null;

      if (force) {
        _allSeriesLoaded = false;
        _allSeries = <TvSeries>[];
        _selectedGroup = null;
        _selectedDetails = null;
      }
    });

    try {
      final series = !force
          ? (_cachedAllSeries() ??
              (await _searchIndexService.ensureSeriesIndex(widget.session))
                  .expand((entry) => entry.group.variants)
                  .toList(growable: false))
          : await _apiService.loadSeries(
              widget.session,
              forceRefresh: force,
            );

      if (!mounted) {
        return;
      }

      final groups = _filterGroups(groupSeries(series), _searchQuery);
      final firstGroup = groups.isEmpty ? null : groups.first;

      setState(() {
        _allSeries = series;
        _allSeriesLoaded = true;
        _loadingGlobalSearch = false;
        _selectedGroup = firstGroup;
        _selectedVersionIndex = 0;
        _selectedSeasonIndex = 0;
        _selectedDetails = firstGroup == null
            ? null
            : SeriesDetails(series: firstGroup.primary, seasons: const []);
      });

      if (firstGroup != null) {
        unawaited(_loadSelectedDetails(firstGroup));
      }

    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingGlobalSearch = false;
        _allSeriesLoaded = false;
        _selectedGroup = null;
        _selectedDetails = null;
        _globalSearchError = 'No fue posible buscar en todas las series.';
      });
    }
  }

  Future<void> _refreshVisibleContent() async {
    if (_isSearching) {
      await _loadAllSeriesForSearch(force: true);
      return;
    }

    final categoryId = _selectedCategoryId;

    if (categoryId == null || _loadingSeries) {
      return;
    }

    final requestId = ++_seriesRequestId;

    setState(() {
      _loadingSeries = true;
      _errorMessage = null;
    });

    try {
      final series = await _apiService.loadSeries(
        widget.session,
        categoryId: categoryId,
        forceRefresh: true,
      );

      if (!mounted || requestId != _seriesRequestId) {
        return;
      }

      final groups = groupSeries(series);
      SeriesGroup? selected;
      final previousKey = _selectedGroup?.key;

      if (previousKey != null) {
        for (final group in groups) {
          if (group.key == previousKey) {
            selected = group;
            break;
          }
        }
      }

      selected ??= groups.isEmpty ? null : groups.first;

      setState(() {
        _categorySeries = series;
        _selectedGroup = selected;
        _selectedVersionIndex = 0;
        _selectedSeasonIndex = 0;
        _selectedDetails = selected == null
            ? null
            : SeriesDetails(series: selected.primary, seasons: const []);
        _loadingSeries = false;
      });

    } catch (_) {
      if (!mounted || requestId != _seriesRequestId) {
        return;
      }

      setState(() {
        _loadingSeries = false;
        _errorMessage = 'No fue posible actualizar esta categoría.';
      });
    }
  }

  void _selectGroup(SeriesGroup group) {
    if (_selectedGroup?.key == group.key) {
      return;
    }

    setState(() {
      _selectedGroup = group;
      _selectedVersionIndex = 0;
      _selectedSeasonIndex = 0;
      _selectedDetails = SeriesDetails(series: group.primary, seasons: const []);
      _detailsError = null;
    });

    unawaited(_loadSelectedDetails(group));
  }

  Future<SeriesDetails?> _fetchDetails(TvSeries series) async {
    final cached = _detailsCache[series.seriesId];

    if (cached != null) {
      return cached;
    }

    try {
      final details = await _apiService.loadSeriesDetails(
        widget.session,
        series: series,
      );
      _detailsCache[series.seriesId] = details;
      return details;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadSelectedDetails(
    SeriesGroup group, {
    int? versionIndex,
  }) async {
    if (group.variants.isEmpty) {
      return;
    }

    final index = (versionIndex ?? _selectedVersionIndex)
        .clamp(0, group.variants.length - 1)
        .toInt();
    final previousSeasonNumber = _selectedSeason?.seasonNumber;
    final requestId = ++_detailsRequestId;

    setState(() {
      _selectedVersionIndex = index;
      _selectedDetails = SeriesDetails(
        series: group.variants[index],
        seasons: const [],
      );
      _loadingDetails = true;
      _detailsError = null;
    });

    final details = await _fetchDetails(group.variants[index]);

    if (!mounted ||
        requestId != _detailsRequestId ||
        _selectedGroup?.key != group.key ||
        _selectedVersionIndex != index) {
      return;
    }

    if (details == null) {
      setState(() {
        _loadingDetails = false;
        _detailsError = 'No se pudieron cargar las temporadas y episodios.';
      });
      return;
    }

    int seasonIndex = 0;

    if (previousSeasonNumber != null) {
      final found = details.seasons.indexWhere(
        (season) => season.seasonNumber == previousSeasonNumber,
      );

      if (found >= 0) {
        seasonIndex = found;
      }
    }

    setState(() {
      _selectedDetails = details;
      _selectedSeasonIndex = seasonIndex;
      _loadingDetails = false;
      _detailsError = null;
    });
  }

  void _selectVersion(int index) {
    final group = _selectedGroup;

    if (group == null ||
        index < 0 ||
        index >= group.variants.length ||
        index == _selectedVersionIndex) {
      return;
    }

    unawaited(_loadSelectedDetails(group, versionIndex: index));
  }

  void _selectSeason(int index) {
    final details = _selectedDetails;

    if (details == null ||
        index < 0 ||
        index >= details.seasons.length ||
        index == _selectedSeasonIndex) {
      return;
    }

    setState(() {
      _selectedSeasonIndex = index;
    });
  }

  bool _isFavorite(SeriesGroup group) {
    return _favoriteSeriesIds.contains(group.primary.seriesId);
  }

  WatchProgressEntry? _progressForGroup(SeriesGroup group) {
    return _seriesProgress[group.primary.seriesId];
  }

  Future<void> _toggleFavorite(SeriesGroup group) async {
    if (_favoriteActionLoading) {
      return;
    }

    setState(() {
      _favoriteActionLoading = true;
    });

    try {
      final favorite = await _libraryService.toggleSeriesFavorite(
        widget.session,
        group.primary,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        if (favorite) {
          _favoriteSeriesIds.add(group.primary.seriesId);
        } else {
          _favoriteSeriesIds.remove(group.primary.seriesId);
        }
        _favoriteActionLoading = false;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              favorite
                  ? '${group.displayTitle} agregada a favoritos.'
                  : '${group.displayTitle} eliminada de favoritos.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _favoriteActionLoading = false;
      });
    }
  }

  Future<List<SeriesPlaybackVersion>> _loadPlaybackVersions(
    SeriesGroup group,
  ) async {
    final result = <SeriesPlaybackVersion>[];

    for (final series in group.variants) {
      final details = await _fetchDetails(series);

      if (details != null && details.seasons.isNotEmpty) {
        result.add(
          SeriesPlaybackVersion(
            series: series,
            details: details,
          ),
        );
      }
    }

    return result;
  }

  Future<void> _playSelectedEpisode(int episodeIndex) async {
    final group = _selectedGroup;
    final selectedDetails = _selectedDetails;
    final selectedSeason = _selectedSeason;

    if (group == null ||
        selectedDetails == null ||
        selectedSeason == null ||
        episodeIndex < 0 ||
        episodeIndex >= selectedSeason.episodes.length ||
        _preparingPlayback) {
      return;
    }

    setState(() {
      _preparingPlayback = true;
    });

    final selectedEpisode = selectedSeason.episodes[episodeIndex];
    final canonicalDetails = await _fetchDetails(group.primary);

    if (!mounted) {
      return;
    }

    if (canonicalDetails == null || canonicalDetails.seasons.isEmpty) {
      setState(() {
        _preparingPlayback = false;
      });
      return;
    }

    SeriesSeason? canonicalSeason;

    for (final season in canonicalDetails.seasons) {
      if (season.seasonNumber == selectedSeason.seasonNumber) {
        canonicalSeason = season;
        break;
      }
    }

    canonicalSeason ??= canonicalDetails.seasons.first;

    int canonicalIndex = canonicalSeason.episodes.indexWhere(
      (episode) => episode.episodeNumber == selectedEpisode.episodeNumber,
    );

    if (canonicalIndex < 0) {
      canonicalIndex = episodeIndex
          .clamp(0, canonicalSeason.episodes.length - 1)
          .toInt();
    }

    await _launchEpisode(
      group: group,
      canonicalDetails: canonicalDetails,
      season: canonicalSeason,
      episodeIndex: canonicalIndex,
    );
  }

  Future<void> _continueSeries(SeriesGroup group) async {
    if (_preparingPlayback) {
      return;
    }

    setState(() {
      _preparingPlayback = true;
    });

    final details = await _fetchDetails(group.primary);

    if (!mounted) {
      return;
    }

    if (details == null || details.seasons.isEmpty) {
      setState(() {
        _preparingPlayback = false;
      });
      return;
    }

    final progress = _progressForGroup(group);
    SeriesSeason season = details.seasons.first;
    int episodeIndex = 0;

    if (progress?.episode != null) {
      final savedEpisode = progress!.episode!;

      for (final candidate in details.seasons) {
        final directIndex = candidate.episodes.indexWhere(
          (episode) => episode.episodeId == savedEpisode.episodeId,
        );

        if (directIndex >= 0) {
          season = candidate;
          episodeIndex = directIndex;
          break;
        }

        if (candidate.seasonNumber == savedEpisode.seasonNumber) {
          final numberIndex = candidate.episodes.indexWhere(
            (episode) =>
                episode.episodeNumber == savedEpisode.episodeNumber,
          );

          if (numberIndex >= 0) {
            season = candidate;
            episodeIndex = numberIndex;
          }
        }
      }
    }

    if (_selectedGroup?.key == group.key) {
      final seasonIndex = (_selectedDetails ?? details).seasons.indexWhere(
        (item) => item.seasonNumber == season.seasonNumber,
      );

      if (seasonIndex >= 0) {
        setState(() {
          _selectedSeasonIndex = seasonIndex;
        });
      }
    }

    await _launchEpisode(
      group: group,
      canonicalDetails: details,
      season: season,
      episodeIndex: episodeIndex,
    );
  }

  Future<void> _launchEpisode({
    required SeriesGroup group,
    required SeriesDetails canonicalDetails,
    required SeriesSeason season,
    required int episodeIndex,
  }) async {
    final playbackVersions = await _loadPlaybackVersions(group);

    if (!mounted) {
      return;
    }

    if (season.episodes.isEmpty || playbackVersions.isEmpty) {
      setState(() {
        _preparingPlayback = false;
      });
      return;
    }

    final safeIndex = episodeIndex.clamp(0, season.episodes.length - 1).toInt();
    final episode = season.episodes[safeIndex];
    final preferredSeriesId = group.variants[
      _selectedVersionIndex.clamp(0, group.variants.length - 1).toInt()
    ].seriesId;
    final playbackSelectedIndex = playbackVersions.indexWhere(
      (version) => version.series.seriesId == preferredSeriesId,
    );

    WatchProgressEntry? savedProgress;

    try {
      savedProgress = await _libraryService.episodeProgress(
        widget.session,
        episode.episodeId,
      );
    } catch (_) {
      savedProgress = _episodeProgress[episode.episodeId];
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _preparingPlayback = false;
    });

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvSeriesPlayerScreen(
          session: widget.session,
          series: group.primary,
          seasonName: season.name,
          episodes: season.episodes,
          initialIndex: safeIndex,
          initialPosition: savedProgress?.position ?? Duration.zero,
          playbackVersions: playbackVersions,
          initialVersionIndex:
              playbackSelectedIndex < 0 ? 0 : playbackSelectedIndex,
          displayTitle: group.displayTitle,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadLibraryState();

    if (mounted) {
      setState(() {
        _selectedGroup = group;
        _selectedDetails = canonicalDetails.series.seriesId ==
                (_selectedDetails?.series.seriesId ?? 0)
            ? canonicalDetails
            : _selectedDetails;
      });
    }
  }

  SeriesGroup? _effectiveSelectedGroup(List<SeriesGroup> visibleGroups) {
    final selected = _selectedGroup;

    if (selected != null) {
      for (final group in visibleGroups) {
        if (group.key == selected.key) {
          return group;
        }
      }
    }

    return visibleGroups.isEmpty ? null : visibleGroups.first;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingInitialData) {
      return const _TvSeriesInitialLoading();
    }

    if (_errorMessage != null && _categories.isEmpty) {
      return _TvSeriesFullError(
        message: _errorMessage!,
        onRetry: _loadInitialData,
      );
    }

    final visibleGroups = _visibleGroups;
    final selectedGroup = _effectiveSelectedGroup(visibleGroups);

    if (selectedGroup != null && _selectedGroup?.key != selectedGroup.key) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        setState(() {
          _selectedGroup = selectedGroup;
          _selectedVersionIndex = 0;
          _selectedSeasonIndex = 0;
          _selectedDetails = SeriesDetails(
            series: selectedGroup.primary,
            seasons: const [],
          );
        });

      });
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TvSeriesHeader(
            categoryName: _isSearching
                ? 'Resultados en todas las categorías'
                : _selectedCategoryName,
            seriesCount: visibleGroups.length,
            loading: _loadingSeries || _loadingGlobalSearch,
            onRefresh: _refreshVisibleContent,
          ),
          const SizedBox(height: 14),
          _TvSeriesSearchField(
            controller: _searchController,
            loading: _loadingGlobalSearch,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final categoryWidth = (constraints.maxWidth * 0.18)
                    .clamp(145.0, 225.0)
                    .toDouble();
                final catalogWidth = (constraints.maxWidth * 0.36)
                    .clamp(330.0, 500.0)
                    .toDouble();
                final compact = constraints.maxWidth < 1050 ||
                    constraints.maxHeight < 600;
                final gap = compact ? 10.0 : 14.0;

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: categoryWidth,
                      child: _TvSeriesCategoryPanel(
                        categories: _categories,
                        selectedCategoryId: _selectedCategoryId,
                        searching: _isSearching,
                        loading: _loadingSeries,
                        onSelected: _selectCategory,
                      ),
                    ),
                    SizedBox(width: gap),
                    SizedBox(
                      width: catalogWidth,
                      child: _TvSeriesCatalogPanel(
                        groups: visibleGroups,
                        selectedGroup: selectedGroup,
                        categoryName: _isSearching
                            ? 'Búsqueda global'
                            : _selectedCategoryName,
                        searching: _isSearching,
                        loadingSeries: _loadingSeries,
                        loadingSearch: _loadingGlobalSearch,
                        errorMessage:
                            _isSearching ? _globalSearchError : _errorMessage,
                        categoryNames: _categoryNames,
                        favoriteIds: _favoriteSeriesIds,
                        progressBySeries: _seriesProgress,
                        onSelected: _selectGroup,
                        onRetry: _refreshVisibleContent,
                      ),
                    ),
                    SizedBox(width: gap),
                    Expanded(
                      child: _TvSeriesDetailsPanel(
                        group: selectedGroup,
                        details: _selectedGroup?.key == selectedGroup?.key
                            ? _selectedDetails
                            : null,
                        selectedVersionIndex:
                            _selectedGroup?.key == selectedGroup?.key
                                ? _selectedVersionIndex
                                : 0,
                        selectedSeasonIndex:
                            _selectedGroup?.key == selectedGroup?.key
                                ? _selectedSeasonIndex
                                : 0,
                        loadingDetails: _loadingDetails,
                        detailsError: _detailsError,
                        favorite: selectedGroup != null &&
                            _isFavorite(selectedGroup),
                        favoriteLoading: _favoriteActionLoading,
                        preparingPlayback: _preparingPlayback,
                        progress: selectedGroup == null
                            ? null
                            : _progressForGroup(selectedGroup),
                        episodeProgress: _episodeProgress,
                        compact: compact,
                        onSelectVersion: _selectVersion,
                        onSelectSeason: _selectSeason,
                        onFavorite: selectedGroup == null
                            ? null
                            : () {
                                unawaited(_toggleFavorite(selectedGroup));
                              },
                        onContinue: selectedGroup == null
                            ? null
                            : () {
                                unawaited(_continueSeries(selectedGroup));
                              },
                        onPlayEpisode: (index) {
                          unawaited(_playSelectedEpisode(index));
                        },
                        onRetryDetails: selectedGroup == null
                            ? null
                            : () {
                                unawaited(_loadSelectedDetails(selectedGroup));
                              },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TvSeriesHeader extends StatelessWidget {
  const _TvSeriesHeader({
    required this.categoryName,
    required this.seriesCount,
    required this.loading,
    required this.onRefresh,
  });

  final String categoryName;
  final int seriesCount;
  final bool loading;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF2D2340),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            Icons.video_library_rounded,
            color: Color(0xFFBE91FF),
            size: 26,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Series',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '$categoryName • $seriesCount títulos',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF8D97A8),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Actualizar series',
          onPressed: loading
              ? null
              : () {
                  unawaited(onRefresh());
                },
          icon: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

class _TvSeriesSearchField extends StatelessWidget {
  const _TvSeriesSearchField({
    required this.controller,
    required this.loading,
  });

  final TextEditingController controller;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Buscar series, actores, géneros o años...',
        hintStyle: const TextStyle(color: Color(0xFF6F7888)),
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: loading
            ? const Padding(
                padding: EdgeInsets.all(13),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar búsqueda',
                    onPressed: controller.clear,
                    icon: const Icon(Icons.close_rounded),
                  ),
        filled: true,
        fillColor: const Color(0xFF111720),
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF202632)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF202632)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFFBE91FF), width: 1.3),
        ),
      ),
    );
  }
}

class _TvSeriesCategoryPanel extends StatelessWidget {
  const _TvSeriesCategoryPanel({
    required this.categories,
    required this.selectedCategoryId,
    required this.searching,
    required this.loading,
    required this.onSelected,
  });

  final List<IptvCategory> categories;
  final String? selectedCategoryId;
  final bool searching;
  final bool loading;
  final ValueChanged<IptvCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return _TvSeriesPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Icon(
                  Icons.grid_view_rounded,
                  color: Color(0xFFBE91FF),
                  size: 19,
                ),
                SizedBox(width: 8),
                Text(
                  'CATEGORÍAS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF202632)),
          Expanded(
            child: Stack(
              children: [
                ListView.separated(
                  padding: const EdgeInsets.all(9),
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 5),
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final selected = !searching &&
                        category.id == selectedCategoryId;

                    return Material(
                      color: selected
                          ? const Color(0xFF2D2340)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                      child: InkWell(
        focusColor: const Color(0x665B7CFF),
                        onTap: loading ? null : () => onSelected(category),
                        borderRadius: BorderRadius.circular(11),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF7E57C2)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.folder_rounded
                                    : Icons.folder_outlined,
                                color: selected
                                    ? const Color(0xFFBE91FF)
                                    : const Color(0xFF788295),
                                size: 18,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  category.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : const Color(0xFFBBC1CC),
                                    fontSize: 12,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (loading)
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TvSeriesCatalogPanel extends StatelessWidget {
  const _TvSeriesCatalogPanel({
    required this.groups,
    required this.selectedGroup,
    required this.categoryName,
    required this.searching,
    required this.loadingSeries,
    required this.loadingSearch,
    required this.errorMessage,
    required this.categoryNames,
    required this.favoriteIds,
    required this.progressBySeries,
    required this.onSelected,
    required this.onRetry,
  });

  final List<SeriesGroup> groups;
  final SeriesGroup? selectedGroup;
  final String categoryName;
  final bool searching;
  final bool loadingSeries;
  final bool loadingSearch;
  final String? errorMessage;
  final Map<String, String> categoryNames;
  final Set<int> favoriteIds;
  final Map<int, WatchProgressEntry> progressBySeries;
  final ValueChanged<SeriesGroup> onSelected;
  final Future<void> Function() onRetry;

  bool get _loading => searching ? loadingSearch : loadingSeries;

  @override
  Widget build(BuildContext context) {
    return _TvSeriesPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    categoryName.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF202632),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${groups.length}',
                    style: const TextStyle(
                      color: Color(0xFFBEC5D0),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF202632)),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading && groups.isEmpty) {
      return const _TvSeriesPanelLoading(
        message: 'Cargando series...',
      );
    }

    if (errorMessage != null && groups.isEmpty) {
      return _TvSeriesPanelError(
        message: errorMessage!,
        onRetry: onRetry,
      );
    }

    if (groups.isEmpty) {
      return _TvSeriesPanelEmpty(
        icon: searching ? Icons.search_off_rounded : Icons.tv_off_rounded,
        title: searching ? 'Sin resultados' : 'No hay series',
        message: searching
            ? 'Prueba con otro nombre, actor, género o año.'
            : 'Esta categoría no contiene series disponibles.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 440 ? 3 : 2;
        final cardWidth =
            (constraints.maxWidth - 22 - ((columns - 1) * 9)) / columns;
        final cardHeight = cardWidth * 1.72;
        final ratio = cardWidth / cardHeight;

        return GridView.builder(
          padding: const EdgeInsets.all(11),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 9,
            mainAxisSpacing: 10,
            childAspectRatio: ratio,
          ),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            final primary = group.primary;

            return _TvSeriesCard(
              group: group,
              selected: selectedGroup?.key == group.key,
              favorite: favoriteIds.contains(primary.seriesId),
              progress: progressBySeries[primary.seriesId],
              categoryName: categoryNames[primary.categoryId] ?? '',
              onPressed: () => onSelected(group),
            );
          },
        );
      },
    );
  }
}

class _TvSeriesCard extends StatelessWidget {
  const _TvSeriesCard({
    required this.group,
    required this.selected,
    required this.favorite,
    required this.progress,
    required this.categoryName,
    required this.onPressed,
  });

  final SeriesGroup group;
  final bool selected;
  final bool favorite;
  final WatchProgressEntry? progress;
  final String categoryName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final series = group.primary;

    return Material(
      color: selected ? const Color(0xFF2D2340) : const Color(0xFF121720),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        focusColor: const Color(0x665B7CFF),
        onTap: onPressed,
        borderRadius: BorderRadius.circular(15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected
                  ? const Color(0xFFBE91FF)
                  : const Color(0xFF202632),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: AppCachedImage(
                        imageUrl: series.coverUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 300,
                        cacheHeight: 450,
                        placeholder: const _TvSeriesPosterFallback(
                          loading: true,
                        ),
                        fallback: const _TvSeriesPosterFallback(),
                      ),
                    ),
                    if (favorite)
                      const Positioned(
                        top: 7,
                        right: 7,
                        child: _TvSeriesBadge(
                          icon: Icons.favorite_rounded,
                          color: Color(0xFFFF6B7A),
                        ),
                      ),
                    if (group.versionCount > 1)
                      Positioned(
                        left: 7,
                        bottom: progress == null ? 7 : 13,
                        child: _TvSeriesBadge(
                          icon: Icons.layers_rounded,
                          text: '${group.versionCount}',
                          color: const Color(0xFFBE91FF),
                        ),
                      ),
                    if (progress != null)
                      Positioned(
                        left: 6,
                        right: 6,
                        bottom: 6,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: progress!.progress,
                            minHeight: 4,
                            backgroundColor: const Color(0xAA151A22),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Text(
                group.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : const Color(0xFFD4D8DF),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (series.displayYear.isNotEmpty)
                    Text(
                      series.displayYear,
                      style: const TextStyle(
                        color: Color(0xFF8D97A8),
                        fontSize: 9.5,
                      ),
                    ),
                  if (series.displayYear.isNotEmpty &&
                      series.displayRating.isNotEmpty)
                    const Text(
                      '  •  ',
                      style: TextStyle(color: Color(0xFF5D6676), fontSize: 9),
                    ),
                  if (series.displayRating.isNotEmpty) ...[
                    const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFFFC857),
                      size: 11,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      series.displayRating,
                      style: const TextStyle(
                        color: Color(0xFF8D97A8),
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ],
              ),
              if (categoryName.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  categoryName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8E76B4),
                    fontSize: 9,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TvSeriesDetailsPanel extends StatelessWidget {
  const _TvSeriesDetailsPanel({
    required this.group,
    required this.details,
    required this.selectedVersionIndex,
    required this.selectedSeasonIndex,
    required this.loadingDetails,
    required this.detailsError,
    required this.favorite,
    required this.favoriteLoading,
    required this.preparingPlayback,
    required this.progress,
    required this.episodeProgress,
    required this.compact,
    required this.onSelectVersion,
    required this.onSelectSeason,
    required this.onFavorite,
    required this.onContinue,
    required this.onPlayEpisode,
    required this.onRetryDetails,
  });

  final SeriesGroup? group;
  final SeriesDetails? details;
  final int selectedVersionIndex;
  final int selectedSeasonIndex;
  final bool loadingDetails;
  final String? detailsError;
  final bool favorite;
  final bool favoriteLoading;
  final bool preparingPlayback;
  final WatchProgressEntry? progress;
  final Map<int, WatchProgressEntry> episodeProgress;
  final bool compact;
  final ValueChanged<int> onSelectVersion;
  final ValueChanged<int> onSelectSeason;
  final VoidCallback? onFavorite;
  final VoidCallback? onContinue;
  final ValueChanged<int> onPlayEpisode;
  final VoidCallback? onRetryDetails;

  @override
  Widget build(BuildContext context) {
    final selectedGroup = group;

    if (selectedGroup == null) {
      return const _TvSeriesPanel(
        child: _TvSeriesPanelEmpty(
          icon: Icons.video_library_outlined,
          title: 'Selecciona una serie',
          message: 'La información, temporadas y episodios aparecerán aquí.',
        ),
      );
    }

    final currentDetails = details ??
        SeriesDetails(series: selectedGroup.primary, seasons: const []);
    final series = currentDetails.series;
    final backgroundUrl = series.backdropUrl.isNotEmpty
        ? series.backdropUrl
        : series.coverUrl;
    final seasons = currentDetails.seasons;
    final safeSeasonIndex = seasons.isEmpty
        ? 0
        : selectedSeasonIndex.clamp(0, seasons.length - 1).toInt();
    final selectedSeason = seasons.isEmpty ? null : seasons[safeSeasonIndex];

    return _TvSeriesPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: compact ? 176 : 215,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AppCachedImage(
                  imageUrl: backgroundUrl,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  cacheWidth: 900,
                  cacheHeight: 500,
                  placeholder: const _TvSeriesBackdropFallback(
                    loading: true,
                  ),
                  fallback: const _TvSeriesBackdropFallback(),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x33101620),
                        Color(0xC910151E),
                        Color(0xFF10151E),
                      ],
                      stops: [0, 0.62, 1],
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: IconButton.filled(
                    tooltip: favorite
                        ? 'Quitar de favoritos'
                        : 'Agregar a favoritos',
                    onPressed: favoriteLoading ? null : onFavorite,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xCC111720),
                    ),
                    icon: favoriteLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            favorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: favorite
                                ? const Color(0xFFFF6B7A)
                                : Colors.white,
                          ),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 15,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              selectedGroup.displayTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: compact ? 20 : 25,
                                height: 1.05,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 7,
                              runSpacing: 5,
                              children: [
                                if (series.displayYear.isNotEmpty)
                                  _TvSeriesInfoChip(
                                    icon: Icons.calendar_month_rounded,
                                    label: series.displayYear,
                                  ),
                                if (series.displayRating.isNotEmpty)
                                  _TvSeriesInfoChip(
                                    icon: Icons.star_rounded,
                                    label: series.displayRating,
                                    iconColor: const Color(0xFFFFC857),
                                  ),
                                if (seasons.isNotEmpty)
                                  _TvSeriesInfoChip(
                                    icon: Icons.video_collection_rounded,
                                    label: '${seasons.length} temporadas',
                                  ),
                                if (currentDetails.episodeCount > 0)
                                  _TvSeriesInfoChip(
                                    icon: Icons.playlist_play_rounded,
                                    label:
                                        '${currentDetails.episodeCount} episodios',
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: preparingPlayback ? null : onContinue,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF7E57C2),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 14 : 18,
                            vertical: 12,
                          ),
                        ),
                        icon: preparingPlayback
                            ? const SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                progress == null
                                    ? Icons.play_arrow_rounded
                                    : Icons.play_circle_fill_rounded,
                              ),
                        label: Text(
                          progress == null ? 'REPRODUCIR' : 'CONTINUAR',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (progress != null)
            LinearProgressIndicator(
              value: progress!.progress,
              minHeight: 4,
              backgroundColor: const Color(0xFF202632),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              compact ? 10 : 13,
              16,
              compact ? 7 : 10,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (series.genre.isNotEmpty)
                  Text(
                    series.genre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFBE91FF),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (series.genre.isNotEmpty) const SizedBox(height: 6),
                Text(
                  series.plot.isEmpty
                      ? 'No hay sinopsis disponible para esta serie.'
                      : series.plot,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB5BCC8),
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
                if (!compact &&
                    (series.director.isNotEmpty || series.cast.isNotEmpty)) ...[
                  const SizedBox(height: 7),
                  if (series.director.isNotEmpty)
                    _TvSeriesDetailLine(
                      label: 'Director',
                      value: series.director,
                    ),
                  if (series.cast.isNotEmpty)
                    _TvSeriesDetailLine(
                      label: 'Reparto',
                      value: series.cast,
                    ),
                ],
              ],
            ),
          ),
          if (selectedGroup.variants.length > 1) ...[
            const Divider(height: 1, color: Color(0xFF202632)),
            SizedBox(
              height: 48,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 7,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: selectedGroup.variants.length,
                separatorBuilder: (_, _) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final variant = selectedGroup.variants[index];
                  final selected = index == selectedVersionIndex;

                  return ChoiceChip(
                    selected: selected,
                    onSelected: (_) => onSelectVersion(index),
                    avatar: const Icon(Icons.layers_rounded, size: 16),
                    label: Text(seriesVariantLabel(variant)),
                    labelStyle: TextStyle(
                      color: selected
                          ? Colors.white
                          : const Color(0xFFBBC1CC),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                    backgroundColor: const Color(0xFF171D27),
                    selectedColor: const Color(0xFF5D3B88),
                    side: BorderSide(
                      color: selected
                          ? const Color(0xFFBE91FF)
                          : const Color(0xFF2A313D),
                    ),
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
          ],
          const Divider(height: 1, color: Color(0xFF202632)),
          if (loadingDetails && seasons.isEmpty)
            const Expanded(
              child: _TvSeriesPanelLoading(
                message: 'Cargando temporadas y episodios...',
              ),
            )
          else if (detailsError != null && seasons.isEmpty)
            Expanded(
              child: _TvSeriesPanelError(
                message: detailsError!,
                onRetry: () async {
                  onRetryDetails?.call();
                },
              ),
            )
          else if (seasons.isEmpty)
            const Expanded(
              child: _TvSeriesPanelEmpty(
                icon: Icons.video_collection_outlined,
                title: 'Sin episodios',
                message: 'No se encontraron temporadas para esta versión.',
              ),
            )
          else ...[
            SizedBox(
              height: 51,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 8,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: seasons.length,
                separatorBuilder: (_, _) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final season = seasons[index];
                  final selected = index == safeSeasonIndex;

                  return ChoiceChip(
                    selected: selected,
                    onSelected: (_) => onSelectSeason(index),
                    label: Text(
                      '${season.name} (${season.episodes.length})',
                    ),
                    labelStyle: TextStyle(
                      color: selected
                          ? Colors.white
                          : const Color(0xFFBBC1CC),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                    backgroundColor: const Color(0xFF171D27),
                    selectedColor: const Color(0xFF5D3B88),
                    side: BorderSide(
                      color: selected
                          ? const Color(0xFFBE91FF)
                          : const Color(0xFF2A313D),
                    ),
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
            const Divider(height: 1, color: Color(0xFF202632)),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(11),
                itemCount: selectedSeason!.episodes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final episode = selectedSeason.episodes[index];

                  return _TvSeriesEpisodeCard(
                    episode: episode,
                    progress: episodeProgress[episode.episodeId],
                    disabled: preparingPlayback,
                    compact: compact,
                    onPressed: () => onPlayEpisode(index),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TvSeriesEpisodeCard extends StatelessWidget {
  const _TvSeriesEpisodeCard({
    required this.episode,
    required this.progress,
    required this.disabled,
    required this.compact,
    required this.onPressed,
  });

  final SeriesEpisode episode;
  final WatchProgressEntry? progress;
  final bool disabled;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF151B24),
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        focusColor: const Color(0x665B7CFF),
        onTap: disabled ? null : onPressed,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              SizedBox(
                width: compact ? 88 : 112,
                height: compact ? 54 : 66,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: AppCachedImage(
                        imageUrl: episode.imageUrl,
                        fit: BoxFit.cover,
                        cacheWidth: 260,
                        cacheHeight: 150,
                        placeholder: const _TvEpisodeFallback(
                          loading: true,
                        ),
                        fallback: const _TvEpisodeFallback(),
                      ),
                    ),
                    Center(
                      child: Container(
                        width: 31,
                        height: 31,
                        decoration: const BoxDecoration(
                          color: Color(0xCC7E57C2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    if (progress != null)
                      Positioned(
                        left: 4,
                        right: 4,
                        bottom: 4,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress!.progress,
                            minHeight: 3,
                            backgroundColor: const Color(0xAA111720),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      episode.episodeNumber > 0
                          ? 'E${episode.episodeNumber} • ${episode.displayTitle}'
                          : episode.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    if (episode.plot.isNotEmpty)
                      Text(
                        episode.plot,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF929CAA),
                          fontSize: 10.5,
                          height: 1.25,
                        ),
                      )
                    else
                      Text(
                        progress == null
                            ? 'Listo para reproducir'
                            : 'Continuar desde el progreso guardado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF929CAA),
                          fontSize: 10.5,
                        ),
                      ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 3,
                      children: [
                        if (episode.duration.isNotEmpty)
                          _TvEpisodeMeta(
                            icon: Icons.schedule_rounded,
                            text: episode.duration,
                          ),
                        if (episode.displayRating.isNotEmpty)
                          _TvEpisodeMeta(
                            icon: Icons.star_rounded,
                            text: episode.displayRating,
                            iconColor: const Color(0xFFFFC857),
                          ),
                        if (progress != null)
                          const _TvEpisodeMeta(
                            icon: Icons.history_rounded,
                            text: 'En progreso',
                            iconColor: Color(0xFFBE91FF),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                progress == null
                    ? Icons.play_circle_outline_rounded
                    : Icons.play_circle_fill_rounded,
                color: const Color(0xFFBE91FF),
                size: 27,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvEpisodeMeta extends StatelessWidget {
  const _TvEpisodeMeta({
    required this.icon,
    required this.text,
    this.iconColor = const Color(0xFF7F8999),
  });

  final IconData icon;
  final String text;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: iconColor),
        const SizedBox(width: 3),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFF7F8999),
            fontSize: 9.5,
          ),
        ),
      ],
    );
  }
}

class _TvSeriesInfoChip extends StatelessWidget {
  const _TvSeriesInfoChip({
    required this.icon,
    required this.label,
    this.iconColor = const Color(0xFFBE91FF),
  });

  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xBB111720),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x552F3744)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFD7DBE2),
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TvSeriesDetailLine extends StatelessWidget {
  const _TvSeriesDetailLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: const TextStyle(fontSize: 10.5, height: 1.25),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: Color(0xFF7F8999),
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(color: Color(0xFFB8BFCA)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvSeriesPanel extends StatelessWidget {
  const _TvSeriesPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF10151E),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFF202632)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
    );
  }
}

class _TvSeriesBadge extends StatelessWidget {
  const _TvSeriesBadge({
    required this.icon,
    required this.color,
    this.text,
  });

  final IconData icon;
  final Color color;
  final String? text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: text == null ? 6 : 7,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: const Color(0xD9111720),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          if (text != null) ...[
            const SizedBox(width: 3),
            Text(
              text!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TvSeriesPosterFallback extends StatelessWidget {
  const _TvSeriesPosterFallback({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF1A202B),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(
                Icons.video_library_outlined,
                color: Color(0xFF596273),
                size: 38,
              ),
      ),
    );
  }
}

class _TvSeriesBackdropFallback extends StatelessWidget {
  const _TvSeriesBackdropFallback({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF262033), Color(0xFF10151E)],
        ),
      ),
      child: Center(
        child: loading
            ? const CircularProgressIndicator(strokeWidth: 2.4)
            : const Icon(
                Icons.video_library_rounded,
                color: Color(0x556F4B9D),
                size: 76,
              ),
      ),
    );
  }
}

class _TvEpisodeFallback extends StatelessWidget {
  const _TvEpisodeFallback({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF222936),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(
                Icons.play_circle_outline_rounded,
                color: Color(0xFF697386),
                size: 29,
              ),
      ),
    );
  }
}

class _TvSeriesPanelLoading extends StatelessWidget {
  const _TvSeriesPanelLoading({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 2.4),
          const SizedBox(height: 13),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF9BA4B2),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _TvSeriesPanelError extends StatelessWidget {
  const _TvSeriesPanelError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFFF8A80),
              size: 38,
            ),
            const SizedBox(height: 11),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFBBC1CC),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 13),
            OutlinedButton.icon(
              onPressed: () {
                unawaited(onRetry());
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvSeriesPanelEmpty extends StatelessWidget {
  const _TvSeriesPanelEmpty({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF697386), size: 42),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF8892A1),
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TvSeriesInitialLoading extends StatelessWidget {
  const _TvSeriesInitialLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(strokeWidth: 2.5),
          SizedBox(height: 14),
          Text(
            'Preparando catálogo de series...',
            style: TextStyle(color: Color(0xFFA5ADBA)),
          ),
        ],
      ),
    );
  }
}

class _TvSeriesFullError extends StatelessWidget {
  const _TvSeriesFullError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Color(0xFFFF8A80),
              size: 52,
            ),
            const SizedBox(height: 15),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 15),
            FilledButton.icon(
              onPressed: () {
                unawaited(onRetry());
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Volver a intentar'),
            ),
          ],
        ),
      ),
    );
  }
}
