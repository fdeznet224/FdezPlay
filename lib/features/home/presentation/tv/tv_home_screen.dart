import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/models/catalog_overview.dart';
import '../../../../shared/services/iptv_api_service.dart';
import '../../../auth/domain/auth_session.dart';
import '../../../favorites/data/local_library_service.dart';
import '../../../live_tv/presentation/tv/tv_live_tv_screen.dart';
import '../../../movies/domain/movie.dart';
import '../../../movies/domain/movie_group.dart';
import '../../../movies/presentation/mobile/mobile_movie_detail_screen.dart';
import '../../../movies/presentation/tv/tv_movies_screen.dart';
import '../../../player/presentation/tv/tv_live_player_screen.dart';
import '../../../player/presentation/tv/tv_movie_player_screen.dart';
import '../../../player/presentation/tv/tv_series_player_screen.dart';
import '../../../series/domain/series_group.dart';
import '../../../series/domain/tv_series.dart';
import '../../../series/presentation/mobile/mobile_series_detail_screen.dart';
import '../../../series/presentation/tv/tv_series_screen.dart';
import '../../../search/data/search_index_service.dart';
import '../../../search/presentation/tv/tv_global_search_screen.dart';
import '../../../settings/presentation/tv/tv_settings_screen.dart';

class TvHomeScreen extends StatefulWidget {
  const TvHomeScreen({
    required this.session,
    super.key,
  });

  final AuthSession session;

  @override
  State<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends State<TvHomeScreen>
    with WidgetsBindingObserver {
  final FdezSearchIndexService _searchIndexService = FdezSearchIndexService();
  final List<Widget?> _sectionCache = List<Widget?>.filled(5, null);

  int _selectedIndex = 0;
  int _dashboardRefreshToken = 0;

  Timer? _orientationRestoreTimer;
  Timer? _catalogPrewarmTimer;
  bool _restoringTvChrome = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreTvChrome());
    _catalogPrewarmTimer = Timer(
      const Duration(milliseconds: 1800),
      () {
        if (mounted) {
          unawaited(_prewarmTvCatalogIndexes());
        }
      },
    );
  }

  Future<void> _prewarmTvCatalogIndexes() async {
    try {
      await _searchIndexService.prepare(widget.session);
    } catch (_) {
      // Si el precalentamiento falla, cada sección conserva su carga normal.
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();

    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) {
      return;
    }

    final size = views.first.physicalSize;
    if (size.height > size.width) {
      debugPrint(
        '[FDEZPLAY-TV] Vista vertical detectada; restaurando horizontal.',
      );
      _scheduleTvChromeRestore();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleTvChromeRestore();
    }
  }

  void _scheduleTvChromeRestore({
    Duration delay = const Duration(milliseconds: 90),
  }) {
    _orientationRestoreTimer?.cancel();
    _orientationRestoreTimer = Timer(delay, () {
      if (mounted) {
        unawaited(_restoreTvChrome(scheduleVerification: false));
      }
    });
  }

  Future<void> _restoreTvChrome({
    bool scheduleVerification = true,
  }) async {
    if (!mounted || _restoringTvChrome) {
      return;
    }

    _restoringTvChrome = true;

    try {
      await SystemChrome.setPreferredOrientations(
        const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      );

      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
      );
    } finally {
      _restoringTvChrome = false;
    }

    if (scheduleVerification && mounted) {
      _scheduleTvChromeRestore(
        delay: const Duration(milliseconds: 450),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _orientationRestoreTimer?.cancel();
    _catalogPrewarmTimer?.cancel();
    super.dispose();
  }

  void _selectSection(int index) {
    if (_selectedIndex == index) {
      if (index == 0) {
        setState(() {
          _dashboardRefreshToken++;
        });
      }
      _scheduleTvChromeRestore();
      return;
    }

    setState(() {
      _selectedIndex = index;
      if (index == 0) {
        _dashboardRefreshToken++;
      }
    });

    _scheduleTvChromeRestore();
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvGlobalSearchScreen(session: widget.session),
      ),
    );
  }

  Widget _createSection(int index) {
    switch (index) {
      case 0:
        return _TvDashboard(
          session: widget.session,
          refreshToken: _dashboardRefreshToken,
          onOpenSection: _selectSection,
          onRestoreTvChrome: _restoreTvChrome,
        );
      case 1:
        return TvLiveTvScreen(
          session: widget.session,
        );
      case 2:
        return TvMoviesScreen(
          session: widget.session,
        );
      case 3:
        return TvSeriesScreen(
          session: widget.session,
        );
      case 4:
        return TvSettingsScreen(
          session: widget.session,
        );
    }

    return const SizedBox.shrink();
  }

  Widget _sectionFor(int index) {
    if (index == 0) {
      return _createSection(0);
    }

    return _sectionCache[index] ??= _createSection(index);
  }

  List<Widget> _buildLazySectionStack() {
    return List<Widget>.generate(5, (index) {
      if (index == 0 || index == _selectedIndex || _sectionCache[index] != null) {
        return _sectionFor(index);
      }

      return const SizedBox.shrink();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        focusColor: const Color(0x995B7CFF),
        hoverColor: const Color(0x335B7CFF),
        splashColor: const Color(0x445B7CFF),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF090C13),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compactNavigation = _selectedIndex != 0 || constraints.maxWidth < 900;
            final shortNavigation = constraints.maxHeight < 520;
            final navigationWidth = compactNavigation ? 76.0 : 218.0;

            return Row(
              children: [
                SizedBox(
                  width: navigationWidth,
                  child: _TvNavigationRail(
                    compact: compactNavigation,
                    shortHeight: shortNavigation,
                    selectedIndex: _selectedIndex,
                    onSelected: _selectSection,
                    onOpenSearch: _openSearch,
                  ),
                ),
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: Color(0xFF202632),
                ),
                Expanded(
                  child: ClipRect(
                    child: IndexedStack(
                      index: _selectedIndex,
                      sizing: StackFit.expand,
                      children: _buildLazySectionStack(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      ),
    );
  }
}

class _TvNavigationRail extends StatelessWidget {
  const _TvNavigationRail({
    required this.compact,
    required this.shortHeight,
    required this.selectedIndex,
    required this.onSelected,
    required this.onOpenSearch,
  });

  final bool compact;
  final bool shortHeight;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    final destinations = <_TvDestination>[
      const _TvDestination(
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
        label: 'Inicio',
      ),
      const _TvDestination(
        icon: Icons.live_tv_outlined,
        selectedIcon: Icons.live_tv_rounded,
        label: 'TV en vivo',
      ),
      const _TvDestination(
        icon: Icons.movie_outlined,
        selectedIcon: Icons.movie_rounded,
        label: 'Películas',
      ),
      const _TvDestination(
        icon: Icons.video_library_outlined,
        selectedIcon: Icons.video_library_rounded,
        label: 'Series',
      ),
      const _TvDestination(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
        label: 'Ajustes',
      ),
    ];

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1119),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 8 : 16,
          shortHeight ? 8 : 14,
          compact ? 8 : 16,
          shortHeight ? 8 : 14,
        ),
        child: Column(
          children: [
            _TvBrand(
              compact: compact,
              shortHeight: shortHeight,
            ),
            SizedBox(height: shortHeight ? 9 : 18),
            _TvNavigationItem(
              compact: compact,
              shortHeight: shortHeight,
              destination: const _TvDestination(
                icon: Icons.search_rounded,
                selectedIcon: Icons.search_rounded,
                label: 'Buscar',
              ),
              selected: false,
              onPressed: onOpenSearch,
            ),
            SizedBox(height: shortHeight ? 8 : 16),
            for (int index = 0; index < destinations.length; index++) ...[
              _TvNavigationItem(
                compact: compact,
                shortHeight: shortHeight,
                destination: destinations[index],
                selected: selectedIndex == index,
                onPressed: () => onSelected(index),
              ),
              if (index != destinations.length - 1)
                SizedBox(height: shortHeight ? 3 : 7),
            ],
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _TvDestination {
  const _TvDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _TvBrand extends StatelessWidget {
  const _TvBrand({
    required this.compact,
    required this.shortHeight,
  });

  final bool compact;
  final bool shortHeight;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment:
          compact ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Container(
          width: shortHeight ? 38 : 48,
          height: shortHeight ? 38 : 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF6F8CFF),
                Color(0xFF405DD3),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: shortHeight ? 26 : 32,
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FdezPlay',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Experiencia TV',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF8791A3),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TvNavigationItem extends StatelessWidget {
  const _TvNavigationItem({
    required this.compact,
    required this.shortHeight,
    required this.destination,
    required this.selected,
    required this.onPressed,
  });

  final bool compact;
  final bool shortHeight;
  final _TvDestination destination;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: destination.label,
        child: InkWell(
          autofocus: selected,
          focusColor: const Color(0x665B7CFF),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(15),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: shortHeight ? 39 : 50,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 0 : 14,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF17213B)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: selected
                    ? const Color(0xFF2A3C70)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  color: selected
                      ? const Color(0xFF86A0FF)
                      : const Color(0xFF98A2B3),
                  size: shortHeight ? 21 : 23,
                ),
                if (!compact) ...[
                  const SizedBox(width: 13),
                  Expanded(
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : const Color(0xFFB0B8C6),
                        fontSize: 13.5,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvDashboard extends StatefulWidget {
  const _TvDashboard({
    required this.session,
    required this.refreshToken,
    required this.onOpenSection,
    required this.onRestoreTvChrome,
  });

  final AuthSession session;
  final int refreshToken;
  final ValueChanged<int> onOpenSection;
  final Future<void> Function() onRestoreTvChrome;

  @override
  State<_TvDashboard> createState() => _TvDashboardState();
}

class _TvDashboardState extends State<_TvDashboard> {
  final IptvApiService _apiService = IptvApiService();
  final LocalLibraryService _libraryService = LocalLibraryService.instance;

  CatalogOverview? _catalog;
  LocalLibrarySnapshot? _library;
  List<MovieGroup> _movies = const [];
  List<SeriesGroup> _series = const [];

  bool _loading = true;
  bool _refreshing = false;
  String? _errorMessage;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _TvDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.refreshToken != widget.refreshToken) {
      unawaited(_load(showMainLoading: false));
    }
  }

  Future<void> _load({bool showMainLoading = true}) async {
    final requestId = ++_requestId;

    if (showMainLoading && mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final libraryFuture = _libraryService.load(widget.session);
      final catalogFuture = _apiService.loadOverview(widget.session);

      final library = await libraryFuture;
      final catalog = await catalogFuture;

      List<MovieGroup> movies = const [];
      List<SeriesGroup> series = const [];

      if (catalog.movieCategories.isNotEmpty) {
        try {
          final loadedMovies = await _apiService.loadMovies(
            widget.session,
            categoryId: catalog.movieCategories.first.id,
          );
          movies = groupMovies(loadedMovies).take(14).toList(growable: false);
        } catch (_) {
          movies = const [];
        }
      }

      if (catalog.seriesCategories.isNotEmpty) {
        try {
          final loadedSeries = await _apiService.loadSeries(
            widget.session,
            categoryId: catalog.seriesCategories.first.id,
          );
          series = groupSeries(loadedSeries).take(14).toList(growable: false);
        } catch (_) {
          series = const [];
        }
      }

      if (!mounted || requestId != _requestId) {
        return;
      }

      setState(() {
        _catalog = catalog;
        _library = library;
        _movies = movies;
        _series = series;
        _loading = false;
        _refreshing = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) {
        return;
      }

      setState(() {
        _loading = false;
        _refreshing = false;
        _errorMessage = 'No fue posible actualizar el inicio Tv.';
      });
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      return;
    }

    setState(() {
      _refreshing = true;
      _errorMessage = null;
    });

    await _load(showMainLoading: false);
  }

  Future<void> _afterNavigation() async {
    await widget.onRestoreTvChrome();
    await _reloadLibrary();
  }

  Future<void> _reloadLibrary() async {
    try {
      final library = await _libraryService.load(widget.session);
      if (!mounted) {
        return;
      }
      setState(() {
        _library = library;
      });
    } catch (_) {
      // El dashboard puede seguir utilizándose con los datos anteriores.
    }
  }

  Future<void> _openProgress(WatchProgressEntry item) async {
    if (item.movie != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => TvMoviePlayerScreen(
            session: widget.session,
            movie: item.movie!,
            initialPosition: item.position,
          ),
        ),
      );
    } else if (item.series != null &&
        item.episodes.isNotEmpty &&
        item.currentIndex >= 0 &&
        item.currentIndex < item.episodes.length) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => TvSeriesPlayerScreen(
            session: widget.session,
            series: item.series!,
            seasonName: item.seasonName,
            episodes: item.episodes,
            initialIndex: item.currentIndex,
            initialPosition: item.position,
          ),
        ),
      );
    }

    if (mounted) {
      await _afterNavigation();
    }
  }

  Future<void> _openProgressDetails(WatchProgressEntry item) async {
    if (item.movie != null) {
      await _openMovie(item.movie!);
    } else if (item.series != null) {
      await _openSeries(item.series!);
    }
  }

  Future<void> _openFavorite(FavoriteEntry item) async {
    if (item.channel != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => TvLivePlayerScreen(
            session: widget.session,
            channel: item.channel!,
            channelVariants: item.channelVariants,
          ),
        ),
      );

      if (mounted) {
        await _afterNavigation();
      }
      return;
    }

    if (item.movie != null) {
      await _openMovie(item.movie!);
    } else if (item.series != null) {
      await _openSeries(item.series!);
    }
  }

  Future<void> _openMovie(Movie movie) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MobileMovieDetailScreen(
          session: widget.session,
          movie: movie,
          enableTvRemoteNavigation: true,
        ),
      ),
    );

    if (mounted) {
      await _afterNavigation();
    }
  }

  Future<void> _openMovieGroup(MovieGroup group) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MobileMovieDetailScreen(
          session: widget.session,
          movie: group.primary,
          versions: group.variants,
          displayTitle: group.displayTitle,
          enableTvRemoteNavigation: true,
        ),
      ),
    );

    if (mounted) {
      await _afterNavigation();
    }
  }

  Future<void> _openSeries(TvSeries series) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MobileSeriesDetailScreen(
          session: widget.session,
          series: series,
          enableTvRemoteNavigation: true,
        ),
      ),
    );

    if (mounted) {
      await _afterNavigation();
    }
  }

  Future<void> _openSeriesGroup(SeriesGroup group) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MobileSeriesDetailScreen(
          session: widget.session,
          series: group.primary,
          versions: group.variants,
          displayTitle: group.displayTitle,
          enableTvRemoteNavigation: true,
        ),
      ),
    );

    if (mounted) {
      await _afterNavigation();
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _library?.progress ?? const <WatchProgressEntry>[];
    final favorites = _library?.favorites ?? const <FavoriteEntry>[];
    final channelFavorites = favorites
        .where((item) => item.channel != null)
        .take(10)
        .toList(growable: false);
    final mediaFavorites = favorites
        .where((item) => item.movie != null || item.series != null)
        .take(12)
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHeight = constraints.maxHeight < 600;
        final contentPadding = constraints.maxWidth < 760 ? 16.0 : 24.0;

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              contentPadding,
              compactHeight ? 14 : 20,
              contentPadding,
              34,
            ),
            children: [
              _TvDashboardHeader(
                username: widget.session.username,
                isActive: widget.session.isActive,
                refreshing: _refreshing,
                onRefresh: _refresh,
                onSettings: () => widget.onOpenSection(4),
              ),
              SizedBox(height: compactHeight ? 14 : 20),
              if (_loading && _library == null)
                _TvDashboardLoading(compactHeight: compactHeight)
              else ...[
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  _TvInlineError(
                    message: _errorMessage!,
                    onRetry: () => unawaited(_load()),
                  ),
                ],
                if (progress.isNotEmpty) ...[
                  SizedBox(height: compactHeight ? 18 : 24),
                  const _TvSectionHeader(
                    title: 'Continuar viendo',
                    subtitle: 'Retoma exactamente desde donde te quedaste',
                  ),
                  const SizedBox(height: 12),
                  _TvProgressRow(
                    items: progress.take(12).toList(growable: false),
                    compactHeight: compactHeight,
                    onOpen: (item) => unawaited(_openProgress(item)),
                  ),
                ],
                if (_movies.isNotEmpty) ...[
                  SizedBox(height: compactHeight ? 20 : 28),
                  _TvSectionHeader(
                    title: 'Películas en tendencia',
                    subtitle: _catalog?.movieCategories.isNotEmpty == true
                        ? _catalog!.movieCategories.first.name
                        : 'Lo más visto en películas',
                    actionLabel: 'Ver todas',
                    onAction: () => widget.onOpenSection(2),
                  ),
                  const SizedBox(height: 12),
                  _TvMovieRow(
                    groups: _movies,
                    compactHeight: compactHeight,
                    onOpen: (group) => unawaited(_openMovieGroup(group)),
                  ),
                ],
                if (_series.isNotEmpty) ...[
                  SizedBox(height: compactHeight ? 20 : 28),
                  _TvSectionHeader(
                    title: 'Series en tendencia',
                    subtitle: _catalog?.seriesCategories.isNotEmpty == true
                        ? _catalog!.seriesCategories.first.name
                        : 'Historias populares para ver ahora',
                    actionLabel: 'Ver todas',
                    onAction: () => widget.onOpenSection(3),
                  ),
                  const SizedBox(height: 12),
                  _TvSeriesRow(
                    groups: _series,
                    compactHeight: compactHeight,
                    onOpen: (group) => unawaited(_openSeriesGroup(group)),
                  ),
                ],
                if (channelFavorites.isNotEmpty) ...[
                  SizedBox(height: compactHeight ? 20 : 28),
                  const _TvSectionHeader(
                    title: 'Canales favoritos',
                    subtitle: 'Acceso rápido a tus canales guardados',
                  ),
                  const SizedBox(height: 12),
                  _TvChannelRow(
                    items: channelFavorites,
                    compactHeight: compactHeight,
                    onOpen: (item) => unawaited(_openFavorite(item)),
                  ),
                ],
                if (mediaFavorites.isNotEmpty) ...[
                  SizedBox(height: compactHeight ? 20 : 28),
                  const _TvSectionHeader(
                    title: 'Mi biblioteca',
                    subtitle: 'Películas y series guardadas como favoritas',
                  ),
                  const SizedBox(height: 12),
                  _TvFavoriteRow(
                    items: mediaFavorites,
                    compactHeight: compactHeight,
                    onOpen: (item) => unawaited(_openFavorite(item)),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TvDashboardHeader extends StatelessWidget {
  const _TvDashboardHeader({
    required this.username,
    required this.isActive,
    required this.refreshing,
    required this.onRefresh,
    required this.onSettings,
  });

  final String username;
  final bool isActive;
  final bool refreshing;
  final Future<void> Function() onRefresh;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hola, $username',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFF50D5B7)
                          : const Color(0xFFFF7D8A),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    isActive
                        ? 'Todo listo para reproducir'
                        : 'Revisa el estado de tu suscripción',
                    style: const TextStyle(
                      color: Color(0xFF98A2B3),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Actualizar inicio',
          onPressed: refreshing ? null : () => unawaited(onRefresh()),
          icon: refreshing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Ajustes',
          onPressed: onSettings,
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    );
  }
}

class _TvHeroSection extends StatelessWidget {
  const _TvHeroSection({
    required this.compactHeight,
    required this.progress,
    required this.movieGroup,
    required this.onContinue,
    required this.onProgressDetails,
    required this.onMovieDetails,
    required this.onOpenTv,
  });

  final bool compactHeight;
  final WatchProgressEntry? progress;
  final MovieGroup? movieGroup;
  final ValueChanged<WatchProgressEntry> onContinue;
  final ValueChanged<WatchProgressEntry> onProgressDetails;
  final ValueChanged<MovieGroup> onMovieDetails;
  final VoidCallback onOpenTv;

  @override
  Widget build(BuildContext context) {
    return _TvHero(
      compactHeight: compactHeight,
      progress: progress,
      movieGroup: movieGroup,
      onContinue: onContinue,
      onProgressDetails: onProgressDetails,
      onMovieDetails: onMovieDetails,
      onOpenTv: onOpenTv,
    );
  }
}

class _TvHero extends StatelessWidget {
  const _TvHero({
    required this.compactHeight,
    required this.progress,
    required this.movieGroup,
    required this.onContinue,
    required this.onProgressDetails,
    required this.onMovieDetails,
    required this.onOpenTv,
  });

  final bool compactHeight;
  final WatchProgressEntry? progress;
  final MovieGroup? movieGroup;
  final ValueChanged<WatchProgressEntry> onContinue;
  final ValueChanged<WatchProgressEntry> onProgressDetails;
  final ValueChanged<MovieGroup> onMovieDetails;
  final VoidCallback onOpenTv;

  @override
  Widget build(BuildContext context) {
    final progressItem = progress;
    final group = movieGroup;
    final movie = group?.primary;

    final String title;
    final String subtitle;
    final String imageUrl;
    final double? progressValue;
    final String label;
    final String buttonLabel;

    if (progressItem != null) {
      title = progressItem.title;
      subtitle = progressItem.subtitle;
      imageUrl = progressItem.movie?.backdropUrl.isNotEmpty == true
          ? progressItem.movie!.backdropUrl
          : progressItem.series?.backdropUrl.isNotEmpty == true
              ? progressItem.series!.backdropUrl
              : progressItem.imageUrl;
      progressValue = progressItem.progress;
      label = 'CONTINUAR VIENDO';
      buttonLabel = 'Continuar';
    } else if (movie != null) {
      title = group?.displayTitle ?? movie.name;
      subtitle = [
        if (movie.displayYear.isNotEmpty) movie.displayYear,
        if (movie.genre.isNotEmpty) movie.genre,
        if (group != null && group.versionCount > 1)
          '${group.versionCount} versiones',
      ].join(' • ');
      imageUrl = movie.backdropUrl.isNotEmpty
          ? movie.backdropUrl
          : movie.posterUrl;
      progressValue = null;
      label = 'DESTACADA PARA TI';
      buttonLabel = 'Ver detalles';
    } else {
      title = 'Todo tu entretenimiento en un solo lugar';
      subtitle = 'TV en vivo, películas y series';
      imageUrl = '';
      progressValue = null;
      label = 'FDEZPLAY TABLET';
      buttonLabel = 'Ver TV';
    }

    return Container(
      height: compactHeight ? 234 : 318,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF101626),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF252D3A)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _TvNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            fallback: const _TvHeroFallback(),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                colors: [
                  Color(0x14000000),
                  Color(0x85090C13),
                  Color(0xF5090C13),
                ],
                stops: [0, 0.52, 1],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(compactHeight ? 20 : 28),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          color: Color(0xFF9CB0FF),
                          size: 16,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          label,
                          style: const TextStyle(
                            color: Color(0xFFD8E0FF),
                            fontSize: 10.5,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      maxLines: compactHeight ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compactHeight ? 27 : 38,
                        height: 1.02,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                        shadows: const [
                          Shadow(color: Colors.black54, blurRadius: 10),
                        ],
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFFDCE2EC),
                          fontSize: compactHeight ? 12 : 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (progressValue != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: progressValue,
                          minHeight: 5,
                          backgroundColor: const Color(0x66000000),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () {
                            if (progressItem != null) {
                              onContinue(progressItem);
                            } else if (group != null) {
                              onMovieDetails(group);
                            } else {
                              onOpenTv();
                            }
                          },
                          icon: Icon(
                            progressItem != null
                                ? Icons.play_arrow_rounded
                                : group != null
                                    ? Icons.info_outline_rounded
                                    : Icons.live_tv_rounded,
                          ),
                          label: Text(buttonLabel),
                        ),
                        if (progressItem != null)
                          OutlinedButton.icon(
                            onPressed: () =>
                                onProgressDetails(progressItem),
                            icon: const Icon(Icons.info_outline_rounded),
                            label: const Text('Detalles'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(
                                color: Color(0xAAFFFFFF),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TvHeroFallback extends StatelessWidget {
  const _TvHeroFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF273D89),
            Color(0xFF17234F),
            Color(0xFF0C101C),
          ],
        ),
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: EdgeInsets.only(right: 30),
          child: Icon(
            Icons.play_circle_fill_rounded,
            size: 180,
            color: Color(0x245B7CFF),
          ),
        ),
      ),
    );
  }
}

class _TvQuickAccess extends StatelessWidget {
  const _TvQuickAccess({
    required this.catalog,
    required this.onOpenSection,
  });

  final CatalogOverview? catalog;
  final ValueChanged<int> onOpenSection;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 720;
        final cards = <Widget>[
          _TvQuickCard(
            icon: Icons.live_tv_rounded,
            title: 'TV en vivo',
            subtitle: '${catalog?.liveCategoryCount ?? 0} categorías',
            accent: const Color(0xFF50D5B7),
            background: const Color(0xFF143630),
            onPressed: () => onOpenSection(1),
          ),
          _TvQuickCard(
            icon: Icons.movie_creation_rounded,
            title: 'Películas',
            subtitle: '${catalog?.movieCategoryCount ?? 0} categorías',
            accent: const Color(0xFFC7A0FF),
            background: const Color(0xFF302342),
            onPressed: () => onOpenSection(2),
          ),
          _TvQuickCard(
            icon: Icons.video_library_rounded,
            title: 'Series',
            subtitle: '${catalog?.seriesCategoryCount ?? 0} categorías',
            accent: const Color(0xFFFFA66B),
            background: const Color(0xFF3D2A22),
            onPressed: () => onOpenSection(3),
          ),
        ];

        if (narrow) {
          return Column(
            children: [
              for (int index = 0; index < cards.length; index++) ...[
                cards[index],
                if (index != cards.length - 1)
                  const SizedBox(height: 10),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (int index = 0; index < cards.length; index++) ...[
              Expanded(child: cards[index]),
              if (index != cards.length - 1)
                const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _TvQuickCard extends StatelessWidget {
  const _TvQuickCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.background,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Color background;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 88,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF111620),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF252D39)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: accent, size: 25),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF98A2B3),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Color(0xFF667085),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvSectionHeader extends StatelessWidget {
  const _TvSectionHeader({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF98A2B3),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

class _TvProgressRow extends StatelessWidget {
  const _TvProgressRow({
    required this.items,
    required this.compactHeight,
    required this.onOpen,
  });

  final List<WatchProgressEntry> items;
  final bool compactHeight;
  final ValueChanged<WatchProgressEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    return _TvHorizontalRow(
      height: compactHeight ? 176 : 218,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _TvPosterCard(
          compactHeight: compactHeight,
          title: item.title,
          subtitle: item.subtitle,
          imageUrl: item.imageUrl,
          progress: item.progress,
          showPlayBadge: true,
          onPressed: () => onOpen(item),
        );
      },
    );
  }
}

class _TvFavoriteRow extends StatelessWidget {
  const _TvFavoriteRow({
    required this.items,
    required this.compactHeight,
    required this.onOpen,
  });

  final List<FavoriteEntry> items;
  final bool compactHeight;
  final ValueChanged<FavoriteEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    return _TvHorizontalRow(
      height: compactHeight ? 176 : 218,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _TvPosterCard(
          compactHeight: compactHeight,
          title: item.title,
          subtitle: item.subtitle,
          imageUrl: item.imageUrl,
          showFavoriteBadge: true,
          onPressed: () => onOpen(item),
        );
      },
    );
  }
}

class _TvMovieRow extends StatelessWidget {
  const _TvMovieRow({
    required this.groups,
    required this.compactHeight,
    required this.onOpen,
  });

  final List<MovieGroup> groups;
  final bool compactHeight;
  final ValueChanged<MovieGroup> onOpen;

  @override
  Widget build(BuildContext context) {
    return _TvHorizontalRow(
      height: compactHeight ? 176 : 218,
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final movie = group.primary;
        final metadata = [
          if (movie.displayYear.isNotEmpty) movie.displayYear,
          if (group.versionCount > 1) '${group.versionCount} versiones',
          if (movie.displayRating.isNotEmpty) '★ ${movie.displayRating}',
        ].join('  ');

        return _TvPosterCard(
          compactHeight: compactHeight,
          title: group.displayTitle,
          subtitle: metadata.isEmpty ? 'Película' : metadata,
          imageUrl: movie.posterUrl,
          onPressed: () => onOpen(group),
        );
      },
    );
  }
}

class _TvSeriesRow extends StatelessWidget {
  const _TvSeriesRow({
    required this.groups,
    required this.compactHeight,
    required this.onOpen,
  });

  final List<SeriesGroup> groups;
  final bool compactHeight;
  final ValueChanged<SeriesGroup> onOpen;

  @override
  Widget build(BuildContext context) {
    return _TvHorizontalRow(
      height: compactHeight ? 176 : 218,
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final series = group.primary;
        final metadata = [
          if (series.displayYear.isNotEmpty) series.displayYear,
          if (group.versionCount > 1) '${group.versionCount} versiones',
          if (series.displayRating.isNotEmpty) '★ ${series.displayRating}',
        ].join('  ');

        return _TvPosterCard(
          compactHeight: compactHeight,
          title: group.displayTitle,
          subtitle: metadata.isEmpty ? 'Serie' : metadata,
          imageUrl: series.coverUrl,
          onPressed: () => onOpen(group),
        );
      },
    );
  }
}

class _TvChannelRow extends StatelessWidget {
  const _TvChannelRow({
    required this.items,
    required this.compactHeight,
    required this.onOpen,
  });

  final List<FavoriteEntry> items;
  final bool compactHeight;
  final ValueChanged<FavoriteEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    return _TvHorizontalRow(
      height: compactHeight ? 116 : 138,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final channel = item.channel!;
        final variantCount = item.channelVariants.isEmpty
            ? 1
            : item.channelVariants.length;

        return SizedBox(
          width: compactHeight ? 152 : 178,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onOpen(item),
              borderRadius: BorderRadius.circular(18),
              child: Ink(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: const Color(0xFF111620),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF252D39)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: compactHeight ? 54 : 64,
                      height: compactHeight ? 54 : 64,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F4F7),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: _TvNetworkImage(
                        imageUrl: channel.iconUrl,
                        fit: BoxFit.contain,
                        fallback: const Icon(
                          Icons.live_tv_rounded,
                          color: Color(0xFF5B7CFF),
                          size: 30,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            channel.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            variantCount > 1
                                ? '$variantCount señales'
                                : 'En vivo',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF50D5B7),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TvHorizontalRow extends StatelessWidget {
  const _TvHorizontalRow({
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
  });

  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: itemCount,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

class _TvPosterCard extends StatelessWidget {
  const _TvPosterCard({
    required this.compactHeight,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.onPressed,
    this.progress,
    this.showPlayBadge = false,
    this.showFavoriteBadge = false,
  });

  final bool compactHeight;
  final String title;
  final String subtitle;
  final String imageUrl;
  final VoidCallback onPressed;
  final double? progress;
  final bool showPlayBadge;
  final bool showFavoriteBadge;

  @override
  Widget build(BuildContext context) {
    final width = compactHeight ? 116.0 : 144.0;

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _TvNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        fallback: const _TvPosterFallback(),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Color(0x22000000),
                              Color(0x99000000),
                            ],
                          ),
                        ),
                      ),
                      if (showPlayBadge)
                        const Positioned(
                          right: 8,
                          bottom: 8,
                          child: _TvRoundBadge(
                            icon: Icons.play_arrow_rounded,
                          ),
                        ),
                      if (showFavoriteBadge)
                        const Positioned(
                          right: 8,
                          top: 8,
                          child: _TvRoundBadge(
                            icon: Icons.favorite_rounded,
                            iconColor: Color(0xFFFF7285),
                          ),
                        ),
                      if (progress != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 5,
                            backgroundColor: const Color(0xAA000000),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF98A2B3),
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvRoundBadge extends StatelessWidget {
  const _TvRoundBadge({
    required this.icon,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xD9000000),
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: iconColor, size: 18),
      ),
    );
  }
}

class _TvNetworkImage extends StatelessWidget {
  const _TvNetworkImage({
    required this.imageUrl,
    required this.fit,
    required this.fallback,
  });

  final String imageUrl;
  final BoxFit fit;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl.trim();
    if (url.isEmpty) {
      return fallback;
    }

    return Image.network(
      url,
      fit: fit,
      cacheWidth: 520,
      cacheHeight: 760,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}

class _TvPosterFallback extends StatelessWidget {
  const _TvPosterFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF171D28),
      child: Center(
        child: Icon(
          Icons.play_circle_outline_rounded,
          color: Color(0xFF667085),
          size: 36,
        ),
      ),
    );
  }
}

class _TvInlineError extends StatelessWidget {
  const _TvInlineError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF291B20),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: Color(0xFFFF7D8A),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

class _TvDashboardLoading extends StatelessWidget {
  const _TvDashboardLoading({required this.compactHeight});

  final bool compactHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: compactHeight ? 230 : 316,
          decoration: BoxDecoration(
            color: const Color(0xFF111620),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFF252D39)),
          ),
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
        const SizedBox(height: 18),
        const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }
}
