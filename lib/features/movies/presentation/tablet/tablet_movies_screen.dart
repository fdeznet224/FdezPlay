import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/models/iptv_category.dart';
import '../../../../shared/services/iptv_api_service.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../auth/domain/auth_session.dart';
import '../../../favorites/data/local_library_service.dart';
import '../../../player/presentation/mobile/mobile_movie_player_screen.dart';
import '../../domain/movie.dart';
import '../../domain/movie_group.dart';

class TabletMoviesScreen extends StatefulWidget {
  const TabletMoviesScreen({
    required this.session,
    super.key,
  });

  final AuthSession session;

  @override
  State<TabletMoviesScreen> createState() => _TabletMoviesScreenState();
}

class _TabletMoviesScreenState extends State<TabletMoviesScreen> {
  final IptvApiService _apiService = IptvApiService();
  final LocalLibraryService _libraryService = LocalLibraryService.instance;
  final TextEditingController _searchController = TextEditingController();

  Timer? _searchDebounce;

  List<IptvCategory> _categories = <IptvCategory>[];
  List<Movie> _categoryMovies = <Movie>[];
  List<Movie> _allMovies = <Movie>[];

  String? _selectedCategoryId;
  MovieGroup? _selectedGroup;
  Movie? _selectedMovieDetails;
  int _selectedVersionIndex = 0;
  String _searchQuery = '';

  bool _loadingInitialData = true;
  bool _loadingMovies = false;
  bool _loadingGlobalSearch = false;
  bool _allMoviesLoaded = false;
  bool _loadingDetails = false;
  bool _favoriteActionLoading = false;

  String? _errorMessage;
  String? _globalSearchError;

  int _movieRequestId = 0;
  int _detailsRequestId = 0;

  Set<int> _favoriteMovieIds = <int>{};
  Map<int, WatchProgressEntry> _movieProgress = <int, WatchProgressEntry>{};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    unawaited(_loadLibraryState());
    unawaited(_loadInitialData());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  bool get _isSearching => _searchQuery.trim().isNotEmpty;

  Map<String, String> get _categoryNames {
    return <String, String>{
      for (final category in _categories) category.id: category.name,
    };
  }

  String get _selectedCategoryName {
    final categoryId = _selectedCategoryId;

    if (categoryId == null) {
      return 'Películas';
    }

    for (final category in _categories) {
      if (category.id == categoryId) {
        return category.name;
      }
    }

    return 'Películas';
  }

  List<MovieGroup> get _visibleGroups {
    final source = _isSearching ? _allMovies : _categoryMovies;
    final groups = groupMovies(source);
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

  Future<void> _loadLibraryState() async {
    try {
      final snapshot = await _libraryService.load(widget.session);

      if (!mounted) {
        return;
      }

      final favoriteIds = <int>{};
      final progressByMovie = <int, WatchProgressEntry>{};

      for (final item in snapshot.favorites) {
        final movie = item.movie;

        if (movie != null) {
          favoriteIds.add(movie.streamId);
        }
      }

      for (final item in snapshot.progress) {
        final movie = item.movie;

        if (movie != null) {
          progressByMovie[movie.streamId] = item;
        }
      }

      setState(() {
        _favoriteMovieIds = favoriteIds;
        _movieProgress = progressByMovie;
      });
    } catch (_) {
      // El catálogo puede seguir funcionando aunque la biblioteca local falle.
    }
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loadingInitialData = true;
      _errorMessage = null;
    });

    try {
      final categories = await _apiService.loadMovieCategories(widget.session);

      if (!mounted) {
        return;
      }

      if (categories.isEmpty) {
        setState(() {
          _categories = <IptvCategory>[];
          _categoryMovies = <Movie>[];
          _selectedGroup = null;
          _selectedMovieDetails = null;
          _loadingInitialData = false;
          _errorMessage = 'No se encontraron categorías de películas.';
        });
        return;
      }

      final firstCategory = categories.first;

      setState(() {
        _categories = categories;
        _selectedCategoryId = firstCategory.id;
      });

      final movies = await _apiService.loadMovies(
        widget.session,
        categoryId: firstCategory.id,
      );

      if (!mounted) {
        return;
      }

      final groups = groupMovies(movies);
      final selectedGroup = groups.isEmpty ? null : groups.first;

      setState(() {
        _categoryMovies = movies;
        _selectedGroup = selectedGroup;
        _selectedVersionIndex = 0;
        _selectedMovieDetails = selectedGroup?.primary;
        _loadingInitialData = false;
      });

      if (selectedGroup != null) {
        unawaited(_loadSelectedMovieDetails(selectedGroup));
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingInitialData = false;
        _errorMessage = 'No fue posible cargar las películas.';
      });
    }
  }

  Future<void> _selectCategory(IptvCategory category) async {
    if (_loadingMovies || category.id == _selectedCategoryId) {
      if (_isSearching) {
        _searchController.clear();
      }
      return;
    }

    _searchController.clear();
    final requestId = ++_movieRequestId;

    setState(() {
      _selectedCategoryId = category.id;
      _loadingMovies = true;
      _errorMessage = null;
      _categoryMovies = <Movie>[];
      _selectedGroup = null;
      _selectedMovieDetails = null;
      _selectedVersionIndex = 0;
    });

    try {
      final movies = await _apiService.loadMovies(
        widget.session,
        categoryId: category.id,
      );

      if (!mounted || requestId != _movieRequestId) {
        return;
      }

      final groups = groupMovies(movies);
      final selectedGroup = groups.isEmpty ? null : groups.first;

      setState(() {
        _categoryMovies = movies;
        _selectedGroup = selectedGroup;
        _selectedMovieDetails = selectedGroup?.primary;
        _selectedVersionIndex = 0;
        _loadingMovies = false;
      });

      if (selectedGroup != null) {
        unawaited(_loadSelectedMovieDetails(selectedGroup));
      }
    } catch (_) {
      if (!mounted || requestId != _movieRequestId) {
        return;
      }

      setState(() {
        _loadingMovies = false;
        _errorMessage = 'No fue posible cargar esta categoría.';
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();

    _searchDebounce?.cancel();

    MovieGroup? firstGroup;

    if (query.isEmpty) {
      final groups = groupMovies(_categoryMovies);
      firstGroup = groups.isEmpty ? null : groups.first;
    } else if (_allMoviesLoaded) {
      final groups = _filterGroups(groupMovies(_allMovies), query);
      firstGroup = groups.isEmpty ? null : groups.first;
    }

    setState(() {
      _searchQuery = query;

      if (query.isEmpty) {
        _globalSearchError = null;
        _selectedGroup = firstGroup;
        _selectedVersionIndex = 0;
        _selectedMovieDetails = firstGroup?.primary;
      } else if (_allMoviesLoaded) {
        _selectedGroup = firstGroup;
        _selectedVersionIndex = 0;
        _selectedMovieDetails = firstGroup?.primary;
      }
    });

    if (firstGroup != null) {
      unawaited(_loadSelectedMovieDetails(firstGroup));
    }

    if (query.isEmpty || _allMoviesLoaded || _loadingGlobalSearch) {
      return;
    }

    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      _loadAllMoviesForSearch,
    );
  }

  List<MovieGroup> _filterGroups(
    List<MovieGroup> groups,
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

  Future<void> _loadAllMoviesForSearch({bool force = false}) async {
    if (_loadingGlobalSearch) {
      return;
    }

    if (_allMoviesLoaded && !force) {
      return;
    }

    setState(() {
      _loadingGlobalSearch = true;
      _globalSearchError = null;

      if (force) {
        _allMoviesLoaded = false;
        _allMovies = <Movie>[];
        _selectedGroup = null;
        _selectedMovieDetails = null;
      }
    });

    try {
      final movies = await _apiService.loadMovies(
        widget.session,
        forceRefresh: force,
      );

      if (!mounted) {
        return;
      }

      final groups = _filterGroups(groupMovies(movies), _searchQuery);
      final firstGroup = groups.isEmpty ? null : groups.first;

      setState(() {
        _allMovies = movies;
        _allMoviesLoaded = true;
        _loadingGlobalSearch = false;
        _selectedGroup = firstGroup;
        _selectedVersionIndex = 0;
        _selectedMovieDetails = firstGroup?.primary;
      });

      if (firstGroup != null) {
        unawaited(_loadSelectedMovieDetails(firstGroup));
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingGlobalSearch = false;
        _allMoviesLoaded = false;
        _selectedGroup = null;
        _selectedMovieDetails = null;
        _globalSearchError = 'No fue posible buscar en todas las películas.';
      });
    }
  }

  Future<void> _refreshVisibleContent() async {
    if (_isSearching) {
      await _loadAllMoviesForSearch(force: true);
      return;
    }

    final categoryId = _selectedCategoryId;

    if (categoryId == null) {
      await _loadInitialData();
      return;
    }

    final requestId = ++_movieRequestId;

    setState(() {
      _loadingMovies = true;
      _errorMessage = null;
    });

    try {
      final movies = await _apiService.loadMovies(
        widget.session,
        categoryId: categoryId,
        forceRefresh: true,
      );

      if (!mounted || requestId != _movieRequestId) {
        return;
      }

      final groups = groupMovies(movies);
      final currentKey = _selectedGroup?.key;
      MovieGroup? selectedGroup;

      for (final group in groups) {
        if (group.key == currentKey) {
          selectedGroup = group;
          break;
        }
      }

      selectedGroup ??= groups.isEmpty ? null : groups.first;

      setState(() {
        _categoryMovies = movies;
        _selectedGroup = selectedGroup;
        _selectedVersionIndex = 0;
        _selectedMovieDetails = selectedGroup?.primary;
        _loadingMovies = false;
      });

      if (selectedGroup != null) {
        unawaited(_loadSelectedMovieDetails(selectedGroup));
      }
    } catch (_) {
      if (!mounted || requestId != _movieRequestId) {
        return;
      }

      setState(() {
        _loadingMovies = false;
        _errorMessage = 'No fue posible actualizar las películas.';
      });
    }
  }

  void _selectGroup(MovieGroup group) {
    if (_selectedGroup?.key == group.key) {
      return;
    }

    setState(() {
      _selectedGroup = group;
      _selectedVersionIndex = 0;
      _selectedMovieDetails = group.primary;
    });

    unawaited(_loadSelectedMovieDetails(group));
  }

  Future<void> _loadSelectedMovieDetails(MovieGroup group) async {
    if (group.variants.isEmpty) {
      return;
    }

    final selectedIndex = _selectedVersionIndex
        .clamp(0, group.variants.length - 1)
        .toInt();
    final selected = group.variants[selectedIndex];
    final requestId = ++_detailsRequestId;

    setState(() {
      _selectedMovieDetails = selected;
      _loadingDetails = true;
    });

    try {
      final details = await _apiService.loadMovieDetails(
        widget.session,
        movie: selected,
      );

      if (!mounted ||
          requestId != _detailsRequestId ||
          _selectedGroup?.key != group.key ||
          _selectedVersionIndex != selectedIndex) {
        return;
      }

      setState(() {
        _selectedMovieDetails = details;
        _loadingDetails = false;
      });
    } catch (_) {
      if (!mounted ||
          requestId != _detailsRequestId ||
          _selectedGroup?.key != group.key ||
          _selectedVersionIndex != selectedIndex) {
        return;
      }

      setState(() {
        _selectedMovieDetails = selected;
        _loadingDetails = false;
      });
    }
  }

  void _selectVersion(int index) {
    final group = _selectedGroup;

    if (group == null ||
        index < 0 ||
        index >= group.variants.length ||
        index == _selectedVersionIndex) {
      return;
    }

    setState(() {
      _selectedVersionIndex = index;
      _selectedMovieDetails = group.variants[index];
    });

    unawaited(_loadSelectedMovieDetails(group));
  }

  bool _isFavorite(MovieGroup group) {
    return _favoriteMovieIds.contains(group.primary.streamId);
  }

  WatchProgressEntry? _progressFor(MovieGroup group) {
    return _movieProgress[group.primary.streamId];
  }

  Future<void> _toggleFavorite(MovieGroup group) async {
    if (_favoriteActionLoading) {
      return;
    }

    setState(() {
      _favoriteActionLoading = true;
    });

    try {
      final isFavorite = await _libraryService.toggleMovieFavorite(
        widget.session,
        group.primary,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        if (isFavorite) {
          _favoriteMovieIds.add(group.primary.streamId);
        } else {
          _favoriteMovieIds.remove(group.primary.streamId);
        }
        _favoriteActionLoading = false;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              isFavorite
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

  Future<void> _playSelectedMovie(MovieGroup group) async {
    WatchProgressEntry? progress;

    try {
      progress = await _libraryService.movieProgress(
        widget.session,
        group.primary.streamId,
      );
    } catch (_) {
      progress = _progressFor(group);
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MobileMoviePlayerScreen(
          session: widget.session,
          movie: group.primary,
          versions: group.variants,
          initialVersionIndex: _selectedVersionIndex,
          displayTitle: group.displayTitle,
          initialPosition: progress?.position ?? Duration.zero,
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
      });
    }
  }


  MovieGroup? _effectiveSelectedGroup(List<MovieGroup> visibleGroups) {
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
      return const _TabletMoviesInitialLoading();
    }

    if (_errorMessage != null && _categories.isEmpty) {
      return _TabletMoviesFullError(
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
          _selectedMovieDetails = selectedGroup.primary;
        });

        unawaited(_loadSelectedMovieDetails(selectedGroup));
      });
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TabletMoviesHeader(
            categoryName: _isSearching
                ? 'Resultados en todas las categorías'
                : _selectedCategoryName,
            movieCount: visibleGroups.length,
            loading: _loadingMovies || _loadingGlobalSearch,
            onRefresh: _refreshVisibleContent,
          ),
          const SizedBox(height: 14),
          _TabletMoviesSearchField(
            controller: _searchController,
            loading: _loadingGlobalSearch,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final categoryWidth = (constraints.maxWidth * 0.19)
                    .clamp(145.0, 230.0)
                    .toDouble();
                final catalogWidth = (constraints.maxWidth * 0.39)
                    .clamp(330.0, 520.0)
                    .toDouble();
                final compact = constraints.maxWidth < 1000;
                final gap = compact ? 10.0 : 14.0;

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: categoryWidth,
                      child: _TabletMovieCategoryPanel(
                        categories: _categories,
                        selectedCategoryId: _selectedCategoryId,
                        searching: _isSearching,
                        loading: _loadingMovies,
                        onSelected: _selectCategory,
                      ),
                    ),
                    SizedBox(width: gap),
                    SizedBox(
                      width: catalogWidth,
                      child: _TabletMovieCatalogPanel(
                        groups: visibleGroups,
                        selectedGroup: selectedGroup,
                        categoryName: _isSearching
                            ? 'Búsqueda global'
                            : _selectedCategoryName,
                        searching: _isSearching,
                        loadingMovies: _loadingMovies,
                        loadingSearch: _loadingGlobalSearch,
                        errorMessage:
                            _isSearching ? _globalSearchError : _errorMessage,
                        categoryNames: _categoryNames,
                        favoriteIds: _favoriteMovieIds,
                        progressByMovie: _movieProgress,
                        onSelected: _selectGroup,
                        onRetry: _refreshVisibleContent,
                      ),
                    ),
                    SizedBox(width: gap),
                    Expanded(
                      child: _TabletMovieDetailsPanel(
                        group: selectedGroup,
                        movie: selectedGroup == null
                            ? null
                            : (_selectedGroup?.key == selectedGroup.key
                                ? (_selectedMovieDetails ?? selectedGroup.primary)
                                : selectedGroup.primary),
                        selectedVersionIndex:
                            _selectedGroup?.key == selectedGroup?.key
                                ? _selectedVersionIndex
                                : 0,
                        loadingDetails: _loadingDetails,
                        favorite: selectedGroup != null &&
                            _isFavorite(selectedGroup),
                        favoriteLoading: _favoriteActionLoading,
                        progress: selectedGroup == null
                            ? null
                            : _progressFor(selectedGroup),
                        compact: compact,
                        onSelectVersion: _selectVersion,
                        onFavorite: selectedGroup == null
                            ? null
                            : () {
                                unawaited(_toggleFavorite(selectedGroup));
                              },
                        onPlay: selectedGroup == null
                            ? null
                            : () {
                                unawaited(_playSelectedMovie(selectedGroup));
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

class _TabletMoviesHeader extends StatelessWidget {
  const _TabletMoviesHeader({
    required this.categoryName,
    required this.movieCount,
    required this.loading,
    required this.onRefresh,
  });

  final String categoryName;
  final int movieCount;
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
            color: const Color(0xFF35254D),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            Icons.movie_rounded,
            color: Color(0xFFBE91FF),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Películas',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                categoryName,
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF2D2340),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$movieCount películas',
            style: const TextStyle(
              color: Color(0xFFE2D2FF),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: 'Actualizar películas',
          onPressed: loading
              ? null
              : () {
                  unawaited(onRefresh());
                },
          icon: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

class _TabletMoviesSearchField extends StatelessWidget {
  const _TabletMoviesSearchField({
    required this.controller,
    required this.loading,
  });

  final TextEditingController controller;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Buscar una película en todas las categorías',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: loading
              ? const Padding(
                  padding: EdgeInsets.all(15),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    if (value.text.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return IconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: controller.clear,
                      icon: const Icon(Icons.close_rounded),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _TabletMovieCategoryPanel extends StatelessWidget {
  const _TabletMovieCategoryPanel({
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
    return _TabletMoviePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                Icon(
                  Icons.grid_view_rounded,
                  size: 18,
                  color: Color(0xFFBE91FF),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'CATEGORÍAS',
                    style: TextStyle(
                      color: Color(0xFFB8C0CC),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (searching)
            Container(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2340),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xFF4D386D)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.travel_explore_rounded,
                    size: 17,
                    color: Color(0xFFBE91FF),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Buscando en todas',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE2D2FF),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 12),
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final category = categories[index];
                final selected = !searching &&
                    category.id == selectedCategoryId;

                return Material(
                  color: selected
                      ? const Color(0xFF35254D)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: loading ? null : () => onSelected(category),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFFBE91FF)
                                  : const Color(0xFF495365),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              category.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFFB8C0CC),
                                fontSize: 12,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (selected)
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: Color(0xFFBE91FF),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TabletMovieCatalogPanel extends StatelessWidget {
  const _TabletMovieCatalogPanel({
    required this.groups,
    required this.selectedGroup,
    required this.categoryName,
    required this.searching,
    required this.loadingMovies,
    required this.loadingSearch,
    required this.errorMessage,
    required this.categoryNames,
    required this.favoriteIds,
    required this.progressByMovie,
    required this.onSelected,
    required this.onRetry,
  });

  final List<MovieGroup> groups;
  final MovieGroup? selectedGroup;
  final String categoryName;
  final bool searching;
  final bool loadingMovies;
  final bool loadingSearch;
  final String? errorMessage;
  final Map<String, String> categoryNames;
  final Set<int> favoriteIds;
  final Map<int, WatchProgressEntry> progressByMovie;
  final ValueChanged<MovieGroup> onSelected;
  final Future<void> Function() onRetry;

  bool get _loading => searching ? loadingSearch : loadingMovies;

  @override
  Widget build(BuildContext context) {
    return _TabletMoviePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CATÁLOGO',
                        style: TextStyle(
                          color: Color(0xFFB8C0CC),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        categoryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF6F7B8E),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171D28),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '${groups.length}',
                    style: const TextStyle(
                      color: Color(0xFF9BA6B8),
                      fontSize: 11,
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
    if (_loading) {
      return const _TabletMoviePanelLoading(
        message: 'Cargando películas...',
      );
    }

    if (errorMessage != null) {
      return _TabletMoviePanelError(
        message: errorMessage!,
        onRetry: onRetry,
      );
    }

    if (groups.isEmpty) {
      return _TabletMoviePanelEmpty(
        icon: searching ? Icons.search_off_rounded : Icons.movie_outlined,
        title: searching
            ? 'No encontramos esa película'
            : 'No hay películas disponibles',
        subtitle: searching
            ? 'Prueba con otro nombre.'
            : 'Actualiza para volver a intentarlo.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 460 ? 3 : 2;

        return RefreshIndicator(
          onRefresh: onRetry,
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(10),
            itemCount: groups.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 11,
              crossAxisSpacing: 9,
              childAspectRatio: 0.57,
            ),
            itemBuilder: (context, index) {
              final group = groups[index];
              final selected = selectedGroup?.key == group.key;
              final movie = group.primary;

              return _TabletMovieCard(
                group: group,
                selected: selected,
                favorite: favoriteIds.contains(movie.streamId),
                progress: progressByMovie[movie.streamId],
                categoryName: searching
                    ? (categoryNames[movie.categoryId] ?? '')
                    : '',
                onPressed: () => onSelected(group),
              );
            },
          ),
        );
      },
    );
  }
}

class _TabletMovieCard extends StatelessWidget {
  const _TabletMovieCard({
    required this.group,
    required this.selected,
    required this.favorite,
    required this.progress,
    required this.categoryName,
    required this.onPressed,
  });

  final MovieGroup group;
  final bool selected;
  final bool favorite;
  final WatchProgressEntry? progress;
  final String categoryName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final movie = group.primary;

    return Material(
      color: selected ? const Color(0xFF2D2340) : const Color(0xFF121720),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
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
                      child: movie.posterUrl.isEmpty
                          ? const _TabletMoviePosterFallback()
                          : AppCachedImage(
                              imageUrl: movie.posterUrl,
                              fit: BoxFit.cover,
                              cacheWidth: 300,
                              cacheHeight: 450,
                              placeholder: const _TabletMoviePosterFallback(
                                loading: true,
                              ),
                              fallback: const _TabletMoviePosterFallback(),
                            ),
                    ),
                    if (favorite)
                      const Positioned(
                        top: 7,
                        right: 7,
                        child: _TabletMovieBadge(
                          icon: Icons.favorite_rounded,
                          color: Color(0xFFFF6B7A),
                        ),
                      ),
                    if (group.versionCount > 1)
                      Positioned(
                        left: 7,
                        bottom: progress == null ? 7 : 13,
                        child: _TabletMovieBadge(
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
                  if (movie.displayYear.isNotEmpty)
                    Text(
                      movie.displayYear,
                      style: const TextStyle(
                        color: Color(0xFF8D97A8),
                        fontSize: 9.5,
                      ),
                    ),
                  if (movie.displayYear.isNotEmpty &&
                      movie.displayRating.isNotEmpty)
                    const Text(
                      '  •  ',
                      style: TextStyle(
                        color: Color(0xFF5D6676),
                        fontSize: 9,
                      ),
                    ),
                  if (movie.displayRating.isNotEmpty) ...[
                    const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFFFC857),
                      size: 11,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      movie.displayRating,
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

class _TabletMovieDetailsPanel extends StatelessWidget {
  const _TabletMovieDetailsPanel({
    required this.group,
    required this.movie,
    required this.selectedVersionIndex,
    required this.loadingDetails,
    required this.favorite,
    required this.favoriteLoading,
    required this.progress,
    required this.compact,
    required this.onSelectVersion,
    required this.onFavorite,
    required this.onPlay,
  });

  final MovieGroup? group;
  final Movie? movie;
  final int selectedVersionIndex;
  final bool loadingDetails;
  final bool favorite;
  final bool favoriteLoading;
  final WatchProgressEntry? progress;
  final bool compact;
  final ValueChanged<int> onSelectVersion;
  final VoidCallback? onFavorite;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final selectedGroup = group;
    final selectedMovie = movie;

    if (selectedGroup == null || selectedMovie == null) {
      return const _TabletMoviePanel(
        child: _TabletMoviePanelEmpty(
          icon: Icons.movie_filter_outlined,
          title: 'Selecciona una película',
          subtitle: 'Aquí aparecerán su información y opciones.',
        ),
      );
    }

    final backgroundUrl = selectedMovie.backdropUrl.isNotEmpty
        ? selectedMovie.backdropUrl
        : selectedMovie.posterUrl;

    return _TabletMoviePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                compact ? 14 : 18,
                compact ? 14 : 18,
                compact ? 14 : 18,
                16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: compact ? 1.8 : 2.05,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (backgroundUrl.isNotEmpty)
                            AppCachedImage(
                              imageUrl: backgroundUrl,
                              fit: BoxFit.cover,
                              cacheWidth: 950,
                              cacheHeight: 520,
                              fallback: const _TabletMovieBackdropFallback(),
                            )
                          else
                            const _TabletMovieBackdropFallback(),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0x22000000),
                                  Color(0x88000000),
                                  Color(0xEE0F131C),
                                ],
                                stops: [0, 0.58, 1],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 14,
                            right: 14,
                            bottom: 13,
                            child: Text(
                              selectedGroup.displayTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: compact ? 20 : 24,
                                height: 1.05,
                                fontWeight: FontWeight.w800,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black54,
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 9,
                            right: 9,
                            child: IconButton.filled(
                              tooltip: favorite
                                  ? 'Quitar de favoritos'
                                  : 'Agregar a favoritos',
                              onPressed:
                                  favoriteLoading ? null : onFavorite,
                              style: IconButton.styleFrom(
                                backgroundColor: const Color(0xB3151922),
                              ),
                              icon: favoriteLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
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
                        ],
                      ),
                    ),
                  ),
                  if (loadingDetails) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(minHeight: 2),
                  ],
                  const SizedBox(height: 15),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      if (selectedMovie.displayYear.isNotEmpty)
                        _TabletMovieInfoChip(
                          icon: Icons.calendar_month_rounded,
                          label: selectedMovie.displayYear,
                        ),
                      if (selectedMovie.duration.isNotEmpty)
                        _TabletMovieInfoChip(
                          icon: Icons.schedule_rounded,
                          label: selectedMovie.duration,
                        ),
                      if (selectedMovie.displayRating.isNotEmpty)
                        _TabletMovieInfoChip(
                          icon: Icons.star_rounded,
                          label: selectedMovie.displayRating,
                          accent: true,
                        ),
                      _TabletMovieInfoChip(
                        icon: Icons.high_quality_rounded,
                        label: selectedMovie.safeExtension.toUpperCase(),
                      ),
                    ],
                  ),
                  if (selectedMovie.genre.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      selectedMovie.genre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFBE91FF),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (selectedGroup.versionCount > 1) ...[
                    const SizedBox(height: 17),
                    const Text(
                      'VERSIONES DISPONIBLES',
                      style: TextStyle(
                        color: Color(0xFF8993A4),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.55,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (var index = 0;
                            index < selectedGroup.variants.length;
                            index++)
                          ChoiceChip(
                            selected: index == selectedVersionIndex,
                            onSelected: (_) => onSelectVersion(index),
                            label: Text(
                              movieVariantLabel(
                                selectedGroup.variants[index],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  const Text(
                    'Sinopsis',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    selectedMovie.plot.isEmpty
                        ? 'No hay una descripción disponible para esta película.'
                        : selectedMovie.plot,
                    style: const TextStyle(
                      color: Color(0xFFB0B7C3),
                      fontSize: 12,
                      height: 1.48,
                    ),
                  ),
                  if (selectedMovie.director.isNotEmpty) ...[
                    const SizedBox(height: 15),
                    _TabletMovieDetailLine(
                      label: 'Dirección',
                      value: selectedMovie.director,
                    ),
                  ],
                  if (selectedMovie.cast.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _TabletMovieDetailLine(
                      label: 'Reparto',
                      value: selectedMovie.cast,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 16,
              12,
              compact ? 12 : 16,
              14,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF10151E),
              border: Border(
                top: BorderSide(color: Color(0xFF202632)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (progress != null) ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.history_rounded,
                        size: 15,
                        color: Color(0xFFBE91FF),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Continuar viendo',
                          style: TextStyle(
                            color: Color(0xFFD7C5F4),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${(progress!.progress * 100).round()}%',
                        style: const TextStyle(
                          color: Color(0xFF98A2B3),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress!.progress,
                      minHeight: 5,
                      backgroundColor: const Color(0xFF252C38),
                    ),
                  ),
                  const SizedBox(height: 11),
                ],
                FilledButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    progress == null ? 'REPRODUCIR' : 'CONTINUAR',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _TabletMovieInfoChip extends StatelessWidget {
  const _TabletMovieInfoChip({
    required this.icon,
    required this.label,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: accent ? const Color(0xFF3A3021) : const Color(0xFF171D28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent ? const Color(0xFF66522E) : const Color(0xFF252D3A),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: accent
                ? const Color(0xFFFFC857)
                : const Color(0xFF98A2B3),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: accent
                  ? const Color(0xFFFFD783)
                  : const Color(0xFFB8C0CC),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabletMovieDetailLine extends StatelessWidget {
  const _TabletMovieDetailLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(
          color: Color(0xFFADB5C1),
          fontSize: 11,
          height: 1.4,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              color: Color(0xFFE0E4EA),
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class _TabletMoviePanel extends StatelessWidget {
  const _TabletMoviePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0F141D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF202632)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: child,
      ),
    );
  }
}

class _TabletMovieBadge extends StatelessWidget {
  const _TabletMovieBadge({
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
        color: const Color(0xD9171B24),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x443A4352)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          if (text != null) ...[
            const SizedBox(width: 4),
            Text(
              text!,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TabletMoviePosterFallback extends StatelessWidget {
  const _TabletMoviePosterFallback({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF171D28),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(
                Icons.movie_outlined,
                color: Color(0xFF667085),
                size: 34,
              ),
      ),
    );
  }
}

class _TabletMovieBackdropFallback extends StatelessWidget {
  const _TabletMovieBackdropFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF171D28),
      child: Center(
        child: Icon(
          Icons.movie_filter_outlined,
          color: Color(0xFF667085),
          size: 46,
        ),
      ),
    );
  }
}

class _TabletMoviePanelLoading extends StatelessWidget {
  const _TabletMoviePanelLoading({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 13),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF98A2B3),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabletMoviePanelError extends StatelessWidget {
  const _TabletMoviePanelError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Color(0xFF8C96A7),
              size: 36,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFB0B7C3),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 13),
            OutlinedButton(
              onPressed: () {
                unawaited(onRetry());
              },
              child: const Text('REINTENTAR'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabletMoviePanelEmpty extends StatelessWidget {
  const _TabletMoviePanelEmpty({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF667085), size: 42),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF8D97A8),
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

class _TabletMoviesInitialLoading extends StatelessWidget {
  const _TabletMoviesInitialLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 14),
          Text(
            'Preparando películas...',
            style: TextStyle(color: Color(0xFF98A2B3)),
          ),
        ],
      ),
    );
  }
}

class _TabletMoviesFullError extends StatelessWidget {
  const _TabletMoviesFullError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Color(0xFF8C96A7),
              size: 50,
            ),
            const SizedBox(height: 15),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFB0B7C3),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                unawaited(onRetry());
              },
              child: const Text('REINTENTAR'),
            ),
          ],
        ),
      ),
    );
  }
}
