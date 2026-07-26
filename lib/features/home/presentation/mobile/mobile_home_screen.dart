import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/models/catalog_overview.dart';
import '../../../../shared/models/iptv_category.dart';
import '../../../../shared/services/iptv_api_service.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/tv_focusable_surface.dart';
import '../../../auth/domain/auth_session.dart';
import '../../../downloads/data/offline_download_service.dart';
import '../../../downloads/presentation/mobile/mobile_downloads_screen.dart';
import '../../../favorites/data/local_library_service.dart';
import '../../../live_tv/presentation/mobile/mobile_live_tv_screen.dart';
import '../../../movies/domain/movie_group.dart';
import '../../../movies/domain/movie.dart';
import '../../../movies/presentation/mobile/mobile_movie_detail_screen.dart';
import '../../../movies/presentation/mobile/mobile_movies_screen.dart';
import '../../../player/presentation/mobile/mobile_live_player_screen.dart';
import '../../../player/presentation/mobile/mobile_movie_player_screen.dart';
import '../../../player/presentation/mobile/mobile_series_player_screen.dart';
import '../../../series/domain/series_group.dart';
import '../../../series/domain/tv_series.dart';
import '../../../series/presentation/mobile/mobile_series_detail_screen.dart';
import '../../../series/presentation/mobile/mobile_series_screen.dart';
import '../../../settings/presentation/mobile/mobile_settings_screen.dart';
import '../../../search/data/search_index_service.dart';
import '../../../search/presentation/tv/tv_global_search_screen.dart';

class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({
    required this.session,
    this.useSideNavigation = false,
    this.enableTvRemoteNavigation = false,
    super.key,
  });

  final AuthSession session;
  final bool useSideNavigation;
  final bool enableTvRemoteNavigation;

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  final IptvApiService _apiService = IptvApiService();
  final FdezSearchIndexService _searchIndexService = FdezSearchIndexService();
  final OfflineDownloadService _homeDownloadService =
      OfflineDownloadService.instance;
  final List<FocusNode> _tvNavigationFocusNodes = List<FocusNode>.generate(
    _sideNavigationItems.length,
    (index) => FocusNode(debugLabel: 'tv-navigation-$index'),
  );
  final FocusNode _tvSearchFocusNode =
      FocusNode(debugLabel: 'tv-navigation-global-search');

  late Future<CatalogOverview> _overview;
  int _selectedIndex = 0;
  int _dashboardRefreshToken = 0;
  final Set<int> _builtTabs = <int>{0};
  bool _hasActiveDownloads = false;

  @override
  void initState() {
    super.initState();
    _hasActiveDownloads = _homeDownloadService.activeTasks.value.isNotEmpty;
    _homeDownloadService.activeTasks.addListener(_handleHomeDownloadTasksChanged);
    _loadOverview();

    if (widget.enableTvRemoteNavigation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusSelectedTvNavigation();
        }
      });
    }
  }

  @override
  void dispose() {
    _homeDownloadService.activeTasks.removeListener(
      _handleHomeDownloadTasksChanged,
    );

    for (final focusNode in _tvNavigationFocusNodes) {
      focusNode.dispose();
    }
    _tvSearchFocusNode.dispose();

    super.dispose();
  }

  void _handleHomeDownloadTasksChanged() {
    if (!mounted) {
      return;
    }

    final hasActive = _homeDownloadService.activeTasks.value.isNotEmpty;
    if (_hasActiveDownloads == hasActive) {
      return;
    }

    setState(() {
      _hasActiveDownloads = hasActive;
    });
  }

  void _loadOverview() {
    _overview = _apiService.loadOverview(widget.session);
  }

  void _retryOverview() {
    setState(() {
      _loadOverview();
      _dashboardRefreshToken++;
    });
  }

  void _selectTab(int index) {
    if (!widget.useSideNavigation && index == 4) {
      unawaited(_openDownloadsFromNavigation());
      return;
    }

    if (_selectedIndex == index) {
      if (index == 0) {
        setState(() {
          _dashboardRefreshToken++;
        });
      }

      return;
    }

    setState(() {
      _selectedIndex = index;
      _builtTabs.add(index);

      if (index == 0) {
        _dashboardRefreshToken++;
      }
    });
  }

  bool get _tvNavigationHasFocus {
    return _tvNavigationFocusNodes.any((focusNode) => focusNode.hasFocus);
  }

  void _focusSelectedTvNavigation() {
    if (!widget.enableTvRemoteNavigation || !mounted) {
      return;
    }

    _tvNavigationFocusNodes[_selectedIndex].requestFocus();
  }

  void _focusTvContent() {
    final moved = FocusScope.of(context).focusInDirection(
      TraversalDirection.right,
    );

    if (!moved) {
      FocusScope.of(context).nextFocus();
    }
  }

  KeyEventResult _handleTvRemoteKey(
    FocusNode node,
    KeyEvent event,
  ) {
    if (!widget.enableTvRemoteNavigation || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isBackKey = key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.escape;

    if (isBackKey && !_tvNavigationHasFocus) {
      _focusSelectedTvNavigation();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _openDownloadsFromNavigation() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MobileDownloadsScreen(
          session: widget.session,
          enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
        ),
      ),
    );
  }

  void _openTvGlobalSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvGlobalSearchScreen(session: widget.session),
      ),
    );
  }

  Widget _buildContent() {
    _builtTabs.add(_selectedIndex);

    Widget lazyTab(int index, Widget child) {
      if (_builtTabs.contains(index) || _selectedIndex == index) {
        return child;
      }

      return const SizedBox.shrink();
    }

    return IndexedStack(
      index: _selectedIndex,
      children: [
        lazyTab(
          0,
          _MobileDashboard(
            session: widget.session,
            overview: _overview,
            onRetryOverview: _retryOverview,
            onOpenTab: _selectTab,
            refreshToken: _dashboardRefreshToken,
            enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
          ),
        ),
        lazyTab(
          1,
          MobileLiveTvScreen(
            session: widget.session,
            enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
          ),
        ),
        lazyTab(
          2,
          MobileMoviesScreen(
            session: widget.session,
            enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
          ),
        ),
        lazyTab(
          3,
          MobileSeriesScreen(
            session: widget.session,
            enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
          ),
        ),
        lazyTab(
          4,
          MobileSettingsScreen(
            session: widget.session,
            enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent();

    if (!widget.useSideNavigation) {
      return Scaffold(
        body: content,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _selectTab,
          destinations: _buildMobileNavigationDestinations(
            hasActiveDownloads: _hasActiveDownloads,
          ),
        ),
      );
    }

    final sideNavigation = widget.enableTvRemoteNavigation
        ? _TvRemoteSideNavigation(
            selectedIndex: _selectedIndex,
            focusNodes: _tvNavigationFocusNodes,
            searchFocusNode: _tvSearchFocusNode,
            onSelected: _selectTab,
            onMoveToContent: _focusTvContent,
            onOpenSearch: _openTvGlobalSearch,
          )
        : SafeArea(
            right: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final shortHeight = constraints.maxHeight < 520;

                return NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _selectTab,
                  minWidth: shortHeight ? 68 : 92,
                  groupAlignment: -0.15,
                  labelType: shortHeight
                      ? NavigationRailLabelType.selected
                      : NavigationRailLabelType.all,
                  useIndicator: true,
                  destinations: _sideNavigationDestinations,
                );
              },
            ),
          );

    final scaffold = Scaffold(
      body: Row(
        children: [
          sideNavigation,
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: content,
            ),
          ),
        ],
      ),
    );

    if (!widget.enableTvRemoteNavigation) {
      return scaffold;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !mounted) {
          return;
        }

        if (!_tvNavigationHasFocus) {
          _focusSelectedTvNavigation();
          return;
        }

        if (_selectedIndex != 0) {
          _selectTab(0);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _focusSelectedTvNavigation();
          });
          return;
        }

        _focusSelectedTvNavigation();
      },
      child: Theme(
        data: Theme.of(context).copyWith(
          focusColor: const Color(0x886F8CFF),
          hoverColor: const Color(0x336F8CFF),
          inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: kTvFocusNeonColor,
                width: 3.2,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF31384A)),
            ),
          ),
        ),
        child: Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          },
          child: Focus(
            onKeyEvent: _handleTvRemoteKey,
            child: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: scaffold,
            ),
          ),
        ),
      ),
    );
  }

}

class _TvNavigationItemData {
  const _TvNavigationItemData({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const List<_TvNavigationItemData> _sideNavigationItems = [
  _TvNavigationItemData(
    label: 'Inicio',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
  ),
  _TvNavigationItemData(
    label: 'TV',
    icon: Icons.live_tv_outlined,
    selectedIcon: Icons.live_tv_rounded,
  ),
  _TvNavigationItemData(
    label: 'Películas',
    icon: Icons.movie_outlined,
    selectedIcon: Icons.movie_rounded,
  ),
  _TvNavigationItemData(
    label: 'Series',
    icon: Icons.video_library_outlined,
    selectedIcon: Icons.video_library_rounded,
  ),
  _TvNavigationItemData(
    label: 'Ajustes',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
  ),
];

class _TvRemoteSideNavigation extends StatelessWidget {
  const _TvRemoteSideNavigation({
    required this.selectedIndex,
    required this.focusNodes,
    required this.searchFocusNode,
    required this.onSelected,
    required this.onMoveToContent,
    required this.onOpenSearch,
  });

  final int selectedIndex;
  final List<FocusNode> focusNodes;
  final FocusNode searchFocusNode;
  final ValueChanged<int> onSelected;
  final VoidCallback onMoveToContent;
  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      right: false,
      child: SizedBox(
        width: 178,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 18, 10, 18),
          child: Column(
            children: [
              _TvRemoteNavigationButton(
                focusNode: searchFocusNode,
                label: 'Buscar',
                icon: Icons.search_rounded,
                selected: false,
                onPressed: onOpenSearch,
                onMoveDown: () => focusNodes.first.requestFocus(),
                onMoveRight: onOpenSearch,
              ),
              const SizedBox(height: 22),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List<Widget>.generate(
                    _sideNavigationItems.length,
                    (index) {
                      final item = _sideNavigationItems[index];

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: _TvRemoteNavigationButton(
                          focusNode: focusNodes[index],
                          label: item.label,
                          icon: index == selectedIndex
                              ? item.selectedIcon
                              : item.icon,
                          selected: index == selectedIndex,
                          onPressed: () => onSelected(index),
                          onMoveUp: index > 0
                              ? () => focusNodes[index - 1].requestFocus()
                              : () => searchFocusNode.requestFocus(),
                          onMoveDown: index < focusNodes.length - 1
                              ? () => focusNodes[index + 1].requestFocus()
                              : null,
                          onMoveRight: onMoveToContent,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TvRemoteNavigationButton extends StatefulWidget {
  const _TvRemoteNavigationButton({
    required this.focusNode,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
    required this.onMoveRight,
    this.onMoveUp,
    this.onMoveDown,
  });

  final FocusNode focusNode;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback onMoveRight;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  State<_TvRemoteNavigationButton> createState() {
    return _TvRemoteNavigationButtonState();
  }
}

class _TvRemoteNavigationButtonState
    extends State<_TvRemoteNavigationButton> {
  bool _focused = false;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowUp && widget.onMoveUp != null) {
      widget.onMoveUp!();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown && widget.onMoveDown != null) {
      widget.onMoveDown!();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      widget.onMoveRight();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      widget.onPressed();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final highlighted = widget.selected || _focused;

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        if (_focused != focused) {
          setState(() {
            _focused = focused;
          });
        }
      },
      onKeyEvent: _handleKey,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          canRequestFocus: false,
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _focused
                  ? const Color(0xFF263B75)
                  : widget.selected
                      ? const Color(0xFF17213B)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _focused
                    ? kTvFocusNeonColor
                    : widget.selected
                        ? const Color(0xFF6F8CFF)
                        : const Color(0x33252C38),
                width: _focused ? 3.4 : 1,
              ),
              boxShadow: _focused
                  ? const [
                      BoxShadow(
                        color: kTvFocusGlowColor,
                        blurRadius: 24,
                        spreadRadius: 2.5,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  color: highlighted
                      ? const Color(0xFF8EA5FF)
                      : const Color(0xFF98A2B3),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: highlighted
                          ? Colors.white
                          : const Color(0xFFB4BBC6),
                      fontWeight: highlighted
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (_focused)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF8EA5FF),
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<NavigationDestination> _buildMobileNavigationDestinations({
  required bool hasActiveDownloads,
}) {
  Widget downloadsIcon(IconData icon, {required bool selected}) {
    final content = Icon(icon);

    if (!hasActiveDownloads) {
      return content;
    }

    return Badge(
      smallSize: 8,
      backgroundColor: const Color(0xFF39FFB6),
      alignment: Alignment.topRight,
      offset: const Offset(2, -2),
      child: content,
    );
  }

  return [
    const NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Inicio',
    ),
    const NavigationDestination(
      icon: Icon(Icons.live_tv_outlined),
      selectedIcon: Icon(Icons.live_tv_rounded),
      label: 'TV',
    ),
    const NavigationDestination(
      icon: Icon(Icons.movie_outlined),
      selectedIcon: Icon(Icons.movie_rounded),
      label: 'Películas',
    ),
    const NavigationDestination(
      icon: Icon(Icons.video_library_outlined),
      selectedIcon: Icon(Icons.video_library_rounded),
      label: 'Series',
    ),
    NavigationDestination(
      icon: downloadsIcon(Icons.download_outlined, selected: false),
      selectedIcon: downloadsIcon(Icons.download_rounded, selected: true),
      label: 'Descargas',
    ),
  ];
}

const List<NavigationRailDestination> _sideNavigationDestinations = [
  NavigationRailDestination(
    icon: Icon(Icons.home_outlined),
    selectedIcon: Icon(Icons.home_rounded),
    label: Text('Inicio'),
  ),
  NavigationRailDestination(
    icon: Icon(Icons.live_tv_outlined),
    selectedIcon: Icon(Icons.live_tv_rounded),
    label: Text('TV'),
  ),
  NavigationRailDestination(
    icon: Icon(Icons.movie_outlined),
    selectedIcon: Icon(Icons.movie_rounded),
    label: Text('Películas'),
  ),
  NavigationRailDestination(
    icon: Icon(Icons.video_library_outlined),
    selectedIcon: Icon(Icons.video_library_rounded),
    label: Text('Series'),
  ),
  NavigationRailDestination(
    icon: Icon(Icons.settings_outlined),
    selectedIcon: Icon(Icons.settings_rounded),
    label: Text('Ajustes'),
  ),
];

class _MobileDashboard extends StatefulWidget {
  const _MobileDashboard({
    required this.session,
    required this.overview,
    required this.onRetryOverview,
    required this.onOpenTab,
    required this.refreshToken,
    required this.enableTvRemoteNavigation,
  });

  final AuthSession session;
  final Future<CatalogOverview> overview;
  final VoidCallback onRetryOverview;
  final ValueChanged<int> onOpenTab;
  final int refreshToken;
  final bool enableTvRemoteNavigation;

  @override
  State<_MobileDashboard> createState() => _MobileDashboardState();
}

class _MobileDashboardState extends State<_MobileDashboard> {
  final IptvApiService _apiService = IptvApiService();
  final FdezSearchIndexService _searchIndexService = FdezSearchIndexService();
  final OfflineDownloadService _homeDownloadService =
      OfflineDownloadService.instance;
  final LocalLibraryService _libraryService = LocalLibraryService.instance;
  final OfflineDownloadService _downloadService =
      OfflineDownloadService.instance;

  LocalLibrarySnapshot? _library;
  CatalogOverview? _catalog;

  List<MovieGroup> _recommendedMovies = const [];
  List<MovieGroup> _trendingMovies = const [];
  List<MovieGroup> _recentMovies = const [];
  List<SeriesGroup> _recommendedSeries = const [];
  List<SeriesGroup> _trendingSeries = const [];
  List<OfflineDownloadEntry> _downloads = const [];
  List<OfflineDownloadTaskSnapshot> _activeDownloadTasks = const [];

  bool _loading = true;
  bool _refreshing = false;
  String? _errorMessage;
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.enableTvRemoteNavigation) {
      _activeDownloadTasks = _downloadService.activeTasks.value;
      _downloadService.activeTasks.addListener(_handleActiveDownloadsChanged);
    }
    unawaited(_loadDashboard());
  }

  @override
  void dispose() {
    _downloadService.activeTasks.removeListener(_handleActiveDownloadsChanged);
    super.dispose();
  }

  void _handleActiveDownloadsChanged() {
    if (widget.enableTvRemoteNavigation || !mounted) {
      return;
    }

    setState(() {
      _activeDownloadTasks = _downloadService.activeTasks.value;
    });

    unawaited(_reloadDownloads());
  }

  @override
  void didUpdateWidget(covariant _MobileDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.refreshToken != widget.refreshToken ||
        oldWidget.overview != widget.overview) {
      unawaited(_loadDashboard(showMainLoading: false));
    }
  }

  Future<void> _loadDashboard({bool showMainLoading = true}) async {
    final loadId = ++_loadId;

    if (showMainLoading && mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final libraryFuture = _libraryService.load(widget.session);
      final catalogFuture = widget.overview;
      final downloadsFuture = widget.enableTvRemoteNavigation
          ? Future<List<OfflineDownloadEntry>>.value(const <OfflineDownloadEntry>[])
          : _downloadService.loadDownloads(widget.session);

      final library = await libraryFuture;
      final catalog = await catalogFuture;
      final downloads = await downloadsFuture;

      if (!mounted || loadId != _loadId) {
        return;
      }

      List<MovieGroup> movies = const [];
      List<MovieGroup> trendingMovies = const [];
      List<MovieGroup> recentMovies = const [];
      List<SeriesGroup> series = const [];
      List<SeriesGroup> trendingSeries = const [];

      if (catalog.movieCategories.isNotEmpty) {
        try {
          final category = _pickHomeCategory(catalog.movieCategories);
          final loadedMovies = await _apiService.loadMovies(
            widget.session,
            categoryId: category.id,
          );

          final groupedMovies = groupMovies(loadedMovies);
          movies = groupedMovies.take(12).toList(growable: false);
          trendingMovies = _sortMovieGroupsByRating(groupedMovies)
              .take(10)
              .toList(growable: false);
          recentMovies = _sortMovieGroupsByRecent(groupedMovies)
              .take(12)
              .toList(growable: false);
        } catch (_) {
          movies = const [];
          trendingMovies = const [];
          recentMovies = const [];
        }
      }

      if (catalog.seriesCategories.isNotEmpty) {
        try {
          final category = _pickHomeCategory(catalog.seriesCategories);
          final loadedSeries = await _apiService.loadSeries(
            widget.session,
            categoryId: category.id,
          );

          final groupedSeries = groupSeries(loadedSeries);
          series = groupedSeries.take(12).toList(growable: false);
          trendingSeries = _sortSeriesGroupsByRating(groupedSeries)
              .take(10)
              .toList(growable: false);
        } catch (_) {
          series = const [];
          trendingSeries = const [];
        }
      }

      if (!mounted || loadId != _loadId) {
        return;
      }

      setState(() {
        _library = library;
        _catalog = catalog;
        _recommendedMovies = movies;
        _trendingMovies = trendingMovies;
        _recentMovies = recentMovies;
        _recommendedSeries = series;
        _trendingSeries = trendingSeries;
        _downloads = widget.enableTvRemoteNavigation
            ? const <OfflineDownloadEntry>[]
            : downloads;
        _activeDownloadTasks = widget.enableTvRemoteNavigation
            ? const <OfflineDownloadTaskSnapshot>[]
            : _downloadService.activeTasks.value;
        _loading = false;
        _refreshing = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted || loadId != _loadId) {
        return;
      }

      setState(() {
        _loading = false;
        _refreshing = false;
        _errorMessage = 'No fue posible actualizar el Inicio.';
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

    widget.onRetryOverview();
  }

  Future<void> _openProgress(WatchProgressEntry item) async {
    if (item.movie != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => MobileMoviePlayerScreen(
            session: widget.session,
            movie: item.movie!,
            initialPosition: item.position,
            enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
          ),
        ),
      );
    } else if (item.series != null &&
        item.episodes.isNotEmpty &&
        item.currentIndex >= 0 &&
        item.currentIndex < item.episodes.length) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => MobileSeriesPlayerScreen(
            session: widget.session,
            series: item.series!,
            seasonName: item.seasonName,
            episodes: item.episodes,
            initialIndex: item.currentIndex,
            initialPosition: item.position,
            enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
          ),
        ),
      );
    }

    if (mounted) {
      await _reloadLibrary();
    }
  }

  Future<void> _openProgressDetails(WatchProgressEntry item) async {
    if (item.movie != null) {
      await _openMovie(item.movie!);
      return;
    }

    if (item.series != null) {
      await _openSeries(item.series!);
    }
  }

  Future<void> _openFavorite(FavoriteEntry item) async {
    if (item.channel != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => MobileLivePlayerScreen(
            session: widget.session,
            channel: item.channel!,
            channelVariants: item.channelVariants,
          ),
        ),
      );

      if (mounted) {
        await _reloadLibrary();
      }

      return;
    }

    if (item.movie != null) {
      await _openMovie(item.movie!);
      return;
    }

    if (item.series != null) {
      await _openSeries(item.series!);
    }
  }

  Future<void> _openMovie(Movie movie) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MobileMovieDetailScreen(
          session: widget.session,
          movie: movie,
          enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
        ),
      ),
    );

    if (mounted) {
      await _reloadLibrary();
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
          enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
        ),
      ),
    );

    if (mounted) {
      await _reloadLibrary();
    }
  }

  Future<void> _openSeries(TvSeries series) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MobileSeriesDetailScreen(
          session: widget.session,
          series: series,
          enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
        ),
      ),
    );

    if (mounted) {
      await _reloadLibrary();
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
          enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
        ),
      ),
    );

    if (mounted) {
      await _reloadLibrary();
    }
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
      // El contenido principal puede seguir mostrándose.
    }
  }

  Future<void> _reloadDownloads() async {
    if (widget.enableTvRemoteNavigation) {
      return;
    }

    try {
      final downloads = await _downloadService.loadDownloads(widget.session);

      if (!mounted) {
        return;
      }

      setState(() {
        _downloads = downloads;
      });
    } catch (_) {
      // El inicio puede seguir funcionando aunque no se lea la lista local.
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MobileSettingsScreen(
          session: widget.session,
          enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
        ),
      ),
    );
  }

  Future<void> _openDownloads() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MobileDownloadsScreen(
          session: widget.session,
          enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
        ),
      ),
    );

    if (mounted) {
      await _reloadDownloads();
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _library?.progress ?? const <WatchProgressEntry>[];
    final favorites = _library?.favorites ?? const <FavoriteEntry>[];
    final channelFavorites = favorites
        .where((item) => item.channel != null)
        .toList(growable: false);
    final mediaFavorites = favorites
        .where((item) => item.movie != null || item.series != null)
        .toList(growable: false);

    final isTvLayout = widget.enableTvRemoteNavigation;
    final horizontalPadding = isTvLayout ? 26.0 : 20.0;
    final topPadding = isTvLayout ? 10.0 : 18.0;

    return SafeArea(
      bottom: false,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF080C14),
              Color(0xFF0B1020),
              Color(0xFF070A10),
            ],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              topPadding,
              horizontalPadding,
              38,
            ),
            children: [
              _DashboardHeader(
                username: widget.session.username,
                isActive: widget.session.isActive,
                showSettingsButton: !isTvLayout,
                onSettings: () {
                  unawaited(_openSettings());
                },
              ),
              SizedBox(height: isTvLayout ? 12 : 20),
              if (_loading && _library == null)
                const _DashboardLoading()
              else ...[
                _RotatingHomeHero(
                  movieGroups: (_recentMovies.isNotEmpty
                          ? _recentMovies
                          : _trendingMovies)
                      .take(5)
                      .toList(growable: false),
                  seriesGroups: const [],
                  progressFallback: progress.isEmpty ? null : progress.first,
                  onMovieDetails: (group) {
                    unawaited(_openMovieGroup(group));
                  },
                  onSeriesDetails: (group) {
                    unawaited(_openSeriesGroup(group));
                  },
                  onContinue: (item) {
                    unawaited(_openProgress(item));
                  },
                  onProgressDetails: (item) {
                    unawaited(_openProgressDetails(item));
                  },
                  onOpenTv: () => widget.onOpenTab(1),
                  compactForTv: isTvLayout,
                ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                _CompactErrorCard(
                  message: _errorMessage!,
                  onRetry: () {
                    unawaited(_loadDashboard());
                  },
                ),
              ],
              if (progress.isNotEmpty) ...[
                SizedBox(height: isTvLayout ? 18 : 30),
                const _SectionTitle(
                  title: 'Continuar viendo',
                  subtitle: 'Retoma exactamente desde donde te quedaste',
                ),
                const SizedBox(height: 14),
                _ProgressRow(
                  items: progress.take(10).toList(growable: false),
                  enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
                  onOpen: (item) {
                    unawaited(_openProgress(item));
                  },
                ),
              ],
              if (_trendingMovies.isNotEmpty) ...[
                SizedBox(height: isTvLayout ? 18 : 30),
                _SectionTitle(
                  title: 'Películas en tendencia',
                  subtitle: 'Las películas más destacadas de tu lista',
                  actionLabel: 'Ver más',
                  onAction: () => widget.onOpenTab(2),
                ),
                const SizedBox(height: 14),
                _RankedMovieRow(
                  groups: _trendingMovies,
                  enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
                  onOpen: (group) {
                    unawaited(_openMovieGroup(group));
                  },
                ),
              ],
              if (_trendingSeries.isNotEmpty) ...[
                SizedBox(height: isTvLayout ? 18 : 30),
                _SectionTitle(
                  title: 'Series en tendencia',
                  subtitle: 'Series destacadas de tu catálogo',
                  actionLabel: 'Ver todas',
                  onAction: () => widget.onOpenTab(3),
                ),
                const SizedBox(height: 14),
                _RankedSeriesRow(
                  groups: _trendingSeries,
                  enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
                  onOpen: (group) {
                    unawaited(_openSeriesGroup(group));
                  },
                ),
              ],
            ],
          ],
        ),
      ),
    ),
  );
  }
}


IptvCategory _pickHomeCategory(List<IptvCategory> categories) {
  for (final category in categories) {
    final normalized = _normalizeHomeText(category.name);
    if (normalized.contains('new release') ||
        normalized.contains('estreno') ||
        normalized.contains('reciente') ||
        normalized.contains('recent') ||
        normalized.contains('added') ||
        normalized.contains('novedad')) {
      return category;
    }
  }

  return categories.first;
}

List<MovieGroup> _sortMovieGroupsByRating(List<MovieGroup> groups) {
  final result = List<MovieGroup>.from(groups);
  result.sort((a, b) {
    final ratingCompare = _movieRating(b).compareTo(_movieRating(a));
    if (ratingCompare != 0) {
      return ratingCompare;
    }

    return a.displayTitle.compareTo(b.displayTitle);
  });
  return result;
}

List<MovieGroup> _sortMovieGroupsByRecent(List<MovieGroup> groups) {
  final result = List<MovieGroup>.from(groups);
  result.sort((a, b) {
    final yearCompare = _movieYearValue(b).compareTo(_movieYearValue(a));
    if (yearCompare != 0) {
      return yearCompare;
    }

    return a.displayTitle.compareTo(b.displayTitle);
  });
  return result;
}

List<SeriesGroup> _sortSeriesGroupsByRating(List<SeriesGroup> groups) {
  final result = List<SeriesGroup>.from(groups);
  result.sort((a, b) {
    final ratingCompare = _seriesRating(b).compareTo(_seriesRating(a));
    if (ratingCompare != 0) {
      return ratingCompare;
    }

    return a.displayTitle.compareTo(b.displayTitle);
  });
  return result;
}

double _movieRating(MovieGroup group) {
  return double.tryParse(
        group.primary.rating.replaceAll(',', '.').trim(),
      ) ??
      0;
}

double _seriesRating(SeriesGroup group) {
  return double.tryParse(
        group.primary.rating.replaceAll(',', '.').trim(),
      ) ??
      0;
}

int _movieYearValue(MovieGroup group) {
  final text = [
    group.primary.displayYear,
    group.primary.releaseDate,
    group.year,
  ].join(' ');
  final match = RegExp(r'(?:19|20)\d{2}').firstMatch(text);
  return int.tryParse(match?.group(0) ?? '') ?? 0;
}

String _normalizeHomeText(String value) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñ';
  const to = 'aaaaaeeeeiiiiooooouuuun';
  var result = value.toLowerCase().trim();
  for (var i = 0; i < from.length; i++) {
    result = result.replaceAll(from[i], to[i]);
  }

  return result.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.username,
    required this.isActive,
    required this.onSettings,
    this.showSettingsButton = true,
  });

  final String username;
  final bool isActive;
  final VoidCallback onSettings;
  final bool showSettingsButton;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF6F8CFF),
                Color(0xFF415FD0),
              ],
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 31,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'FdezPlay',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Hola, $username',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF98A2B3),
                ),
              ),
            ],
          ),
        ),
        if (showSettingsButton) ...[
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Ajustes',
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ],
    );
  }
}



class _TvCompactHomeHeroCard extends StatelessWidget {
  const _TvCompactHomeHeroCard({required this.entry});

  final _HomeHeroEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 108,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF101626),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x334C6DFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF6F8CFF),
                  Color(0xFF1B2C6F),
                ],
              ),
            ),
            child: const Icon(
              Icons.new_releases_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x2239FFB6),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0x6639FFB6)),
                      ),
                      child: Text(
                        entry.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8DFFD9),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (entry.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    entry.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB9C2D3),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFF8EA5FF),
            size: 30,
          ),
        ],
      ),
    );
  }
}

class _HomeHeroEntry {
  const _HomeHeroEntry({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.imageUrl,
    required this.primaryLabel,
    required this.onPrimary,
    this.onDetails,
  });

  final String label;
  final String title;
  final String subtitle;
  final String description;
  final String imageUrl;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback? onDetails;
}

class _RotatingHomeHero extends StatefulWidget {
  const _RotatingHomeHero({
    required this.movieGroups,
    required this.seriesGroups,
    required this.progressFallback,
    required this.onMovieDetails,
    required this.onSeriesDetails,
    required this.onContinue,
    required this.onProgressDetails,
    required this.onOpenTv,
    this.compactForTv = false,
  });

  final List<MovieGroup> movieGroups;
  final List<SeriesGroup> seriesGroups;
  final WatchProgressEntry? progressFallback;
  final ValueChanged<MovieGroup> onMovieDetails;
  final ValueChanged<SeriesGroup> onSeriesDetails;
  final ValueChanged<WatchProgressEntry> onContinue;
  final ValueChanged<WatchProgressEntry> onProgressDetails;
  final VoidCallback onOpenTv;
  final bool compactForTv;

  @override
  State<_RotatingHomeHero> createState() => _RotatingHomeHeroState();
}

class _RotatingHomeHeroState extends State<_RotatingHomeHero> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _RotatingHomeHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCount = _buildEntries(oldWidget).length;
    final newCount = _buildEntries(widget).length;

    if (oldCount != newCount) {
      _index = 0;
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();

    // En Android TV dejamos la card superior fija para evitar que el
    // AnimatedSwitcher cambie imágenes grandes mientras el usuario navega con
    // el control remoto. Esto reduce trabas y consumo de memoria.
    if (widget.compactForTv) {
      return;
    }

    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted) {
        return;
      }

      final count = _buildEntries(widget).length;
      if (count <= 1) {
        return;
      }

      setState(() {
        _index = (_index + 1) % count;
      });
    });
  }

  List<_HomeHeroEntry> _buildEntries(_RotatingHomeHero source) {
    final entries = <_HomeHeroEntry>[];

    for (final group in source.movieGroups.take(5)) {
      final movie = group.primary;
      final subtitleParts = <String>[
        if (movie.displayYear.isNotEmpty) movie.displayYear,
        if (movie.genre.isNotEmpty) movie.genre,
        if (movie.displayRating.isNotEmpty) '★ ${movie.displayRating}',
      ];

      entries.add(
        _HomeHeroEntry(
          label: 'RECIÉN AGREGADO',
          title: group.displayTitle,
          subtitle: subtitleParts.join(' • '),
          description: _shortText(movie.plot),
          imageUrl: movie.backdropUrl.isNotEmpty
              ? movie.backdropUrl
              : movie.posterUrl,
          primaryLabel: 'Ver ahora',
          onPrimary: () => source.onMovieDetails(group),
          onDetails: () => source.onMovieDetails(group),
        ),
      );
    }

    if (entries.length < 5) {
      for (final group in source.seriesGroups.take(5 - entries.length)) {
        final series = group.primary;
        final subtitleParts = <String>[
          if (series.displayYear.isNotEmpty) series.displayYear,
          if (series.genre.isNotEmpty) series.genre,
          if (series.displayRating.isNotEmpty) '★ ${series.displayRating}',
        ];

        entries.add(
          _HomeHeroEntry(
            label: 'SERIE EN TENDENCIA',
            title: group.displayTitle,
            subtitle: subtitleParts.join(' • '),
            description: _shortText(series.plot),
            imageUrl: series.backdropUrl.isNotEmpty
                ? series.backdropUrl
                : series.coverUrl,
            primaryLabel: 'Ver serie',
            onPrimary: () => source.onSeriesDetails(group),
            onDetails: () => source.onSeriesDetails(group),
          ),
        );
      }
    }

    final progress = source.progressFallback;
    if (entries.isEmpty && progress != null) {
      entries.add(
        _HomeHeroEntry(
          label: 'CONTINUAR VIENDO',
          title: progress.title,
          subtitle: progress.subtitle,
          description: 'Retoma el contenido exactamente desde donde te quedaste.',
          imageUrl: progress.movie?.backdropUrl.isNotEmpty == true
              ? progress.movie!.backdropUrl
              : progress.series?.backdropUrl.isNotEmpty == true
                  ? progress.series!.backdropUrl
                  : progress.imageUrl,
          primaryLabel: 'Continuar',
          onPrimary: () => source.onContinue(progress),
          onDetails: () => source.onProgressDetails(progress),
        ),
      );
    }

    if (entries.isEmpty) {
      entries.add(
        _HomeHeroEntry(
          label: 'FDEZPLAY',
          title: 'Todo tu entretenimiento en un solo lugar',
          subtitle: 'TV en vivo • Películas • Series',
          description: 'Explora tu catálogo y encuentra contenido para ver al instante.',
          imageUrl: '',
          primaryLabel: 'Ver TV',
          onPrimary: source.onOpenTv,
        ),
      );
    }

    return entries;
  }

  static String _shortText(String value) {
    final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) {
      return 'Recomendación destacada de tu catálogo.';
    }

    if (cleaned.length <= 155) {
      return cleaned;
    }

    return '${cleaned.substring(0, 152).trimRight()}...';
  }

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries(widget);
    final safeIndex = entries.isEmpty
        ? 0
        : _index.clamp(0, entries.length - 1).toInt();
    final entry = entries[safeIndex];

    if (widget.compactForTv) {
      return _TvCompactHomeHeroCard(entry: entry);
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 900;
    final compactForTv = widget.compactForTv;
    final heroHeight = compactForTv ? 236.0 : (isWide ? 410.0 : 286.0);
    final heroRadius = compactForTv ? 24.0 : (isWide ? 34.0 : 28.0);
    final heroPadding = compactForTv ? 24.0 : (isWide ? 34.0 : 22.0);
    final titleSize = compactForTv ? 32.0 : (isWide ? 48.0 : 30.0);
    final subtitleSize = compactForTv ? 13.0 : (isWide ? 15.0 : 12.5);
    final descriptionSize = compactForTv ? 12.5 : (isWide ? 14.0 : 12.0);
    final imageCacheWidth = compactForTv ? 960 : (isWide ? 1600 : 900);
    final imageCacheHeight = compactForTv ? 540 : (isWide ? 900 : 520);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: Container(
        key: ValueKey('${entry.label}-${entry.title}-$safeIndex'),
        height: heroHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF101626),
          borderRadius: BorderRadius.circular(heroRadius),
          border: Border.all(color: const Color(0x334C6DFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 34,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (entry.imageUrl.isNotEmpty)
              AppCachedImage(
                imageUrl: entry.imageUrl,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                cacheWidth: imageCacheWidth,
                cacheHeight: imageCacheHeight,
                fallback: const _HeroFallback(),
              )
            else
              const _HeroFallback(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x22000000),
                    Color(0x70000000),
                    Color(0xF40A0D14),
                  ],
                  stops: [0, 0.46, 1],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(heroPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  _HeroLabel(
                    icon: Icons.auto_awesome_rounded,
                    text: entry.label,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: titleSize,
                      height: 1.03,
                      fontWeight: FontWeight.w900,
                      shadows: const [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  if (entry.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      entry.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFFE3E7EF),
                        fontSize: subtitleSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 9),
                  Text(
                    entry.description,
                    maxLines: compactForTv ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFFD2DAE8),
                      fontSize: descriptionSize,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (!compactForTv) ...[
                    const SizedBox(height: 17),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: entry.onPrimary,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(entry.primaryLabel),
                        ),
                        if (entry.onDetails != null) ...[
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: entry.onDetails,
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
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (entries.length > 1)
              Positioned(
                right: isWide ? 30 : 22,
                bottom: isWide ? 30 : 22,
                child: Row(
                  children: List<Widget>.generate(entries.length, (index) {
                    final active = index == safeIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 20 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFF9CB0FF)
                            : const Color(0x66FFFFFF),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DynamicHero extends StatelessWidget {
  const _DynamicHero({
    required this.progress,
    required this.fallbackMovieGroup,
    required this.onContinue,
    required this.onProgressDetails,
    required this.onMovieDetails,
    required this.onOpenTv,
  });

  final WatchProgressEntry? progress;
  final MovieGroup? fallbackMovieGroup;
  final ValueChanged<WatchProgressEntry> onContinue;
  final ValueChanged<WatchProgressEntry> onProgressDetails;
  final ValueChanged<MovieGroup> onMovieDetails;
  final VoidCallback onOpenTv;

  @override
  Widget build(BuildContext context) {
    final progressItem = progress;
    final movieGroup = fallbackMovieGroup;
    final movie = movieGroup?.primary;

    final String title;
    final String subtitle;
    final String imageUrl;
    final double? progressValue;
    final String primaryLabel;

    if (progressItem != null) {
      title = progressItem.title;
      subtitle = progressItem.subtitle;
      imageUrl = progressItem.movie?.backdropUrl.isNotEmpty == true
          ? progressItem.movie!.backdropUrl
          : progressItem.series?.backdropUrl.isNotEmpty == true
              ? progressItem.series!.backdropUrl
              : progressItem.imageUrl;
      progressValue = progressItem.progress;
      primaryLabel = 'Continuar';
    } else if (movie != null) {
      title = movieGroup?.displayTitle ?? movie.name;
      subtitle = [
        if (movie.displayYear.isNotEmpty) movie.displayYear,
        if (movie.genre.isNotEmpty) movie.genre,
      ].join(' • ');
      imageUrl = movie.backdropUrl.isNotEmpty
          ? movie.backdropUrl
          : movie.posterUrl;
      progressValue = null;
      primaryLabel = 'Ver detalles';
    } else {
      title = 'TV en vivo, películas y series';
      subtitle = 'Todo tu entretenimiento en un solo lugar';
      imageUrl = '';
      progressValue = null;
      primaryLabel = 'Ver TV';
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 900;

    return Container(
      height: isWide ? 390 : 270,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF101626),
        borderRadius: BorderRadius.circular(isWide ? 34 : 28),
        border: Border.all(color: const Color(0x334C6DFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 34,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl.isNotEmpty)
            AppCachedImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              cacheWidth: isWide ? 1600 : 900,
              cacheHeight: isWide ? 900 : 520,
              fallback: const _HeroFallback(),
            )
          else
            const _HeroFallback(),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x22000000),
                  Color(0x70000000),
                  Color(0xF20A0D14),
                ],
                stops: [0, 0.45, 1],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(isWide ? 34 : 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                if (progressItem != null)
                  const _HeroLabel(
                    icon: Icons.play_circle_outline_rounded,
                    text: 'CONTINUAR VIENDO',
                  )
                else if (movie != null)
                  const _HeroLabel(
                    icon: Icons.auto_awesome_rounded,
                    text: 'DESTACADA',
                  )
                else
                  const _HeroLabel(
                    icon: Icons.live_tv_rounded,
                    text: 'FDEZPLAY',
                  ),
                const SizedBox(height: 10),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isWide ? 46 : 27,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFFE3E7EF),
                      fontSize: isWide ? 15 : 12.5,
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
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () {
                        if (progressItem != null) {
                          onContinue(progressItem);
                        } else if (movie != null) {
                          onMovieDetails(movieGroup!);
                        } else {
                          onOpenTv();
                        }
                      },
                      icon: Icon(
                        progressItem != null
                            ? Icons.play_arrow_rounded
                            : movie != null
                                ? Icons.info_outline_rounded
                                : Icons.live_tv_rounded,
                      ),
                      label: Text(primaryLabel),
                    ),
                    if (progressItem != null) ...[
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          onProgressDetails(progressItem);
                        },
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
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroLabel extends StatelessWidget {
  const _HeroLabel({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF9CB0FF), size: 16),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFFD8E0FF),
            fontSize: 10.5,
            letterSpacing: 0.9,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _HeroFallback extends StatelessWidget {
  const _HeroFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF293F91),
            Color(0xFF17234F),
            Color(0xFF0C101C),
          ],
        ),
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: EdgeInsets.only(right: 18),
          child: Icon(
            Icons.play_circle_fill_rounded,
            size: 148,
            color: Color(0x245B7CFF),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
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
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF98A2B3),
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          _SectionActionButton(
            label: actionLabel!,
            onPressed: onAction!,
          ),
      ],
    );
  }
}


class _SectionActionButton extends StatelessWidget {
  const _SectionActionButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.arrow_forward_rounded, size: 17),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFD8E2FF),
        backgroundColor: const Color(0x1A7B91FF),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: const BorderSide(color: Color(0x336F8CFF)),
        ),
      ),
    );
  }
}

class _PremiumShortcutStrip extends StatelessWidget {
  const _PremiumShortcutStrip({
    required this.catalog,
    required this.enableTvRemoteNavigation,
    required this.onOpenTab,
  });

  final CatalogOverview? catalog;
  final bool enableTvRemoteNavigation;
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final items = [
      _PremiumShortcutData(
        icon: Icons.live_tv_rounded,
        title: 'TV en vivo',
        subtitle: '${catalog?.liveCategoryCount ?? 0} categorías',
        colors: const [Color(0xFF143B5C), Color(0xFF0C1D35)],
        accent: const Color(0xFF58D8FF),
        index: 1,
      ),
      _PremiumShortcutData(
        icon: Icons.movie_creation_rounded,
        title: 'Películas',
        subtitle: '${catalog?.movieCategoryCount ?? 0} categorías',
        colors: const [Color(0xFF3A2464), Color(0xFF19122E)],
        accent: const Color(0xFFC89BFF),
        index: 2,
      ),
      _PremiumShortcutData(
        icon: Icons.video_library_rounded,
        title: 'Series',
        subtitle: '${catalog?.seriesCategoryCount ?? 0} categorías',
        colors: const [Color(0xFF55331E), Color(0xFF21130C)],
        accent: const Color(0xFFFFB16E),
        index: 3,
      ),
    ];

    if (isWide) {
      return Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            Expanded(
              child: _PremiumShortcutCard(
                data: items[i],
                enableTvRemoteNavigation: enableTvRemoteNavigation,
                onPressed: () => onOpenTab(items[i].index),
              ),
            ),
            if (i < items.length - 1) const SizedBox(width: 14),
          ],
        ],
      );
    }

    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return SizedBox(
            width: 188,
            child: _PremiumShortcutCard(
              data: items[index],
              enableTvRemoteNavigation: enableTvRemoteNavigation,
              onPressed: () => onOpenTab(items[index].index),
            ),
          );
        },
      ),
    );
  }
}

class _PremiumShortcutData {
  const _PremiumShortcutData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.accent,
    required this.index,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final Color accent;
  final int index;
}

class _PremiumShortcutCard extends StatelessWidget {
  const _PremiumShortcutCard({
    required this.data,
    required this.enableTvRemoteNavigation,
    required this.onPressed,
  });

  final _PremiumShortcutData data;
  final bool enableTvRemoteNavigation;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      height: 104,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: data.colors,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: data.accent.withOpacity(0.24)),
        boxShadow: [
          BoxShadow(
            color: data.accent.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: data.accent.withOpacity(0.18),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(data.icon, color: data.accent, size: 25),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFBFC7D5),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_rounded, color: data.accent, size: 20),
        ],
      ),
    );

    return TvFocusableSurface(
      enabled: enableTvRemoteNavigation,
      borderRadius: BorderRadius.circular(22),
      onPressed: onPressed,
      builder: (context, focused) => card,
    );
  }
}

class _QuickAccessRow extends StatelessWidget {
  const _QuickAccessRow({
    required this.catalog,
    required this.onOpenTab,
  });

  final CatalogOverview? catalog;
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickAccessCard(
            icon: Icons.live_tv_rounded,
            title: 'TV',
            subtitle: '${catalog?.liveCategoryCount ?? 0} categorías',
            background: const Color(0xFF153630),
            foreground: const Color(0xFF50D5B7),
            onPressed: () => onOpenTab(1),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickAccessCard(
            icon: Icons.movie_creation_rounded,
            title: 'Películas',
            subtitle: '${catalog?.movieCategoryCount ?? 0} categorías',
            background: const Color(0xFF302342),
            foreground: const Color(0xFFC7A0FF),
            onPressed: () => onOpenTab(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickAccessCard(
            icon: Icons.video_library_rounded,
            title: 'Series',
            subtitle: '${catalog?.seriesCategoryCount ?? 0} categorías',
            background: const Color(0xFF3D2A22),
            foreground: const Color(0xFFFFA66B),
            onPressed: () => onOpenTab(3),
          ),
        ),
      ],
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  const _QuickAccessCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 106,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFF111620),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF232A36)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: foreground, size: 21),
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
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


class _DownloadsPreviewRow extends StatelessWidget {
  const _DownloadsPreviewRow({
    required this.activeTasks,
    required this.downloads,
    required this.onOpenDownloads,
  });

  final List<OfflineDownloadTaskSnapshot> activeTasks;
  final List<OfflineDownloadEntry> downloads;
  final VoidCallback onOpenDownloads;

  @override
  Widget build(BuildContext context) {
    final itemCount = activeTasks.length + downloads.length + 1;

    return SizedBox(
      height: 166,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: itemCount,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          if (index < activeTasks.length) {
            final task = activeTasks[index];

            return _DownloadPreviewCard(
              title: task.title,
              subtitle: task.subtitle.isEmpty
                  ? (task.isMovie ? 'Película' : 'Episodio')
                  : task.subtitle,
              imageUrl: task.imageUrl,
              progress: task.progress,
              badgeIcon: task.hasError
                  ? Icons.error_outline_rounded
                  : task.isPaused
                      ? Icons.pause_circle_outline_rounded
                      : Icons.downloading_rounded,
              badgeLabel: task.hasError
                  ? 'Error'
                  : task.isPaused
                      ? 'Pausada'
                      : task.progressLabel,
              onPressed: onOpenDownloads,
            );
          }

          final downloadIndex = index - activeTasks.length;

          if (downloadIndex < downloads.length) {
            final entry = downloads[downloadIndex];

            return _DownloadPreviewCard(
              title: entry.title,
              subtitle: entry.isMovie
                  ? 'Película · ${entry.sizeLabel}'
                  : '${entry.seriesTitle} · ${entry.seasonName}',
              imageUrl: entry.imageUrl,
              progress: 1,
              badgeIcon: Icons.offline_pin_rounded,
              badgeLabel: entry.sizeLabel,
              onPressed: onOpenDownloads,
            );
          }

          return _OpenDownloadsCard(onPressed: onOpenDownloads);
        },
      ),
    );
  }
}

class _DownloadPreviewCard extends StatelessWidget {
  const _DownloadPreviewCard({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.progress,
    required this.badgeIcon,
    required this.badgeLabel,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final String imageUrl;
  final double progress;
  final IconData badgeIcon;
  final String badgeLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF111620),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF232A36)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 78,
                    height: double.infinity,
                    child: imageUrl.isEmpty
                        ? const _PosterFallback()
                        : AppCachedImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            cacheWidth: 220,
                            cacheHeight: 320,
                            fallback: const _PosterFallback(),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            badgeIcon,
                            color: const Color(0xFF8EA5FF),
                            size: 17,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              badgeLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF8EA5FF),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF98A2B3),
                          fontSize: 11.5,
                          height: 1.2,
                        ),
                      ),
                      const Spacer(),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress.clamp(0.0, 1.0).toDouble(),
                          minHeight: 6,
                          backgroundColor: const Color(0xFF252C38),
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
  }
}

class _OpenDownloadsCard extends StatelessWidget {
  const _OpenDownloadsCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 154,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF17213B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF354780)),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.download_for_offline_rounded,
                  color: Color(0xFF9CB0FF),
                  size: 30,
                ),
                SizedBox(height: 12),
                Text(
                  'Mis descargas',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Ver todo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFB8C5FF),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.items,
    required this.onOpen,
    this.enableTvRemoteNavigation = false,
  });

  final List<WatchProgressEntry> items;
  final ValueChanged<WatchProgressEntry> onOpen;
  final bool enableTvRemoteNavigation;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return SizedBox(
      height: enableTvRemoteNavigation ? 142 : (isWide ? 288 : 216),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];

          return _PosterCard(
            title: item.title,
            subtitle: item.subtitle,
            imageUrl: item.imageUrl,
            progress: item.progress,
            playBadge: true,
            enableTvRemoteNavigation: enableTvRemoteNavigation,
            onPressed: () => onOpen(item),
          );
        },
      ),
    );
  }
}

class _ChannelFavoritesRow extends StatelessWidget {
  const _ChannelFavoritesRow({
    required this.items,
    required this.onOpen,
  });

  final List<FavoriteEntry> items;
  final ValueChanged<FavoriteEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) {
          return const SizedBox(width: 12);
        },
        itemBuilder: (context, index) {
          final item = items[index];
          final channel = item.channel!;

          return SizedBox(
            width: 112,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onOpen(item),
                borderRadius: BorderRadius.circular(18),
                child: Ink(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111620),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFF232A36),
                    ),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            Container(
                              width: double.infinity,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF2F4F7),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: channel.iconUrl.isEmpty
                                  ? const Icon(
                                      Icons.live_tv_rounded,
                                      color: Color(0xFF5B7CFF),
                                      size: 30,
                                    )
                                  : Image.network(
                                      channel.iconUrl,
                                      fit: BoxFit.contain,
                                      errorBuilder: (
                                        context,
                                        error,
                                        stackTrace,
                                      ) {
                                        return const Icon(
                                          Icons.live_tv_rounded,
                                          color: Color(0xFF5B7CFF),
                                          size: 30,
                                        );
                                      },
                                    ),
                            ),
                            const Positioned(
                              right: 5,
                              bottom: 5,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Color(0xD9000000),
                                  shape: BoxShape.circle,
                                ),
                                child: Padding(
                                  padding: EdgeInsets.all(5),
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 17,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        channel.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FavoritesRow extends StatelessWidget {
  const _FavoritesRow({
    required this.items,
    required this.onOpen,
  });

  final List<FavoriteEntry> items;
  final ValueChanged<FavoriteEntry> onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 198,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = items[index];

          return _PosterCard(
            title: item.title,
            subtitle: item.subtitle,
            imageUrl: item.imageUrl,
            favoriteBadge: true,
            onPressed: () => onOpen(item),
          );
        },
      ),
    );
  }
}


class _RankedMovieRow extends StatelessWidget {
  const _RankedMovieRow({
    required this.groups,
    required this.onOpen,
    this.enableTvRemoteNavigation = false,
  });

  final List<MovieGroup> groups;
  final ValueChanged<MovieGroup> onOpen;
  final bool enableTvRemoteNavigation;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return SizedBox(
      height: enableTvRemoteNavigation ? 142 : (isWide ? 288 : 216),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: groups.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final group = groups[index];
          final movie = group.primary;
          final meta = [
            if (movie.displayRating.isNotEmpty) '★ ${movie.displayRating}',
            if (movie.displayYear.isNotEmpty) movie.displayYear,
            if (group.versionCount > 1) '${group.versionCount} versiones',
          ].join('  ');

          return _PosterCard(
            title: group.displayTitle,
            subtitle: meta.isEmpty ? 'Película' : meta,
            imageUrl: movie.posterUrl,
            rank: index + 1,
            enableTvRemoteNavigation: enableTvRemoteNavigation,
            onPressed: () => onOpen(group),
          );
        },
      ),
    );
  }
}

class _RankedSeriesRow extends StatelessWidget {
  const _RankedSeriesRow({
    required this.groups,
    required this.onOpen,
    this.enableTvRemoteNavigation = false,
  });

  final List<SeriesGroup> groups;
  final ValueChanged<SeriesGroup> onOpen;
  final bool enableTvRemoteNavigation;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: enableTvRemoteNavigation ? 142 : 216,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: groups.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final group = groups[index];
          final item = group.primary;
          final meta = [
            if (item.displayRating.isNotEmpty) '★ ${item.displayRating}',
            if (item.displayYear.isNotEmpty) item.displayYear,
            if (group.versionCount > 1) '${group.versionCount} versiones',
          ].join('  ');

          return _PosterCard(
            title: group.displayTitle,
            subtitle: meta.isEmpty ? 'Serie' : meta,
            imageUrl: item.coverUrl,
            rank: index + 1,
            enableTvRemoteNavigation: enableTvRemoteNavigation,
            onPressed: () => onOpen(group),
          );
        },
      ),
    );
  }
}

class _MovieRow extends StatelessWidget {
  const _MovieRow({
    required this.groups,
    required this.onOpen,
    this.enableTvRemoteNavigation = false,
  });

  final List<MovieGroup> groups;
  final ValueChanged<MovieGroup> onOpen;
  final bool enableTvRemoteNavigation;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return SizedBox(
      height: isWide ? 270 : 205,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: groups.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final group = groups[index];
          final movie = group.primary;
          final meta = [
            if (movie.displayYear.isNotEmpty) movie.displayYear,
            if (group.versionCount > 1) '${group.versionCount} versiones',
            if (movie.displayRating.isNotEmpty) '★ ${movie.displayRating}',
          ].join('  ');

          return _PosterCard(
            title: group.displayTitle,
            subtitle: meta.isEmpty ? 'Película' : meta,
            imageUrl: movie.posterUrl,
            enableTvRemoteNavigation: enableTvRemoteNavigation,
            onPressed: () => onOpen(group),
          );
        },
      ),
    );
  }
}

class _SeriesRow extends StatelessWidget {
  const _SeriesRow({
    required this.groups,
    required this.onOpen,
    this.enableTvRemoteNavigation = false,
  });

  final List<SeriesGroup> groups;
  final ValueChanged<SeriesGroup> onOpen;
  final bool enableTvRemoteNavigation;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return SizedBox(
      height: isWide ? 270 : 205,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: groups.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final group = groups[index];
          final item = group.primary;
          final meta = [
            if (item.displayYear.isNotEmpty) item.displayYear,
            if (group.versionCount > 1) '${group.versionCount} versiones',
            if (item.displayRating.isNotEmpty) '★ ${item.displayRating}',
          ].join('  ');

          return _PosterCard(
            title: group.displayTitle,
            subtitle: meta.isEmpty ? 'Serie' : meta,
            imageUrl: item.coverUrl,
            enableTvRemoteNavigation: enableTvRemoteNavigation,
            onPressed: () => onOpen(group),
          );
        },
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.onPressed,
    this.progress,
    this.playBadge = false,
    this.favoriteBadge = false,
    this.enableTvRemoteNavigation = false,
    this.rank,
  });

  final String title;
  final String subtitle;
  final String imageUrl;
  final VoidCallback onPressed;
  final double? progress;
  final bool playBadge;
  final bool favoriteBadge;
  final bool enableTvRemoteNavigation;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl.isNotEmpty)
                  AppCachedImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    cacheWidth: 420,
                    cacheHeight: 620,
                    fallback: const _PosterFallback(),
                  )
                else
                  const _PosterFallback(),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Color(0x77000000),
                      ],
                    ),
                  ),
                ),
                if (rank != null)
                  Positioned(
                    left: 6,
                    bottom: -10,
                    child: Text(
                      rank.toString(),
                      style: const TextStyle(
                        color: Color(0xFFE8FF63),
                        fontSize: 64,
                        height: 0.95,
                        fontWeight: FontWeight.w900,
                        shadows: [
                          Shadow(
                            color: Color(0xCC000000),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (playBadge)
                  const Positioned(
                    right: 8,
                    bottom: 9,
                    child: _RoundBadge(
                      icon: Icons.play_arrow_rounded,
                    ),
                  ),
                if (favoriteBadge)
                  const Positioned(
                    right: 8,
                    top: 8,
                    child: _RoundBadge(
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
        const SizedBox(height: 8),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
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
    );

    if (enableTvRemoteNavigation) {
      return SizedBox(
        width: 138,
        child: TvFocusableSurface(
          enabled: true,
          borderRadius: BorderRadius.circular(18),
          onPressed: onPressed,
          builder: (context, focused) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              padding: const EdgeInsets.all(10),
              decoration: tvFocusedDecoration(
                focused: focused,
                backgroundColor: const Color(0xFF111620),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF17213B),
                            Color(0xFF0B1020),
                          ],
                        ),
                        border: Border.all(color: Color(0x224C6DFF)),
                      ),
                      child: Stack(
                        children: [
                          Align(
                            alignment: Alignment.center,
                            child: Icon(
                              playBadge
                                  ? Icons.play_circle_fill_rounded
                                  : favoriteBadge
                                      ? Icons.favorite_rounded
                                      : Icons.movie_rounded,
                              color: const Color(0xFF8EA5FF),
                              size: 30,
                            ),
                          ),
                          if (rank != null)
                            Positioned(
                              left: 0,
                              bottom: -3,
                              child: Text(
                                rank.toString(),
                                style: const TextStyle(
                                  color: Color(0xFFE8FF63),
                                  fontSize: 38,
                                  height: 0.9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          if (progress != null)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 4,
                                backgroundColor: Color(0x66000000),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
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
            );
          },
        ),
      );
    }

    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return SizedBox(
      width: isWide ? 176 : 132,
      child: TvFocusableSurface(
        enabled: false,
        borderRadius: BorderRadius.circular(16),
        onPressed: onPressed,
        builder: (context, focused) => card,
      ),
    );
  }
}

class _RoundBadge extends StatelessWidget {
  const _RoundBadge({
    required this.icon,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xCC000000),
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(icon, color: iconColor, size: 19),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF171D28),
      child: Center(
        child: Icon(
          Icons.play_circle_outline_rounded,
          color: Color(0xFF667085),
          size: 38,
        ),
      ),
    );
  }
}

class _CompactErrorCard extends StatelessWidget {
  const _CompactErrorCard({
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

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: MediaQuery.sizeOf(context).width >= 900 ? 390 : 270,
          decoration: BoxDecoration(
            color: const Color(0xFF111620),
            borderRadius: BorderRadius.circular(28),
          ),
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
        const SizedBox(height: 24),
        const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }
}
