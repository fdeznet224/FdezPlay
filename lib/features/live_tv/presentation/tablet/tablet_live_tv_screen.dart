import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/models/iptv_category.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../auth/domain/auth_session.dart';
import '../../../favorites/data/local_library_service.dart';
import '../../../player/presentation/mobile/mobile_live_player_screen.dart';
import '../../data/live_tv_service.dart';
import '../../domain/live_channel.dart';
import '../../domain/live_channel_group.dart';

class TabletLiveTvScreen extends StatefulWidget {
  const TabletLiveTvScreen({
    required this.session,
    super.key,
  });

  final AuthSession session;

  @override
  State<TabletLiveTvScreen> createState() => _TabletLiveTvScreenState();
}

class _TabletLiveTvScreenState extends State<TabletLiveTvScreen> {
  final LiveTvService _service = LiveTvService();
  final LocalLibraryService _libraryService = LocalLibraryService.instance;
  final TextEditingController _searchController = TextEditingController();

  Timer? _searchDebounce;

  List<IptvCategory> _categories = <IptvCategory>[];
  List<LiveChannelGroup> _channelGroups = <LiveChannelGroup>[];
  List<LiveChannelGroup> _allChannelGroups = <LiveChannelGroup>[];

  String? _selectedCategoryId;
  LiveChannelGroup? _selectedGroup;
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
    super.dispose();
  }

  bool get _isSearching => _searchQuery.trim().isNotEmpty;

  String get _selectedCategoryName {
    return _categoryNameFromId(
      _selectedCategoryId,
      fallback: 'TV en vivo',
    );
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

  String _categoryNameFromId(
    String? categoryId, {
    String fallback = 'Sin categoría',
  }) {
    if (categoryId == null || categoryId.isEmpty) {
      return fallback;
    }

    for (final category in _categories) {
      if (category.id == categoryId) {
        return category.name;
      }
    }

    return fallback;
  }

  void _reportGrouping(
    String scope,
    List<LiveChannel> channels,
    List<LiveChannelGroup> groups,
  ) {
    final groupedCount = groups.where((group) => group.variantCount > 1).length;

    debugPrint(
      '[FDEZPLAY-TABLET-TV] $scope: ${channels.length} señales -> '
      '${groups.length} canales únicos ($groupedCount agrupados)',
    );
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
      // La TV puede seguir funcionando aunque los favoritos no se carguen.
    }
  }

  bool _isChannelGroupFavorite(LiveChannelGroup group) {
    return group.streamIds.any(_favoriteChannelIds.contains);
  }

  Future<void> _toggleChannelGroupFavorite(
    LiveChannelGroup group,
  ) async {
    final variants = group.variants
        .map((variant) => variant.channel)
        .toList(growable: false);

    final isFavorite = await _libraryService.toggleChannelFavoriteGroup(
      widget.session,
      channel: group.representative,
      variants: variants,
    );

    if (!mounted) {
      return;
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
          _categories = <IptvCategory>[];
          _channelGroups = <LiveChannelGroup>[];
          _selectedGroup = null;
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
        _selectedGroup = groups.isEmpty ? null : groups.first;
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

  void _onSearchChanged() {
    final query = _searchController.text.trim();

    _searchDebounce?.cancel();

    setState(() {
      _searchQuery = query;

      if (query.isEmpty) {
        _globalSearchError = null;
        _selectedGroup = _channelGroups.isEmpty ? null : _channelGroups.first;
      } else if (_allChannelsLoaded) {
        final matches = _filterGroups(_allChannelGroups, query);
        _selectedGroup = matches.isEmpty ? null : matches.first;
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

  List<LiveChannelGroup> _filterGroups(
    List<LiveChannelGroup> source,
    String query,
  ) {
    final normalizedQuery = query.trim().toLowerCase();

    if (normalizedQuery.isEmpty) {
      return List<LiveChannelGroup>.unmodifiable(source);
    }

    return source.where((group) {
      if (group.displayName.toLowerCase().contains(normalizedQuery)) {
        return true;
      }

      return group.variants.any(
        (variant) =>
            variant.channel.name.toLowerCase().contains(normalizedQuery),
      );
    }).toList(growable: false);
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
        _allChannelGroups = <LiveChannelGroup>[];
        _selectedGroup = null;
      }
    });

    try {
      final channels = await _service.loadAllChannels(
        session: widget.session,
      );

      if (!mounted) {
        return;
      }

      final groups = groupLiveChannels(channels);
      final matches = _filterGroups(groups, _searchQuery);
      _reportGrouping('búsqueda global', channels, groups);

      setState(() {
        _allChannelGroups = groups;
        _allChannelsLoaded = true;
        _loadingGlobalSearch = false;
        _selectedGroup = matches.isEmpty ? null : matches.first;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingGlobalSearch = false;
        _allChannelsLoaded = false;
        _selectedGroup = null;
        _globalSearchError = 'No fue posible buscar en todos los canales.';
      });
    }
  }

  Future<void> _selectCategory(IptvCategory category) async {
    if (_loadingChannels || category.id == _selectedCategoryId) {
      if (_isSearching) {
        _searchController.clear();
      }
      return;
    }

    _searchController.clear();

    setState(() {
      _selectedCategoryId = category.id;
      _loadingChannels = true;
      _errorMessage = null;
      _channelGroups = <LiveChannelGroup>[];
      _selectedGroup = null;
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
        _selectedGroup = groups.isEmpty ? null : groups.first;
        _loadingChannels = false;
      });
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

  Future<void> _refreshVisibleContent() async {
    if (_isSearching) {
      await _loadAllChannelsForSearch(force: true);
      return;
    }

    final categoryId = _selectedCategoryId;

    if (categoryId == null) {
      await _loadInitialData();
      return;
    }

    setState(() {
      _loadingChannels = true;
      _errorMessage = null;
    });

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
        _selectedGroup = groups.isEmpty ? null : groups.first;
        _loadingChannels = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingChannels = false;
        _errorMessage = 'No fue posible actualizar los canales.';
      });
    }
  }

  Future<void> _playChannel(LiveChannelGroup group) async {
    final channel = group.representative;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MobileLivePlayerScreen(
          session: widget.session,
          channel: channel,
          channelVariants: group.variants
              .map((variant) => variant.channel)
              .toList(growable: false),
        ),
      ),
    );

    if (mounted) {
      setState(() {
        _selectedGroup = group;
      });
    }
  }

  LiveChannelGroup? _effectiveSelectedGroup(
    List<LiveChannelGroup> visibleGroups,
  ) {
    final selected = _selectedGroup;

    if (selected != null) {
      for (final group in visibleGroups) {
        if (group.key == selected.key &&
            group.representative.streamId ==
                selected.representative.streamId) {
          return group;
        }
      }
    }

    if (visibleGroups.isEmpty) {
      return null;
    }

    return visibleGroups.first;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingInitialData) {
      return const _TabletTvInitialLoading();
    }

    if (_errorMessage != null && _categories.isEmpty) {
      return _TabletTvFullError(
        message: _errorMessage!,
        onRetry: _loadInitialData,
      );
    }

    final visibleGroups = _visibleChannelGroups;
    final selectedGroup = _effectiveSelectedGroup(visibleGroups);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TabletTvHeader(
            categoryName: _isSearching
                ? 'Resultados en todas las categorías'
                : _selectedCategoryName,
            channelCount: visibleGroups.length,
            loading: _loadingChannels || _loadingGlobalSearch,
            onRefresh: _refreshVisibleContent,
          ),
          const SizedBox(height: 14),
          _TabletTvSearchField(
            controller: _searchController,
            loading: _loadingGlobalSearch,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final categoryWidth = (constraints.maxWidth * 0.20)
                    .clamp(150.0, 245.0)
                    .toDouble();
                final channelWidth = (constraints.maxWidth * 0.36)
                    .clamp(270.0, 455.0)
                    .toDouble();
                final compact = constraints.maxWidth < 920;
                final gap = compact ? 10.0 : 14.0;

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: categoryWidth,
                      child: _TabletCategoryPanel(
                        categories: _categories,
                        selectedCategoryId: _selectedCategoryId,
                        searching: _isSearching,
                        loading: _loadingChannels,
                        onSelected: _selectCategory,
                      ),
                    ),
                    SizedBox(width: gap),
                    SizedBox(
                      width: channelWidth,
                      child: _TabletChannelPanel(
                        groups: visibleGroups,
                        selectedGroup: selectedGroup,
                        categoryName: _isSearching
                            ? 'Búsqueda global'
                            : _selectedCategoryName,
                        searching: _isSearching,
                        loadingChannels: _loadingChannels,
                        loadingSearch: _loadingGlobalSearch,
                        errorMessage:
                            _isSearching ? _globalSearchError : _errorMessage,
                        categoryNameFromId: (categoryId, fallback) {
                          return _categoryNameFromId(
                            categoryId,
                            fallback: fallback,
                          );
                        },
                        isFavorite: _isChannelGroupFavorite,
                        onSelected: (group) {
                          setState(() {
                            _selectedGroup = group;
                          });
                        },
                        onFavorite: (group) {
                          unawaited(_toggleChannelGroupFavorite(group));
                        },
                        onRetry: _refreshVisibleContent,
                      ),
                    ),
                    SizedBox(width: gap),
                    Expanded(
                      child: _TabletChannelDetailsPanel(
                        group: selectedGroup,
                        categoryName: selectedGroup == null
                            ? ''
                            : _categoryNameFromId(
                                selectedGroup.representative.categoryId,
                                fallback: _selectedCategoryName,
                              ),
                        favorite: selectedGroup != null &&
                            _isChannelGroupFavorite(selectedGroup),
                        compact: compact,
                        onFavorite: selectedGroup == null
                            ? null
                            : () {
                                unawaited(
                                  _toggleChannelGroupFavorite(selectedGroup!),
                                );
                              },
                        onPlay: selectedGroup == null
                            ? null
                            : () {
                                unawaited(_playChannel(selectedGroup!));
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

class _TabletTvHeader extends StatelessWidget {
  const _TabletTvHeader({
    required this.categoryName,
    required this.channelCount,
    required this.loading,
    required this.onRefresh,
  });

  final String categoryName;
  final int channelCount;
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
            color: const Color(0xFF183A36),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            Icons.live_tv_rounded,
            color: Color(0xFF50D5B7),
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TV en vivo',
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
            color: const Color(0xFF17213B),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$channelCount canales',
            style: const TextStyle(
              color: Color(0xFFC8D3FF),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          tooltip: 'Actualizar canales',
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

class _TabletTvSearchField extends StatelessWidget {
  const _TabletTvSearchField({
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
          hintText: 'Buscar un canal en todas las categorías',
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

class _TabletCategoryPanel extends StatelessWidget {
  const _TabletCategoryPanel({
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
    return _TabletPanel(
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
                  color: Color(0xFF8EA2FF),
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
                color: const Color(0xFF17213B),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xFF26365F)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.travel_explore_rounded,
                    size: 17,
                    color: Color(0xFF8EA2FF),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Buscando en todas',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFC8D3FF),
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
                      ? const Color(0xFF1C294F)
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
                                  ? const Color(0xFF6F8BFF)
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
                              color: Color(0xFF8EA2FF),
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

class _TabletChannelPanel extends StatelessWidget {
  const _TabletChannelPanel({
    required this.groups,
    required this.selectedGroup,
    required this.categoryName,
    required this.searching,
    required this.loadingChannels,
    required this.loadingSearch,
    required this.errorMessage,
    required this.categoryNameFromId,
    required this.isFavorite,
    required this.onSelected,
    required this.onFavorite,
    required this.onRetry,
  });

  final List<LiveChannelGroup> groups;
  final LiveChannelGroup? selectedGroup;
  final String categoryName;
  final bool searching;
  final bool loadingChannels;
  final bool loadingSearch;
  final String? errorMessage;
  final String Function(String?, String) categoryNameFromId;
  final bool Function(LiveChannelGroup) isFavorite;
  final ValueChanged<LiveChannelGroup> onSelected;
  final ValueChanged<LiveChannelGroup> onFavorite;
  final Future<void> Function() onRetry;

  bool get _loading => searching ? loadingSearch : loadingChannels;

  @override
  Widget build(BuildContext context) {
    return _TabletPanel(
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
                        'CANALES',
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
      return const _TabletPanelLoading(
        message: 'Cargando canales...',
      );
    }

    if (errorMessage != null) {
      return _TabletPanelError(
        message: errorMessage!,
        onRetry: onRetry,
      );
    }

    if (groups.isEmpty) {
      return _TabletPanelEmpty(
        icon: searching ? Icons.search_off_rounded : Icons.live_tv_outlined,
        title: searching
            ? 'No encontramos ese canal'
            : 'No hay canales disponibles',
        subtitle: searching
            ? 'Prueba con otro nombre.'
            : 'Actualiza para volver a intentarlo.',
      );
    }

    return RefreshIndicator(
      onRefresh: onRetry,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(9),
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(height: 7),
        itemBuilder: (context, index) {
          final group = groups[index];
          final selected = selectedGroup != null &&
              group.key == selectedGroup!.key &&
              group.representative.streamId ==
                  selectedGroup!.representative.streamId;

          return _TabletChannelTile(
            group: group,
            selected: selected,
            favorite: isFavorite(group),
            categoryName: searching
                ? categoryNameFromId(
                    group.representative.categoryId,
                    'Sin categoría',
                  )
                : null,
            onPressed: () => onSelected(group),
            onFavorite: () => onFavorite(group),
          );
        },
      ),
    );
  }
}

class _TabletChannelTile extends StatelessWidget {
  const _TabletChannelTile({
    required this.group,
    required this.selected,
    required this.favorite,
    required this.categoryName,
    required this.onPressed,
    required this.onFavorite,
  });

  final LiveChannelGroup group;
  final bool selected;
  final bool favorite;
  final String? categoryName;
  final VoidCallback onPressed;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final qualityText = group.qualityLabels.take(2).join(' · ');

    return Material(
      color: selected
          ? const Color(0xFF1A2542)
          : const Color(0xFF121720),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? const Color(0xFF5B7CFF)
                  : const Color(0xFF252D39),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              _TabletChannelLogo(
                channel: group.representative,
                size: 52,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: selected
                            ? Colors.white
                            : const Color(0xFFD4D8DF),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      categoryName ?? qualityText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF7F8999),
                        fontSize: 10,
                      ),
                    ),
                    if (categoryName != null && qualityText.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        qualityText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8EA2FF),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: favorite
                    ? 'Quitar de favoritos'
                    : 'Agregar a favoritos',
                visualDensity: VisualDensity.compact,
                onPressed: onFavorite,
                icon: Icon(
                  favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 20,
                  color: favorite
                      ? const Color(0xFFFF6B7A)
                      : const Color(0xFF798395),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabletChannelDetailsPanel extends StatelessWidget {
  const _TabletChannelDetailsPanel({
    required this.group,
    required this.categoryName,
    required this.favorite,
    required this.compact,
    required this.onFavorite,
    required this.onPlay,
  });

  final LiveChannelGroup? group;
  final String categoryName;
  final bool favorite;
  final bool compact;
  final VoidCallback? onFavorite;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final currentGroup = group;

    if (currentGroup == null) {
      return const _TabletPanel(
        child: _TabletPanelEmpty(
          icon: Icons.touch_app_rounded,
          title: 'Selecciona un canal',
          subtitle: 'Aquí aparecerá su información y el botón para reproducir.',
        ),
      );
    }

    final channel = currentGroup.representative;

    return _TabletPanel(
      child: Stack(
        children: [
          Positioned(
            top: -70,
            right: -60,
            child: Container(
              width: 210,
              height: 210,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0x334D6DFF),
                    Color(0x004D6DFF),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: -70,
            bottom: -90,
            child: Container(
              width: 220,
              height: 220,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(0x2231C6A2),
                    Color(0x0031C6A2),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                compact ? 18 : 24,
                compact ? 18 : 24,
                compact ? 18 : 24,
                22,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF17352F),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF245A4F),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.circle,
                              color: Color(0xFF50D5B7),
                              size: 8,
                            ),
                            SizedBox(width: 7),
                            Text(
                              'EN VIVO',
                              style: TextStyle(
                                color: Color(0xFF78E7CE),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: favorite
                            ? 'Quitar de favoritos'
                            : 'Agregar a favoritos',
                        onPressed: onFavorite,
                        icon: Icon(
                          favorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: favorite
                              ? const Color(0xFFFF6B7A)
                              : const Color(0xFF98A2B3),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 14 : 22),
                  Center(
                    child: _TabletChannelLogo(
                      channel: channel,
                      size: compact ? 104 : 132,
                      large: true,
                    ),
                  ),
                  SizedBox(height: compact ? 16 : 24),
                  Text(
                    currentGroup.displayName,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 20 : 25,
                      height: 1.12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    categoryName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF98A2B3),
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: compact ? 16 : 22),
                  _TabletInfoRow(
                    icon: Icons.cell_tower_rounded,
                    label: 'Señales disponibles',
                    value: '${currentGroup.variantCount}',
                  ),
                  const SizedBox(height: 9),
                  _TabletInfoRow(
                    icon: Icons.high_quality_rounded,
                    label: 'Calidad',
                    value: currentGroup.qualityLabels.join(' · '),
                  ),
                  if (channel.hasArchive) ...[
                    const SizedBox(height: 9),
                    _TabletInfoRow(
                      icon: Icons.history_rounded,
                      label: 'Programación anterior',
                      value: channel.archiveDuration > 0
                          ? '${channel.archiveDuration} días'
                          : 'Disponible',
                    ),
                  ],
                  SizedBox(height: compact ? 18 : 26),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded, size: 26),
                      label: const Text(
                        'REPRODUCIR CANAL',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton.icon(
                      onPressed: onFavorite,
                      icon: Icon(
                        favorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: favorite
                            ? const Color(0xFFFF6B7A)
                            : null,
                      ),
                      label: Text(
                        favorite
                            ? 'QUITAR DE FAVORITOS'
                            : 'AGREGAR A FAVORITOS',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabletInfoRow extends StatelessWidget {
  const _TabletInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xB3121720),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFF252D39)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF8EA2FF)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF8993A3),
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value.isEmpty ? 'Estándar' : value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Color(0xFFE2E6EC),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabletChannelLogo extends StatelessWidget {
  const _TabletChannelLogo({
    required this.channel,
    required this.size,
    this.large = false,
  });

  final LiveChannel channel;
  final double size;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: const Color(0xFF18202B),
      alignment: Alignment.center,
      child: Icon(
        Icons.live_tv_rounded,
        size: large ? size * 0.40 : size * 0.42,
        color: const Color(0xFF697486),
      ),
    );

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(large ? 12 : 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0E131B),
        borderRadius: BorderRadius.circular(large ? 24 : 12),
        border: Border.all(
          color: large
              ? const Color(0xFF313B4B)
              : const Color(0xFF28313E),
        ),
        boxShadow: large
            ? const [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(large ? 15 : 8),
        child: AppCachedImage(
          imageUrl: channel.iconUrl,
          fit: BoxFit.contain,
          cacheWidth: large ? 320 : 140,
          cacheHeight: large ? 320 : 140,
          fallback: fallback,
          placeholder: fallback,
        ),
      ),
    );
  }
}

class _TabletPanel extends StatelessWidget {
  const _TabletPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0F141D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF232A35)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x30000000),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _TabletPanelLoading extends StatelessWidget {
  const _TabletPanelLoading({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
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

class _TabletPanelError extends StatelessWidget {
  const _TabletPanelError({
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
              Icons.cloud_off_rounded,
              size: 42,
              color: Color(0xFF697486),
            ),
            const SizedBox(height: 13),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {
                unawaited(onRetry());
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('REINTENTAR'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabletPanelEmpty extends StatelessWidget {
  const _TabletPanelEmpty({
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
            Icon(icon, size: 52, color: const Color(0xFF566173)),
            const SizedBox(height: 15),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF7F8999),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabletTvInitialLoading extends StatelessWidget {
  const _TabletTvInitialLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Cargando TV en vivo...',
            style: TextStyle(color: Color(0xFF98A2B3)),
          ),
        ],
      ),
    );
  }
}

class _TabletTvFullError extends StatelessWidget {
  const _TabletTvFullError({
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
              Icons.live_tv_outlined,
              size: 64,
              color: Color(0xFF566173),
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
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () {
                unawaited(onRetry());
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('VOLVER A INTENTAR'),
            ),
          ],
        ),
      ),
    );
  }
}
