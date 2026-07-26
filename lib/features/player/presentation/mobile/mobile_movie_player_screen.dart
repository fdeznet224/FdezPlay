import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

import '../../../auth/domain/auth_session.dart';
import '../../../cast/domain/cast_device.dart';
import '../../../cast/presentation/cast_device_sheet.dart';
import '../../../favorites/data/local_library_service.dart';
import '../../../movies/domain/movie.dart';
import '../../../settings/data/playback_preferences_service.dart';
import '../../../../shared/services/device_orientation_service.dart';
import '../../../../shared/services/playback_network_probe.dart';
import '../../../../shared/services/screen_awake_service.dart';
import '../../../../shared/services/picture_in_picture_service.dart';
import '../../../../shared/widgets/tv_focusable_surface.dart';

class MobileMoviePlayerScreen extends StatefulWidget {
  const MobileMoviePlayerScreen({
    required this.session,
    required this.movie,
    this.versions = const [],
    this.initialVersionIndex = 0,
    this.displayTitle,
    this.initialPosition = Duration.zero,
    this.localPath,
    this.enableTvRemoteNavigation = false,
    super.key,
  });

  final AuthSession session;
  final Movie movie;
  final List<Movie> versions;
  final int initialVersionIndex;
  final String? displayTitle;
  final Duration initialPosition;
  final String? localPath;
  final bool enableTvRemoteNavigation;

  @override
  State<MobileMoviePlayerScreen> createState() {
    return _MobileMoviePlayerScreenState();
  }
}

class _MobileMoviePlayerScreenState
    extends State<MobileMoviePlayerScreen>
    with WidgetsBindingObserver {
  final FocusNode _remotePlayerFocusNode = FocusNode(
    debugLabel: 'movie-player-root',
  );
  final FocusNode _backButtonFocusNode = FocusNode(
    debugLabel: 'movie-player-back',
  );
  final FocusNode _audioButtonFocusNode = FocusNode(
    debugLabel: 'movie-player-audio',
  );
  final FocusNode _subtitleButtonFocusNode = FocusNode(
    debugLabel: 'movie-player-subtitle',
  );
  final FocusNode _castButtonFocusNode = FocusNode(
    debugLabel: 'movie-player-cast',
  );
  final FocusNode _playPauseFocusNode = FocusNode(
    debugLabel: 'movie-player-play-pause',
  );
  final FocusNode _seekBarFocusNode = FocusNode(
    debugLabel: 'movie-player-seek-bar',
  );

  late VlcPlayerController _controller;

  final LocalLibraryService _libraryService =
      LocalLibraryService.instance;
  final PlaybackPreferencesService _preferencesService =
      PlaybackPreferencesService.instance;

  PlaybackPreferences _playbackPreferences =
      const PlaybackPreferences();
  bool _preferencesLoaded = false;
  bool _preferredTracksApplied = false;

  List<int> _networkCachingLevels = const [8000, 15000, 25000];
  int _networkCachingIndex = 0;
  int _controllerCachingMs = 8000;
  bool _stabilizingConnection = false;
  bool _warmingUpAfterRecovery = false;
  bool _warmupCheckInProgress = false;
  Duration _recoveryWarmupDuration = const Duration(seconds: 4);
  Duration _warmupLastPosition = Duration.zero;
  DateTime _warmupLastAdvanceAt = DateTime.now();
  DateTime? _warmupStableSince;
  DateTime? _warmupStartedAt;

  int get _networkCachingMs =>
      _networkCachingLevels[_networkCachingIndex];

  Timer? _controlsTimer;
  Timer? _sourceStartupTimer;
  Timer? _watchdogTimer;
  Timer? _networkRecoveryTimer;
  Timer? _recoveryWarmupTimer;
  DateTime? _lastProgressSave;
  bool _savingProgress = false;
  bool _resumeApplied = false;
  bool _resumeInProgress = false;
  late Duration _pendingResumePosition;

  bool _opening = true;
  bool _isClosing = false;
  bool _controlsVisible = true;
  bool _ended = false;
  bool _loadingTracks = false;
  bool _switchingSource = false;
  bool _handlingSourceFailure = false;
  bool _hasStartedCurrentSource = false;
  bool _isInBackground = false;
  bool _resumePlaybackOnForeground = false;
  bool _reconnecting = false;
  int _sameSourceRetryCount = 0;
  bool _waitingForNetwork = false;
  bool _networkCheckInProgress = false;
  bool _playbackExpected = true;
  bool _observedPlaybackAdvance = false;
  bool _controllerMounted = true;
  bool _resettingController = false;
  bool _seekInProgress = false;
  bool _remoteSeekInProgress = false;
  Timer? _remoteSeekHoldTimer;
  LogicalKeyboardKey? _remoteSeekHoldKey;
  int _remoteSeekHoldTicks = 0;
  Duration? _remoteSeekPreviewPosition;
  Timer? _remoteSeekPreviewClearTimer;
  DateTime? _ignoreInstabilityUntil;

  int _controllerGeneration = 0;
  Duration _lastObservedPosition = Duration.zero;
  DateTime _lastPlaybackAdvanceAt = DateTime.now();

  late final List<Movie> _sources;
  int _sourceIndex = 0;

  String? _errorMessage;

  Map<int, String> _audioTracks = const {};
  Map<int, String> _subtitleTracks = const {};

  int? _selectedAudioTrack;
  int? _selectedSubtitleTrack;

  bool get _isOfflinePlayback => widget.localPath?.trim().isNotEmpty == true;

  Movie get _activeMovie => _sources[_sourceIndex];

  String get _playerTitle {
    final title = widget.displayTitle?.trim() ?? '';
    return title.isEmpty ? widget.movie.name : title;
  }

  String get _movieUrl => _isOfflinePlayback
      ? widget.localPath!.trim()
      : _buildMovieUrl(_activeMovie);

  List<Movie> _buildSources() {
    if (_isOfflinePlayback) {
      return <Movie>[widget.movie];
    }

    final input = widget.versions.isEmpty
        ? <Movie>[widget.movie]
        : List<Movie>.from(widget.versions);
    final unique = <Movie>[];
    final seen = <int>{};

    for (final movie in input) {
      if (movie.streamId > 0 && seen.add(movie.streamId)) {
        unique.add(movie);
      }
    }

    if (unique.isEmpty) {
      unique.add(widget.movie);
    }

    final selected = widget.initialVersionIndex
        .clamp(0, unique.length - 1)
        .toInt();
    final ordered = <Movie>[unique[selected]];

    for (int index = 0; index < unique.length; index++) {
      if (index != selected) {
        ordered.add(unique[index]);
      }
    }

    return List<Movie>.unmodifiable(ordered);
  }

  String _buildMovieUrl(Movie movie) {
    final directSource = movie.directSource.trim();

    if (directSource.startsWith('http://') ||
        directSource.startsWith('https://')) {
      return directSource;
    }

    final server = widget.session.server.replaceFirst(RegExp(r'/+$'), '');
    final username = Uri.encodeComponent(widget.session.username);
    final password = Uri.encodeComponent(widget.session.password);

    return '$server/movie/$username/$password/'
        '${movie.streamId}.${movie.safeExtension}';
  }


  VlcPlayerController _buildController() {
    _controllerCachingMs = _networkCachingMs;

    if (_isOfflinePlayback) {
      return VlcPlayerController.file(
        File(_movieUrl),
        autoInitialize: false,
        autoPlay: false,
        allowBackgroundPlayback: false,
        hwAcc: HwAcc.auto,
        options: VlcPlayerOptions(
          advanced: VlcAdvancedOptions(
            [
              VlcAdvancedOptions.clockSynchronization(0),
              VlcAdvancedOptions.clockJitter(0),
            ],
          ),
          audio: VlcAudioOptions(
            [
              VlcAudioOptions.audioTimeStretch(false),
            ],
          ),
        ),
      );
    }

    return VlcPlayerController.network(
      _movieUrl,
      autoInitialize: false,
      autoPlay: false,
      allowBackgroundPlayback: false,
      hwAcc: HwAcc.auto,
      options: VlcPlayerOptions(
        advanced: VlcAdvancedOptions(
          [
            VlcAdvancedOptions.networkCaching(_controllerCachingMs),
            VlcAdvancedOptions.clockSynchronization(0),
            VlcAdvancedOptions.clockJitter(0),
          ],
        ),
        audio: VlcAudioOptions(
          [
            VlcAudioOptions.audioTimeStretch(false),
          ],
        ),
        http: VlcHttpOptions(
          [
            VlcHttpOptions.httpReconnect(true),
            VlcHttpOptions.httpUserAgent('FdezPlay/1.0'),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    unawaited(ScreenAwakeService.enable());
    unawaited(PictureInPictureService.setActive(true));

    _sources = _buildSources();
    _pendingResumePosition = widget.initialPosition;

    _controller = _buildController();

    _controller.addListener(_onPlayerChanged);

    unawaited(_enterFullscreen());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapPlayer());
    });

    _scheduleControlsHide();
    _startPlaybackWatchdog();
  }

  Future<void> _bootstrapPlayer() async {
    await _loadPlaybackPreferences();

    if (_isClosing || !mounted) {
      return;
    }

    if (_controllerCachingMs != _networkCachingMs) {
      final replaced = await _replaceControllerBeforeInitialization();

      if (!replaced) {
        return;
      }
    }

    await _initializePlayer();
  }

  Future<bool> _replaceControllerBeforeInitialization() async {
    final previousController = _controller;

    if (mounted) {
      setState(() {
        _controllerMounted = false;
      });
      await WidgetsBinding.instance.endOfFrame;
    }

    previousController.removeListener(_onPlayerChanged);

    try {
      await previousController.dispose();
    } catch (_) {
      // Todavía no estaba inicializado o ya había sido liberado.
    }

    if (_isClosing || !mounted) {
      return false;
    }

    _controller = _buildController();
    _controller.addListener(_onPlayerChanged);

    setState(() {
      _controllerGeneration++;
      _controllerMounted = true;
    });

    await WidgetsBinding.instance.endOfFrame;
    return true;
  }

  Future<void> _enterFullscreen() async {
    await SystemChrome.setPreferredOrientations(
      const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    );

    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );
  }

  Future<void> _initializePlayer() async {
    if (_isClosing) {
      return;
    }

    setState(() {
      _opening = true;
      _errorMessage = null;
      _ended = false;
    });

    try {
      bool platformReady = false;

      for (int attempt = 0;
          attempt < 60;
          attempt++) {
        if (!mounted || _isClosing) {
          return;
        }

        if (_controller.isReadyToInitialize ==
            true) {
          platformReady = true;
          break;
        }

        await Future<void>.delayed(
          const Duration(milliseconds: 100),
        );
      }

      if (!platformReady) {
        throw TimeoutException(
          'VLC no pudo preparar la superficie.',
        );
      }

      await _controller.initialize().timeout(
            const Duration(seconds: 30),
          );

      if (!mounted || _isClosing) {
        return;
      }

      _playbackExpected = true;
      await _controller.play();
      _resetPlaybackWatchdog();
      _scheduleSourceStartupGuard();

      unawaited(_resumeFromSavedPosition());
      unawaited(_loadMediaTracks());
    } on TimeoutException catch (error) {
      await _handleSourceFailure(
        'VLC tardó demasiado en abrir la película.',
        error: error,
      );
    } catch (error) {
      await _handleSourceFailure(
        'No fue posible iniciar la película.',
        error: error,
      );
    }
  }

  void _resetPlaybackWatchdog() {
    _lastObservedPosition = _controller.value.position;
    _lastPlaybackAdvanceAt = DateTime.now();
    _observedPlaybackAdvance = _lastObservedPosition > Duration.zero;
  }

  void _startPlaybackWatchdog() {
    _watchdogTimer?.cancel();
    _resetPlaybackWatchdog();

    _watchdogTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        if (_isClosing ||
            _isInBackground ||
            !_playbackExpected ||
            _waitingForNetwork ||
            _reconnecting ||
            _stabilizingConnection ||
            _seekInProgress ||
            _switchingSource ||
            _errorMessage != null ||
            _ended) {
          return;
        }

        final value = _controller.value;
        final position = value.position;
        final now = DateTime.now();
        final ignoreUntil = _ignoreInstabilityUntil;

        if (ignoreUntil != null && now.isBefore(ignoreUntil)) {
          return;
        }

        if (position >
            _lastObservedPosition + const Duration(milliseconds: 300)) {
          _lastObservedPosition = position;
          _lastPlaybackAdvanceAt = now;
          _observedPlaybackAdvance = true;
          return;
        }

        final stallThresholdMs = _networkCachingMs + 3000 > 10000
            ? _networkCachingMs + 3000
            : 10000;
        final bufferThresholdMs = _networkCachingMs > 8000
            ? _networkCachingMs
            : 8000;
        final stalled = _observedPlaybackAdvance &&
            now.difference(_lastPlaybackAdvanceAt) >=
                Duration(milliseconds: stallThresholdMs);
        final stuckBuffer = value.isBuffering &&
            !value.isPlaying &&
            now.difference(_lastPlaybackAdvanceAt) >=
                Duration(milliseconds: bufferThresholdMs);

        if (stalled || stuckBuffer) {
          unawaited(_handlePlaybackInstability());
        }
      },
    );
  }

  Future<void> _handlePlaybackInstability() async {
    if (_isClosing ||
        _isInBackground ||
        _stabilizingConnection ||
        _seekInProgress ||
        _waitingForNetwork ||
        _switchingSource) {
      return;
    }

    final online = await PlaybackNetworkProbe.canReach(widget.session);

    if (_isClosing ||
        _isInBackground ||
        _seekInProgress ||
        _waitingForNetwork ||
        _switchingSource) {
      return;
    }

    if (!online) {
      _waitForNetwork();
      return;
    }

    if (_networkCachingIndex + 1 < _networkCachingLevels.length) {
      _networkCachingIndex++;
      _stabilizingConnection = true;

      if (mounted) {
        setState(() {
          _opening = true;
          _errorMessage = null;
        });
      }

      final recovered = await _reconnectCurrentSource(hardReset: true);
      _stabilizingConnection = false;

      if (recovered) {
        _resetPlaybackWatchdog();
        return;
      }
    }

    await _handleSourceFailure(
      'La conexión de la película se interrumpió.',
    );
  }

  void _waitForNetwork() {
    if (_isClosing || _waitingForNetwork) {
      return;
    }

    _cancelRecoveryWarmup();
    _waitingForNetwork = true;
    _reconnecting = false;
    _sourceStartupTimer?.cancel();
    _networkRecoveryTimer?.cancel();

    if (mounted) {
      setState(() {
        _opening = true;
        _errorMessage = null;
        _ended = false;
      });
    }

    _networkRecoveryTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_checkNetworkRecovery()),
    );
    unawaited(_checkNetworkRecovery());
  }

  Future<void> _checkNetworkRecovery() async {
    if (_isClosing ||
        _isInBackground ||
        !_waitingForNetwork ||
        _networkCheckInProgress) {
      return;
    }

    _networkCheckInProgress = true;
    final online = await PlaybackNetworkProbe.canReach(widget.session);
    _networkCheckInProgress = false;

    if (!online || _isClosing || _isInBackground) {
      return;
    }

    _networkRecoveryTimer?.cancel();
    _waitingForNetwork = false;
    _sameSourceRetryCount = 0;

    final recovered = await _reconnectCurrentSource(hardReset: true);

    if (!recovered) {
      await _handleSourceFailure(
        'La conexión volvió, pero la película no respondió.',
      );
    }
  }

  void _scheduleSourceStartupGuard() {
    _sourceStartupTimer?.cancel();
    _hasStartedCurrentSource = false;

    final guardSeconds = ((_networkCachingMs + 8000) ~/ 1000)
        .clamp(18, 40)
        .toInt();

    _sourceStartupTimer = Timer(
      Duration(seconds: guardSeconds),
      () {
        if (!mounted ||
            _isClosing ||
            _isInBackground ||
            _hasStartedCurrentSource ||
            _switchingSource) {
          return;
        }

        unawaited(
          _handleSourceFailure(
            'La versión seleccionada no respondió.',
          ),
        );
      },
    );
  }

  Future<void> _handleSourceFailure(
    String finalMessage, {
    Object? error,
  }) async {
    if (_isOfflinePlayback) {
      if (mounted && !_isClosing) {
        setState(() {
          _opening = false;
          _errorMessage = finalMessage;
        });
      }
      return;
    }

    if (_isClosing ||
        _handlingSourceFailure ||
        _isInBackground ||
        _waitingForNetwork) {
      return;
    }

    _handlingSourceFailure = true;

    try {
      final online = await PlaybackNetworkProbe.canReach(widget.session);

      if (!online) {
        _waitForNetwork();
        return;
      }

      if (_hasStartedCurrentSource && _sameSourceRetryCount < 1) {
        _sameSourceRetryCount++;

        final reconnected = await _reconnectCurrentSource(hardReset: true);

        if (reconnected) {
          return;
        }
      }

      final switched = await _switchToNextSource();

      if (switched) {
        return;
      }

      if (!mounted || _isClosing) {
        return;
      }

      setState(() {
        _opening = false;
        _ended = false;
        _errorMessage =
            'No fue posible reproducir ninguna versión disponible.';
      });

      if (error != null) {
        debugPrint('$finalMessage Error: $error');
      }
    } finally {
      _handlingSourceFailure = false;
    }
  }


  Future<bool> _recreateControllerForCurrentSource({
    bool stabilize = false,
  }) async {
    if (_isClosing || _isInBackground || _resettingController) {
      return false;
    }

    _resettingController = true;
    _cancelRecoveryWarmup();
    final previousController = _controller;

    if (mounted) {
      setState(() {
        _controllerMounted = false;
        _opening = true;
        _errorMessage = null;
      });
      await WidgetsBinding.instance.endOfFrame;
    }

    previousController.removeListener(_onPlayerChanged);

    try {
      await previousController.stop();
    } catch (_) {
      // El controlador anterior puede haber perdido la señal.
    }

    try {
      await previousController.dispose();
    } catch (_) {
      // El controlador anterior puede estar parcialmente liberado.
    }

    if (_isClosing || !mounted) {
      _resettingController = false;
      return false;
    }

    _controller = _buildController();
    _controller.addListener(_onPlayerChanged);

    setState(() {
      _controllerGeneration++;
      _controllerMounted = true;
    });

    await WidgetsBinding.instance.endOfFrame;

    try {
      bool platformReady = false;

      for (int attempt = 0; attempt < 60; attempt++) {
        if (!mounted || _isClosing) {
          return false;
        }

        if (_controller.isReadyToInitialize == true) {
          platformReady = true;
          break;
        }

        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      if (!platformReady) {
        throw TimeoutException('VLC no pudo preparar la superficie.');
      }

      await _controller.initialize().timeout(const Duration(seconds: 30));

      if (!mounted || _isClosing) {
        return false;
      }

      _playbackExpected = true;

      if (stabilize) {
        _warmingUpAfterRecovery = true;
        _stabilizingConnection = true;

        try {
          await _controller.setVolume(0);
        } catch (error) {
          debugPrint(
            'No fue posible silenciar la película durante la estabilización: $error',
          );
        }
      }

      await _controller.play();

      if (stabilize) {
        unawaited(_startRecoveryWarmup());
      }

      return true;
    } catch (error) {
      debugPrint('No fue posible recrear VLC para la película: $error');
      return false;
    } finally {
      _resettingController = false;
    }
  }

  Future<void> _startRecoveryWarmup() async {
    if (_isClosing || _isInBackground || !mounted) {
      return;
    }

    _recoveryWarmupTimer?.cancel();
    _remoteSeekHoldTimer?.cancel();
    _remoteSeekPreviewClearTimer?.cancel();
    _warmupLastPosition = _controller.value.position;
    _warmupLastAdvanceAt = DateTime.now();
    _warmupStableSince = null;
    _warmupStartedAt = DateTime.now();
    _warmupCheckInProgress = false;

    setState(() {
      _warmingUpAfterRecovery = true;
      _stabilizingConnection = true;
      _opening = true;
      _errorMessage = null;
      _controlsVisible = false;
    });

    _recoveryWarmupTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => unawaited(_checkRecoveryWarmup()),
    );
  }

  Future<void> _checkRecoveryWarmup() async {
    if (_warmupCheckInProgress ||
        !_warmingUpAfterRecovery ||
        _isClosing ||
        _isInBackground ||
        !mounted) {
      return;
    }

    _warmupCheckInProgress = true;

    try {
      final value = _controller.value;
      final position = value.position;
      final now = DateTime.now();
      final resumeReady = _pendingResumePosition <= const Duration(seconds: 5) ||
          _resumeApplied;
      final advanced =
          position > _warmupLastPosition + const Duration(milliseconds: 100);

      if (advanced) {
        _warmupLastPosition = position;
        _warmupLastAdvanceAt = now;
      }

      final playbackMoving =
          now.difference(_warmupLastAdvanceAt) <=
              const Duration(milliseconds: 1500);
      final stable = value.isPlaying &&
          !value.isBuffering &&
          !value.hasError &&
          resumeReady &&
          playbackMoving;

      if (stable) {
        _warmupStableSince ??= now;
      } else {
        _warmupStableSince = null;
      }

      final stableSince = _warmupStableSince;

      if (stableSince != null &&
          now.difference(stableSince) >= _recoveryWarmupDuration) {
        await _finishRecoveryWarmup();
        return;
      }

      final startedAt = _warmupStartedAt;
      final timedOut = startedAt != null &&
          now.difference(startedAt) >=
              _recoveryWarmupDuration + const Duration(seconds: 15);

      if (timedOut) {
        if (value.isPlaying && resumeReady) {
          await _finishRecoveryWarmup();
        } else {
          _cancelRecoveryWarmup();
          await _handleSourceFailure(
            'La película no logró estabilizarse.',
          );
        }
      }
    } finally {
      _warmupCheckInProgress = false;
    }
  }

  Future<void> _finishRecoveryWarmup() async {
    _recoveryWarmupTimer?.cancel();
    _remoteSeekHoldTimer?.cancel();
    _remoteSeekPreviewClearTimer?.cancel();

    try {
      await _controller.setVolume(100);
    } catch (error) {
      debugPrint('No fue posible restaurar el audio de la película: $error');
    }

    if (!mounted || _isClosing) {
      return;
    }

    setState(() {
      _warmingUpAfterRecovery = false;
      _stabilizingConnection = false;
      _opening = false;
      _errorMessage = null;
    });

    _resetPlaybackWatchdog();
    _scheduleControlsHide();
  }

  void _cancelRecoveryWarmup() {
    _recoveryWarmupTimer?.cancel();
    _remoteSeekHoldTimer?.cancel();
    _remoteSeekPreviewClearTimer?.cancel();
    _warmingUpAfterRecovery = false;
    _warmupCheckInProgress = false;
    _warmupStableSince = null;
    _warmupStartedAt = null;
  }

  Future<bool> _reconnectCurrentSource({bool hardReset = false}) async {
    if (_isClosing || _reconnecting || _isInBackground) {
      return false;
    }

    _reconnecting = true;
    _sourceStartupTimer?.cancel();

    final currentPosition = _controller.value.position;

    if (currentPosition > const Duration(seconds: 5)) {
      _pendingResumePosition = currentPosition;
      await _saveProgressNow();
    }

    if (mounted && !_isClosing) {
      setState(() {
        _opening = true;
        _errorMessage = null;
        _ended = false;
        _resumeApplied = false;
        _resumeInProgress = false;
      });
    }

    try {
      if (hardReset) {
        final recreated = await _recreateControllerForCurrentSource(
          stabilize: true,
        );

        if (!recreated) {
          return false;
        }
      } else {
        if (!_controller.value.isInitialized) {
          return false;
        }

        await _controller.setMediaFromNetwork(
          _movieUrl,
          autoPlay: true,
          hwAcc: HwAcc.auto,
        );
      }

      _playbackExpected = true;
      _resetPlaybackWatchdog();
      _scheduleSourceStartupGuard();
      unawaited(_resumeFromSavedPosition());
      unawaited(_loadMediaTracks());
      return true;
    } catch (error) {
      debugPrint('No fue posible reconectar la película: $error');
      return false;
    } finally {
      _reconnecting = false;
    }
  }

  Future<bool> _switchToNextSource() async {
    if (_isOfflinePlayback || _isClosing || _switchingSource) {
      return false;
    }

    _switchingSource = true;
    _sourceStartupTimer?.cancel();

    final currentPosition = _controller.value.position;

    if (currentPosition > const Duration(seconds: 5)) {
      _pendingResumePosition = currentPosition;
      await _saveProgressNow();
    }

    try {
      while (_sourceIndex + 1 < _sources.length) {
        _sourceIndex++;
        _sameSourceRetryCount = 0;

        if (mounted && !_isClosing) {
          setState(() {
            _opening = true;
            _errorMessage = null;
            _ended = false;
            _audioTracks = const {};
            _subtitleTracks = const {};
            _selectedAudioTrack = null;
            _selectedSubtitleTrack = null;
            _preferredTracksApplied = false;
            _resumeApplied = false;
            _resumeInProgress = false;
          });
        }

        try {
          final recreated =
              await _recreateControllerForCurrentSource();

          if (!recreated) {
            continue;
          }

          _scheduleSourceStartupGuard();
          unawaited(_resumeFromSavedPosition());
          unawaited(_loadMediaTracks());
          return true;
        } catch (error) {
          debugPrint(
            'Versión ${_activeMovie.streamId} no disponible: $error',
          );
        }
      }

      return false;
    } finally {
      _switchingSource = false;
    }
  }

  Future<void> _resumeFromSavedPosition() async {
    if (_resumeApplied ||
        _resumeInProgress ||
        _isClosing) {
      return;
    }

    final target = _pendingResumePosition;

    if (target < const Duration(seconds: 15)) {
      _resumeApplied = true;
      _pendingResumePosition = Duration.zero;
      return;
    }

    _resumeInProgress = true;

    try {
      for (int attempt = 0; attempt < 48; attempt++) {
        if (!mounted ||
            _isClosing ||
            _seekInProgress ||
            _resumeApplied) {
          return;
        }

        final value = _controller.value;
        final duration = value.duration;
        final seekable = await _controller.isSeekable();

        final durationReady = duration > Duration.zero;
        final targetIsValid = durationReady &&
            target < duration - const Duration(seconds: 2);

        if (value.isInitialized &&
            value.isPlaying &&
            seekable == true &&
            targetIsValid) {
          await _controller.setTime(
            target.inMilliseconds,
          );

          await Future<void>.delayed(
            const Duration(milliseconds: 350),
          );

          if (!mounted || _isClosing) {
            return;
          }

          final currentTime = await _controller.getTime();
          final minimumAccepted =
              target.inMilliseconds - 5000;

          int confirmedTime = currentTime;

          if (confirmedTime < minimumAccepted) {
            await _controller.seekTo(target);
            await Future<void>.delayed(
              const Duration(milliseconds: 350),
            );
            confirmedTime = await _controller.getTime();
          }

          if (confirmedTime >= minimumAccepted) {
            _resumeApplied = true;
            _pendingResumePosition = Duration.zero;
            return;
          }
        }

        await Future<void>.delayed(
          const Duration(milliseconds: 250),
        );
      }

      debugPrint(
        'VLC no confirmó la posición guardada de la película.',
      );
    } catch (error) {
      debugPrint(
        'Error reanudando la película: $error',
      );
    } finally {
      _resumeInProgress = false;
    }
  }

  void _onPlayerChanged() {
    if (!mounted || _isClosing) {
      return;
    }

    final value = _controller.value;

    if (_seekInProgress) {
      return;
    }

    if (value.hasError) {
      _cancelRecoveryWarmup();

      if (_reconnecting || _waitingForNetwork || _switchingSource) {
        return;
      }

      unawaited(
        _handleSourceFailure(
          value.errorDescription.trim().isEmpty
              ? 'No fue posible reproducir la película.'
              : value.errorDescription.trim(),
        ),
      );
      return;
    }

    if (value.isPlaying) {
      _hasStartedCurrentSource = true;
      _playbackExpected = true;
      _waitingForNetwork = false;
      _networkRecoveryTimer?.cancel();

      if (value.position > _lastObservedPosition) {
        _lastObservedPosition = value.position;
        _lastPlaybackAdvanceAt = DateTime.now();
        _observedPlaybackAdvance = true;
      }
      _sourceStartupTimer?.cancel();

      if (!_resumeApplied) {
        unawaited(_resumeFromSavedPosition());
      } else {
        unawaited(_saveProgressIfNeeded(value));
      }

      if (!_warmingUpAfterRecovery &&
          (_opening ||
              _errorMessage != null ||
              _ended)) {
        setState(() {
          _opening = false;
          _errorMessage = null;
          _ended = false;
        });
      }

      return;
    }

    if (_reconnecting || _waitingForNetwork || _switchingSource) {
      return;
    }

    if (value.isEnded && !_ended) {
      unawaited(
        _libraryService.removeMovieProgress(
          widget.session,
          widget.movie.streamId,
        ),
      );

      setState(() {
        _opening = false;
        _ended = true;
        _controlsVisible = true;
      });
    }
  }

  Future<void> _retry() async {
    if (_isClosing) {
      return;
    }

    _sourceStartupTimer?.cancel();
    _networkRecoveryTimer?.cancel();
    _waitingForNetwork = false;
    _sourceIndex = 0;
    _sameSourceRetryCount = 0;
    _resumeApplied = false;
    _resumeInProgress = false;

    setState(() {
      _opening = true;
      _errorMessage = null;
      _ended = false;
      _audioTracks = const {};
      _subtitleTracks = const {};
      _selectedAudioTrack = null;
      _selectedSubtitleTrack = null;
      _preferredTracksApplied = false;
    });

    try {
      final recreated = await _recreateControllerForCurrentSource();

      if (!recreated) {
        throw StateError('No se pudo recrear VLC.');
      }

      _playbackExpected = true;
      _resetPlaybackWatchdog();
      _scheduleSourceStartupGuard();
      unawaited(_resumeFromSavedPosition());
      unawaited(_loadMediaTracks());
    } catch (error) {
      await _handleSourceFailure(
        'No fue posible volver a abrir la película.',
        error: error,
      );
    }
  }

  Future<void> _loadMediaTracks() async {
    if (_isClosing || _loadingTracks) {
      return;
    }

    _loadingTracks = true;

    try {
      Map<int, String> audioTracks = const {};
      Map<int, String> subtitleTracks = const {};
      int? selectedAudioTrack;
      int? selectedSubtitleTrack;

      for (int attempt = 0; attempt < 8; attempt++) {
        if (_isClosing) {
          return;
        }

        try {
          audioTracks = await _controller.getAudioTracks();
          subtitleTracks = await _controller.getSpuTracks();
          selectedAudioTrack = await _controller.getAudioTrack();
          selectedSubtitleTrack = await _controller.getSpuTrack();
        } catch (_) {
          // Algunas películas tardan en publicar sus pistas.
        }

        if (audioTracks.isNotEmpty || subtitleTracks.isNotEmpty) {
          break;
        }

        await Future<void>.delayed(
          const Duration(milliseconds: 500),
        );
      }

      if (!mounted || _isClosing) {
        return;
      }

      final cleanedAudioTracks = <int, String>{};

      for (final entry in audioTracks.entries) {
        if (entry.key < 0) {
          continue;
        }

        cleanedAudioTracks[entry.key] = _trackName(
          entry.value,
          fallback: 'Pista de audio ${cleanedAudioTracks.length + 1}',
        );
      }

      final cleanedSubtitleTracks = <int, String>{
        -1: 'Desactivados',
      };

      for (final entry in subtitleTracks.entries) {
        if (entry.key < 0) {
          continue;
        }

        cleanedSubtitleTracks[entry.key] = _trackName(
          entry.value,
          fallback: 'Subtítulo ${cleanedSubtitleTracks.length}',
        );
      }

      setState(() {
        _audioTracks = cleanedAudioTracks;
        _subtitleTracks = cleanedSubtitleTracks;
        _selectedAudioTrack = selectedAudioTrack;
        _selectedSubtitleTrack = selectedSubtitleTrack ?? -1;
      });

      await _applyPreferredTracks();
    } catch (error) {
      debugPrint('Error cargando pistas VLC: $error');
    } finally {
      _loadingTracks = false;
    }
  }

  Future<void> _loadPlaybackPreferences() async {
    try {
      final preferences = await _preferencesService.load(
        widget.session,
      );

      if (!mounted || _isClosing) {
        return;
      }

      _playbackPreferences = preferences;
      _networkCachingLevels =
          preferences.stabilityMode.vodCachingLevels;
      _networkCachingIndex = 0;
      _recoveryWarmupDuration =
          preferences.stabilityMode.vodRecoveryWarmup;
      _preferencesLoaded = true;

      await _applyPreferredTracks();
    } catch (error) {
      debugPrint(
        'Error cargando preferencias de reproducción: $error',
      );
    }
  }

  Future<void> _applyPreferredTracks() async {
    if (!_preferencesLoaded ||
        _preferredTracksApplied ||
        _isClosing ||
        (_audioTracks.isEmpty && _subtitleTracks.isEmpty)) {
      return;
    }

    _preferredTracksApplied = true;

    int? selectedAudio = _selectedAudioTrack;
    int? selectedSubtitle = _selectedSubtitleTrack ?? -1;

    try {
      final preferredAudio = _findPreferredTrack(
        _audioTracks,
        _playbackPreferences.audioLanguage,
      );

      if (preferredAudio != null) {
        await _controller.setAudioTrack(preferredAudio);
        selectedAudio = preferredAudio;
      }

      if (!_playbackPreferences.subtitlesEnabled) {
        await _controller.setSpuTrack(-1);
        selectedSubtitle = -1;
        unawaited(_keepSubtitlesDisabled());
      } else {
        final preferredSubtitle = _findPreferredTrack(
              _subtitleTracks,
              _playbackPreferences.audioLanguage,
            ) ??
            _firstEnabledTrack(_subtitleTracks);

        if (preferredSubtitle != null && preferredSubtitle >= 0) {
          await _controller.setSpuTrack(preferredSubtitle);
          selectedSubtitle = preferredSubtitle;
        }
      }

      if (mounted && !_isClosing) {
        setState(() {
          _selectedAudioTrack = selectedAudio;
          _selectedSubtitleTrack = selectedSubtitle;
        });
      }
    } catch (error) {
      debugPrint(
        'Error aplicando preferencias de pistas: $error',
      );
    }
  }

  Future<void> _keepSubtitlesDisabled() async {
    // Algunos archivos activan una pista de subtítulos unos segundos
    // después de iniciar VLC. Se fuerza nuevamente la opción de
    // "sin subtítulos" para que Ajustes se respete de forma real.
    const retries = <Duration>[
      Duration(milliseconds: 350),
      Duration(milliseconds: 1200),
      Duration(milliseconds: 2600),
    ];

    for (final delay in retries) {
      await Future<void>.delayed(delay);

      if (_isClosing ||
          _playbackPreferences.subtitlesEnabled) {
        return;
      }

      try {
        await _controller.setSpuTrack(-1);
      } catch (_) {
        // VLC puede no tener lista de subtítulos lista todavía.
      }
    }

    if (mounted && !_isClosing) {
      setState(() {
        _selectedSubtitleTrack = -1;
      });
    }
  }

  int? _findPreferredTrack(
    Map<int, String> tracks,
    PreferredAudioLanguage language,
  ) {
    if (language == PreferredAudioLanguage.automatic) {
      return null;
    }

    final aliases = language == PreferredAudioLanguage.spanish
        ? const <String>[
            'spanish',
            'espanol',
            'castellano',
            'latino',
            'spa',
          ]
        : const <String>[
            'english',
            'ingles',
            'eng',
          ];

    for (final entry in tracks.entries) {
      if (entry.key < 0) {
        continue;
      }

      final label = _normalizeTrackLabel(entry.value);

      if (aliases.any(label.contains)) {
        return entry.key;
      }
    }

    return null;
  }

  int? _firstEnabledTrack(Map<int, String> tracks) {
    for (final track in tracks.keys) {
      if (track >= 0) {
        return track;
      }
    }

    return null;
  }

  String _normalizeTrackLabel(String value) {
    return value
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');
  }

  Future<void> _showAudioTracks() async {
    _showControls();

    await _loadMediaTracks();

    if (!mounted || _isClosing) {
      return;
    }

    if (_audioTracks.isEmpty) {
      _showMessage(
        'Esta película no informa pistas de audio adicionales.',
      );
      return;
    }

    final selectedTrack = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return _TrackSelectorSheet(
          icon: Icons.audiotrack_rounded,
          title: 'Pistas de audio',
          tracks: _audioTracks,
          selectedTrack: _selectedAudioTrack,
        );
      },
    );

    if (selectedTrack == null || !mounted || _isClosing) {
      return;
    }

    try {
      await _controller.setAudioTrack(selectedTrack);

      if (mounted) {
        setState(() {
          _selectedAudioTrack = selectedTrack;
        });
      }
    } catch (error) {
      debugPrint('Error cambiando pista de audio: $error');
      _showMessage('No fue posible cambiar la pista de audio.');
    }
  }

  Future<void> _showSubtitleTracks() async {
    _showControls();

    await _loadMediaTracks();

    if (!mounted || _isClosing) {
      return;
    }

    final availableSubtitles = _subtitleTracks.entries
        .where((entry) => entry.key >= 0)
        .toList();

    if (availableSubtitles.isEmpty) {
      _showMessage(
        'Esta película no contiene subtítulos integrados.',
      );
      return;
    }

    final selectedTrack = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return _TrackSelectorSheet(
          icon: Icons.subtitles_rounded,
          title: 'Subtítulos',
          tracks: _subtitleTracks,
          selectedTrack: _selectedSubtitleTrack ?? -1,
        );
      },
    );

    if (selectedTrack == null || !mounted || _isClosing) {
      return;
    }

    try {
      await _controller.setSpuTrack(selectedTrack);

      if (mounted) {
        setState(() {
          _selectedSubtitleTrack = selectedTrack;
        });
      }
    } catch (error) {
      debugPrint('Error cambiando subtítulo: $error');
      _showMessage('No fue posible cambiar el subtítulo.');
    }
  }

  Future<void> _showCastDevices() async {
    _showControls();

    if (_isOfflinePlayback) {
      _showMessage(
        'Las descargas offline todavía no se pueden transmitir por DLNA. Usa la reproducción online para enviarla a una Smart TV.',
      );
      return;
    }

    final media = FdezCastMedia(
      title: _playerTitle,
      url: _movieUrl,
      mimeType: fdezCastMimeTypeFromUrl(_movieUrl),
      startPosition: _controller.value.position,
    );

    final sent = await showFdezCastDeviceSheet(
      context,
      media: media,
    );

    if (!mounted || _isClosing) {
      return;
    }

    if (sent) {
      try {
        await _controller.pause();
      } catch (_) {
        // El controlador puede estar cambiando de estado.
      }

      _showMessage('Enviado a la Smart TV. La reproducción local quedó pausada.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _trackName(
    String rawName, {
    required String fallback,
  }) {
    final value = rawName.trim();

    if (value.isEmpty || value.toLowerCase() == 'track') {
      return fallback;
    }

    return value;
  }

  String get _selectedAudioLabel {
    final selected = _selectedAudioTrack;

    if (selected == null) {
      return 'Audio';
    }

    return _audioTracks[selected] ?? 'Audio';
  }

  String get _selectedSubtitleLabel {
    final selected = _selectedSubtitleTrack ?? -1;

    if (selected < 0) {
      return 'Subtítulos';
    }

    return _subtitleTracks[selected] ?? 'Subtítulos';
  }

  Future<void> _togglePlayback() async {
    _showControls();

    if (_ended ||
        _controller.value.isEnded) {
      _playbackExpected = true;
      _resetPlaybackWatchdog();
      await _controller.seekTo(Duration.zero);
      await _controller.play();

      if (mounted) {
        setState(() {
          _ended = false;
        });
      }

      return;
    }

    if (_controller.value.isPlaying) {
      _playbackExpected = false;
      await _controller.pause();
    } else {
      _playbackExpected = true;
      _resetPlaybackWatchdog();
      await _controller.play();
    }
  }

  Future<void> _seekTo(Duration requestedPosition) async {
    _showControls();

    if (_seekInProgress ||
        _isClosing ||
        _resettingController ||
        _reconnecting ||
        _switchingSource ||
        _waitingForNetwork ||
        _warmingUpAfterRecovery) {
      return;
    }

    final value = _controller.value;
    final duration = value.duration;

    if (!value.isInitialized || duration <= Duration.zero) {
      _showMessage('La película todavía no está lista para adelantar.');
      return;
    }

    final maximumTargetMs = duration.inMilliseconds > 2000
        ? duration.inMilliseconds - 2000
        : duration.inMilliseconds;
    final targetMs = requestedPosition.inMilliseconds
        .clamp(0, maximumTargetMs)
        .toInt();
    final shouldResume = value.isPlaying || _playbackExpected;

    _seekInProgress = true;
    _ignoreInstabilityUntil = DateTime.now().add(
      Duration(milliseconds: _networkCachingMs + 5000),
    );
    _resumeApplied = true;
    _resumeInProgress = false;
    _pendingResumePosition = Duration.zero;
    _sourceStartupTimer?.cancel();

    if (mounted) {
      setState(() {});
    }

    try {
      final seekable = await _controller.isSeekable();

      if (seekable != true) {
        _showMessage('Esta película no permite adelantar desde el servidor.');
        return;
      }

      _playbackExpected = false;

      if (shouldResume) {
        await _controller.pause();
      }

      await _controller.setTime(targetMs);
      await Future<void>.delayed(const Duration(milliseconds: 500));

      int confirmedTime = await _controller.getTime();

      if ((confirmedTime - targetMs).abs() > 15000) {
        await _controller.seekTo(
          Duration(milliseconds: targetMs),
        );
        await Future<void>.delayed(
          const Duration(milliseconds: 700),
        );
        confirmedTime = await _controller.getTime();
      }

      if ((confirmedTime - targetMs).abs() > 30000) {
        _showMessage(
          'El servidor no confirmó esa posición. Intenta un salto más corto.',
        );
      }

      if (shouldResume && !_isClosing) {
        await _controller.play();
        _playbackExpected = true;
      }

      _lastObservedPosition = Duration(
        milliseconds: confirmedTime >= 0 ? confirmedTime : targetMs,
      );
      _lastPlaybackAdvanceAt = DateTime.now();
      _observedPlaybackAdvance = false;
    } catch (error) {
      debugPrint('Error adelantando película: $error');
      _showMessage('No fue posible adelantar esta película.');

      if (shouldResume && !_isClosing) {
        try {
          await _controller.play();
          _playbackExpected = true;
        } catch (_) {
          // VLC puede tardar en recuperar el audio y video después del salto.
        }
      }
    } finally {
      _ignoreInstabilityUntil = DateTime.now().add(
        Duration(milliseconds: _networkCachingMs + 5000),
      );
      _seekInProgress = false;

      if (!_isClosing) {
        _resetPlaybackWatchdog();
      }

      if (mounted && !_isClosing) {
        setState(() {});
      }
    }
  }

  Future<void> _saveProgressIfNeeded(
    VlcPlayerValue value, {
    bool force = false,
  }) async {
    if (_savingProgress || _seekInProgress || _ended) {
      return;
    }

    final duration = value.duration;
    final position = value.position;

    if (duration <= Duration.zero ||
        position <= Duration.zero) {
      return;
    }

    final now = DateTime.now();
    final lastSave = _lastProgressSave;

    if (!force &&
        lastSave != null &&
        now.difference(lastSave) <
            const Duration(seconds: 10)) {
      return;
    }

    _savingProgress = true;
    _lastProgressSave = now;

    try {
      await _libraryService.saveMovieProgress(
        session: widget.session,
        movie: widget.movie,
        position: position,
        duration: duration,
      );
    } finally {
      _savingProgress = false;
    }
  }

  Future<void> _saveProgressNow() async {
    for (int attempt = 0; attempt < 20 && _savingProgress; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    await _saveProgressIfNeeded(
      _controller.value,
      force: true,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(ScreenAwakeService.enable());
    unawaited(PictureInPictureService.setActive(true));
        unawaited(_handleForeground());
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(ScreenAwakeService.disable());
        unawaited(_handleBackground());
        return;
    }
  }

  Future<void> _handleBackground() async {
    if (_isClosing || _isInBackground) {
      return;
    }

    _cancelRecoveryWarmup();
    _isInBackground = true;
    final wasPlaying = _controller.value.isPlaying;
    _playbackExpected = false;
    _resumePlaybackOnForeground = wasPlaying;
    _sourceStartupTimer?.cancel();

    await _saveProgressNow();

    if (wasPlaying) {
      final enteredPictureInPicture = await PictureInPictureService.enter();
      if (enteredPictureInPicture) {
        _playbackExpected = true;
        return;
      }
    }

    try {
      if (_controller.value.isPlaying) {
        await _controller.pause();
      }
    } catch (error) {
      debugPrint('No fue posible pausar la película al minimizar: $error');
    }
  }

  Future<void> _handleForeground() async {
    if (_isClosing || !_isInBackground) {
      return;
    }

    _isInBackground = false;
    final shouldResume = _resumePlaybackOnForeground;
    _resumePlaybackOnForeground = false;

    if (!shouldResume || _ended || _errorMessage != null) {
      return;
    }

    _playbackExpected = true;

    if (_waitingForNetwork) {
      unawaited(_checkNetworkRecovery());
      return;
    }

    try {
      if (_controller.value.isInitialized) {
        _resetPlaybackWatchdog();
        await _controller.play();
      }
    } catch (error) {
      await _handleSourceFailure(
        'No fue posible reanudar la película.',
        error: error,
      );
    }
  }

  void _toggleControls() {
    if (_errorMessage != null) {
      return;
    }

    setState(() {
      _controlsVisible = !_controlsVisible;
    });

    if (_controlsVisible) {
      _scheduleControlsHide();
    }
  }

  void _showControls() {
    if (!_controlsVisible) {
      setState(() {
        _controlsVisible = true;
      });
    }

    _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();

    _controlsTimer = Timer(
      const Duration(seconds: 4),
      () {
        if (!mounted ||
            _isClosing ||
            _errorMessage != null ||
            _ended) {
          return;
        }

        setState(() {
          _controlsVisible = false;
        });
      },
    );
  }

  Future<void> _closePlayer() async {
    if (_isClosing) {
      return;
    }

    await _saveProgressNow();

    _isClosing = true;
    _controlsTimer?.cancel();
    _sourceStartupTimer?.cancel();
    _watchdogTimer?.cancel();
    _networkRecoveryTimer?.cancel();
    _recoveryWarmupTimer?.cancel();
    _remoteSeekHoldTimer?.cancel();
    _remoteSeekPreviewClearTimer?.cancel();

    try {
      await _controller.stop();
    } catch (_) {
      // VLC puede estar cerrándose.
    }

    unawaited(PictureInPictureService.setActive(false));
    unawaited(ScreenAwakeService.disable());

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _disposePlayer() async {
    await _saveProgressNow();

    try {
      await _controller.stop();
    } catch (_) {
      // VLC ya puede estar detenido.
    }

    try {
      await _controller.dispose();
    } catch (_) {
      // VLC ya puede estar liberado.
    }

    unawaited(PictureInPictureService.setActive(false));
    unawaited(ScreenAwakeService.disable());

    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );

    await DeviceOrientationService.restoreSavedMode();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isClosing = true;

    _controlsTimer?.cancel();
    _sourceStartupTimer?.cancel();
    _watchdogTimer?.cancel();
    _networkRecoveryTimer?.cancel();
    _recoveryWarmupTimer?.cancel();
    _remoteSeekHoldTimer?.cancel();
    _remoteSeekPreviewClearTimer?.cancel();

    _controller.removeListener(
      _onPlayerChanged,
    );

    _remotePlayerFocusNode.dispose();
    _backButtonFocusNode.dispose();
    _audioButtonFocusNode.dispose();
    _subtitleButtonFocusNode.dispose();
    _castButtonFocusNode.dispose();
    _playPauseFocusNode.dispose();
    _seekBarFocusNode.dispose();

    unawaited(_disposePlayer());

    super.dispose();
  }

  void _startRemoteSeekHold(
    LogicalKeyboardKey key,
    Duration direction,
  ) {
    if (_isClosing || !_controllerMounted) {
      return;
    }

    _showControls();
    _remoteSeekPreviewClearTimer?.cancel();

    if (_remoteSeekHoldKey == key &&
        _remoteSeekHoldTimer?.isActive == true) {
      return;
    }

    _remoteSeekHoldTimer?.cancel();
    _remoteSeekHoldKey = key;
    _remoteSeekHoldTicks = 0;
    _remoteSeekPreviewPosition ??= _controller.value.position;

    _stepRemoteSeekHold(direction);

    _remoteSeekHoldTimer = Timer.periodic(
      const Duration(milliseconds: 260),
      (_) {
        _remoteSeekHoldTicks++;
        final seconds = _remoteSeekHoldTicks >= 18
            ? 30
            : _remoteSeekHoldTicks >= 8
                ? 20
                : 10;
        final signedSeconds = direction.inMilliseconds < 0
            ? -seconds
            : seconds;
        _stepRemoteSeekHold(Duration(seconds: signedSeconds));
      },
    );
  }

  void _stopRemoteSeekHold({bool commit = true}) {
    final preview = _remoteSeekPreviewPosition;
    _remoteSeekHoldTimer?.cancel();
    _remoteSeekHoldTimer = null;
    _remoteSeekHoldKey = null;
    _remoteSeekHoldTicks = 0;

    if (commit && preview != null) {
      unawaited(_applyRemoteSeekPreview(preview));
    }

    _remoteSeekPreviewClearTimer?.cancel();
    _remoteSeekPreviewClearTimer = Timer(
      const Duration(milliseconds: 900),
      () {
        if (!mounted || _isClosing) {
          return;
        }
        setState(() {
          _remoteSeekPreviewPosition = null;
        });
      },
    );
  }

  void _stepRemoteSeekHold(Duration offset) {
    if (_isClosing ||
        !_controllerMounted ||
        _resettingController ||
        _reconnecting ||
        _switchingSource ||
        _waitingForNetwork ||
        _warmingUpAfterRecovery) {
      return;
    }

    final value = _controller.value;
    final duration = value.duration;

    if (!value.isInitialized || duration.inMilliseconds <= 0) {
      return;
    }

    final durationMs = duration.inMilliseconds;
    final maximumTargetMs = durationMs > 2000 ? durationMs - 2000 : durationMs;
    final currentMs = (_remoteSeekPreviewPosition ?? value.position)
        .inMilliseconds
        .clamp(0, maximumTargetMs)
        .toInt();
    final targetMs = (currentMs + offset.inMilliseconds)
        .clamp(0, maximumTargetMs)
        .toInt();
    final target = Duration(milliseconds: targetMs);

    _ignoreInstabilityUntil = DateTime.now().add(
      Duration(milliseconds: _networkCachingMs + 5000),
    );
    _remoteSeekPreviewPosition = target;

    if (mounted) {
      setState(() {});
    }

    unawaited(_applyRemoteSeekPreview(target));
  }

  Future<void> _applyRemoteSeekPreview(Duration target) async {
    if (_remoteSeekInProgress ||
        _isClosing ||
        !_controllerMounted ||
        _resettingController ||
        _reconnecting ||
        _switchingSource ||
        _waitingForNetwork ||
        _warmingUpAfterRecovery) {
      return;
    }

    final value = _controller.value;
    final duration = value.duration;

    if (!value.isInitialized || duration.inMilliseconds <= 0) {
      return;
    }

    final maximumTargetMs = duration.inMilliseconds > 2000
        ? duration.inMilliseconds - 2000
        : duration.inMilliseconds;
    final targetMs = target.inMilliseconds
        .clamp(0, maximumTargetMs)
        .toInt();
    final shouldResume = value.isPlaying || _playbackExpected;

    _remoteSeekInProgress = true;
    _resumeApplied = true;
    _resumeInProgress = false;
    _pendingResumePosition = Duration.zero;
    _sourceStartupTimer?.cancel();

    try {
      await _controller.setTime(targetMs);
      _lastObservedPosition = Duration(milliseconds: targetMs);
      _lastPlaybackAdvanceAt = DateTime.now();
      _observedPlaybackAdvance = false;

      if (shouldResume && !_isClosing && !_controller.value.isPlaying) {
        await _controller.play();
        _playbackExpected = true;
      }
    } catch (error) {
      debugPrint('No fue posible adelantar con el control remoto: $error');
    } finally {
      _remoteSeekInProgress = false;
      if (!_isClosing) {
        _resetPlaybackWatchdog();
      }
    }
  }

  void _seekRelative(Duration offset) {
    if (_isClosing || !_controllerMounted || _seekInProgress) {
      return;
    }

    final value = _controller.value;
    final duration = value.duration;

    if (duration.inMilliseconds <= 0) {
      return;
    }

    final currentMs = value.position.inMilliseconds;
    final targetMs = (currentMs + offset.inMilliseconds)
        .clamp(0, duration.inMilliseconds)
        .toInt();

    _showControls();
    unawaited(_seekTo(Duration(milliseconds: targetMs)));
  }

  KeyEventResult _handleRemotePlayerKey(
    FocusNode node,
    KeyEvent event,
  ) {
    if (!widget.enableTvRemoteNavigation || _isClosing) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (event is KeyUpEvent) {
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        _stopRemoteSeekHold();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final isBackKey = key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.escape;

    if (isBackKey) {
      unawaited(_closePlayer());
      return KeyEventResult.handled;
    }

    final isDirectionalKey = key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
    final controlHasFocus = _backButtonFocusNode.hasFocus ||
        _audioButtonFocusNode.hasFocus ||
        _subtitleButtonFocusNode.hasFocus ||
        _playPauseFocusNode.hasFocus ||
        _seekBarFocusNode.hasFocus;

    if (isDirectionalKey) {
      _showControls();

      if (!controlHasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _playPauseFocusNode.requestFocus();
          }
        });
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.arrowUp) {
        if (_seekBarFocusNode.hasFocus) {
          _playPauseFocusNode.requestFocus();
        } else if (_playPauseFocusNode.hasFocus) {
          _audioButtonFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.arrowDown) {
        if (_playPauseFocusNode.hasFocus) {
          _seekBarFocusNode.requestFocus();
        } else if (_backButtonFocusNode.hasFocus ||
            _audioButtonFocusNode.hasFocus ||
            _subtitleButtonFocusNode.hasFocus) {
          _playPauseFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.arrowLeft) {
        if (_playPauseFocusNode.hasFocus || _seekBarFocusNode.hasFocus) {
          _startRemoteSeekHold(
            LogicalKeyboardKey.arrowLeft,
            const Duration(seconds: -10),
          );
        } else if (_subtitleButtonFocusNode.hasFocus) {
          _audioButtonFocusNode.requestFocus();
        } else if (_audioButtonFocusNode.hasFocus) {
          _backButtonFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.arrowRight) {
        if (_playPauseFocusNode.hasFocus || _seekBarFocusNode.hasFocus) {
          _startRemoteSeekHold(
            LogicalKeyboardKey.arrowRight,
            const Duration(seconds: 10),
          );
        } else if (_backButtonFocusNode.hasFocus) {
          _audioButtonFocusNode.requestFocus();
        } else if (_audioButtonFocusNode.hasFocus) {
          _subtitleButtonFocusNode.requestFocus();
        }
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.mediaRewind) {
      _seekRelative(const Duration(seconds: -10));
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.mediaFastForward) {
      _seekRelative(const Duration(seconds: 10));
      return KeyEventResult.handled;
    }

    final isMediaPlayPause = key == LogicalKeyboardKey.mediaPlayPause;

    if (isMediaPlayPause) {
      unawaited(_togglePlayback());
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult:
          (didPop, result) {
        if (!didPop) {
          unawaited(_closePlayer());
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _remotePlayerFocusNode,
          autofocus: widget.enableTvRemoteNavigation,
          onKeyEvent: _handleRemotePlayerKey,
          child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_controllerMounted)
                Center(
                  child: VlcPlayer(
                    key: ValueKey<int>(_controllerGeneration),
                    controller: _controller,
                    aspectRatio: 16 / 9,
                    placeholder:
                        const ColoredBox(
                      color: Colors.black,
                    ),
                  ),
                )
              else
                const ColoredBox(color: Colors.black),
              if (_warmingUpAfterRecovery)
                const ColoredBox(color: Colors.black),
              if (_controllerMounted)
                ValueListenableBuilder<
                    VlcPlayerValue>(
                  valueListenable: _controller,
                builder: (context, value, _) {
                  final showLoading =
                      _opening ||
                          _seekInProgress ||
                          _warmingUpAfterRecovery ||
                          (value.isBuffering &&
                              !value.isPlaying);

                  if (!showLoading ||
                      _errorMessage != null) {
                    return const
                        SizedBox.shrink();
                  }

                  return _LoadingOverlay(
                    message: _seekInProgress
                        ? 'Buscando posición...'
                        : _waitingForNetwork
                        ? 'Sin conexión. Esperando internet...'
                        : _warmingUpAfterRecovery
                            ? 'Estabilizando conexión...'
                        : _stabilizingConnection
                            ? 'Ajustando búfer...'
                        : _reconnecting
                            ? 'Reconectando película...'
                        : _switchingSource
                            ? 'Probando otra versión...'
                            : 'Abriendo película...',
                  );
                },
              ),
              if (_errorMessage != null)
                _MoviePlayerError(
                  message: _errorMessage!,
                  onRetry: () {
                    unawaited(_retry());
                  },
                  onClose: () {
                    unawaited(_closePlayer());
                  },
                ),
              if (_errorMessage == null &&
                  _controllerMounted &&
                  !_warmingUpAfterRecovery)
                AnimatedOpacity(
                  opacity:
                      _controlsVisible ? 1 : 0,
                  duration: const Duration(
                    milliseconds: 180,
                  ),
                  child: IgnorePointer(
                    ignoring:
                        !_controlsVisible,
                    child: _MovieControls(
                      controller: _controller,
                      title: _playerTitle,
                      ended: _ended,
                      seekPreviewPosition: _remoteSeekPreviewPosition,
                      backFocusNode: _backButtonFocusNode,
                      audioFocusNode: _audioButtonFocusNode,
                      subtitleFocusNode: _subtitleButtonFocusNode,
                      castFocusNode: _castButtonFocusNode,
                      playPauseFocusNode: _playPauseFocusNode,
                      seekBarFocusNode: _seekBarFocusNode,
                      onBack: () {
                        unawaited(
                          _closePlayer(),
                        );
                      },
                      onPlayPause: () {
                        unawaited(
                          _togglePlayback(),
                        );
                      },
                      audioLabel: _selectedAudioLabel,
                      subtitleLabel: _selectedSubtitleLabel,
                      onAudioTracks: () {
                        unawaited(_showAudioTracks());
                      },
                      onSubtitleTracks: () {
                        unawaited(_showSubtitleTracks());
                      },
                      onCast: () {
                        unawaited(_showCastDevices());
                      },
                      onSeek: (position) {
                        unawaited(
                          _seekTo(position),
                        );
                      },
                    ),
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

class _MovieControls extends StatelessWidget {
  const _MovieControls({
    required this.controller,
    required this.title,
    required this.ended,
    required this.seekPreviewPosition,
    required this.backFocusNode,
    required this.audioFocusNode,
    required this.subtitleFocusNode,
    required this.castFocusNode,
    required this.playPauseFocusNode,
    required this.seekBarFocusNode,
    required this.onBack,
    required this.onPlayPause,
    required this.audioLabel,
    required this.subtitleLabel,
    required this.onAudioTracks,
    required this.onSubtitleTracks,
    required this.onCast,
    required this.onSeek,
  });

  final VlcPlayerController controller;
  final String title;
  final bool ended;
  final Duration? seekPreviewPosition;
  final FocusNode backFocusNode;
  final FocusNode audioFocusNode;
  final FocusNode subtitleFocusNode;
  final FocusNode castFocusNode;
  final FocusNode playPauseFocusNode;
  final FocusNode seekBarFocusNode;
  final VoidCallback onBack;
  final VoidCallback onPlayPause;
  final String audioLabel;
  final String subtitleLabel;
  final VoidCallback onAudioTracks;
  final VoidCallback onSubtitleTracks;
  final VoidCallback onCast;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xCC000000),
                Colors.transparent,
                Colors.transparent,
                Color(0xDD000000),
              ],
              stops: [0, 0.3, 0.62, 1],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(
              14,
              10,
              14,
              12,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _RoundButton(
                      focusNode: backFocusNode,
                      icon:
                          Icons.arrow_back_rounded,
                      onPressed: onBack,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow:
                            TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _TrackControlButton(
                      focusNode: audioFocusNode,
                      icon: Icons.audiotrack_rounded,
                      label: audioLabel,
                      onPressed: onAudioTracks,
                    ),
                    const SizedBox(width: 8),
                    _TrackControlButton(
                      focusNode: subtitleFocusNode,
                      icon: Icons.subtitles_rounded,
                      label: subtitleLabel,
                      onPressed: onSubtitleTracks,
                    ),
                    const SizedBox(width: 8),
                    _TrackControlButton(
                      focusNode: castFocusNode,
                      icon: Icons.cast_rounded,
                      label: 'Transmitir',
                      onPressed: onCast,
                    ),
                  ],
                ),
                const Spacer(),
                ValueListenableBuilder<
                    VlcPlayerValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    final duration =
                        value.duration;
                    final position =
                        seekPreviewPosition ?? value.position;

                    final icon = ended
                        ? Icons.replay_rounded
                        : value.isPlaying
                            ? Icons
                                .pause_rounded
                            : Icons
                                .play_arrow_rounded;

                    return Column(
                      children: [
                        Center(
                          child:
                              _LargePlayButton(
                            focusNode: playPauseFocusNode,
                            icon: icon,
                            onPressed:
                                onPlayPause,
                          ),
                        ),
                        const SizedBox(
                          height: 22,
                        ),
                        _SafeSeekBar(
                          focusNode: seekBarFocusNode,
                          duration: duration,
                          position: position,
                          onSeek: onSeek,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}


class _SafeSeekBar extends StatefulWidget {
  const _SafeSeekBar({
    required this.focusNode,
    required this.duration,
    required this.position,
    required this.onSeek,
  });

  final FocusNode focusNode;
  final Duration duration;
  final Duration position;
  final ValueChanged<Duration> onSeek;

  @override
  State<_SafeSeekBar> createState() => _SafeSeekBarState();
}

class _SafeSeekBarState extends State<_SafeSeekBar> {
  double? _dragValueMs;

  @override
  Widget build(BuildContext context) {
    final durationMs = widget.duration.inMilliseconds > 0
        ? widget.duration.inMilliseconds
        : 1;
    final currentMs = widget.position.inMilliseconds
        .clamp(0, durationMs)
        .toDouble();
    final sliderValue = (_dragValueMs ?? currentMs)
        .clamp(0, durationMs.toDouble())
        .toDouble();
    final displayedPosition = Duration(
      milliseconds: sliderValue.round(),
    );
    final enabled = widget.duration.inMilliseconds > 0;

    final content = Row(
      children: [
        Text(
          _formatDuration(displayedPosition),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Slider(
            min: 0,
            max: durationMs.toDouble(),
            value: sliderValue,
            onChangeStart: enabled
                ? (value) {
                    setState(() {
                      _dragValueMs = value;
                    });
                  }
                : null,
            onChanged: enabled
                ? (value) {
                    setState(() {
                      _dragValueMs = value;
                    });
                  }
                : null,
            onChangeEnd: enabled
                ? (value) {
                    setState(() {
                      _dragValueMs = null;
                    });
                    widget.onSeek(
                      Duration(milliseconds: value.round()),
                    );
                  }
                : null,
          ),
        ),
        Text(
          _formatDuration(widget.duration),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    return TvNeonFocus(
      focusNode: widget.focusNode,
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      scale: 1.015,
      child: content,
    );
  }
}

class _TrackControlButton extends StatelessWidget {
  const _TrackControlButton({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvNeonFocus(
      focusNode: focusNode,
      borderRadius: BorderRadius.circular(16),
      onPressed: onPressed,
      child: Material(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          canRequestFocus: false,
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: 46,
              maxWidth: 150,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: Colors.white,
                    size: 21,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackSelectorSheet extends StatelessWidget {
  const _TrackSelectorSheet({
    required this.icon,
    required this.title,
    required this.tracks,
    required this.selectedTrack,
  });

  final IconData icon;
  final String title;
  final Map<int, String> tracks;
  final int? selectedTrack;

  @override
  Widget build(BuildContext context) {
    final entries = tracks.entries.toList();

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF111620),
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(26),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF3A4352),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C2948),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      icon,
                      color: const Color(0xFF8CA2FF),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                itemCount: entries.length,
                separatorBuilder: (context, index) {
                  return const SizedBox(height: 4);
                },
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final selected = entry.key == selectedTrack;

                  return Material(
                    color: selected
                        ? const Color(0xFF1B2B52)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(15),
                    child: ListTile(
                      onTap: () => Navigator.of(context).pop(entry.key),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      leading: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected
                            ? const Color(0xFF8CA2FF)
                            : const Color(0xFF667085),
                      ),
                      title: Text(
                        entry.value,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.focusNode,
    required this.icon,
    required this.onPressed,
  });

  final FocusNode focusNode;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvNeonFocus(
      focusNode: focusNode,
      borderRadius: BorderRadius.circular(28),
      onPressed: onPressed,
      child: Material(
        color: const Color(0x99000000),
        shape: const CircleBorder(),
        child: InkWell(
          canRequestFocus: false,
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(
              icon,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _LargePlayButton extends StatelessWidget {
  const _LargePlayButton({
    required this.focusNode,
    required this.icon,
    required this.onPressed,
  });

  final FocusNode focusNode;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvNeonFocus(
      focusNode: focusNode,
      borderRadius: BorderRadius.circular(46),
      onPressed: onPressed,
      scale: 1.06,
      child: Material(
        color: const Color(0xBB000000),
        shape: const CircleBorder(),
        child: InkWell(
          canRequestFocus: false,
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 74,
            height: 74,
            child: Icon(
              icon,
              color: Colors.white,
              size: 43,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0x66000000),
      child: Center(
        child: Container(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 20,
          ),
          decoration: BoxDecoration(
            color: const Color(0xDD111620),
            borderRadius:
                BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const SizedBox(
                width: 38,
                height: 38,
                child:
                    CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoviePlayerError extends StatelessWidget {
  const _MoviePlayerError({
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Center(
          child: Container(
            constraints:
                const BoxConstraints(
              maxWidth: 440,
            ),
            margin:
                const EdgeInsets.all(28),
            padding:
                const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color:
                  const Color(0xFF111620),
              borderRadius:
                  BorderRadius.circular(24),
              border: Border.all(
                color:
                    const Color(0xFF252C38),
              ),
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                const Icon(
                  Icons
                      .movie_filter_outlined,
                  color:
                      Color(0xFFFF7D8A),
                  size: 50,
                ),
                const SizedBox(height: 18),
                const Text(
                  'No se pudo reproducir',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign:
                      TextAlign.center,
                  style: const TextStyle(
                    color:
                        Color(0xFF98A2B3),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child:
                          OutlinedButton(
                        onPressed: onClose,
                        child: const Text(
                          'REGRESAR',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child:
                          FilledButton(
                        onPressed: onRetry,
                        child: const Text(
                          'REINTENTAR',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDuration(Duration value) {
  final totalSeconds =
      value.inSeconds.clamp(0, 359999).toInt();
  final hours = totalSeconds ~/ 3600;
  final minutes =
      (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  String twoDigits(int number) {
    return number.toString().padLeft(2, '0');
  }

  if (hours > 0) {
    return '$hours:${twoDigits(minutes)}:'
        '${twoDigits(seconds)}';
  }

  return '$minutes:${twoDigits(seconds)}';
}
