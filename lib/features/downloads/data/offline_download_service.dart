import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'download_foreground_service.dart';

import '../../auth/domain/auth_session.dart';
import '../../movies/domain/movie.dart';
import '../../series/domain/tv_series.dart';

class DownloadPausedException implements Exception {
  const DownloadPausedException();

  @override
  String toString() => 'Descarga pausada';
}

enum OfflineDownloadTaskStatus {
  downloading,
  paused,
  error,
}

class OfflineDownloadEntry {
  const OfflineDownloadEntry({
    required this.type,
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.localPath,
    required this.sourceUrl,
    required this.extension,
    required this.sizeBytes,
    required this.downloadedAt,
    this.seriesId = 0,
    this.seriesTitle = '',
    this.seasonName = '',
    this.episodeNumber = 0,
  });

  final String type;
  final int id;
  final String title;
  final String imageUrl;
  final String localPath;
  final String sourceUrl;
  final String extension;
  final int sizeBytes;
  final int downloadedAt;
  final int seriesId;
  final String seriesTitle;
  final String seasonName;
  final int episodeNumber;

  String get key => '$type:$id';

  bool get isMovie => type == 'movie';

  bool get isEpisode => type == 'episode';

  File get file => File(localPath);

  String get sizeLabel => _sizeLabel(sizeBytes, fallback: 'Descargado');

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'id': id,
      'title': title,
      'image_url': imageUrl,
      'local_path': localPath,
      'source_url': sourceUrl,
      'extension': extension,
      'size_bytes': sizeBytes,
      'downloaded_at': downloadedAt,
      'series_id': seriesId,
      'series_title': seriesTitle,
      'season_name': seasonName,
      'episode_number': episodeNumber,
    };
  }

  factory OfflineDownloadEntry.fromJson(Map<String, dynamic> json) {
    return OfflineDownloadEntry(
      type: _text(json['type']),
      id: _toInt(json['id']),
      title: _text(json['title']),
      imageUrl: _text(json['image_url']),
      localPath: _text(json['local_path']),
      sourceUrl: _text(json['source_url']),
      extension: _text(json['extension']),
      sizeBytes: _toInt(json['size_bytes']),
      downloadedAt: _toInt(json['downloaded_at']),
      seriesId: _toInt(json['series_id']),
      seriesTitle: _text(json['series_title']),
      seasonName: _text(json['season_name']),
      episodeNumber: _toInt(json['episode_number']),
    );
  }
}

class OfflineDownloadTaskSnapshot {
  const OfflineDownloadTaskSnapshot({
    required this.key,
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.sourceUrl,
    required this.folder,
    required this.fileName,
    required this.extension,
    required this.progress,
    required this.receivedBytes,
    required this.totalBytes,
    required this.startedAt,
    this.status = OfflineDownloadTaskStatus.downloading,
    this.seriesId = 0,
    this.seriesTitle = '',
    this.seasonName = '',
    this.episodeNumber = 0,
    this.errorMessage = '',
  });

  final String key;
  final String type;
  final int id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String sourceUrl;
  final String folder;
  final String fileName;
  final String extension;
  final double progress;
  final int receivedBytes;
  final int totalBytes;
  final int startedAt;
  final OfflineDownloadTaskStatus status;
  final int seriesId;
  final String seriesTitle;
  final String seasonName;
  final int episodeNumber;
  final String errorMessage;

  bool get isMovie => type == 'movie';

  bool get isEpisode => type == 'episode';

  bool get isDownloading => status == OfflineDownloadTaskStatus.downloading;

  bool get isPaused => status == OfflineDownloadTaskStatus.paused;

  bool get hasError => status == OfflineDownloadTaskStatus.error;

  String get progressLabel {
    final value = (progress.clamp(0.0, 1.0) * 100).round();
    return '$value%';
  }

  String get statusLabel {
    switch (status) {
      case OfflineDownloadTaskStatus.downloading:
        return 'Descargando';
      case OfflineDownloadTaskStatus.paused:
        return 'Pausada';
      case OfflineDownloadTaskStatus.error:
        return 'Error';
    }
  }

  String get sizeProgressLabel {
    if (totalBytes > 0) {
      return '${_sizeLabel(receivedBytes)} / ${_sizeLabel(totalBytes)}';
    }

    if (receivedBytes > 0) {
      return '${_sizeLabel(receivedBytes)} descargados';
    }

    return progressLabel;
  }

  OfflineDownloadTaskSnapshot copyWith({
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    OfflineDownloadTaskStatus? status,
    String? errorMessage,
  }) {
    return OfflineDownloadTaskSnapshot(
      key: key,
      type: type,
      id: id,
      title: title,
      subtitle: subtitle,
      imageUrl: imageUrl,
      sourceUrl: sourceUrl,
      folder: folder,
      fileName: fileName,
      extension: extension,
      progress: progress ?? this.progress,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      startedAt: startedAt,
      status: status ?? this.status,
      seriesId: seriesId,
      seriesTitle: seriesTitle,
      seasonName: seasonName,
      episodeNumber: episodeNumber,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class OfflineDownloadService {
  OfflineDownloadService._();

  static final OfflineDownloadService instance = OfflineDownloadService._();

  final Map<String, Future<void>> _activeDownloads = <String, Future<void>>{};
  final Map<String, _DownloadControl> _downloadControls =
      <String, _DownloadControl>{};
  final Map<String, OfflineDownloadTaskSnapshot> _activeTaskSnapshots =
      <String, OfflineDownloadTaskSnapshot>{};
  final Map<String, int> _lastProgressEmitAt = <String, int>{};
  final Map<String, double> _lastProgressEmitValue = <String, double>{};
  final Map<String, int> _lastProgressEmitBytes = <String, int>{};

  final ValueNotifier<List<OfflineDownloadTaskSnapshot>> activeTasks =
      ValueNotifier<List<OfflineDownloadTaskSnapshot>>(
    const <OfflineDownloadTaskSnapshot>[],
  );

  Future<List<OfflineDownloadEntry>> loadDownloads(
    AuthSession session,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey(session));

    if (raw == null || raw.trim().isEmpty) {
      return const <OfflineDownloadEntry>[];
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        return const <OfflineDownloadEntry>[];
      }

      final entries = decoded
          .whereType<Map>()
          .map((item) => OfflineDownloadEntry.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((item) => item.id > 0 && item.localPath.isNotEmpty)
          .toList();

      final valid = <OfflineDownloadEntry>[];

      for (final entry in entries) {
        if (await entry.file.exists()) {
          valid.add(entry);
        }
      }

      if (valid.length != entries.length) {
        await _saveDownloads(session, valid);
      }

      valid.sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
      return List<OfflineDownloadEntry>.unmodifiable(valid);
    } catch (_) {
      return const <OfflineDownloadEntry>[];
    }
  }

  Future<OfflineDownloadEntry?> movieDownload(
    AuthSession session,
    int streamId,
  ) async {
    final downloads = await loadDownloads(session);

    for (final entry in downloads) {
      if (entry.type == 'movie' && entry.id == streamId) {
        return entry;
      }
    }

    return null;
  }

  Future<OfflineDownloadEntry?> episodeDownload(
    AuthSession session,
    int episodeId,
  ) async {
    final downloads = await loadDownloads(session);

    for (final entry in downloads) {
      if (entry.type == 'episode' && entry.id == episodeId) {
        return entry;
      }
    }

    return null;
  }

  Future<Map<int, OfflineDownloadEntry>> episodeDownloads(
    AuthSession session,
    Iterable<int> episodeIds,
  ) async {
    final ids = episodeIds.toSet();
    final downloads = await loadDownloads(session);
    final result = <int, OfflineDownloadEntry>{};

    for (final entry in downloads) {
      if (entry.type == 'episode' && ids.contains(entry.id)) {
        result[entry.id] = entry;
      }
    }

    return Map<int, OfflineDownloadEntry>.unmodifiable(result);
  }

  Future<bool> isDownloading(String key) async {
    return _activeDownloads.containsKey(key);
  }

  void pauseDownload(String key) {
    final control = _downloadControls[key];

    if (control == null) {
      return;
    }

    control.pause();
    _markTaskPaused(key);
  }

  Future<void> resumeDownload(AuthSession session, String key) async {
    if (_activeDownloads.containsKey(key)) {
      await _activeDownloads[key];
    }

    final snapshot = _activeTaskSnapshots[key];

    if (snapshot == null || snapshot.isDownloading) {
      return;
    }

    final completer = Completer<void>();
    _activeDownloads[key] = completer.future;
    _registerActiveTask(
      snapshot.copyWith(
        status: OfflineDownloadTaskStatus.downloading,
        errorMessage: '',
      ),
    );

    try {
      final entry = await _downloadFromSnapshot(session, snapshot);
      await _upsertDownload(session, entry);
      completer.complete();
    } on DownloadPausedException {
      _markTaskPaused(key);
      completer.complete();
      rethrow;
    } catch (_) {
      _markTaskError(key, 'No se pudo continuar la descarga.');
      completer.complete();
      rethrow;
    } finally {
      _activeDownloads.remove(key);
      _downloadControls.remove(key);
    }
  }

  Future<void> cancelTask(AuthSession session, String key) async {
    pauseDownload(key);

    final snapshot = _activeTaskSnapshots.remove(key);
    _lastProgressEmitAt.remove(key);
    _lastProgressEmitValue.remove(key);
    _lastProgressEmitBytes.remove(key);

    if (snapshot != null) {
      try {
        final tempFile = await _tempFileForSnapshot(session, snapshot);

        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {
        // Se elimina del listado aunque el parcial ya no exista.
      }
    }

    _emitActiveTasks();
  }

  Future<OfflineDownloadEntry> downloadMovie(
    AuthSession session,
    Movie movie, {
    required String displayTitle,
    void Function(double progress)? onProgress,
  }) async {
    final key = 'movie:${movie.streamId}';

    if (_activeDownloads.containsKey(key)) {
      await _activeDownloads[key];
      final existing = await movieDownload(session, movie.streamId);

      if (existing != null) {
        return existing;
      }
    }

    final url = buildMovieUrl(session, movie);
    final extension = movie.safeExtension;
    final title = displayTitle.trim().isEmpty ? movie.name : displayTitle;
    final snapshot = OfflineDownloadTaskSnapshot(
      key: key,
      type: 'movie',
      id: movie.streamId,
      title: title,
      subtitle: 'Película',
      imageUrl: movie.posterUrl,
      sourceUrl: url,
      folder: 'movies',
      fileName: '${_sanitizeFileName(title)}_${movie.streamId}.$extension',
      extension: extension,
      progress: 0,
      receivedBytes: 0,
      totalBytes: 0,
      startedAt: DateTime.now().millisecondsSinceEpoch,
    );

    return _startDownload(
      session,
      snapshot,
      onProgress: onProgress,
    );
  }

  Future<OfflineDownloadEntry> downloadEpisode(
    AuthSession session, {
    required TvSeries series,
    required String seriesTitle,
    required String seasonName,
    required SeriesEpisode episode,
    void Function(double progress)? onProgress,
  }) async {
    final key = 'episode:${episode.episodeId}';

    if (_activeDownloads.containsKey(key)) {
      await _activeDownloads[key];
      final existing = await episodeDownload(session, episode.episodeId);

      if (existing != null) {
        return existing;
      }
    }

    final url = buildEpisodeUrl(session, episode);
    final extension = episode.safeExtension;
    final title = episode.displayTitle;
    final episodeLabel = episode.episodeNumber > 0
        ? 'E${episode.episodeNumber.toString().padLeft(2, '0')}'
        : 'Episodio';
    final poster = episode.imageUrl.isNotEmpty ? episode.imageUrl : series.coverUrl;
    final snapshot = OfflineDownloadTaskSnapshot(
      key: key,
      type: 'episode',
      id: episode.episodeId,
      title: title,
      subtitle: seriesTitle.trim().isEmpty
          ? '$seasonName • $episodeLabel'
          : '$seriesTitle • $seasonName • $episodeLabel',
      imageUrl: poster,
      sourceUrl: url,
      folder: 'series/${_sanitizeFileName(seriesTitle)}_${series.seriesId}',
      fileName:
          '${_sanitizeFileName(seasonName)}_${episodeLabel}_${episode.episodeId}.$extension',
      extension: extension,
      progress: 0,
      receivedBytes: 0,
      totalBytes: 0,
      startedAt: DateTime.now().millisecondsSinceEpoch,
      seriesId: series.seriesId,
      seriesTitle: seriesTitle,
      seasonName: seasonName,
      episodeNumber: episode.episodeNumber,
    );

    return _startDownload(
      session,
      snapshot,
      onProgress: onProgress,
    );
  }

  Future<void> deleteDownload(
    AuthSession session,
    OfflineDownloadEntry entry,
  ) async {
    try {
      final file = File(entry.localPath);

      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Se elimina el registro aunque el archivo ya no exista.
    }

    final downloads = await loadDownloads(session);
    final next = downloads.where((item) => item.key != entry.key).toList();
    await _saveDownloads(session, next);
  }

  Future<OfflineDownloadEntry> _startDownload(
    AuthSession session,
    OfflineDownloadTaskSnapshot snapshot, {
    void Function(double progress)? onProgress,
  }) async {
    final key = snapshot.key;
    final completer = Completer<void>();
    _activeDownloads[key] = completer.future;
    _registerActiveTask(snapshot);

    try {
      final entry = await _downloadFromSnapshot(
        session,
        snapshot,
        onProgress: onProgress,
      );
      await _upsertDownload(session, entry);
      completer.complete();
      return entry;
    } on DownloadPausedException {
      _markTaskPaused(key);
      completer.complete();
      rethrow;
    } catch (_) {
      _markTaskError(key, 'No se pudo descargar el contenido.');
      completer.complete();
      rethrow;
    } finally {
      _activeDownloads.remove(key);
      _downloadControls.remove(key);
    }
  }

  Future<OfflineDownloadEntry> _downloadFromSnapshot(
    AuthSession session,
    OfflineDownloadTaskSnapshot snapshot, {
    void Function(double progress)? onProgress,
  }) async {
    final file = await _downloadFile(
      session: session,
      snapshot: snapshot,
      onProgress: (progress, receivedBytes, totalBytes) {
        _updateActiveTask(
          snapshot.key,
          progress,
          receivedBytes: receivedBytes,
          totalBytes: totalBytes,
          forceEmit: progress >= 1,
        );
        onProgress?.call(progress);
      },
    );

    final entry = OfflineDownloadEntry(
      type: snapshot.type,
      id: snapshot.id,
      title: snapshot.title,
      imageUrl: snapshot.imageUrl,
      localPath: file.path,
      sourceUrl: snapshot.sourceUrl,
      extension: snapshot.extension,
      sizeBytes: await file.length(),
      downloadedAt: DateTime.now().millisecondsSinceEpoch,
      seriesId: snapshot.seriesId,
      seriesTitle: snapshot.seriesTitle,
      seasonName: snapshot.seasonName,
      episodeNumber: snapshot.episodeNumber,
    );

    _removeActiveTask(snapshot.key);
    return entry;
  }

  void _registerActiveTask(OfflineDownloadTaskSnapshot snapshot) {
    _activeTaskSnapshots[snapshot.key] = snapshot;
    _emitActiveTasks();
  }

  void _updateActiveTask(
    String key,
    double progress, {
    int? receivedBytes,
    int? totalBytes,
    bool forceEmit = false,
  }) {
    final current = _activeTaskSnapshots[key];

    if (current == null) {
      return;
    }

    final normalizedProgress = progress.clamp(0.0, 1.0).toDouble();
    _activeTaskSnapshots[key] = current.copyWith(
      progress: normalizedProgress,
      receivedBytes: receivedBytes,
      totalBytes: totalBytes,
      status: OfflineDownloadTaskStatus.downloading,
      errorMessage: '',
    );

    if (_shouldEmitProgress(
      key,
      normalizedProgress,
      receivedBytes ?? current.receivedBytes,
      forceEmit: forceEmit,
    )) {
      _emitActiveTasks();
    }
  }

  bool _shouldEmitProgress(
    String key,
    double progress,
    int receivedBytes, {
    bool forceEmit = false,
  }) {
    if (forceEmit || progress >= 1) {
      _storeEmitState(key, progress, receivedBytes);
      return true;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final lastAt = _lastProgressEmitAt[key] ?? 0;
    final lastProgress = _lastProgressEmitValue[key] ?? -1;
    final lastBytes = _lastProgressEmitBytes[key] ?? 0;
    final progressDelta = (progress - lastProgress).abs();
    final bytesDelta = (receivedBytes - lastBytes).abs();

    // Evita reconstruir toda la pantalla por cada paquete recibido.
    // Se actualiza fluido, pero no tan rápido que provoque parpadeo.
    if (lastAt == 0 ||
        now - lastAt >= 450 ||
        progressDelta >= 0.01 ||
        bytesDelta >= 1024 * 1024) {
      _storeEmitState(key, progress, receivedBytes);
      return true;
    }

    return false;
  }

  void _storeEmitState(String key, double progress, int receivedBytes) {
    _lastProgressEmitAt[key] = DateTime.now().millisecondsSinceEpoch;
    _lastProgressEmitValue[key] = progress;
    _lastProgressEmitBytes[key] = receivedBytes;
  }

  void _markTaskPaused(String key) {
    final current = _activeTaskSnapshots[key];

    if (current == null) {
      return;
    }

    _activeTaskSnapshots[key] = current.copyWith(
      status: OfflineDownloadTaskStatus.paused,
      errorMessage: '',
    );
    _emitActiveTasks();
  }

  void _markTaskError(String key, String message) {
    final current = _activeTaskSnapshots[key];

    if (current == null) {
      return;
    }

    _activeTaskSnapshots[key] = current.copyWith(
      status: OfflineDownloadTaskStatus.error,
      errorMessage: message,
    );
    _emitActiveTasks();
  }

  void _removeActiveTask(String key) {
    if (_activeTaskSnapshots.remove(key) != null) {
      _lastProgressEmitAt.remove(key);
      _lastProgressEmitValue.remove(key);
      _lastProgressEmitBytes.remove(key);
      _emitActiveTasks();
    }
  }

  void _emitActiveTasks() {
    final tasks = _activeTaskSnapshots.values.toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    activeTasks.value = List<OfflineDownloadTaskSnapshot>.unmodifiable(tasks);
    _syncForegroundService();
  }

  void _syncForegroundService() {
    final activeCount = _activeTaskSnapshots.values
        .where((task) => task.status == OfflineDownloadTaskStatus.downloading)
        .length;

    if (activeCount > 0) {
      unawaited(DownloadForegroundService.start(active: activeCount));
    } else {
      unawaited(DownloadForegroundService.stop());
    }
  }

  String buildMovieUrl(AuthSession session, Movie movie) {
    final directSource = movie.directSource.trim();

    if (directSource.startsWith('http://') ||
        directSource.startsWith('https://')) {
      return directSource;
    }

    final server = session.server.replaceFirst(RegExp(r'/+$'), '');
    final username = Uri.encodeComponent(session.username);
    final password = Uri.encodeComponent(session.password);

    return '$server/movie/$username/$password/'
        '${movie.streamId}.${movie.safeExtension}';
  }

  String buildEpisodeUrl(AuthSession session, SeriesEpisode episode) {
    final directSource = episode.directSource.trim();

    if (directSource.startsWith('http://') ||
        directSource.startsWith('https://')) {
      return directSource;
    }

    final server = session.server.replaceFirst(RegExp(r'/+$'), '');
    final username = Uri.encodeComponent(session.username);
    final password = Uri.encodeComponent(session.password);

    return '$server/series/$username/$password/'
        '${episode.episodeId}.${episode.safeExtension}';
  }

  Future<File> _downloadFile({
    required AuthSession session,
    required OfflineDownloadTaskSnapshot snapshot,
    void Function(double progress, int receivedBytes, int totalBytes)? onProgress,
  }) async {
    final baseDir = await _downloadsDirectory(session);
    final targetDir = Directory('${baseDir.path}/${snapshot.folder}');

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final file = File('${targetDir.path}/${snapshot.fileName}');
    final tempFile = File('${file.path}.part');
    final control = _DownloadControl();
    _downloadControls[snapshot.key] = control;

    var existingBytes = 0;

    if (await tempFile.exists()) {
      existingBytes = await tempFile.length();
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 20);
    control.client = client;

    try {
      final request = await client.getUrl(Uri.parse(snapshot.sourceUrl));
      request.followRedirects = true;
      request.headers.set(HttpHeaders.userAgentHeader, 'FdezPlay/1.0');

      if (existingBytes > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
      }

      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'No se pudo descargar el contenido. Código ${response.statusCode}.',
          uri: Uri.parse(snapshot.sourceUrl),
        );
      }

      final serverAcceptedResume = existingBytes > 0 &&
          response.statusCode == HttpStatus.partialContent;

      if (existingBytes > 0 && !serverAcceptedResume) {
        existingBytes = 0;
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }

      final totalBytes = response.contentLength > 0
          ? response.contentLength + existingBytes
          : snapshot.totalBytes;
      var receivedBytes = existingBytes;
      final sink = tempFile.openWrite(
        mode: existingBytes > 0 ? FileMode.append : FileMode.write,
      );

      try {
        onProgress?.call(
          totalBytes > 0 ? receivedBytes / totalBytes : snapshot.progress,
          receivedBytes,
          totalBytes,
        );

        await for (final chunk in response) {
          if (control.pauseRequested) {
            throw const DownloadPausedException();
          }

          receivedBytes += chunk.length;
          sink.add(chunk);

          if (totalBytes > 0) {
            onProgress?.call(
              (receivedBytes / totalBytes).clamp(0.0, 1.0),
              receivedBytes,
              totalBytes,
            );
          } else {
            onProgress?.call(snapshot.progress, receivedBytes, totalBytes);
          }
        }
      } finally {
        await sink.close();
      }

      if (await file.exists()) {
        await file.delete();
      }

      await tempFile.rename(file.path);
      onProgress?.call(1, await file.length(), await file.length());
      return file;
    } on DownloadPausedException {
      rethrow;
    } catch (_) {
      if (control.pauseRequested) {
        throw const DownloadPausedException();
      }

      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<File> _tempFileForSnapshot(
    AuthSession session,
    OfflineDownloadTaskSnapshot snapshot,
  ) async {
    final baseDir = await _downloadsDirectory(session);
    final targetDir = Directory('${baseDir.path}/${snapshot.folder}');
    final file = File('${targetDir.path}/${snapshot.fileName}');
    return File('${file.path}.part');
  }

  Future<Directory> _downloadsDirectory(AuthSession session) async {
    final documents = await getApplicationDocumentsDirectory();
    final identity = _sanitizeFileName(
      '${session.server}_${session.username}',
    );
    final directory = Directory(
      '${documents.path}/FdezPlayDownloads/$identity',
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  Future<void> _upsertDownload(
    AuthSession session,
    OfflineDownloadEntry entry,
  ) async {
    final downloads = await loadDownloads(session);
    final next = <OfflineDownloadEntry>[
      entry,
      for (final item in downloads)
        if (item.key != entry.key) item,
    ];

    await _saveDownloads(session, next);
  }

  Future<void> _saveDownloads(
    AuthSession session,
    List<OfflineDownloadEntry> downloads,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey(session),
      jsonEncode(downloads.map((item) => item.toJson()).toList()),
    );
  }

  String _storageKey(AuthSession session) {
    final identity = base64Url.encode(
      utf8.encode('${session.server}|${session.username}'),
    );

    return 'fdezplay.offline_downloads.$identity';
  }

  String _sanitizeFileName(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleaned.isEmpty) {
      return 'contenido';
    }

    return cleaned.length > 80 ? cleaned.substring(0, 80).trim() : cleaned;
  }
}

class _DownloadControl {
  bool pauseRequested = false;
  HttpClient? client;

  void pause() {
    pauseRequested = true;
    client?.close(force: true);
  }
}

String _text(Object? value) {
  return value?.toString().trim() ?? '';
}

int _toInt(Object? value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _sizeLabel(int bytes, {String fallback = '0 MB'}) {
  if (bytes <= 0) {
    return fallback;
  }

  final mb = bytes / (1024 * 1024);

  if (mb < 1024) {
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }

  final gb = mb / 1024;
  return '${gb.toStringAsFixed(gb >= 10 ? 1 : 2)} GB';
}
