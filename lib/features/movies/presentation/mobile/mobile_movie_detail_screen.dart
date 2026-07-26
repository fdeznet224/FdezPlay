import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/services/iptv_api_service.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../../../auth/domain/auth_session.dart';
import '../../../downloads/data/offline_download_service.dart';
import '../../../favorites/data/local_library_service.dart';
import '../../../player/presentation/mobile/mobile_movie_player_screen.dart';
import '../../domain/movie.dart';
import '../../domain/movie_group.dart';

class MobileMovieDetailScreen extends StatefulWidget {
  const MobileMovieDetailScreen({
    required this.session,
    required this.movie,
    this.versions = const [],
    this.displayTitle,
    this.enableTvRemoteNavigation = false,
    super.key,
  });

  final AuthSession session;
  final Movie movie;
  final List<Movie> versions;
  final String? displayTitle;
  final bool enableTvRemoteNavigation;

  @override
  State<MobileMovieDetailScreen> createState() {
    return _MobileMovieDetailScreenState();
  }
}

class _MobileMovieDetailScreenState
    extends State<MobileMovieDetailScreen> {
  final IptvApiService _apiService = IptvApiService();
  final LocalLibraryService _libraryService =
      LocalLibraryService.instance;
  final OfflineDownloadService _downloadService =
      OfflineDownloadService.instance;

  late final List<Movie> _versions;
  late final Movie _libraryMovie;
  late Movie _movie;

  int _selectedVersionIndex = 0;
  int _detailsRequestId = 0;
  bool _loadingDetails = true;
  bool _favoriteLoading = true;
  bool _isFavorite = false;
  bool _downloadLoading = false;
  double? _downloadProgress;
  WatchProgressEntry? _savedProgress;
  OfflineDownloadEntry? _selectedDownload;
  DateTime? _ignoreTvBackUntil;

  Movie get _selectedMovie => _versions[_selectedVersionIndex];

  String get _displayTitle {
    final provided = widget.displayTitle?.trim() ?? '';

    if (provided.isNotEmpty) {
      return provided;
    }

    final clean = cleanMovieTitle(_libraryMovie.name);
    return clean.isEmpty ? _libraryMovie.name : clean;
  }

  @override
  void initState() {
    super.initState();

    _versions = _buildVersions();
    _libraryMovie = _versions.first;
    _movie = _versions.first;

    unawaited(_loadSelectedDetails());
    unawaited(_loadLibraryState());
  }

  List<Movie> _buildVersions() {
    final source = widget.versions.isEmpty
        ? <Movie>[widget.movie]
        : List<Movie>.from(widget.versions);
    final seen = <int>{};
    final result = <Movie>[];

    for (final movie in source) {
      if (movie.streamId > 0 && seen.add(movie.streamId)) {
        result.add(movie);
      }
    }

    if (result.isEmpty) {
      result.add(widget.movie);
    }

    return List<Movie>.unmodifiable(result);
  }

  Future<void> _loadSelectedDetails() async {
    final requestId = ++_detailsRequestId;
    final selected = _versions[_selectedVersionIndex];

    setState(() {
      _movie = selected;
      _loadingDetails = true;
    });

    try {
      final details = await _apiService.loadMovieDetails(
        widget.session,
        movie: selected,
      );

      if (!mounted || requestId != _detailsRequestId) {
        return;
      }

      setState(() {
        _movie = details;
        _loadingDetails = false;
      });
    } catch (_) {
      if (!mounted || requestId != _detailsRequestId) {
        return;
      }

      setState(() {
        _movie = selected;
        _loadingDetails = false;
      });
    }
  }

  Future<void> _selectVersion(int index) async {
    if (index < 0 ||
        index >= _versions.length ||
        index == _selectedVersionIndex) {
      return;
    }

    setState(() {
      _selectedVersionIndex = index;
    });

    await _loadSelectedDetails();
    await _loadLibraryState();
  }

  Future<void> _loadLibraryState() async {
    try {
      final snapshot = await _libraryService.load(widget.session);

      if (!mounted) {
        return;
      }

      WatchProgressEntry? savedProgress;

      for (final item in snapshot.progress) {
        if (item.movie?.streamId == _libraryMovie.streamId) {
          savedProgress = item;
          break;
        }
      }

      final selectedDownload = await _downloadService.movieDownload(
        widget.session,
        _selectedMovie.streamId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isFavorite = snapshot.favorites.any(
          (item) => item.movie?.streamId == _libraryMovie.streamId,
        );
        _savedProgress = savedProgress;
        _selectedDownload = selectedDownload;
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

  Future<void> _toggleFavorite() async {
    if (_favoriteLoading) {
      return;
    }

    setState(() {
      _favoriteLoading = true;
    });

    try {
      final isFavorite = await _libraryService.toggleMovieFavorite(
        widget.session,
        _libraryMovie,
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
                  ? 'Película agregada a favoritos.'
                  : 'Película eliminada de favoritos.',
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

  Future<void> _downloadMovie() async {
    if (_downloadLoading || _selectedDownload != null) {
      return;
    }

    setState(() {
      _downloadLoading = true;
      _downloadProgress = 0;
    });

    try {
      final downloaded = await _downloadService.downloadMovie(
        widget.session,
        _selectedMovie,
        displayTitle: _displayTitle,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }

          setState(() {
            _downloadProgress = progress;
          });
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedDownload = downloaded;
        _downloadLoading = false;
        _downloadProgress = null;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Película descargada para verla sin conexión.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } on DownloadPausedException {
      if (!mounted) {
        return;
      }

      setState(() {
        _downloadLoading = false;
        _downloadProgress = null;
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

      setState(() {
        _downloadLoading = false;
        _downloadProgress = null;
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No se pudo descargar esta película.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _deleteDownload() async {
    final download = _selectedDownload;

    if (download == null || _downloadLoading) {
      return;
    }

    setState(() {
      _downloadLoading = true;
    });

    try {
      await _downloadService.deleteDownload(widget.session, download);

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedDownload = null;
        _downloadLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _downloadLoading = false;
      });
    }
  }

  Future<void> _playMovie() async {
    WatchProgressEntry? latestProgress;

    try {
      latestProgress = await _libraryService.movieProgress(
        widget.session,
        _libraryMovie.streamId,
      );
    } catch (_) {
      latestProgress = _savedProgress;
    }

    if (!mounted) {
      return;
    }

    _savedProgress = latestProgress;

    final localPath = _selectedDownload?.localPath;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MobileMoviePlayerScreen(
          session: widget.session,
          movie: _selectedMovie,
          versions: _versions,
          initialVersionIndex: _selectedVersionIndex,
          displayTitle: _displayTitle,
          initialPosition: latestProgress?.position ?? Duration.zero,
          localPath: localPath,
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
    final backgroundUrl = _movie.backdropUrl.isNotEmpty
        ? _movie.backdropUrl
        : _movie.posterUrl;

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
                          Color(0x66000000),
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
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 34),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_loadingDetails)
                  const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Hero(
                      tag: 'movie-${_libraryMovie.streamId}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: SizedBox(
                          width: 126,
                          height: 186,
                          child: _movie.posterUrl.isEmpty
                              ? const _MoviePosterFallback()
                              : AppCachedImage(
                                  imageUrl: _movie.posterUrl,
                                  fit: BoxFit.cover,
                                  cacheWidth: 360,
                                  cacheHeight: 540,
                                  fallback: const _MoviePosterFallback(),
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
                              if (_movie.displayYear.isNotEmpty)
                                _InfoChip(
                                  icon: Icons.calendar_month_rounded,
                                  label: _movie.displayYear,
                                ),
                              if (_movie.duration.isNotEmpty)
                                _InfoChip(
                                  icon: Icons.schedule_rounded,
                                  label: _movie.duration,
                                ),
                              if (_movie.displayRating.isNotEmpty)
                                _InfoChip(
                                  icon: Icons.star_rounded,
                                  label: _movie.displayRating,
                                  accent: true,
                                ),
                              _InfoChip(
                                icon: Icons.high_quality_rounded,
                                label: _movie.safeExtension.toUpperCase(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: widget.enableTvRemoteNavigation ? 320 : double.infinity,
                            child: FilledButton.icon(
                              autofocus: widget.enableTvRemoteNavigation,
                              onPressed: _playMovie,
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(
                                _savedProgress == null
                                    ? 'REPRODUCIR'
                                    : 'CONTINUAR',
                              ),
                            ),
                          ),
                          if (widget.enableTvRemoteNavigation) ...[
                            const SizedBox(height: 12),
                            Text(
                              _movie.plot.isEmpty
                                  ? 'No hay una descripción disponible para esta película.'
                                  : _movie.plot,
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFD1D7E2),
                                fontSize: 14.5,
                                height: 1.45,
                              ),
                            ),
                          ],
                          if (!widget.enableTvRemoteNavigation) ...[
                            const SizedBox(height: 10),
                            _DownloadMovieButton(
                              download: _selectedDownload,
                              loading: _downloadLoading,
                              progress: _downloadProgress,
                              onDownload: _downloadMovie,
                              onDelete: _deleteDownload,
                            ),
                            if (_versions.length > 1) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Descarga: ${movieVariantLabel(_selectedMovie)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF98A2B3),
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ],
                          if (_savedProgress != null) ...[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: _savedProgress!.progress,
                                minHeight: 5,
                                backgroundColor: const Color(0xFF252C38),
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
                  _VersionSelector(
                    versions: _versions,
                    selectedIndex: _selectedVersionIndex,
                    loading: _loadingDetails,
                    onSelected: (index) {
                      unawaited(_selectVersion(index));
                    },
                  ),
                ],
                if (_movie.genre.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  Text(
                    _movie.genre,
                    style: const TextStyle(
                      color: Color(0xFFBE91FF),
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
                  _movie.plot.isEmpty
                      ? 'No hay una descripción disponible para esta película.'
                      : _movie.plot,
                  style: const TextStyle(
                    color: Color(0xFFB0B7C3),
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
                if (_movie.director.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  _DetailRow(label: 'Dirección', value: _movie.director),
                ],
                if (_movie.cast.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _DetailRow(label: 'Reparto', value: _movie.cast),
                ],
                if (_movie.releaseDate.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _DetailRow(label: 'Estreno', value: _movie.releaseDate),
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


class _DownloadMovieButton extends StatelessWidget {
  const _DownloadMovieButton({
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
      return OutlinedButton.icon(
        onPressed: loading ? null : onDelete,
        icon: const Icon(Icons.download_done_rounded),
        label: Text('DESCARGADA · ${downloaded.sizeLabel}'),
      );
    }

    final currentProgress = progress;

    return OutlinedButton.icon(
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
            : 'DESCARGAR VERSIÓN',
      ),
    );
  }
}

class _VersionSelector extends StatelessWidget {
  const _VersionSelector({
    required this.versions,
    required this.selectedIndex,
    required this.loading,
    required this.onSelected,
  });

  final List<Movie> versions;
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
              color: const Color(0xFF2D2340),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.translate_rounded,
              color: Color(0xFFBE91FF),
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
                            movieVariantLabel(versions[index]),
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

class _MoviePosterFallback extends StatelessWidget {
  const _MoviePosterFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFF171D28),
      child: Icon(
        Icons.movie_creation_outlined,
        size: 46,
        color: Color(0xFF667085),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent ? const Color(0xFF332A18) : const Color(0xFF171D28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent ? const Color(0xFF5A4720) : const Color(0xFF252D3A),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: accent
                ? const Color(0xFFFFC857)
                : const Color(0xFF98A2B3),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF98A2B3),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(height: 1.4, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
