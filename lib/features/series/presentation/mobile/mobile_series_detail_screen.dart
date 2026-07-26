import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/services/iptv_api_service.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../../shared/widgets/tv_focusable_surface.dart';
import '../../../auth/domain/auth_session.dart';
import '../../../downloads/data/offline_download_service.dart';
import '../../../favorites/data/local_library_service.dart';
import '../../../player/presentation/mobile/mobile_series_player_screen.dart';
import '../../domain/series_group.dart';
import '../../domain/tv_series.dart';

class MobileSeriesDetailScreen extends StatefulWidget {
  const MobileSeriesDetailScreen({
    required this.session,
    required this.series,
    this.versions = const [],
    this.displayTitle,
    this.enableTvRemoteNavigation = false,
    super.key,
  });

  final AuthSession session;
  final TvSeries series;
  final List<TvSeries> versions;
  final String? displayTitle;
  final bool enableTvRemoteNavigation;

  @override
  State<MobileSeriesDetailScreen> createState() {
    return _MobileSeriesDetailScreenState();
  }
}

class _MobileSeriesDetailScreenState
    extends State<MobileSeriesDetailScreen> {
  final IptvApiService _apiService = IptvApiService();
  final LocalLibraryService _libraryService = LocalLibraryService.instance;
  final OfflineDownloadService _downloadService =
      OfflineDownloadService.instance;

  late final List<TvSeries> _versions;
  late final TvSeries _librarySeries;
  final Map<int, SeriesDetails> _detailsBySeriesId = {};

  late SeriesDetails _details;
  int _selectedVersionIndex = 0;
  int _selectedSeasonIndex = 0;
  int _versionRequestId = 0;

  bool _loadingDetails = true;
  bool _loadingAlternatives = false;
  bool _favoriteLoading = true;
  bool _isFavorite = false;
  Map<int, WatchProgressEntry> _episodeProgress = const {};
  Map<int, OfflineDownloadEntry> _episodeDownloads = const {};
  Map<int, double> _episodeDownloadProgress = const {};
  Set<int> _episodeDownloadsLoading = const {};
  bool _seasonDownloadLoading = false;
  double? _seasonDownloadProgress;
  String? _errorMessage;
  DateTime? _ignoreTvBackUntil;

  String get _displayTitle {
    final provided = widget.displayTitle?.trim() ?? '';

    if (provided.isNotEmpty) {
      return provided;
    }

    final clean = cleanSeriesTitle(_librarySeries.name);
    return clean.isEmpty ? _librarySeries.name : clean;
  }

  SeriesSeason? get _selectedSeason {
    if (_details.seasons.isEmpty) {
      return null;
    }

    final safeIndex = _selectedSeasonIndex
        .clamp(0, _details.seasons.length - 1)
        .toInt();

    return _details.seasons[safeIndex];
  }

  @override
  void initState() {
    super.initState();

    _versions = _buildVersions();
    _librarySeries = _versions.first;
    _details = SeriesDetails(series: _librarySeries, seasons: const []);

    unawaited(_loadSelectedVersion(0));
    unawaited(_loadLibraryState());
  }

  List<TvSeries> _buildVersions() {
    final source = widget.versions.isEmpty
        ? <TvSeries>[widget.series]
        : List<TvSeries>.from(widget.versions);
    final result = <TvSeries>[];
    final seen = <int>{};

    for (final series in source) {
      if (series.seriesId > 0 && seen.add(series.seriesId)) {
        result.add(series);
      }
    }

    if (result.isEmpty) {
      result.add(widget.series);
    }

    return List<TvSeries>.unmodifiable(result);
  }

  Future<SeriesDetails?> _fetchVersion(int index) async {
    if (index < 0 || index >= _versions.length) {
      return null;
    }

    final series = _versions[index];
    final cached = _detailsBySeriesId[series.seriesId];

    if (cached != null) {
      return cached;
    }

    try {
      final details = await _apiService.loadSeriesDetails(
        widget.session,
        series: series,
      );
      _detailsBySeriesId[series.seriesId] = details;
      return details;
    } catch (error) {
      debugPrint('Error cargando versión ${series.seriesId}: $error');
      return null;
    }
  }

  Future<void> _loadSelectedVersion(int index) async {
    final requestId = ++_versionRequestId;
    final previousSeasonNumber = _selectedSeason?.seasonNumber;

    setState(() {
      _selectedVersionIndex = index;
      _loadingDetails = true;
      _errorMessage = null;
    });

    final details = await _fetchVersion(index);

    if (!mounted || requestId != _versionRequestId) {
      return;
    }

    if (details == null) {
      setState(() {
        _loadingDetails = false;
        _errorMessage = 'No se pudieron cargar las temporadas y episodios.';
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
      _details = details;
      _selectedSeasonIndex = seasonIndex;
      _loadingDetails = false;
      _errorMessage = null;
    });

    unawaited(_loadDownloadsForCurrentDetails());

    if (index == 0 && _versions.length > 1) {
      unawaited(_preloadAlternativeVersions());
    }
  }

  Future<void> _preloadAlternativeVersions() async {
    if (_loadingAlternatives) {
      return;
    }

    _loadingAlternatives = true;

    try {
      for (int index = 0; index < _versions.length; index++) {
        if (index == _selectedVersionIndex) {
          continue;
        }

        await _fetchVersion(index);
      }
    } finally {
      _loadingAlternatives = false;
    }
  }

  Future<List<SeriesPlaybackVersion>> _allPlaybackVersions() async {
    final result = <SeriesPlaybackVersion>[];

    for (int index = 0; index < _versions.length; index++) {
      final details = await _fetchVersion(index);

      if (details != null && details.seasons.isNotEmpty) {
        result.add(
          SeriesPlaybackVersion(
            series: _versions[index],
            details: details,
          ),
        );
      }
    }

    return result;
  }

  void _selectSeason(int index) {
    if (_selectedSeasonIndex == index) {
      return;
    }

    setState(() {
      _selectedSeasonIndex = index;
    });
  }

  Future<void> _loadLibraryState() async {
    try {
      final snapshot = await _libraryService.load(widget.session);

      if (!mounted) {
        return;
      }

      final progress = <int, WatchProgressEntry>{};

      for (final item in snapshot.progress) {
        final episodeId = item.episode?.episodeId;

        if (episodeId != null && episodeId > 0) {
          progress[episodeId] = item;
        }
      }

      final episodeDownloads = await _downloadService.episodeDownloads(
        widget.session,
        progress.keys,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isFavorite = snapshot.favorites.any(
          (item) => item.series?.seriesId == _librarySeries.seriesId,
        );
        _episodeProgress = progress;
        _episodeDownloads = {
          ..._episodeDownloads,
          ...episodeDownloads,
        };
        _favoriteLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _favoriteLoading = false;
      });
    }
  }

  Future<void> _loadDownloadsForCurrentDetails() async {
    final episodeIds = <int>{};

    for (final season in _details.seasons) {
      for (final episode in season.episodes) {
        if (episode.episodeId > 0) {
          episodeIds.add(episode.episodeId);
        }
      }
    }

    if (episodeIds.isEmpty) {
      return;
    }

    try {
      final downloads = await _downloadService.episodeDownloads(
        widget.session,
        episodeIds,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _episodeDownloads = downloads;
      });
    } catch (_) {
      // La pantalla puede seguir funcionando aunque no se lea la lista local.
    }
  }

  Future<void> _downloadEpisode(
    SeriesSeason season,
    SeriesEpisode episode,
  ) async {
    if (_episodeDownloadsLoading.contains(episode.episodeId) ||
        _episodeDownloads.containsKey(episode.episodeId)) {
      return;
    }

    setState(() {
      _episodeDownloadsLoading = {
        ..._episodeDownloadsLoading,
        episode.episodeId,
      };
      _episodeDownloadProgress = {
        ..._episodeDownloadProgress,
        episode.episodeId: 0,
      };
    });

    try {
      final downloaded = await _downloadService.downloadEpisode(
        widget.session,
        series: _details.series,
        seriesTitle: _displayTitle,
        seasonName: season.name,
        episode: episode,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }

          setState(() {
            _episodeDownloadProgress = {
              ..._episodeDownloadProgress,
              episode.episodeId: progress,
            };
          });
        },
      );

      if (!mounted) {
        return;
      }

      final loading = {..._episodeDownloadsLoading}..remove(episode.episodeId);
      final progress = {..._episodeDownloadProgress}
        ..remove(episode.episodeId);

      setState(() {
        _episodeDownloads = {
          ..._episodeDownloads,
          episode.episodeId: downloaded,
        };
        _episodeDownloadsLoading = loading;
        _episodeDownloadProgress = progress;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${episode.displayTitle} descargado.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } on DownloadPausedException {
      if (!mounted) {
        return;
      }

      final loading = {..._episodeDownloadsLoading}..remove(episode.episodeId);
      final progress = {..._episodeDownloadProgress}
        ..remove(episode.episodeId);

      setState(() {
        _episodeDownloadsLoading = loading;
        _episodeDownloadProgress = progress;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Descarga pausada. Puedes reanudarla en Mis descargas.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }

      final loading = {..._episodeDownloadsLoading}..remove(episode.episodeId);
      final progress = {..._episodeDownloadProgress}
        ..remove(episode.episodeId);

      setState(() {
        _episodeDownloadsLoading = loading;
        _episodeDownloadProgress = progress;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No se pudo descargar este episodio.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _downloadSelectedSeason() async {
    final season = _selectedSeason;

    if (season == null ||
        season.episodes.isEmpty ||
        _seasonDownloadLoading) {
      return;
    }

    final pendingEpisodes = season.episodes
        .where(
          (episode) => episode.episodeId > 0 &&
              !_episodeDownloads.containsKey(episode.episodeId),
        )
        .toList(growable: false);

    if (pendingEpisodes.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Esta temporada ya está descargada.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    setState(() {
      _seasonDownloadLoading = true;
      _seasonDownloadProgress = 0;
    });

    var completed = 0;
    var failed = 0;
    final total = pendingEpisodes.length;

    for (final episode in pendingEpisodes) {
      if (!mounted) {
        break;
      }

      setState(() {
        _episodeDownloadsLoading = {
          ..._episodeDownloadsLoading,
          episode.episodeId,
        };
        _episodeDownloadProgress = {
          ..._episodeDownloadProgress,
          episode.episodeId: 0,
        };
      });

      try {
        final downloaded = await _downloadService.downloadEpisode(
          widget.session,
          series: _details.series,
          seriesTitle: _displayTitle,
          seasonName: season.name,
          episode: episode,
          onProgress: (progress) {
            if (!mounted) {
              return;
            }

            setState(() {
              _episodeDownloadProgress = {
                ..._episodeDownloadProgress,
                episode.episodeId: progress,
              };
              _seasonDownloadProgress =
                  ((completed + progress.clamp(0.0, 1.0)) / total)
                      .clamp(0.0, 1.0)
                      .toDouble();
            });
          },
        );

        completed++;

        if (!mounted) {
          break;
        }

        final loading = {..._episodeDownloadsLoading}
          ..remove(episode.episodeId);
        final progress = {..._episodeDownloadProgress}
          ..remove(episode.episodeId);

        setState(() {
          _episodeDownloads = {
            ..._episodeDownloads,
            episode.episodeId: downloaded,
          };
          _episodeDownloadsLoading = loading;
          _episodeDownloadProgress = progress;
          _seasonDownloadProgress =
              (completed / total).clamp(0.0, 1.0).toDouble();
        });
      } catch (_) {
        failed++;

        if (!mounted) {
          break;
        }

        final loading = {..._episodeDownloadsLoading}
          ..remove(episode.episodeId);
        final progress = {..._episodeDownloadProgress}
          ..remove(episode.episodeId);

        setState(() {
          _episodeDownloadsLoading = loading;
          _episodeDownloadProgress = progress;
          _seasonDownloadProgress =
              ((completed + failed) / total).clamp(0.0, 1.0).toDouble();
        });
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _seasonDownloadLoading = false;
      _seasonDownloadProgress = null;
    });

    final message = failed == 0
        ? 'Temporada descargada para verla sin conexión.'
        : 'Descarga terminada con $failed episodios pendientes.';

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _deleteEpisodeDownload(SeriesEpisode episode) async {
    final download = _episodeDownloads[episode.episodeId];

    if (download == null) {
      return;
    }

    try {
      await _downloadService.deleteDownload(widget.session, download);

      if (!mounted) {
        return;
      }

      final next = {..._episodeDownloads}..remove(episode.episodeId);

      setState(() {
        _episodeDownloads = next;
      });
    } catch (_) {
      // Se mantiene el estado anterior si no se puede eliminar.
    }
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteLoading) {
      return;
    }

    setState(() {
      _favoriteLoading = true;
    });

    try {
      final isFavorite = await _libraryService.toggleSeriesFavorite(
        widget.session,
        _librarySeries,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isFavorite = isFavorite;
        _favoriteLoading = false;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              isFavorite
                  ? 'Serie agregada a favoritos.'
                  : 'Serie eliminada de favoritos.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _favoriteLoading = false;
      });
    }
  }

  Future<void> _playEpisode(int episodeIndex) async {
    final selectedSeason = _selectedSeason;

    if (selectedSeason == null ||
        episodeIndex < 0 ||
        episodeIndex >= selectedSeason.episodes.length) {
      return;
    }

    final selectedEpisode = selectedSeason.episodes[episodeIndex];
    final playbackVersions = await _allPlaybackVersions();

    if (!mounted) {
      return;
    }

    final preferredSeriesId = _versions[_selectedVersionIndex].seriesId;
    final playbackSelectedIndex = playbackVersions.indexWhere(
      (version) => version.series.seriesId == preferredSeriesId,
    );

    final canonicalDetails = _detailsBySeriesId[_librarySeries.seriesId] ??
        _details;
    SeriesSeason canonicalSeason = selectedSeason;

    for (final season in canonicalDetails.seasons) {
      if (season.seasonNumber == selectedSeason.seasonNumber) {
        canonicalSeason = season;
        break;
      }
    }

    int canonicalIndex = canonicalSeason.episodes.indexWhere(
      (episode) => episode.episodeNumber == selectedEpisode.episodeNumber,
    );

    if (canonicalIndex < 0) {
      canonicalIndex = episodeIndex
          .clamp(0, canonicalSeason.episodes.length - 1)
          .toInt();
    }

    final canonicalEpisode = canonicalSeason.episodes[canonicalIndex];
    WatchProgressEntry? savedProgress;

    try {
      savedProgress = await _libraryService.episodeProgress(
        widget.session,
        canonicalEpisode.episodeId,
      );
    } catch (_) {
      savedProgress = _episodeProgress[canonicalEpisode.episodeId];
    }

    if (!mounted) {
      return;
    }

    final offlineEpisodePaths = <int, String>{
      for (final episode in canonicalSeason.episodes)
        if (_episodeDownloads[episode.episodeId]?.localPath.isNotEmpty == true)
          episode.episodeId: _episodeDownloads[episode.episodeId]!.localPath,
    };

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MobileSeriesPlayerScreen(
          session: widget.session,
          series: _librarySeries,
          seasonName: canonicalSeason.name,
          episodes: canonicalSeason.episodes,
          initialIndex: canonicalIndex,
          initialPosition: savedProgress?.position ?? Duration.zero,
          playbackVersions: playbackVersions,
          initialVersionIndex:
              playbackSelectedIndex < 0 ? 0 : playbackSelectedIndex,
          displayTitle: _displayTitle,
          offlineEpisodePaths: offlineEpisodePaths,
          enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
        ),
      ),
    );

    if (mounted) {
      if (widget.enableTvRemoteNavigation) {
        _ignoreTvBackUntil = DateTime.now().add(
          const Duration(milliseconds: 650),
        );
      }
      unawaited(_loadLibraryState());
    }
  }

  void _handleTvDetailBack() {
    final ignoreUntil = _ignoreTvBackUntil;

    if (ignoreUntil != null && DateTime.now().isBefore(ignoreUntil)) {
      return;
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final series = _details.series;
    final backgroundUrl = series.backdropUrl.isNotEmpty
        ? series.backdropUrl
        : series.coverUrl;
    final selectedSeason = _selectedSeason;

    return PopScope(
      canPop: !widget.enableTvRemoteNavigation,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }

        _handleTvDetailBack();
      },
      child: Scaffold(
        body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 310,
            backgroundColor: const Color(0xFF0B0F17),
            actions: [
              IconButton(
                tooltip: _isFavorite
                    ? 'Quitar de favoritos'
                    : 'Agregar a favoritos',
                onPressed: _favoriteLoading ? null : _toggleFavorite,
                icon: _favoriteLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : Icon(
                        _isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: _isFavorite
                            ? const Color(0xFFFF6B7A)
                            : Colors.white,
                      ),
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (backgroundUrl.isNotEmpty)
                    AppCachedImage(
                      imageUrl: backgroundUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 1200,
                      cacheHeight: 700,
                      fallback: const ColoredBox(color: Color(0xFF171D28)),
                    )
                  else
                    const ColoredBox(color: Color(0xFF171D28)),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x33000000),
                          Color(0x77000000),
                          Color(0xFF0B0F17),
                        ],
                        stops: [0, 0.55, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 36),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_loadingDetails)
                  const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Hero(
                      tag: 'series-${_librarySeries.seriesId}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: SizedBox(
                          width: 126,
                          height: 186,
                          child: series.coverUrl.isEmpty
                              ? const _SeriesCoverFallback()
                              : AppCachedImage(
                                  imageUrl: series.coverUrl,
                                  fit: BoxFit.cover,
                                  cacheWidth: 360,
                                  cacheHeight: 540,
                                  fallback: const _SeriesCoverFallback(),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayTitle,
                            style: const TextStyle(
                              fontSize: 25,
                              height: 1.08,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (series.displayYear.isNotEmpty)
                                _InfoChip(
                                  icon: Icons.calendar_month_rounded,
                                  label: series.displayYear,
                                ),
                              if (series.displayRating.isNotEmpty)
                                _InfoChip(
                                  icon: Icons.star_rounded,
                                  label: series.displayRating,
                                  accent: true,
                                ),
                              if (_details.seasons.isNotEmpty)
                                _InfoChip(
                                  icon: Icons.video_library_rounded,
                                  label: '${_details.seasons.length} temporadas',
                                ),
                              if (_details.episodeCount > 0)
                                _InfoChip(
                                  icon: Icons.playlist_play_rounded,
                                  label: '${_details.episodeCount} episodios',
                                ),
                            ],
                          ),
                          if (selectedSeason != null &&
                              selectedSeason.episodes.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            SizedBox(
                              width: widget.enableTvRemoteNavigation ? 320 : double.infinity,
                              child: FilledButton.icon(
                                autofocus: widget.enableTvRemoteNavigation,
                                onPressed: () {
                                  unawaited(_playEpisode(0));
                                },
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('REPRODUCIR'),
                              ),
                            ),
                            if (!widget.enableTvRemoteNavigation) ...[
                              const SizedBox(height: 10),
                              _DownloadSeasonButton(
                                loading: _seasonDownloadLoading,
                                progress: _seasonDownloadProgress,
                                versionLabel: seriesVariantLabel(
                                  _versions[_selectedVersionIndex],
                                ),
                                onDownload: () {
                                  unawaited(_downloadSelectedSeason());
                                },
                              ),
                            ],
                          ],
                          if (widget.enableTvRemoteNavigation) ...[
                            const SizedBox(height: 12),
                            Text(
                              series.plot.isEmpty
                                  ? 'No hay una descripción disponible para esta serie.'
                                  : series.plot,
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFD1D7E2),
                                fontSize: 14.5,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (_versions.length > 1) ...[
                  const SizedBox(height: 24),
                  _SeriesVersionSelector(
                    versions: _versions,
                    selectedIndex: _selectedVersionIndex,
                    loading: _loadingDetails,
                    onSelected: (index) {
                      unawaited(_loadSelectedVersion(index));
                    },
                  ),
                ],
                if (series.genre.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  Text(
                    series.genre,
                    style: const TextStyle(
                      color: Color(0xFFFFA66B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Sinopsis',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 9),
                Text(
                  series.plot.isEmpty
                      ? 'No hay una descripción disponible para esta serie.'
                      : series.plot,
                  style: const TextStyle(
                    color: Color(0xFFB0B7C3),
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
                if (series.director.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _DetailRow(label: 'Dirección', value: series.director),
                ],
                if (series.cast.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _DetailRow(label: 'Reparto', value: series.cast),
                ],
                if (series.releaseDate.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _DetailRow(label: 'Estreno', value: series.releaseDate),
                ],
                if (series.episodeRunTime.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _DetailRow(
                    label: 'Duración aproximada',
                    value: series.episodeRunTime,
                  ),
                ],
                const SizedBox(height: 30),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Temporadas y episodios',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (selectedSeason != null)
                      Text(
                        '${selectedSeason.episodes.length} capítulos',
                        style: const TextStyle(
                          color: Color(0xFF98A2B3),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (_errorMessage != null)
                  _LoadError(
                    message: _errorMessage!,
                    onRetry: () {
                      unawaited(_loadSelectedVersion(_selectedVersionIndex));
                    },
                  )
                else if (!_loadingDetails && _details.seasons.isEmpty)
                  const _EmptyEpisodes()
                else ...[
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _details.seasons.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 9),
                      itemBuilder: (context, index) {
                        final season = _details.seasons[index];

                        return ChoiceChip(
                          selected: _selectedSeasonIndex == index,
                          onSelected: (_) => _selectSeason(index),
                          label: Text(season.name),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (selectedSeason != null)
                    ...List<Widget>.generate(
                      selectedSeason.episodes.length,
                      (index) {
                        final episode = selectedSeason.episodes[index];

                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index == selectedSeason.episodes.length - 1
                                ? 0
                                : 12,
                          ),
                          child: _EpisodeCard(
                            episode: episode,
                            progress:
                                _episodeProgress[episode.episodeId]?.progress ??
                                    0,
                            download: _episodeDownloads[episode.episodeId],
                            downloadLoading: _episodeDownloadsLoading
                                .contains(episode.episodeId),
                            downloadProgress:
                                _episodeDownloadProgress[episode.episodeId],
                            fallbackImage: selectedSeason.coverUrl.isNotEmpty
                                ? selectedSeason.coverUrl
                                : series.coverUrl,
                            onPressed: () {
                              unawaited(_playEpisode(index));
                            },
                            onDownload: () {
                              unawaited(
                                _downloadEpisode(selectedSeason, episode),
                              );
                            },
                            onDeleteDownload: () {
                              unawaited(_deleteEpisodeDownload(episode));
                            },
                            enableTvRemoteNavigation:
                                widget.enableTvRemoteNavigation,
                          ),
                        );
                      },
                    ),
                ],
              ]),
            ),
          ),
        ],
        ),
      ),
    );
  }
}


class _DownloadSeasonButton extends StatelessWidget {
  const _DownloadSeasonButton({
    required this.loading,
    required this.progress,
    required this.versionLabel,
    required this.onDownload,
  });

  final bool loading;
  final double? progress;
  final String versionLabel;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final currentProgress = progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: loading ? null : onDownload,
          icon: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_rounded),
          label: Text(
            loading && currentProgress != null
                ? 'DESCARGANDO ${(currentProgress * 100).clamp(0, 100).toStringAsFixed(0)}%'
                : 'DESCARGAR TEMPORADA',
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Descarga: $versionLabel',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF98A2B3),
            fontSize: 11.5,
          ),
        ),
      ],
    );
  }
}

class _SeriesVersionSelector extends StatelessWidget {
  const _SeriesVersionSelector({
    required this.versions,
    required this.selectedIndex,
    required this.loading,
    required this.onSelected,
  });

  final List<TvSeries> versions;
  final int selectedIndex;
  final bool loading;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
      decoration: BoxDecoration(
        color: const Color(0xFF111620),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF252D3A)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF3C2B22),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.translate_rounded,
              color: Color(0xFFFFA66B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Versión para reproducir o descargar',
                  style: TextStyle(fontSize: 12, color: Color(0xFF98A2B3)),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: selectedIndex,
                    isExpanded: true,
                    isDense: true,
                    borderRadius: BorderRadius.circular(16),
                    items: [
                      for (int index = 0; index < versions.length; index++)
                        DropdownMenuItem<int>(
                          value: index,
                          child: Text(
                            seriesVariantLabel(versions[index]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                    onChanged: loading
                        ? null
                        : (value) {
                            if (value != null) {
                              onSelected(value);
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(left: 8, right: 4),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.episode,
    required this.progress,
    required this.download,
    required this.downloadLoading,
    required this.downloadProgress,
    required this.fallbackImage,
    required this.onPressed,
    required this.onDownload,
    required this.onDeleteDownload,
    required this.enableTvRemoteNavigation,
  });

  final SeriesEpisode episode;
  final double progress;
  final OfflineDownloadEntry? download;
  final bool downloadLoading;
  final double? downloadProgress;
  final String fallbackImage;
  final VoidCallback onPressed;
  final VoidCallback onDownload;
  final VoidCallback onDeleteDownload;
  final bool enableTvRemoteNavigation;

  @override
  Widget build(BuildContext context) {
    final imageUrl = episode.imageUrl.isNotEmpty
        ? episode.imageUrl
        : fallbackImage;

    final radius = BorderRadius.circular(18);

    return TvFocusableSurface(
      enabled: enableTvRemoteNavigation,
      onPressed: onPressed,
      borderRadius: radius,
      builder: (context, focused) {
        return Ink(
          padding: const EdgeInsets.all(10),
          decoration: tvFocusedDecoration(
            focused: focused,
            backgroundColor: const Color(0xFF111620),
            borderRadius: radius,
            normalBorderColor: const Color(0xFF232A36),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 126,
                  height: 74,
                  child: imageUrl.isEmpty
                      ? const _EpisodeImageFallback()
                      : AppCachedImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          cacheWidth: 420,
                          cacheHeight: 240,
                          fallback: const _EpisodeImageFallback(),
                        ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      episode.episodeNumber > 0
                          ? 'Episodio ${episode.episodeNumber}'
                          : 'Episodio',
                      style: const TextStyle(
                        color: Color(0xFFFFA66B),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      episode.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        if (episode.duration.isNotEmpty)
                          _EpisodeMeta(
                            icon: Icons.schedule_rounded,
                            value: episode.duration,
                          ),
                        if (episode.duration.isNotEmpty &&
                            episode.displayRating.isNotEmpty)
                          const SizedBox(width: 12),
                        if (episode.displayRating.isNotEmpty)
                          _EpisodeMeta(
                            icon: Icons.star_rounded,
                            value: episode.displayRating,
                            accent: true,
                          ),
                      ],
                    ),
                    if (progress > 0) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          backgroundColor:
                              const Color(0xFF252C38),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2130),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Color(0xFFFFA66B),
                      size: 28,
                    ),
                  ),
                  if (!enableTvRemoteNavigation) ...[
                    const SizedBox(height: 8),
                    _EpisodeDownloadIcon(
                      download: download,
                      loading: downloadLoading,
                      progress: downloadProgress,
                      onDownload: onDownload,
                      onDelete: onDeleteDownload,
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}


class _EpisodeDownloadIcon extends StatelessWidget {
  const _EpisodeDownloadIcon({
    required this.download,
    required this.loading,
    required this.progress,
    required this.onDownload,
    required this.onDelete,
  });

  final OfflineDownloadEntry? download;
  final bool loading;
  final double? progress;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final downloaded = download;

    if (downloaded != null) {
      return Tooltip(
        message: 'Descargado · tocar para eliminar',
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: loading ? null : onDelete,
          child: Container(
            width: 42,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF13341F),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.download_done_rounded,
              size: 20,
              color: Color(0xFF59D383),
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: 'Descargar episodio',
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: loading ? null : onDownload,
        child: Container(
          width: 42,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF1C2430),
            borderRadius: BorderRadius.circular(11),
          ),
          child: loading
              ? Text(
                  '${((progress ?? 0) * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : const Icon(
                  Icons.download_rounded,
                  size: 20,
                  color: Color(0xFFD0D5DD),
                ),
        ),
      ),
    );
  }
}

class _EpisodeMeta extends StatelessWidget {
  const _EpisodeMeta({
    required this.icon,
    required this.value,
    this.accent = false,
  });

  final IconData icon;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 13,
          color: accent
              ? const Color(0xFFFFC857)
              : const Color(0xFF98A2B3),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF98A2B3),
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }
}

class _SeriesCoverFallback extends StatelessWidget {
  const _SeriesCoverFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF171D28),
      child: Center(
        child: Icon(
          Icons.video_library_outlined,
          size: 46,
          color: Color(0xFF667085),
        ),
      ),
    );
  }
}

class _EpisodeImageFallback extends StatelessWidget {
  const _EpisodeImageFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF171D28),
      child: Center(
        child: Icon(
          Icons.play_circle_outline_rounded,
          color: Color(0xFF667085),
          size: 34,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = accent
        ? const Color(0xFFFFC857)
        : const Color(0xFFD0D5DD);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF171D28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2A3240)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF98A2B3),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFFD0D5DD),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({
    required this.message,
    required this.onRetry,
  });

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
          const Icon(
            Icons.cloud_off_rounded,
            color: Color(0xFFFF7D8A),
            size: 38,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFD0D5DD)),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('REINTENTAR'),
          ),
        ],
      ),
    );
  }
}

class _EmptyEpisodes extends StatelessWidget {
  const _EmptyEpisodes();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF111620),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF232A36)),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.playlist_remove_rounded,
            color: Color(0xFF667085),
            size: 46,
          ),
          SizedBox(height: 12),
          Text(
            'Esta serie no informa episodios disponibles.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF98A2B3)),
          ),
        ],
      ),
    );
  }
}
