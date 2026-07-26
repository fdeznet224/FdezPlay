import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/models/iptv_category.dart';
import '../../../../shared/utils/category_name_localizer.dart';
import '../../../../shared/services/iptv_api_service.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/tv_focusable_surface.dart';
import '../../../auth/domain/auth_session.dart';
import '../../domain/movie.dart';
import '../../domain/movie_group.dart';
import '../../../search/data/search_index_service.dart';
import 'mobile_movie_detail_screen.dart';

class MobileMoviesScreen extends StatefulWidget {
  const MobileMoviesScreen({
    required this.session,
    this.enableTvRemoteNavigation = false,
    super.key,
  });

  final AuthSession session;
  final bool enableTvRemoteNavigation;

  @override
  State<MobileMoviesScreen> createState() {
    return _MobileMoviesScreenState();
  }
}

class _MobileMoviesScreenState
    extends State<MobileMoviesScreen> {
  final IptvApiService _apiService = IptvApiService();
  final TextEditingController _searchController =
      TextEditingController();
  final GlobalKey<_MoviesContentState> _contentKey =
      GlobalKey<_MoviesContentState>();
  final FocusNode _searchButtonFocusNode =
      FocusNode(debugLabel: 'tv-movies-search-button');
  final ScrollController _categoryScrollController =
      ScrollController();
  final List<FocusNode> _categoryFocusNodes = <FocusNode>[];

  Timer? _searchDebounce;

  List<IptvCategory> _categories = const [];
  List<Movie> _categoryMovies = const [];
  List<Movie>? _allMovies;
  List<IndexedMovieGroup>? _allMovieSearchIndex;

  String? _selectedCategoryId;
  String _searchQuery = '';
  String _searchDraft = '';

  bool _loadingCategories = true;
  bool _loadingMovies = false;
  bool _loadingGlobalSearch = false;

  String? _errorMessage;
  int _movieRequestId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadInitialContent());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchButtonFocusNode.dispose();
    _categoryScrollController.dispose();
    for (final node in _categoryFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Map<String, String> get _categoryNames {
    return {
      for (final category in _categories)
        category.id: CategoryNameLocalizer.toSpanish(
          category.name,
          section: CategorySection.movies,
        ),
    };
  }

  List<MovieGroup> get _visibleMovieGroups {
    final query = _searchQuery.trim();

    if (query.isEmpty) {
      return groupMovies(_categoryMovies);
    }

    final searchIndex = _allMovieSearchIndex;

    if (searchIndex != null) {
      return FdezSearchIndexService.filterMovies(
        searchIndex,
        query,
        limit: 120,
      );
    }

    final fallbackIndex = FdezSearchIndexService.buildMovieIndex(
      _categoryMovies,
      categoryNames: _categoryNames,
    );

    return FdezSearchIndexService.filterMovies(
      fallbackIndex,
      query,
      limit: 120,
    );
  }

  Future<void> _loadInitialContent() async {
    setState(() {
      _loadingCategories = true;
      _errorMessage = null;
    });

    try {
      final categories =
          await _apiService.loadMovieCategories(
        widget.session,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _categories = categories;
        _loadingCategories = false;
        _selectedCategoryId =
            categories.isEmpty ? null : categories.first.id;
      });

      await _loadSelectedCategory();
      unawaited(_loadAllMoviesForSearch());
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingCategories = false;
        _errorMessage =
            'No se pudieron cargar las categorías de películas.';
      });
    }
  }

  Future<void> _loadSelectedCategory({bool forceRefresh = false}) async {
    final requestId = ++_movieRequestId;
    final categoryId = _selectedCategoryId;

    setState(() {
      _loadingMovies = true;
      _errorMessage = null;
    });

    try {
      final movies = await _apiService.loadMovies(
        widget.session,
        categoryId: categoryId,
        forceRefresh: forceRefresh,
      );

      if (!mounted || requestId != _movieRequestId) {
        return;
      }

      setState(() {
        _categoryMovies = movies;
        _loadingMovies = false;
      });
    } catch (_) {
      if (!mounted || requestId != _movieRequestId) {
        return;
      }

      setState(() {
        _loadingMovies = false;
        _errorMessage =
            'No se pudieron cargar las películas.';
      });
    }
  }

  Future<void> _loadAllMoviesForSearch({bool forceRefresh = false}) async {
    if ((_allMovies != null && !forceRefresh) ||
        _loadingGlobalSearch) {
      return;
    }

    setState(() {
      _loadingGlobalSearch = true;
      _errorMessage = null;
    });

    try {
      final movies = await _apiService
          .loadMovies(
            widget.session,
            forceRefresh: forceRefresh,
          )
          .timeout(const Duration(seconds: 25));

      if (!mounted) {
        return;
      }

      final index = FdezSearchIndexService.buildMovieIndex(
        movies,
        categoryNames: _categoryNames,
      );

      setState(() {
        _allMovies = movies;
        _allMovieSearchIndex = index;
        _loadingGlobalSearch = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingGlobalSearch = false;
        _errorMessage =
            'No se pudo cargar la búsqueda global.';
      });
    }
  }

  void _selectCategory(IptvCategory category) {
    if (_selectedCategoryId == category.id) {
      return;
    }

    setState(() {
      _selectedCategoryId = category.id;
      _categoryMovies = const [];
    });

    unawaited(_loadSelectedCategory());
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();

    if (widget.enableTvRemoteNavigation) {
      setState(() {
        _searchDraft = value;
      });
      return;
    }

    setState(() {
      _searchDraft = value;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 110), () {
      if (!mounted) {
        return;
      }

      final query = _searchController.text.trim();
      setState(() {
        _searchDraft = _searchController.text;
        _searchQuery = query;
      });

      if (query.isNotEmpty && _allMovieSearchIndex == null) {
        unawaited(_loadAllMoviesForSearch());
      }
    });
  }

  void _submitSearch(String value) {
    _searchDebounce?.cancel();

    if (widget.enableTvRemoteNavigation) {
      setState(() {
        _searchDraft = value;
      });
      _searchButtonFocusNode.requestFocus();
      return;
    }

    final query = value.trim();

    setState(() {
      _searchDraft = value;
      _searchQuery = query;
    });

    if (query.isNotEmpty) {
      unawaited(_loadAllMoviesForSearch());
    }

    FocusScope.of(context).unfocus();
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();

    setState(() {
      _searchDraft = '';
      _searchQuery = '';
    });

    FocusScope.of(context).unfocus();
  }


  void _syncCategoryFocusNodes() {
    while (_categoryFocusNodes.length < _categories.length) {
      _categoryFocusNodes.add(
        FocusNode(debugLabel: 'tv-movie-category-${_categoryFocusNodes.length}'),
      );
    }

    while (_categoryFocusNodes.length > _categories.length) {
      _categoryFocusNodes.removeLast().dispose();
    }
  }

  int get _selectedCategoryIndex {
    final selectedId = _selectedCategoryId;
    if (selectedId == null) {
      return 0;
    }

    final index = _categories.indexWhere((category) => category.id == selectedId);
    return index < 0 ? 0 : index;
  }

  void _focusCategory(int index) {
    if (!mounted || _categories.isEmpty) {
      return;
    }

    final safeIndex = index.clamp(0, _categories.length - 1).toInt();
    _syncCategoryFocusNodes();
    if (safeIndex >= _categoryFocusNodes.length) {
      return;
    }

    _categoryFocusNodes[safeIndex].requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _categoryFocusNodes[safeIndex].context;
      if (context != null && mounted) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          alignment: 0.18,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  void _focusSelectedCategory() {
    _focusCategory(_selectedCategoryIndex);
  }

  void _focusFirstContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _contentKey.currentState?.focusFirstCard();
    });
  }

  Future<void> _submitTvSearch() async {
    _searchDebounce?.cancel();
    final query = _searchController.text.trim();

    setState(() {
      _searchDraft = _searchController.text;
      _searchQuery = query;
      if (query.isEmpty) {
        _errorMessage = null;
      }
    });

    if (query.isEmpty) {
      _focusSelectedCategory();
      return;
    }

    if (_allMovies == null) {
      setState(() {
        _allMovies = List<Movie>.from(_categoryMovies);
      });
    }

    unawaited(_loadAllMoviesForSearch());
    _focusFirstContent();
  }

  KeyEventResult _handleSearchButtonKey(FocusNode node, KeyEvent event) {
    if (!widget.enableTvRemoteNavigation || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      unawaited(_submitTvSearch());
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      if (_searchQuery.trim().isNotEmpty) {
        _focusFirstContent();
      } else {
        _focusSelectedCategory();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleCategoryKey(int index, FocusNode node, KeyEvent event) {
    if (!widget.enableTvRemoteNavigation || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      _focusCategory(index + 1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        _focusCategory(index - 1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      _focusFirstContent();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      _selectCategory(_categories[index]);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _refresh() async {
    if (_searchQuery.trim().isNotEmpty) {
      setState(() {
        _allMovies = null;
      });

      await _loadAllMoviesForSearch(forceRefresh: true);
      return;
    }

    await _loadSelectedCategory(forceRefresh: true);
  }

  void _openMovieGroup(MovieGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MobileMovieDetailScreen(
          session: widget.session,
          movie: group.primary,
          versions: group.variants,
          displayTitle: group.displayTitle,
          enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searching =
        _searchQuery.trim().isNotEmpty;
    final loading = searching
        ? _loadingGlobalSearch
        : _loadingMovies;

    if (widget.enableTvRemoteNavigation) {
      _syncCategoryFocusNodes();
    }

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              widget.enableTvRemoteNavigation ? 10 : 18,
              20,
              widget.enableTvRemoteNavigation ? 8 : 14,
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'Películas',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Explora el catálogo de tu cuenta',
                  style: TextStyle(
                    color: Color(0xFF98A2B3),
                    fontSize: 13,
                  ),
                ),
                if (!widget.enableTvRemoteNavigation)
                  const SizedBox(height: 18),
                if (!widget.enableTvRemoteNavigation)
                  TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    onSubmitted: _submitSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Buscar en todas las películas',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: (_searchDraft.isEmpty && _searchQuery.isEmpty)
                          ? null
                          : IconButton(
                              onPressed: _clearSearch,
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
              ],
            ),
          ),
          if (!searching)
            SizedBox(
              height: 48,
              child: _loadingCategories
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2.5,
                        ),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection:
                          Axis.horizontal,
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      itemCount:
                          _categories.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: 9),
                      controller: widget.enableTvRemoteNavigation
                          ? _categoryScrollController
                          : null,
                      itemBuilder: (context, index) {
                        final category = _categories[index];
                        final label = CategoryNameLocalizer.toSpanish(
                          category.name,
                          section: CategorySection.movies,
                        );
                        final selected = _selectedCategoryId == category.id;

                        if (widget.enableTvRemoteNavigation) {
                          return _TvCategoryChip(
                            label: label,
                            selected: selected,
                            focusNode: _categoryFocusNodes[index],
                            onPressed: () {
                              _selectCategory(category);
                            },
                            onKeyEvent: (node, event) =>
                                _handleCategoryKey(index, node, event),
                          );
                        }

                        return ChoiceChip(
                          selected: selected,
                          onSelected: (_) {
                            _selectCategory(category);
                          },
                          label: Text(label),
                        );
                      },
                    ),
              ),
          const SizedBox(height: 10),
          Expanded(
            child: _MoviesContent(
              key: _contentKey,
              groups: _visibleMovieGroups,
              loading: loading,
              errorMessage: _errorMessage,
              categoryNames: _categoryNames,
              searching: searching,
              onRefresh: _refresh,
              onRetry: searching
                  ? _loadAllMoviesForSearch
                  : _loadSelectedCategory,
              onOpenGroup: _openMovieGroup,
              enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
              onMoveUpFromFirstRow: () {
                if (searching && !widget.enableTvRemoteNavigation) {
                  _searchButtonFocusNode.requestFocus();
                } else {
                  _focusSelectedCategory();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MoviesContent extends StatefulWidget {
  const _MoviesContent({
    super.key,
    required this.groups,
    required this.loading,
    required this.errorMessage,
    required this.categoryNames,
    required this.searching,
    required this.onRefresh,
    required this.onRetry,
    required this.onOpenGroup,
    required this.enableTvRemoteNavigation,
    required this.onMoveUpFromFirstRow,
  });

  final List<MovieGroup> groups;
  final bool loading;
  final String? errorMessage;
  final Map<String, String> categoryNames;
  final bool searching;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onRetry;
  final ValueChanged<MovieGroup> onOpenGroup;
  final bool enableTvRemoteNavigation;
  final VoidCallback onMoveUpFromFirstRow;

  @override
  State<_MoviesContent> createState() => _MoviesContentState();
}

class _MoviesContentState extends State<_MoviesContent> {
  final List<FocusNode> _cardFocusNodes = <FocusNode>[];
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant _MoviesContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFocusNodes();
    final changedDataset = oldWidget.groups.length != widget.groups.length ||
        (oldWidget.groups.isNotEmpty &&
            widget.groups.isNotEmpty &&
            oldWidget.groups.first.primary.streamId !=
                widget.groups.first.primary.streamId);
    if (changedDataset) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _syncFocusNodes() {
    while (_cardFocusNodes.length < widget.groups.length) {
      _cardFocusNodes.add(
        FocusNode(debugLabel: 'tv-movie-card-${_cardFocusNodes.length}'),
      );
    }

    while (_cardFocusNodes.length > widget.groups.length) {
      _cardFocusNodes.removeLast().dispose();
    }
  }

  void focusFirstCard() {
    _focusCard(0, alignment: 0.14);
  }

  void _focusCard(int index, {double alignment = 0.22}) {
    if (!mounted || index < 0 || index >= _cardFocusNodes.length) {
      return;
    }

    _cardFocusNodes[index].requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _cardFocusNodes[index].context;
      if (context != null && mounted) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          alignment: alignment,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        );
      }
    });
  }

  KeyEventResult _handleCardKey(
    int index,
    int crossAxisCount,
    FocusNode node,
    KeyEvent event,
  ) {
    if (!widget.enableTvRemoteNavigation || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final row = index ~/ crossAxisCount;
    final column = index % crossAxisCount;

    if (key == LogicalKeyboardKey.arrowRight) {
      final target = index + 1;
      if (column < crossAxisCount - 1 && target < widget.groups.length) {
        _focusCard(target);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (column > 0 && index > 0) {
        _focusCard(index - 1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      final target = index + crossAxisCount;
      if (target < widget.groups.length) {
        _focusCard(target, alignment: 0.72);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (row > 0) {
        _focusCard(index - crossAxisCount, alignment: 0.16);
        return KeyEventResult.handled;
      }

      widget.onMoveUpFromFirstRow();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    _syncFocusNodes();

    if (widget.loading && widget.groups.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (widget.errorMessage != null && widget.groups.isEmpty) {
      return _CenteredMessage(
        icon: Icons.cloud_off_rounded,
        title: 'No se pudo cargar',
        message: widget.errorMessage!,
        buttonLabel: 'REINTENTAR',
        onPressed: () {
          unawaited(widget.onRetry());
        },
      );
    }

    if (widget.groups.isEmpty) {
      return _CenteredMessage(
        icon: widget.searching
            ? Icons.search_off_rounded
            : Icons.movie_filter_outlined,
        title: widget.searching ? 'Sin resultados' : 'Categoría vacía',
        message: widget.searching
            ? 'No encontramos películas con esa búsqueda.'
            : 'Esta categoría no contiene películas.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final crossAxisCount = width >= 850
            ? 6
            : width >= 650
                ? 5
                : width >= 480
                    ? 4
                    : 3;

        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: GridView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
            itemCount: widget.groups.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 14,
              crossAxisSpacing: 10,
              childAspectRatio: 0.56,
            ),
            itemBuilder: (context, index) {
              final group = widget.groups[index];

              return _MovieCard(
                group: group,
                categoryName: widget.categoryNames[group.primary.categoryId] ?? '',
                showCategory: widget.searching,
                onPressed: () {
                  widget.onOpenGroup(group);
                },
                enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
                focusNode: widget.enableTvRemoteNavigation
                    ? _cardFocusNodes[index]
                    : null,
                autofocus: widget.enableTvRemoteNavigation && index == 0,
                onKeyEvent: (node, event) => _handleCardKey(
                  index,
                  crossAxisCount,
                  node,
                  event,
                ),
              );
            },
          ),
        );
      },
    );
  }
}


class _TvCategoryChip extends StatelessWidget {
  const _TvCategoryChip({
    required this.label,
    required this.selected,
    required this.focusNode,
    required this.onPressed,
    required this.onKeyEvent,
  });

  final String label;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final FocusOnKeyEventCallback onKeyEvent;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);

    return TvFocusableSurface(
      enabled: true,
      onPressed: onPressed,
      focusNode: focusNode,
      onKeyEvent: onKeyEvent,
      borderRadius: radius,
      builder: (context, focused) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF5877FF) : const Color(0xFF151B27),
            borderRadius: radius,
            border: Border.all(
              color: focused ? Colors.white : const Color(0xFF2B3444),
              width: focused ? 3 : 1,
            ),
            boxShadow: focused
                ? const [
                    BoxShadow(
                      color: Color(0xAA6F8CFF),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : const Color(0xFFD8DEEA),
            ),
          ),
        );
      },
    );
  }
}

class _MovieCard extends StatelessWidget {
  const _MovieCard({
    required this.group,
    required this.categoryName,
    required this.showCategory,
    required this.onPressed,
    required this.enableTvRemoteNavigation,
    this.focusNode,
    this.autofocus = false,
    this.onKeyEvent,
  });

  final MovieGroup group;
  final String categoryName;
  final bool showCategory;
  final VoidCallback onPressed;
  final bool enableTvRemoteNavigation;
  final FocusNode? focusNode;
  final bool autofocus;
  final FocusOnKeyEventCallback? onKeyEvent;

  @override
  Widget build(BuildContext context) {
    final movie = group.primary;

    final radius = BorderRadius.circular(16);

    return TvFocusableSurface(
      enabled: enableTvRemoteNavigation,
      onPressed: onPressed,
      focusNode: focusNode,
      autofocus: autofocus,
      onKeyEvent: onKeyEvent,
      borderRadius: radius,
      builder: (context, focused) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: focused ? const EdgeInsets.all(3) : EdgeInsets.zero,
          decoration: focused
              ? BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: const Color(0xFF6F8CFF),
                    width: 3,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x806F8CFF),
                      blurRadius: 14,
                    ),
                  ],
                )
              : null,
          child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Hero(
                tag: 'movie-${movie.streamId}',
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(16),
                  child: SizedBox.expand(
                    child: movie.posterUrl.isEmpty
                        ? const _MoviePosterFallback()
                        : AppCachedImage(
                            imageUrl: movie.posterUrl,
                            fit: BoxFit.cover,
                            cacheWidth: 360,
                            cacheHeight: 540,
                            placeholder: const _MoviePosterFallback(
                              loading: true,
                            ),
                            fallback: const _MoviePosterFallback(),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              group.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            if (group.versionCount > 1) ...[
              Row(
                children: [
                  const Icon(
                    Icons.layers_rounded,
                    size: 12,
                    color: Color(0xFFBE91FF),
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      '${group.versionCount} versiones',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFBE91FF),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
            ],
            Row(
              children: [
                if (movie.displayYear.isNotEmpty)
                  Text(
                    movie.displayYear,
                    style: const TextStyle(
                      color: Color(0xFF98A2B3),
                      fontSize: 10.5,
                    ),
                  ),
                if (movie.displayYear.isNotEmpty &&
                    movie.displayRating.isNotEmpty)
                  const Text(
                    '  •  ',
                    style: TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 10,
                    ),
                  ),
                if (movie.displayRating.isNotEmpty)
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFFFC857),
                        size: 13,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        movie.displayRating,
                        style: const TextStyle(
                          color: Color(0xFF98A2B3),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (showCategory &&
                categoryName.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                categoryName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF7F8DB5),
                  fontSize: 9.5,
                ),
              ),
            ],
          ],
          ),
        );
      },
    );
  }
}

class _MoviePosterFallback extends StatelessWidget {
  const _MoviePosterFallback({
    this.loading = false,
  });

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF171D28),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                ),
              )
            : const Icon(
                Icons.movie_creation_outlined,
                color: Color(0xFF667085),
                size: 38,
              ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.buttonLabel,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      children: [
        const SizedBox(height: 90),
        Icon(
          icon,
          size: 62,
          color: const Color(0xFF667085),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF98A2B3),
            height: 1.4,
          ),
        ),
        if (buttonLabel != null &&
            onPressed != null) ...[
          const SizedBox(height: 22),
          Center(
            child: FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(
                Icons.refresh_rounded,
              ),
              label: Text(buttonLabel!),
            ),
          ),
        ],
      ],
    );
  }
}
