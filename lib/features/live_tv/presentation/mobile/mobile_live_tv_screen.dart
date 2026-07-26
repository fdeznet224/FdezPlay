import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../favorites/data/local_library_service.dart';
import '../../../player/presentation/mobile/mobile_live_player_screen.dart';
import '../../../../shared/models/iptv_category.dart';
import '../../../../shared/utils/category_name_localizer.dart';
import '../../../../shared/widgets/tv_focusable_surface.dart';
import '../../../auth/domain/auth_session.dart';
import '../../data/live_tv_service.dart';
import '../../domain/live_channel.dart';
import '../../domain/live_channel_group.dart';

class MobileLiveTvScreen extends StatefulWidget {
  const MobileLiveTvScreen({
    required this.session,
    this.enableTvRemoteNavigation = false,
    super.key,
  });

  final AuthSession session;
  final bool enableTvRemoteNavigation;

  @override
  State<MobileLiveTvScreen> createState() => _MobileLiveTvScreenState();
}

class _MobileLiveTvScreenState extends State<MobileLiveTvScreen> {
  final LiveTvService _service = LiveTvService();
  final LocalLibraryService _libraryService =
      LocalLibraryService.instance;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _categoryScrollController = ScrollController();
  final ScrollController _channelScrollController = ScrollController();
  final List<FocusNode> _categoryFocusNodes = <FocusNode>[];
  final List<FocusNode> _channelFocusNodes = <FocusNode>[];

  Timer? _searchDebounce;

  List<IptvCategory> _categories = [];
  List<LiveChannelGroup> _channelGroups = [];
  List<LiveChannelGroup> _allChannelGroups = [];

  String? _selectedCategoryId;
  String _searchQuery = '';

  String? _errorMessage;
  String? _globalSearchError;

  bool _loadingInitialData = true;
  bool _loadingChannels = false;
  bool _loadingGlobalSearch = false;
  bool _allChannelsLoaded = false;

  Set<int> _favoriteChannelIds = <int>{};

  @override
  void initState() {
    super.initState();

    _searchController.addListener(_onSearchChanged);
    unawaited(_loadFavoriteChannels());
    unawaited(_loadInitialData());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();

    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _categoryScrollController.dispose();
    _channelScrollController.dispose();
    for (final node in _categoryFocusNodes) {
      node.dispose();
    }
    for (final node in _channelFocusNodes) {
      node.dispose();
    }

    super.dispose();
  }

  bool get _isSearching {
    return _searchQuery.trim().isNotEmpty;
  }

  List<LiveChannelGroup> get _visibleChannelGroups {
    final groups = _isSearching ? _allChannelGroups : _channelGroups;
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) {
      return List<LiveChannelGroup>.unmodifiable(groups);
    }

    return groups.where((group) {
      if (group.displayName.toLowerCase().contains(query)) {
        return true;
      }

      return group.variants.any(
        (variant) => variant.channel.name.toLowerCase().contains(query),
      );
    }).toList(growable: false);
  }

  void _reportGrouping(
    String scope,
    List<LiveChannel> channels,
    List<LiveChannelGroup> groups,
  ) {
    final multipleSignalGroups =
        groups.where((group) => group.variantCount > 1).length;

    debugPrint(
      '[FDEZPLAY-TV-GROUP] $scope: ${channels.length} señales -> '
      '${groups.length} canales únicos ($multipleSignalGroups agrupados)',
    );
  }

  String get _selectedCategoryName {
    return _categoryNameFromId(_selectedCategoryId, fallback: 'TV en vivo');
  }

  String _categoryNameFromId(
    String? categoryId, {
    String fallback = 'Sin categoría',
  }) {
    if (categoryId == null || categoryId.isEmpty) {
      return fallback;
    }

    for (final category in _categories) {
      if (category.id == categoryId) {
        return CategoryNameLocalizer.toSpanish(
          category.name,
          section: CategorySection.liveTv,
        );
      }
    }

    return fallback;
  }

  Future<void> _loadFavoriteChannels() async {
    try {
      final snapshot = await _libraryService.load(widget.session);

      if (!mounted) {
        return;
      }

      final favoriteIds = <int>{};

      for (final item in snapshot.favorites) {
        final channel = item.channel;

        if (channel != null) {
          favoriteIds.add(channel.streamId);
        }

        favoriteIds.addAll(
          item.channelVariants.map((variant) => variant.streamId),
        );
      }

      setState(() {
        _favoriteChannelIds = favoriteIds;
      });
    } catch (_) {
      // La TV puede seguir funcionando aunque no se carguen favoritos.
    }
  }

  bool _isChannelGroupFavorite(LiveChannelGroup group) {
    return group.streamIds.any(_favoriteChannelIds.contains);
  }

  Future<bool> _toggleChannelGroupFavorite(
    LiveChannelGroup group,
  ) async {
    final variants = group.variants
        .map((variant) => variant.channel)
        .toList(growable: false);
    final isFavorite =
        await _libraryService.toggleChannelFavoriteGroup(
      widget.session,
      channel: group.representative,
      variants: variants,
    );

    if (!mounted) {
      return isFavorite;
    }

    setState(() {
      if (isFavorite) {
        _favoriteChannelIds.addAll(group.streamIds);
      } else {
        _favoriteChannelIds.removeAll(group.streamIds);
      }
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            isFavorite
                ? '${group.displayName} agregado a favoritos.'
                : '${group.displayName} eliminado de favoritos.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );

    return isFavorite;
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();

    _searchDebounce?.cancel();

    setState(() {
      _searchQuery = query;

      if (query.isEmpty) {
        _globalSearchError = null;
      }
    });

    if (query.isEmpty || _allChannelsLoaded || _loadingGlobalSearch) {
      return;
    }

    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      _loadAllChannelsForSearch,
    );
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _loadingInitialData = true;
      _errorMessage = null;
    });

    try {
      final categories = await _service.loadCategories(widget.session);

      if (!mounted) {
        return;
      }

      if (categories.isEmpty) {
        setState(() {
          _categories = [];
          _channelGroups = [];
          _errorMessage = 'No se encontraron categorías de TV.';
          _loadingInitialData = false;
        });

        return;
      }

      final firstCategory = categories.first;

      setState(() {
        _categories = categories;
        _selectedCategoryId = firstCategory.id;
      });

      final channels = await _service.loadChannels(
        session: widget.session,
        categoryId: firstCategory.id,
      );

      if (!mounted) {
        return;
      }

      final groups = groupLiveChannels(channels);
      _reportGrouping('categoría ${firstCategory.id}', channels, groups);

      setState(() {
        _channelGroups = groups;
        _loadingInitialData = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingInitialData = false;
        _errorMessage = 'No fue posible cargar la TV en vivo.';
      });
    }
  }

  Future<void> _loadAllChannelsForSearch({bool force = false}) async {
    if (_loadingGlobalSearch) {
      return;
    }

    if (_allChannelsLoaded && !force) {
      return;
    }

    setState(() {
      _loadingGlobalSearch = true;
      _globalSearchError = null;

      if (force) {
        _allChannelsLoaded = false;
        _allChannelGroups = [];
      }
    });

    try {
      final channels = await _service.loadAllChannels(session: widget.session);

      if (!mounted) {
        return;
      }

      final groups = groupLiveChannels(channels);
      _reportGrouping('búsqueda global', channels, groups);

      setState(() {
        _allChannelGroups = groups;
        _allChannelsLoaded = true;
        _loadingGlobalSearch = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingGlobalSearch = false;
        _allChannelsLoaded = false;
        _globalSearchError = 'No fue posible buscar en todos los canales.';
      });
    }
  }

  Future<void> _selectCategory(IptvCategory category) async {
    if (_loadingChannels || category.id == _selectedCategoryId) {
      return;
    }

    _searchController.clear();

    setState(() {
      _selectedCategoryId = category.id;
      _loadingChannels = true;
      _errorMessage = null;
      _channelGroups = [];
    });

    try {
      final channels = await _service.loadChannels(
        session: widget.session,
        categoryId: category.id,
      );

      if (!mounted) {
        return;
      }

      final groups = groupLiveChannels(channels);
      _reportGrouping('categoría ${category.id}', channels, groups);

      setState(() {
        _channelGroups = groups;
        _loadingChannels = false;
      });

      if (widget.enableTvRemoteNavigation) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focusFirstChannel();
        });
      }
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingChannels = false;
        _errorMessage = 'No fue posible cargar los canales.';
      });
    }
  }


  void _syncTvFocusNodes(List<LiveChannelGroup> groups) {
    if (!widget.enableTvRemoteNavigation) {
      return;
    }

    while (_categoryFocusNodes.length < _categories.length) {
      _categoryFocusNodes.add(
        FocusNode(debugLabel: 'tv-live-category-${_categoryFocusNodes.length}'),
      );
    }

    while (_categoryFocusNodes.length > _categories.length) {
      _categoryFocusNodes.removeLast().dispose();
    }

    while (_channelFocusNodes.length < groups.length) {
      _channelFocusNodes.add(
        FocusNode(debugLabel: 'tv-live-channel-${_channelFocusNodes.length}'),
      );
    }

    while (_channelFocusNodes.length > groups.length) {
      _channelFocusNodes.removeLast().dispose();
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
    if (!widget.enableTvRemoteNavigation || _categories.isEmpty) {
      return;
    }

    final safeIndex = index.clamp(0, _categories.length - 1).toInt();
    if (safeIndex >= _categoryFocusNodes.length) {
      return;
    }

    _categoryFocusNodes[safeIndex].requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _categoryFocusNodes[safeIndex].context;
      if (context != null && mounted) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          alignment: 0.15,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  void _focusSelectedCategory() {
    _focusCategory(_selectedCategoryIndex);
  }

  void _focusChannel(int index, {double alignment = 0.18}) {
    if (!widget.enableTvRemoteNavigation ||
        index < 0 ||
        index >= _channelFocusNodes.length) {
      return;
    }

    _channelFocusNodes[index].requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _channelFocusNodes[index].context;
      if (context != null && mounted) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          alignment: alignment,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        );
      }
    });
  }

  void _focusFirstChannel() {
    if (_channelScrollController.hasClients) {
      _channelScrollController.jumpTo(0);
    }
    _focusChannel(0, alignment: 0.06);
  }

  KeyEventResult _handleLiveCategoryKey(
    int index,
    FocusNode node,
    KeyEvent event,
  ) {
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
      _focusFirstChannel();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      unawaited(_selectCategory(_categories[index]));
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleLiveChannelKey(
    int index,
    FocusNode node,
    KeyEvent event,
  ) {
    if (!widget.enableTvRemoteNavigation || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown) {
      final target = index + 1;
      if (target < _channelFocusNodes.length) {
        _focusChannel(target, alignment: 0.22);
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (index > 0) {
        _focusChannel(index - 1, alignment: 0.18);
      } else {
        _focusSelectedCategory();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _refreshCategoryChannels() async {
    final categoryId = _selectedCategoryId;

    if (categoryId == null) {
      await _loadInitialData();
      return;
    }

    try {
      final channels = await _service.loadChannels(
        session: widget.session,
        categoryId: categoryId,
      );

      if (!mounted) {
        return;
      }

      final groups = groupLiveChannels(channels);
      _reportGrouping('actualización $categoryId', channels, groups);

      setState(() {
        _channelGroups = groups;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'No fue posible actualizar los canales.';
      });
    }
  }

  Future<void> _refreshVisibleContent() async {
    if (_isSearching) {
      await _loadAllChannelsForSearch(force: true);

      return;
    }

    await _refreshCategoryChannels();
  }

  void _playChannelGroup(
    LiveChannelGroup group, {
    LiveChannel? selectedChannel,
  }) {
    final variants = group.variants
        .map((variant) => variant.channel)
        .toList(growable: false);

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MobileLivePlayerScreen(
          session: widget.session,
          channel: selectedChannel ?? group.preferredVariant.channel,
          channelVariants: variants,
        ),
      ),
    );
  }

  void _openChannel(LiveChannelGroup group) {
    if (widget.enableTvRemoteNavigation) {
      _playChannelGroup(group);
      return;
    }

    final categoryName = _categoryNameFromId(
      group.categoryId,
      fallback: _selectedCategoryName,
    );
    final variants = group.variants;
    var selectedChannel = group.preferredVariant.channel;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111620),
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isFavorite = _isChannelGroupFavorite(group);
            final mediaQuery = MediaQuery.of(context);
            final compactLandscape =
                mediaQuery.orientation == Orientation.landscape &&
                    mediaQuery.size.height < 560;
            final maxSelectorHeight = mediaQuery.size.height *
                (compactLandscape ? 0.43 : 0.38);
            final requestedMinHeight = compactLandscape ? 78.0 : 88.0;
            final minSelectorHeight = maxSelectorHeight < requestedMinHeight
                ? maxSelectorHeight
                : requestedMinHeight;
            final selectorHeight = (variants.length *
                    (compactLandscape ? 68.0 : 78.0))
                .clamp(minSelectorHeight, maxSelectorHeight)
                .toDouble();

            final favoriteButton = SizedBox(
              height: compactLandscape ? 44 : 48,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await _toggleChannelGroupFavorite(group);

                  if (sheetContext.mounted) {
                    setSheetState(() {});
                  }
                },
                icon: Icon(
                  isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isFavorite ? const Color(0xFFFF6B7A) : null,
                ),
                label: Text(
                  isFavorite
                      ? 'QUITAR DE FAVORITOS'
                      : 'AGREGAR A FAVORITOS',
                ),
              ),
            );

            final playButton = SizedBox(
              height: compactLandscape ? 46 : 52,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  _playChannelGroup(group, selectedChannel: selectedChannel);
                },
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text(
                  'REPRODUCIR SEÑAL',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            );

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: mediaQuery.size.height * 0.96,
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  compactLandscape ? 18 : 22,
                  compactLandscape ? 12 : 10,
                  compactLandscape ? 18 : 22,
                  compactLandscape ? 14 : 24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3A4352),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        SizedBox(height: compactLandscape ? 10 : 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _ChannelLogo(
                              channel: group.representative,
                              size: compactLandscape ? 64 : 76,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    group.displayName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize:
                                          compactLandscape ? 18 : 21,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    categoryName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF98A2B3),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    group.variantCount > 1
                                        ? '${group.variantCount} señales disponibles. Elige cuál reproducir.'
                                        : '1 señal disponible',
                                    style: const TextStyle(
                                      color: Color(0xFFC8D3FF),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: compactLandscape ? 12 : 18),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            group.variantCount > 1
                                ? 'Selecciona una señal'
                                : 'Señal disponible',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        SizedBox(
                          height: selectorHeight,
                          child: ListView.separated(
                            itemCount: variants.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final variant = variants[index];
                              final channel = variant.channel;
                              final selected = channel.streamId ==
                                  selectedChannel.streamId;

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  autofocus: selected,
                                  onTap: () {
                                    setSheetState(() {
                                      selectedChannel = channel;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(15),
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 160),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 13,
                                      vertical:
                                          compactLandscape ? 9 : 11,
                                    ),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? const Color(0xFF17213B)
                                          : const Color(0xFF0D1119),
                                      borderRadius: BorderRadius.circular(15),
                                      border: Border.all(
                                        color: selected
                                            ? const Color(0xFF6F8CFF)
                                            : const Color(0xFF252C38),
                                        width: selected ? 1.5 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          selected
                                              ? Icons.radio_button_checked
                                              : Icons.radio_button_unchecked,
                                          color: selected
                                              ? const Color(0xFF6F8CFF)
                                              : const Color(0xFF7D8797),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                channel.name,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                variant.description,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  color: Color(0xFF98A2B3),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (variant.isBackup)
                                          Container(
                                            margin:
                                                const EdgeInsets.only(left: 8),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF30251A),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: const Text(
                                              'RESPALDO',
                                              style: TextStyle(
                                                color: Color(0xFFFFC27A),
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
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
                        ),
                        SizedBox(height: compactLandscape ? 12 : 18),
                        Row(
                          children: [
                            Expanded(child: favoriteButton),
                            const SizedBox(width: 10),
                            Expanded(child: playButton),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingInitialData) {
      return const _InitialLoadingView();
    }

    if (_errorMessage != null && _categories.isEmpty) {
      return _FullErrorView(message: _errorMessage!, onRetry: _loadInitialData);
    }

    final groups = _visibleChannelGroups;
    _syncTvFocusNodes(groups);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            categoryName: _isSearching
                ? 'Búsqueda en todas las categorías'
                : _selectedCategoryName,
            channelCount: groups.length,
          ),
          if (!widget.enableTvRemoteNavigation)
            _SearchField(controller: _searchController),
          if (_isSearching)
            _GlobalSearchBanner(
              loading: _loadingGlobalSearch,
              totalChannels: _allChannelGroups.length,
            )
          else
            _CategorySelector(
              categories: _categories,
              selectedCategoryId: _selectedCategoryId,
              enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
              scrollController: widget.enableTvRemoteNavigation
                  ? _categoryScrollController
                  : null,
              focusNodes: _categoryFocusNodes,
              onSelected: _selectCategory,
              onCategoryKey: _handleLiveCategoryKey,
            ),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshVisibleContent,
              child: _buildContent(groups, searching: _isSearching),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(List<LiveChannelGroup> groups, {required bool searching}) {
    if (searching && _loadingGlobalSearch) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 150),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 18),
          Center(
            child: Text(
              'Buscando en todos los canales...',
              style: TextStyle(color: Color(0xFF98A2B3)),
            ),
          ),
        ],
      );
    }

    if (searching && _globalSearchError != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          _InlineErrorCard(
            message: _globalSearchError!,
            onRetry: () {
              _loadAllChannelsForSearch(force: true);
            },
          ),
        ],
      );
    }

    if (!searching && _loadingChannels) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 180),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (!searching && _errorMessage != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          _InlineErrorCard(
            message: _errorMessage!,
            onRetry: _refreshCategoryChannels,
          ),
        ],
      );
    }

    if (groups.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 90),
        children: [
          Icon(
            searching ? Icons.search_off_rounded : Icons.live_tv_outlined,
            size: 64,
            color: const Color(0xFF5B6473),
          ),
          const SizedBox(height: 18),
          Text(
            searching
                ? 'No encontramos ese canal'
                : 'No hay canales en esta categoría',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Text(
            searching
                ? 'La búsqueda se realizó en todas las categorías.'
                : 'Desliza hacia abajo para volver a intentarlo.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF98A2B3)),
          ),
        ],
      );
    }

    return ListView.separated(
      controller: widget.enableTvRemoteNavigation
          ? _channelScrollController
          : null,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      itemCount: groups.length,
      separatorBuilder: (_, _) {
        return const SizedBox(height: 10);
      },
      itemBuilder: (context, index) {
        final group = groups[index];
        final channel = group.representative;

        return _ChannelCard(
          group: group,
          categoryName: searching
              ? _categoryNameFromId(channel.categoryId)
              : null,
          isFavorite: _isChannelGroupFavorite(group),
          enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
          focusNode: widget.enableTvRemoteNavigation &&
                  index < _channelFocusNodes.length
              ? _channelFocusNodes[index]
              : null,
          onKeyEvent: widget.enableTvRemoteNavigation
              ? (node, event) => _handleLiveChannelKey(index, node, event)
              : null,
          onFavorite: () {
            unawaited(_toggleChannelGroupFavorite(group));
          },
          onPressed: () => _openChannel(group),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.categoryName, required this.channelCount});

  final String categoryName;
  final int channelCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF183A36),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(Icons.live_tv_rounded, color: Color(0xFF50D5B7)),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TV en vivo',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
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
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF17213B),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$channelCount únicos',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFFC8D3FF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Buscar en todos los canales',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) {
                return const SizedBox.shrink();
              }

              return IconButton(
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

class _GlobalSearchBanner extends StatelessWidget {
  const _GlobalSearchBanner({
    required this.loading,
    required this.totalChannels,
  });

  final bool loading;
  final int totalChannels;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF17213B),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFF26365F)),
        ),
        child: Row(
          children: [
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.public_rounded,
                size: 19,
                color: Color(0xFF6F8CFF),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                loading
                    ? 'Preparando búsqueda global...'
                    : 'Buscando entre $totalChannels canales',
                style: const TextStyle(fontSize: 12, color: Color(0xFFC8D3FF)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({
    required this.categories,
    required this.selectedCategoryId,
    required this.enableTvRemoteNavigation,
    required this.focusNodes,
    required this.onSelected,
    required this.onCategoryKey,
    this.scrollController,
  });

  final List<IptvCategory> categories;
  final String? selectedCategoryId;
  final bool enableTvRemoteNavigation;
  final List<FocusNode> focusNodes;
  final ScrollController? scrollController;
  final ValueChanged<IptvCategory> onSelected;
  final KeyEventResult Function(int index, FocusNode node, KeyEvent event) onCategoryKey;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        itemCount: categories.length,
        separatorBuilder: (_, _) {
          return const SizedBox(width: 9);
        },
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = category.id == selectedCategoryId;

          return TvFocusableSurface(
            enabled: enableTvRemoteNavigation,
            autofocus: enableTvRemoteNavigation && index == 0,
            focusNode: enableTvRemoteNavigation && index < focusNodes.length
                ? focusNodes[index]
                : null,
            onKeyEvent: enableTvRemoteNavigation
                ? (node, event) => onCategoryKey(index, node, event)
                : null,
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            onPressed: () => onSelected(category),
            builder: (context, focused) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: focused
                      ? const Color(0xFF263B75)
                      : selected
                          ? const Color(0xFF5B7CFF)
                          : const Color(0xFF111620),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: focused
                        ? Colors.white
                        : selected
                            ? const Color(0xFF5B7CFF)
                            : const Color(0xFF252C38),
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
                  CategoryNameLocalizer.toSpanish(
                    category.name,
                    section: CategorySection.liveTv,
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected || focused
                        ? FontWeight.w800
                        : FontWeight.w500,
                    color: selected || focused
                        ? Colors.white
                        : const Color(0xFFB4BBC6),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
    required this.group,
    required this.onPressed,
    required this.isFavorite,
    required this.enableTvRemoteNavigation,
    required this.onFavorite,
    this.categoryName,
    this.focusNode,
    this.onKeyEvent,
  });

  final LiveChannelGroup group;
  final String? categoryName;
  final VoidCallback onPressed;
  final bool isFavorite;
  final bool enableTvRemoteNavigation;
  final VoidCallback onFavorite;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;

  @override
  Widget build(BuildContext context) {
    final channel = group.representative;

    Widget buildCard(bool focused) {
      return Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: focused ? const Color(0xFF17213B) : const Color(0xFF111620),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: focused ? Colors.white : const Color(0xFF232A36),
            width: focused ? 4 : 1,
          ),
          boxShadow: focused
              ? const [
                  BoxShadow(
                    color: Color(0xBB6F8CFF),
                    blurRadius: 22,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            _ChannelLogo(channel: channel, size: 58),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (categoryName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      categoryName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6F8CFF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF50D5B7),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      const Text(
                        'En vivo',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF98A2B3),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          group.variantCount > 1
                              ? '${group.variantCount} señales disponibles'
                              : 'Señal disponible',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFC8D3FF),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (channel.hasArchive) ...[
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.history_rounded,
                          size: 15,
                          color: Color(0xFF98A2B3),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: isFavorite
                  ? 'Quitar de favoritos'
                  : 'Agregar a favoritos',
              onPressed: onFavorite,
              icon: Icon(
                isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: isFavorite
                    ? const Color(0xFFFF6B7A)
                    : const Color(0xFF98A2B3),
              ),
            ),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: focused ? const Color(0xFF5B7CFF) : const Color(0xFF17213B),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                color: focused ? Colors.white : const Color(0xFF6F8CFF),
              ),
            ),
          ],
        ),
      );
    }

    return TvFocusableSurface(
      enabled: enableTvRemoteNavigation,
      focusNode: focusNode,
      onKeyEvent: onKeyEvent,
      onPressed: onPressed,
      borderRadius: const BorderRadius.all(Radius.circular(18)),
      builder: (context, focused) => buildCard(focused),
    );
  }
}

class _ChannelLogo extends StatelessWidget {
  const _ChannelLogo({required this.channel, required this.size});

  final LiveChannel channel;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(15),
      ),
      child: channel.iconUrl.isEmpty
          ? const Icon(Icons.live_tv_rounded, color: Color(0xFF5B7CFF))
          : Image.network(
              channel.iconUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) {
                return const Icon(
                  Icons.live_tv_rounded,
                  color: Color(0xFF5B7CFF),
                );
              },
            ),
    );
  }
}

class _InitialLoadingView extends StatelessWidget {
  const _InitialLoadingView();

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      bottom: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 18),
            Text(
              'Cargando TV en vivo...',
              style: TextStyle(color: Color(0xFF98A2B3)),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullErrorView extends StatelessWidget {
  const _FullErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 68,
                color: Color(0xFFFF7D8A),
              ),
              const SizedBox(height: 18),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('REINTENTAR'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineErrorCard extends StatelessWidget {
  const _InlineErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF291B20),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFFFF7D8A)),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}
