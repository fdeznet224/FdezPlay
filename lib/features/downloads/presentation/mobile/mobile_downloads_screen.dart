import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/widgets/app_cached_image.dart';
import '../../../auth/domain/auth_session.dart';
import '../../../movies/domain/movie.dart';
import '../../../player/presentation/mobile/mobile_movie_player_screen.dart';
import '../../../player/presentation/mobile/mobile_series_player_screen.dart';
import '../../../series/domain/tv_series.dart';
import '../../data/offline_download_service.dart';

class MobileDownloadsScreen extends StatefulWidget {
  const MobileDownloadsScreen({
    required this.session,
    this.enableTvRemoteNavigation = false,
    super.key,
  });

  final AuthSession session;
  final bool enableTvRemoteNavigation;

  @override
  State<MobileDownloadsScreen> createState() => _MobileDownloadsScreenState();
}

class _MobileDownloadsScreenState extends State<MobileDownloadsScreen> {
  final OfflineDownloadService _downloadService =
      OfflineDownloadService.instance;

  late Future<List<OfflineDownloadEntry>> _downloadsFuture;
  List<OfflineDownloadTaskSnapshot> _activeTasks = const [];

  @override
  void initState() {
    super.initState();
    _downloadsFuture = _downloadService.loadDownloads(widget.session);
    _activeTasks = _downloadService.activeTasks.value;
    _downloadService.activeTasks.addListener(_handleActiveTasksChanged);
  }

  @override
  void dispose() {
    _downloadService.activeTasks.removeListener(_handleActiveTasksChanged);
    super.dispose();
  }

  void _handleActiveTasksChanged() {
    if (!mounted) {
      return;
    }

    final nextTasks = _downloadService.activeTasks.value;
    final shouldRefreshSavedDownloads =
        _activeTasks.isNotEmpty && nextTasks.isEmpty;

    setState(() {
      _activeTasks = nextTasks;

      // No recargamos la lista guardada en cada KB recibido.
      // Eso provocaba parpadeo porque el FutureBuilder reconstruía toda la pantalla.
      if (shouldRefreshSavedDownloads) {
        _downloadsFuture = _downloadService.loadDownloads(widget.session);
      }
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _downloadsFuture = _downloadService.loadDownloads(widget.session);
    });

    await _downloadsFuture;
  }

  Future<void> _resumeTask(OfflineDownloadTaskSnapshot task) async {
    try {
      await _downloadService.resumeDownload(widget.session, task.key);

      if (!mounted) {
        return;
      }

      _showMessage('Descarga completada.');
      await _refresh();
    } on DownloadPausedException {
      if (mounted) {
        _showMessage('Descarga pausada.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('No se pudo reanudar la descarga.');
      }
    }
  }

  Future<void> _cancelTask(OfflineDownloadTaskSnapshot task) async {
    final confirmed = await _confirm(
      title: 'Cancelar descarga',
      message:
          'Se eliminará el archivo parcial de "${task.title}". Puedes descargarlo nuevamente después.',
      confirmLabel: 'CANCELAR DESCARGA',
      destructive: true,
    );

    if (!confirmed) {
      return;
    }

    await _downloadService.cancelTask(widget.session, task.key);

    if (!mounted) {
      return;
    }

    _showMessage('Descarga cancelada.');
    await _refresh();
  }

  Future<void> _deleteDownload(OfflineDownloadEntry entry) async {
    final confirmed = await _confirm(
      title: 'Eliminar descarga',
      message: '¿Quieres eliminar "${entry.title}" del dispositivo?',
      confirmLabel: 'ELIMINAR',
      destructive: true,
    );

    if (!confirmed) {
      return;
    }

    await _downloadService.deleteDownload(widget.session, entry);

    if (!mounted) {
      return;
    }

    _showMessage('Descarga eliminada.');
    await _refresh();
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('VOLVER'),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFC63D4E),
                    )
                  : null,
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  void _playDownload(OfflineDownloadEntry entry) {
    if (entry.isMovie) {
      _playMovie(entry);
      return;
    }

    _playEpisode(entry);
  }

  void _playMovie(OfflineDownloadEntry entry) {
    final movie = Movie(
      streamId: entry.id,
      name: entry.title,
      posterUrl: entry.imageUrl,
      categoryId: '',
      containerExtension: entry.extension.isEmpty ? 'mp4' : entry.extension,
      rating: '',
      year: '',
      plot: '',
      duration: '',
      genre: '',
      director: '',
      cast: '',
      releaseDate: '',
      backdropUrl: entry.imageUrl,
      directSource: entry.sourceUrl,
    );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MobileMoviePlayerScreen(
          session: widget.session,
          movie: movie,
          displayTitle: entry.title,
          localPath: entry.localPath,
          enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
        ),
      ),
    );
  }

  void _playEpisode(OfflineDownloadEntry entry) {
    final seriesTitle = entry.seriesTitle.trim().isEmpty
        ? 'Serie descargada'
        : entry.seriesTitle;
    final seasonName = entry.seasonName.trim().isEmpty
        ? 'Temporada'
        : entry.seasonName;
    final episode = SeriesEpisode(
      episodeId: entry.id,
      episodeNumber: entry.episodeNumber,
      seasonNumber: 0,
      title: entry.title,
      containerExtension: entry.extension.isEmpty ? 'mp4' : entry.extension,
      plot: '',
      duration: '',
      releaseDate: '',
      rating: '',
      imageUrl: entry.imageUrl,
      directSource: entry.sourceUrl,
    );
    final series = TvSeries(
      seriesId: entry.seriesId,
      name: seriesTitle,
      coverUrl: entry.imageUrl,
      categoryId: '',
      plot: '',
      cast: '',
      director: '',
      genre: '',
      releaseDate: '',
      rating: '',
      backdropUrl: entry.imageUrl,
      youtubeTrailer: '',
      episodeRunTime: '',
    );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MobileSeriesPlayerScreen(
          session: widget.session,
          series: series,
          seasonName: seasonName,
          episodes: [episode],
          initialIndex: 0,
          displayTitle: seriesTitle,
          offlineEpisodePaths: {entry.id: entry.localPath},
          enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080B12),
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<List<OfflineDownloadEntry>>(
          future: _downloadsFuture,
          builder: (context, snapshot) {
            final downloads = snapshot.data ?? const <OfflineDownloadEntry>[];
            final loading =
                snapshot.connectionState == ConnectionState.waiting &&
                    downloads.isEmpty;
            final totalBytes = downloads.fold<int>(
              0,
              (total, item) => total + item.sizeBytes,
            );
            final movies = downloads.where((item) => item.isMovie).length;
            final episodes = downloads.where((item) => item.isEpisode).length;

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 34),
                children: [
                  _DownloadsHeader(
                    activeCount: _activeTasks.length,
                    downloadCount: downloads.length,
                    totalBytes: totalBytes,
                    onBack: () => Navigator.of(context).maybePop(),
                    onRefresh: () => unawaited(_refresh()),
                  ),
                  const SizedBox(height: 18),
                  _DownloadsStatsRow(
                    movies: movies,
                    episodes: episodes,
                    active: _activeTasks.length,
                    totalBytes: totalBytes,
                  ),
                  if (loading) ...[
                    const SizedBox(height: 80),
                    const Center(child: CircularProgressIndicator()),
                  ] else if (downloads.isEmpty && _activeTasks.isEmpty) ...[
                    const SizedBox(height: 80),
                    const _EmptyDownloadsMessage(),
                  ] else ...[
                    if (_activeTasks.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      const _SectionHeader(
                        title: 'En progreso',
                        subtitle: 'Pausa, reanuda o cancela tus descargas',
                        icon: Icons.downloading_rounded,
                      ),
                      const SizedBox(height: 12),
                      for (final task in _activeTasks) ...[
                        _ActiveDownloadCard(
                          task: task,
                          onPause: () => _downloadService.pauseDownload(task.key),
                          onResume: () => unawaited(_resumeTask(task)),
                          onCancel: () => unawaited(_cancelTask(task)),
                          enableTvRemoteNavigation:
                              widget.enableTvRemoteNavigation,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                    if (downloads.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const _SectionHeader(
                        title: 'Guardado en este dispositivo',
                        subtitle: 'Disponible para reproducir sin conexión',
                        icon: Icons.offline_pin_rounded,
                      ),
                      const SizedBox(height: 12),
                      for (final entry in downloads) ...[
                        _CompletedDownloadCard(
                          entry: entry,
                          onPlay: () => _playDownload(entry),
                          onDelete: () => unawaited(_deleteDownload(entry)),
                          enableTvRemoteNavigation:
                              widget.enableTvRemoteNavigation,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DownloadsHeader extends StatelessWidget {
  const _DownloadsHeader({
    required this.activeCount,
    required this.downloadCount,
    required this.totalBytes,
    required this.onBack,
    required this.onRefresh,
  });

  final int activeCount;
  final int downloadCount;
  final int totalBytes;
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF18223C),
            Color(0xFF101722),
          ],
        ),
        border: Border.all(color: const Color(0xFF263149)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Volver',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Mis descargas',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Actualizar',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            activeCount > 0
                ? '$activeCount en progreso · $downloadCount guardados · ${_sizeLabel(totalBytes)}'
                : '$downloadCount contenidos guardados · ${_sizeLabel(totalBytes)}',
            style: const TextStyle(
              color: Color(0xFFCFD6E2),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Descarga películas o episodios para verlos después sin depender de internet.',
            style: TextStyle(
              color: Color(0xFF98A2B3),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadsStatsRow extends StatelessWidget {
  const _DownloadsStatsRow({
    required this.movies,
    required this.episodes,
    required this.active,
    required this.totalBytes,
  });

  final int movies;
  final int episodes;
  final int active;
  final int totalBytes;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatChip(
            icon: Icons.movie_rounded,
            label: 'Películas',
            value: '$movies',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatChip(
            icon: Icons.video_library_rounded,
            label: 'Episodios',
            value: '$episodes',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatChip(
            icon: active > 0
                ? Icons.downloading_rounded
                : Icons.storage_rounded,
            label: active > 0 ? 'Activas' : 'Espacio',
            value: active > 0 ? '$active' : _sizeLabel(totalBytes),
          ),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF111620),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF232A36)),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF8EA5FF), size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF98A2B3),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF17213B),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF8EA5FF)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF98A2B3),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActiveDownloadCard extends StatelessWidget {
  const _ActiveDownloadCard({
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.enableTvRemoteNavigation,
  });

  final OfflineDownloadTaskSnapshot task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final bool enableTvRemoteNavigation;

  @override
  Widget build(BuildContext context) {
    final icon = task.isMovie
        ? Icons.movie_outlined
        : Icons.video_library_outlined;
    final statusColor = task.hasError
        ? const Color(0xFFFF7D8A)
        : task.isPaused
            ? const Color(0xFFFFD166)
            : const Color(0xFF50D5B7);

    return _DownloadSurface(
      enableTvRemoteNavigation: enableTvRemoteNavigation,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DownloadPoster(imageUrl: task.imageUrl),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 17, color: const Color(0xFF8EA5FF)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        task.subtitle.isEmpty
                            ? (task.isMovie ? 'Película' : 'Episodio')
                            : task.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF98A2B3),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _StatusPill(
                      label: task.statusLabel,
                      color: statusColor,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      task.progressLabel,
                      style: const TextStyle(
                        color: Color(0xFF8EA5FF),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        task.sizeProgressLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF98A2B3),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: task.totalBytes > 0
                        ? task.progress.clamp(0.0, 1.0).toDouble()
                        : null,
                    minHeight: 7,
                    backgroundColor: const Color(0xFF252C38),
                  ),
                ),
                if (task.hasError && task.errorMessage.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    task.errorMessage,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFFFA0AA),
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: task.isDownloading ? onPause : onResume,
                      icon: Icon(
                        task.isDownloading
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 18,
                      ),
                      label: Text(task.isDownloading ? 'PAUSAR' : 'REANUDAR'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('CANCELAR'),
                    ),
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

class _CompletedDownloadCard extends StatelessWidget {
  const _CompletedDownloadCard({
    required this.entry,
    required this.onPlay,
    required this.onDelete,
    required this.enableTvRemoteNavigation,
  });

  final OfflineDownloadEntry entry;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final bool enableTvRemoteNavigation;

  @override
  Widget build(BuildContext context) {
    final subtitle = entry.isMovie
        ? 'Película · ${entry.sizeLabel}'
        : '${entry.seriesTitle} · ${entry.seasonName} · ${entry.sizeLabel}';

    return _DownloadSurface(
      enableTvRemoteNavigation: enableTvRemoteNavigation,
      onPressed: onPlay,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DownloadPoster(imageUrl: entry.imageUrl),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      entry.isMovie
                          ? Icons.movie_outlined
                          : Icons.video_library_outlined,
                      size: 17,
                      color: const Color(0xFF8EA5FF),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        entry.isMovie ? 'Película descargada' : 'Episodio descargado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF98A2B3),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _StatusPill(
                      label: entry.sizeLabel,
                      color: const Color(0xFF50D5B7),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  entry.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF98A2B3),
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('VER'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('ELIMINAR'),
                    ),
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DownloadSurface extends StatefulWidget {
  const _DownloadSurface({
    required this.child,
    required this.enableTvRemoteNavigation,
    this.onPressed,
  });

  final Widget child;
  final bool enableTvRemoteNavigation;
  final VoidCallback? onPressed;

  @override
  State<_DownloadSurface> createState() => _DownloadSurfaceState();
}

class _DownloadSurfaceState extends State<_DownloadSurface> {
  bool _focused = false;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || widget.onPressed == null) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      widget.onPressed!();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: widget.enableTvRemoteNavigation,
      onKeyEvent: _handleKey,
      onFocusChange: (focused) {
        if (_focused != focused) {
          setState(() {
            _focused = focused;
          });
        }
      },
      child: AnimatedScale(
        scale: _focused ? 1.015 : 1,
        duration: const Duration(milliseconds: 140),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(22),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: const Color(0xFF111620),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: _focused
                      ? Colors.white
                      : const Color(0xFF232A36),
                  width: _focused ? 3 : 1,
                ),
                boxShadow: _focused
                    ? const [
                        BoxShadow(
                          color: Color(0x666F8CFF),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ]
                    : const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 10,
                          offset: Offset(0, 6),
                        ),
                      ],
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadPoster extends StatelessWidget {
  const _DownloadPoster({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 86,
        height: 126,
        child: imageUrl.isEmpty
            ? Container(
                color: const Color(0xFF252C38),
                child: const Icon(Icons.movie_outlined),
              )
            : AppCachedImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                fallback: Container(
                  color: const Color(0xFF252C38),
                  child: const Icon(Icons.movie_outlined),
                ),
              ),
      ),
    );
  }
}

class _EmptyDownloadsMessage extends StatelessWidget {
  const _EmptyDownloadsMessage();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF111620),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF232A36)),
      ),
      child: Column(
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: const Color(0xFF17213B),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(
              Icons.download_for_offline_outlined,
              size: 44,
              color: Color(0xFF6F8CFF),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Todavía no tienes descargas',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Entra al detalle de una película o episodio y toca Descargar. Aquí verás el progreso, podrás pausar y reanudar.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

String _sizeLabel(int bytes) {
  if (bytes <= 0) {
    return '0 MB';
  }

  final mb = bytes / (1024 * 1024);

  if (mb < 1024) {
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }

  final gb = mb / 1024;
  return '${gb.toStringAsFixed(gb >= 10 ? 1 : 2)} GB';
}
