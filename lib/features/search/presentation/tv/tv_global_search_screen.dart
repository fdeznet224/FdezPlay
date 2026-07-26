import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/services/iptv_api_service.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/tv_focusable_surface.dart';
import '../../../auth/domain/auth_session.dart';
import '../../data/search_index_service.dart';
import '../../../live_tv/domain/live_channel.dart';
import '../../../live_tv/domain/live_channel_group.dart';
import '../../../movies/domain/movie.dart';
import '../../../movies/domain/movie_group.dart';
import '../../../movies/presentation/mobile/mobile_movie_detail_screen.dart';
import '../../../player/presentation/tv/tv_live_player_screen.dart';
import '../../../series/domain/series_group.dart';
import '../../../series/domain/tv_series.dart';
import '../../../series/presentation/mobile/mobile_series_detail_screen.dart';

class TvGlobalSearchScreen extends StatefulWidget {
  const TvGlobalSearchScreen({required this.session, super.key});

  final AuthSession session;

  @override
  State<TvGlobalSearchScreen> createState() => _TvGlobalSearchScreenState();
}

class _TvGlobalSearchScreenState extends State<TvGlobalSearchScreen> {
  static const int _sectionChannels = 0;
  static const int _sectionMovies = 1;
  static const int _sectionSeries = 2;

  static const int _filterAll = 0;
  static const int _filterTv = 1;
  static const int _filterMovies = 2;
  static const int _filterSeries = 3;

  final FdezSearchIndexService _searchIndexService = FdezSearchIndexService();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchFieldFocusNode = FocusNode(debugLabel: 'tv-global-search-field');
  final FocusNode _searchButtonFocusNode = FocusNode(debugLabel: 'tv-global-search-button');
  final FocusNode _backFocusNode = FocusNode(debugLabel: 'tv-global-search-back');
  final FocusNode _resultsFocusNode = FocusNode(debugLabel: 'tv-global-search-results');
  final ScrollController _pageScrollController = ScrollController();
  final ScrollController _channelScrollController = ScrollController();
  final ScrollController _movieScrollController = ScrollController();
  final ScrollController _seriesScrollController = ScrollController();

  List<LiveChannel>? _allChannels;
  List<Movie>? _allMovies;
  List<TvSeries>? _allSeries;

  List<LiveChannelGroup>? _allChannelGroups;
  List<MovieGroup>? _allMovieGroups;
  List<SeriesGroup>? _allSeriesGroups;

  List<LiveChannelGroup> _channelResults = const [];
  List<MovieGroup> _movieResults = const [];
  List<SeriesGroup> _seriesResults = const [];

  String _query = '';
  int _selectedFilter = _filterAll;
  bool _loading = false;
  bool _searched = false;
  int _searchGeneration = 0;
  String? _errorMessage;

  int? _focusedSection;
  int _focusedIndex = 0;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _backFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _controller.dispose();
    _searchFieldFocusNode.dispose();
    _searchButtonFocusNode.dispose();
    _backFocusNode.dispose();
    _resultsFocusNode.dispose();
    _pageScrollController.dispose();
    _channelScrollController.dispose();
    _movieScrollController.dispose();
    _seriesScrollController.dispose();
    super.dispose();
  }

  void _onSearchTextChanged(String value) {
    _searchDebounce?.cancel();

    final query = value.trim();
    if (query.isEmpty) {
      _searchGeneration++;
      setState(() {
        _query = '';
        _searched = false;
        _loading = false;
        _errorMessage = null;
        _channelResults = const [];
        _movieResults = const [];
        _seriesResults = const [];
        _focusedSection = null;
        _focusedIndex = 0;
      });
      return;
    }

    setState(() {
      _query = query;
      _searched = true;
      _loading = true;
      _errorMessage = null;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 420), () {
      unawaited(_runSearch(keepKeyboardOpen: true));
    });
  }

  Future<void> _runSearch({bool keepKeyboardOpen = false}) async {
    _searchDebounce?.cancel();
    final query = _controller.text.trim();

    if (!keepKeyboardOpen) {
      FocusScope.of(context).unfocus();
    }

    if (query.isEmpty) {
      _searchGeneration++;
      setState(() {
        _query = '';
        _searched = false;
        _loading = false;
        _errorMessage = null;
        _channelResults = const [];
        _movieResults = const [];
        _seriesResults = const [];
        _focusedSection = null;
        _focusedIndex = 0;
      });
      if (!keepKeyboardOpen) {
        _searchFieldFocusNode.requestFocus();
      }
      return;
    }

    final generation = ++_searchGeneration;

    setState(() {
      _query = query;
      _loading = true;
      _searched = true;
      _errorMessage = null;
      if (!_filterAllowsSection(_sectionChannels)) {
        _channelResults = const [];
      }
      if (!_filterAllowsSection(_sectionMovies)) {
        _movieResults = const [];
      }
      if (!_filterAllowsSection(_sectionSeries)) {
        _seriesResults = const [];
      }
    });

    void applyResults({
      List<LiveChannelGroup>? channelResults,
      List<MovieGroup>? movieResults,
      List<SeriesGroup>? seriesResults,
    }) {
      if (!mounted || generation != _searchGeneration) {
        return;
      }

      setState(() {
        if (channelResults != null) {
          _channelResults = channelResults;
        }
        if (movieResults != null) {
          _movieResults = movieResults;
        }
        if (seriesResults != null) {
          _seriesResults = seriesResults;
        }
      });

      if (!keepKeyboardOpen) {
        _focusFirstResultIfNeeded();
      }
    }

    Future<bool> loadChannels() async {
      try {
        final channelResults = await _searchIndexService
            .searchChannels(widget.session, query, limit: 12)
            .timeout(const Duration(seconds: 24));
        applyResults(channelResults: channelResults);
        return true;
      } catch (_) {
        applyResults(channelResults: const []);
        return false;
      }
    }

    Future<bool> loadMovies() async {
      try {
        final movieResults = await _searchIndexService
            .searchMovies(widget.session, query, limit: 18)
            .timeout(const Duration(seconds: 26));
        applyResults(movieResults: movieResults);
        return true;
      } catch (_) {
        applyResults(movieResults: const []);
        return false;
      }
    }

    Future<bool> loadSeries() async {
      try {
        final seriesResults = await _searchIndexService
            .searchSeries(widget.session, query, limit: 18)
            .timeout(const Duration(seconds: 26));
        applyResults(seriesResults: seriesResults);
        return true;
      } catch (_) {
        applyResults(seriesResults: const []);
        return false;
      }
    }

    final results = <bool>[];

    if (_filterAllowsSection(_sectionChannels)) {
      results.add(await loadChannels());
    } else {
      applyResults(channelResults: const []);
      results.add(true);
    }

    if (!mounted || generation != _searchGeneration) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (_filterAllowsSection(_sectionMovies)) {
      results.add(await loadMovies());
    } else {
      applyResults(movieResults: const []);
      results.add(true);
    }

    if (!mounted || generation != _searchGeneration) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (_filterAllowsSection(_sectionSeries)) {
      results.add(await loadSeries());
    } else {
      applyResults(seriesResults: const []);
      results.add(true);
    }

    if (!mounted || generation != _searchGeneration) {
      return;
    }

    final hasAnyLoaded = results.any((value) => value);

    setState(() {
      _loading = false;
      _errorMessage = hasAnyLoaded
          ? null
          : 'No se pudo completar la búsqueda. Intenta de nuevo.';
    });

    if (_hasResults && !keepKeyboardOpen) {
      _focusFirstResultIfNeeded(force: true);
    }
  }

  bool get _hasResults =>
      (_filterAllowsSection(_sectionChannels) && _channelResults.isNotEmpty) ||
      (_filterAllowsSection(_sectionMovies) && _movieResults.isNotEmpty) ||
      (_filterAllowsSection(_sectionSeries) && _seriesResults.isNotEmpty);

  bool _filterAllowsSection(int section) {
    return _selectedFilter == _filterAll ||
        (_selectedFilter == _filterTv && section == _sectionChannels) ||
        (_selectedFilter == _filterMovies && section == _sectionMovies) ||
        (_selectedFilter == _filterSeries && section == _sectionSeries);
  }

  void _changeFilter(int value) {
    if (_selectedFilter == value) {
      return;
    }

    setState(() {
      _selectedFilter = value;
      _focusedSection = null;
      _focusedIndex = 0;
      if (!_filterAllowsSection(_sectionChannels)) {
        _channelResults = const [];
      }
      if (!_filterAllowsSection(_sectionMovies)) {
        _movieResults = const [];
      }
      if (!_filterAllowsSection(_sectionSeries)) {
        _seriesResults = const [];
      }
    });

    if (_controller.text.trim().isNotEmpty) {
      unawaited(_runSearch(keepKeyboardOpen: true));
    }
  }

  int _sectionLength(int section) {
    if (!_filterAllowsSection(section)) {
      return 0;
    }

    switch (section) {
      case _sectionChannels:
        return _channelResults.length;
      case _sectionMovies:
        return _movieResults.length;
      case _sectionSeries:
        return _seriesResults.length;
    }
    return 0;
  }

  int? _firstNonEmptySection() {
    for (final section in const [_sectionChannels, _sectionMovies, _sectionSeries]) {
      if (_sectionLength(section) > 0) {
        return section;
      }
    }
    return null;
  }

  int? _previousNonEmptySection(int section) {
    for (var candidate = section - 1; candidate >= _sectionChannels; candidate--) {
      if (_sectionLength(candidate) > 0) {
        return candidate;
      }
    }
    return null;
  }

  int? _nextNonEmptySection(int section) {
    for (var candidate = section + 1; candidate <= _sectionSeries; candidate++) {
      if (_sectionLength(candidate) > 0) {
        return candidate;
      }
    }
    return null;
  }

  void _focusFirstResultIfNeeded({bool force = false}) {
    if (!_hasResults || !mounted) {
      return;
    }

    if (!force && _focusedSection != null && _sectionLength(_focusedSection!) > 0) {
      return;
    }

    final section = _firstNonEmptySection();
    if (section == null) {
      return;
    }

    _setFocusedResult(section, 0, requestKeyboardFocus: true);
  }

  void _setFocusedResult(
    int section,
    int index, {
    bool requestKeyboardFocus = true,
  }) {
    final length = _sectionLength(section);
    if (length <= 0) {
      return;
    }

    final safeIndex = index.clamp(0, length - 1).toInt();

    setState(() {
      _focusedSection = section;
      _focusedIndex = safeIndex;
    });

    if (requestKeyboardFocus) {
      _resultsFocusNode.requestFocus();
    }

    _scrollToFocusedResult(section, safeIndex);
  }

  void _scrollToFocusedResult(int section, int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final itemWidth = section == _sectionChannels ? 274.0 : 146.0;
      final controller = switch (section) {
        _sectionChannels => _channelScrollController,
        _sectionMovies => _movieScrollController,
        _ => _seriesScrollController,
      };

      if (controller.hasClients) {
        final target = (index * itemWidth)
            .clamp(0.0, controller.position.maxScrollExtent)
            .toDouble();
        controller.animateTo(
          target,
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
        );
      }

      final pageTarget = switch (section) {
        _sectionChannels => 0.0,
        _sectionMovies => 155.0,
        _ => 420.0,
      };
      if (_pageScrollController.hasClients) {
        _pageScrollController.animateTo(
          pageTarget
              .clamp(0.0, _pageScrollController.position.maxScrollExtent)
              .toDouble(),
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _clearSearch() {
    _controller.clear();
    _searchGeneration++;
    setState(() {
      _query = '';
      _searched = false;
      _loading = false;
      _errorMessage = null;
      _channelResults = const [];
      _movieResults = const [];
      _seriesResults = const [];
      _focusedSection = null;
      _focusedIndex = 0;
    });
    _searchFieldFocusNode.requestFocus();
  }

  void _openChannel(LiveChannelGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TvLivePlayerScreen(
          session: widget.session,
          channel: group.preferredVariant.channel,
          channelVariants: group.variants
              .map((variant) => variant.channel)
              .toList(growable: false),
        ),
      ),
    );
  }

  void _openMovie(MovieGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MobileMovieDetailScreen(
          session: widget.session,
          movie: group.primary,
          versions: group.variants,
          displayTitle: group.displayTitle,
          enableTvRemoteNavigation: true,
        ),
      ),
    );
  }

  void _openSeries(SeriesGroup group) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MobileSeriesDetailScreen(
          session: widget.session,
          series: group.primary,
          versions: group.variants,
          displayTitle: group.displayTitle,
          enableTvRemoteNavigation: true,
        ),
      ),
    );
  }

  void _openFocusedResult() {
    final section = _focusedSection;
    if (section == null) {
      return;
    }

    final index = _focusedIndex;
    switch (section) {
      case _sectionChannels:
        if (index >= 0 && index < _channelResults.length) {
          _openChannel(_channelResults[index]);
        }
        break;
      case _sectionMovies:
        if (index >= 0 && index < _movieResults.length) {
          _openMovie(_movieResults[index]);
        }
        break;
      case _sectionSeries:
        if (index >= 0 && index < _seriesResults.length) {
          _openSeries(_seriesResults[index]);
        }
        break;
    }
  }

  KeyEventResult _handleTopKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _focusFirstResultIfNeeded(force: true);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      _backFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _searchFieldFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleResultsKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final section = _focusedSection ?? _firstNonEmptySection();
    if (section == null) {
      return KeyEventResult.ignored;
    }

    if (_focusedSection == null) {
      _setFocusedResult(section, 0);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      final length = _sectionLength(section);
      if (_focusedIndex + 1 < length) {
        _setFocusedResult(section, _focusedIndex + 1);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_focusedIndex > 0) {
        _setFocusedResult(section, _focusedIndex - 1);
      } else {
        _searchFieldFocusNode.requestFocus();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      final previous = _previousNonEmptySection(section);
      if (previous == null) {
        _searchFieldFocusNode.requestFocus();
      } else {
        _setFocusedResult(previous, _focusedIndex);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      final next = _nextNonEmptySection(section);
      if (next != null) {
        _setFocusedResult(next, _focusedIndex);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      _openFocusedResult();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final hasResults = _hasResults;

    return PopScope(
      canPop: true,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
                child: Row(
                  children: [
                    TvNeonFocus(
                      focusNode: _backFocusNode,
                      borderRadius: BorderRadius.circular(24),
                      padding: const EdgeInsets.all(2),
                      onPressed: () => Navigator.of(context).pop(),
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent &&
                            (event.logicalKey == LogicalKeyboardKey.select ||
                                event.logicalKey == LogicalKeyboardKey.enter ||
                                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                                event.logicalKey == LogicalKeyboardKey.space)) {
                          Navigator.of(context).pop();
                          return KeyEventResult.handled;
                        }
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.arrowRight) {
                          _searchFieldFocusNode.requestFocus();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Buscar',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        focusNode: _searchFieldFocusNode,
                        controller: _controller,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => unawaited(_runSearch()),
                        onChanged: _onSearchTextChanged,
                        decoration: InputDecoration(
                          hintText: 'Buscar canales, películas o series',
                          prefixIcon: const Icon(Icons.search_rounded),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                              color: kTvFocusNeonColor,
                              width: 3.2,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(color: Color(0xFF31384A)),
                          ),
                          suffixIcon: _controller.text.isEmpty
                              ? null
                              : ExcludeFocus(
                                  child: IconButton(
                                    onPressed: _clearSearch,
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ),
                        ),
                      ),
                    ),

                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                child: _TvSearchFilterBar(
                  selectedFilter: _selectedFilter,
                  onChanged: _changeFilter,
                ),
              ),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Color(0xFFFF9A9A)),
                  ),
                ),
              Expanded(
                child: _searched
                    ? hasResults || _loading
                        ? Focus(
                            focusNode: _resultsFocusNode,
                            onKeyEvent: _handleResultsKey,
                            child: ListView(
                              controller: _pageScrollController,
                              padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
                              children: [
                                if (_filterAllowsSection(_sectionChannels))
                                  _ResultSection<LiveChannelGroup>(
                                  title: 'TV Online',
                                  subtitle: '${_channelResults.length} coincidencias',
                                  sectionIndex: _sectionChannels,
                                  focusedSection: _focusedSection,
                                  focusedIndex: _focusedIndex,
                                  items: _channelResults,
                                  scrollController: _channelScrollController,
                                  onPressed: _openChannel,
                                  onFocusIndexChanged: (index) => _setFocusedResult(
                                    _sectionChannels,
                                    index,
                                  ),
                                  height: 142,
                                  itemWidth: 292,
                                  itemBuilder: (context, item, focused) => _ChannelResultCard(
                                    group: item,
                                    focused: focused,
                                  ),
                                ),
                                if (_filterAllowsSection(_sectionMovies))
                                  _ResultSection<MovieGroup>(
                                  title: 'Películas',
                                  subtitle: '${_movieResults.length} coincidencias',
                                  sectionIndex: _sectionMovies,
                                  focusedSection: _focusedSection,
                                  focusedIndex: _focusedIndex,
                                  items: _movieResults,
                                  scrollController: _movieScrollController,
                                  onPressed: _openMovie,
                                  onFocusIndexChanged: (index) => _setFocusedResult(
                                    _sectionMovies,
                                    index,
                                  ),
                                  height: 248,
                                  itemWidth: 170,
                                  itemBuilder: (context, item, focused) => _PosterResultCard(
                                    title: item.displayTitle,
                                    imageUrl: item.primary.posterUrl,
                                    meta: item.versionCount > 1
                                        ? '${item.versionCount} versiones'
                                        : item.primary.displayRating,
                                    focused: focused,
                                  ),
                                ),
                                if (_filterAllowsSection(_sectionSeries))
                                  _ResultSection<SeriesGroup>(
                                  title: 'Series',
                                  subtitle: '${_seriesResults.length} coincidencias',
                                  sectionIndex: _sectionSeries,
                                  focusedSection: _focusedSection,
                                  focusedIndex: _focusedIndex,
                                  items: _seriesResults,
                                  scrollController: _seriesScrollController,
                                  onPressed: _openSeries,
                                  onFocusIndexChanged: (index) => _setFocusedResult(
                                    _sectionSeries,
                                    index,
                                  ),
                                  height: 248,
                                  itemWidth: 170,
                                  itemBuilder: (context, item, focused) => _PosterResultCard(
                                    title: item.displayTitle,
                                    imageUrl: item.primary.coverUrl,
                                    meta: item.versionCount > 1
                                        ? '${item.versionCount} versiones'
                                        : item.primary.displayRating,
                                    focused: focused,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const _EmptySearchView()
                    : const _SearchIntroView(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _TvSearchFilterBar extends StatelessWidget {
  const _TvSearchFilterBar({
    required this.selectedFilter,
    required this.onChanged,
  });

  final int selectedFilter;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final filters = <_SearchFilterOption>[
      const _SearchFilterOption(0, 'Todo', Icons.auto_awesome_rounded),
      const _SearchFilterOption(1, 'TV', Icons.live_tv_rounded),
      const _SearchFilterOption(2, 'Películas', Icons.movie_rounded),
      const _SearchFilterOption(3, 'Series', Icons.video_library_rounded),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final filter in filters)
          ChoiceChip(
            selected: selectedFilter == filter.value,
            onSelected: (_) => onChanged(filter.value),
            avatar: Icon(
              filter.icon,
              size: 17,
              color: selectedFilter == filter.value
                  ? Colors.white
                  : const Color(0xFF9CA3AF),
            ),
            label: Text(filter.label),
            labelStyle: TextStyle(
              color: selectedFilter == filter.value
                  ? Colors.white
                  : const Color(0xFFB8C0CC),
              fontWeight: FontWeight.w800,
            ),
            backgroundColor: const Color(0xFF111620),
            selectedColor: const Color(0xFF334B92),
            side: BorderSide(
              color: selectedFilter == filter.value
                  ? const Color(0xFF8EA5FF)
                  : const Color(0xFF283142),
            ),
          ),
      ],
    );
  }
}

class _SearchFilterOption {
  const _SearchFilterOption(this.value, this.label, this.icon);

  final int value;
  final String label;
  final IconData icon;
}

class _ResultSection<T> extends StatelessWidget {
  const _ResultSection({
    required this.title,
    required this.subtitle,
    required this.sectionIndex,
    required this.focusedSection,
    required this.focusedIndex,
    required this.items,
    required this.scrollController,
    required this.itemBuilder,
    required this.onPressed,
    required this.onFocusIndexChanged,
    required this.height,
    required this.itemWidth,
  });

  final String title;
  final String subtitle;
  final int sectionIndex;
  final int? focusedSection;
  final int focusedIndex;
  final List<T> items;
  final ScrollController scrollController;
  final Widget Function(BuildContext context, T item, bool focused) itemBuilder;
  final ValueChanged<T> onPressed;
  final ValueChanged<int> onFocusIndexChanged;
  final double height;
  final double itemWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 10),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Container(
              height: 74,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: const Color(0xFF111620),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF252C38)),
              ),
              child: const Text(
                'Sin coincidencias en esta sección.',
                style: TextStyle(color: Color(0xFF98A2B3)),
              ),
            )
          else
            SizedBox(
              height: height,
              child: ListView.separated(
                controller: scrollController,
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final focused = focusedSection == sectionIndex && focusedIndex == index;

                  return SizedBox(
                    width: itemWidth,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (_) => onFocusIndexChanged(index),
                      onTap: () => onPressed(item),
                      child: itemBuilder(context, item, focused),
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

class _ChannelResultCard extends StatelessWidget {
  const _ChannelResultCard({required this.group, required this.focused});

  final LiveChannelGroup group;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.all(12),
      decoration: tvFocusedDecoration(
        focused: focused,
        backgroundColor: const Color(0xFF111620),
        borderRadius: radius,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 78,
              height: 78,
              child: AppCachedImage(
                imageUrl: group.representative.iconUrl,
                fit: BoxFit.contain,
                cacheWidth: 180,
                cacheHeight: 180,
                fallback: const ColoredBox(
                  color: Color(0xFF17213B),
                  child: Icon(
                    Icons.live_tv_rounded,
                    color: Color(0xFF8EA5FF),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  group.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  group.variantCount > 1
                      ? '${group.variantCount} señales'
                      : '1 señal disponible',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterResultCard extends StatelessWidget {
  const _PosterResultCard({
    required this.title,
    required this.imageUrl,
    required this.meta,
    required this.focused,
  });

  final String title;
  final String imageUrl;
  final String meta;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: focused ? const EdgeInsets.all(3) : EdgeInsets.zero,
            decoration: focused
                ? BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xCC6F8CFF),
                        blurRadius: 22,
                        spreadRadius: 3,
                      ),
                    ],
                  )
                : null,
            child: ClipRRect(
              borderRadius: radius,
              child: SizedBox.expand(
                child: AppCachedImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  cacheWidth: 360,
                  cacheHeight: 540,
                  placeholder: const _PosterFallback(),
                  fallback: const _PosterFallback(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
        if (meta.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 11),
          ),
        ],
      ],
    );
  }
}


class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF17213B),
            Color(0xFF0B1020),
          ],
        ),
      ),
      child: Icon(
        Icons.movie_rounded,
        color: Color(0xFF8EA5FF),
        size: 42,
      ),
    );
  }
}

class _SearchIntroView extends StatelessWidget {
  const _SearchIntroView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Escribe una búsqueda para encontrar canales, películas y series.',
        style: TextStyle(color: Color(0xFF98A2B3), fontSize: 16),
      ),
    );
  }
}

class _EmptySearchView extends StatelessWidget {
  const _EmptySearchView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No encontramos coincidencias.',
        style: TextStyle(color: Color(0xFF98A2B3), fontSize: 16),
      ),
    );
  }
}

String _normalize(String value) {
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
