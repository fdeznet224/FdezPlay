import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

import '../../../auth/domain/auth_session.dart';
import '../../../live_tv/data/live_quality_observation_service.dart';
import '../../../live_tv/domain/live_channel.dart';
import '../../../live_tv/domain/live_channel_group.dart';
import '../../../settings/data/playback_preferences_service.dart';
import '../../../../shared/services/device_orientation_service.dart';
import '../../../../shared/services/playback_network_probe.dart';

class TvLivePlayerScreen extends StatefulWidget {
  const TvLivePlayerScreen({
    required this.session,
    required this.channel,
    this.channelVariants = const [],
    super.key,
  });

  final AuthSession session;
  final LiveChannel channel;
  final List<LiveChannel> channelVariants;

  @override
  State<TvLivePlayerScreen> createState() {
    return _TvLivePlayerScreenState();
  }
}

class _TvLivePlayerScreenState extends State<TvLivePlayerScreen>
    with WidgetsBindingObserver {
  late VlcPlayerController _controller;

  final PlaybackPreferencesService _preferencesService =
      PlaybackPreferencesService.instance;
  final LiveQualityObservationService _qualityObservationService =
      LiveQualityObservationService.instance;

  late LiveChannel _activeChannel;
  List<LiveChannel> _orderedChannels = const [];
  int _activeChannelIndex = 0;
  int? _controllerStreamId;
  LiveQualityMode _liveQualityMode = LiveQualityMode.automatic;
  bool _switchingQuality = false;
  Map<int, LiveQualityObservation> _qualityObservations =
      <int, LiveQualityObservation>{};
  int? _lastRecordedResolutionStreamId;
  int? _lastRecordedResolutionWidth;
  int? _lastRecordedResolutionHeight;
  bool _correctingMislabeledQuality = false;
  final Set<int> _qualityCorrectionAttemptedStreamIds = <int>{};

  List<int> _networkCachingLevels = const [5000, 8000, 12000];
  int _networkCachingIndex = 0;
  int _controllerCachingMs = 5000;
  bool _stabilizingConnection = false;
  bool _warmingUpAfterRecovery = false;
  bool _warmupCheckInProgress = false;
  Duration _recoveryWarmupDuration = const Duration(seconds: 5);
  DateTime? _warmupStableSince;
  DateTime? _warmupStartedAt;

  int get _networkCachingMs =>
      _networkCachingLevels[_networkCachingIndex];

  Timer? _controlsTimer;
  Timer? _startupTimer;
  Timer? _reconnectTimer;
  Timer? _watchdogTimer;
  Timer? _networkRecoveryTimer;
  Timer? _recoveryWarmupTimer;

  bool _opening = true;
  bool _controlsVisible = true;
  bool _isClosing = false;
  bool _isInBackground = false;
  bool _resumeOnForeground = false;
  bool _reconnecting = false;
  bool _hasStarted = false;
  bool _disposeStarted = false;
  bool _waitingForNetwork = false;
  bool _networkCheckInProgress = false;
  bool _playbackExpected = true;
  bool _observedPlaybackAdvance = false;
  bool _controllerMounted = true;
  bool _resettingController = false;

  int _controllerGeneration = 0;
  Duration _lastObservedPosition = Duration.zero;
  DateTime _lastPlaybackAdvanceAt = DateTime.now();

  int _reconnectAttempt = 0;
  String? _errorMessage;

  String get _liveUrl {
    final server = widget.session.server.replaceFirst(RegExp(r'/+$'), '');
    final username = Uri.encodeComponent(widget.session.username);
    final password = Uri.encodeComponent(widget.session.password);

    return '$server/live/$username/$password/${_activeChannel.streamId}.ts';
  }

  String get _qualityLabel {
    final observed = _qualityObservations[_activeChannel.streamId];

    if (observed != null && observed.height > 0) {
      return observed.resolutionLabel;
    }

    final currentSize = _controller.value.size;

    if (_controllerStreamId == _activeChannel.streamId &&
        currentSize.height > 0) {
      return '${currentSize.height.round()}p';
    }

    return liveChannelQualityLabel(_activeChannel);
  }

  String get _displayTitle => liveChannelBaseName(widget.channel.name);

  List<LiveChannel> _uniqueChannels(Iterable<LiveChannel> channels) {
    final unique = <int, LiveChannel>{};

    for (final channel in channels) {
      unique.putIfAbsent(channel.streamId, () => channel);
    }

    return unique.values.toList(growable: false);
  }

  void _configureQualityOrder(LiveQualityMode mode) {
    final source = _uniqueChannels([
      widget.channel,
      ...widget.channelVariants,
    ]);

    if (source.length <= 1) {
      _orderedChannels = source;
      _activeChannelIndex = 0;
      _activeChannel = source.first;
      return;
    }

    final ordered = source.toList(growable: false);

    ordered.sort((a, b) {
      final aHeight = _qualityHeightForOrdering(a, mode);
      final bHeight = _qualityHeightForOrdering(b, mode);
      int comparison;

      switch (mode) {
        case LiveQualityMode.dataSaver:
          comparison = aHeight.compareTo(bHeight);
          break;
        case LiveQualityMode.bestQuality:
          comparison = bHeight.compareTo(aHeight);
          break;
        case LiveQualityMode.automatic:
          final aDistance = (aHeight - 720).abs();
          final bDistance = (bHeight - 720).abs();
          comparison = aDistance.compareTo(bDistance);

          if (comparison == 0) {
            comparison = aHeight.compareTo(bHeight);
          }
          break;
      }

      if (comparison != 0) {
        return comparison;
      }

      final aObserved = _qualityObservations.containsKey(a.streamId);
      final bObserved = _qualityObservations.containsKey(b.streamId);

      if (aObserved != bObserved) {
        return aObserved ? -1 : 1;
      }

      final orderComparison = a.order.compareTo(b.order);

      if (orderComparison != 0) {
        return orderComparison;
      }

      return a.name.compareTo(b.name);
    });

    _orderedChannels = ordered;
    _activeChannelIndex = 0;
    _activeChannel = _orderedChannels.first;
  }

  int _qualityHeightForOrdering(
    LiveChannel channel,
    LiveQualityMode mode,
  ) {
    final observed = _qualityObservations[channel.streamId];

    if (observed != null && observed.height > 0) {
      return observed.displayHeight;
    }

    final tier = detectLiveChannelQuality(channel.name);

    switch (tier) {
      case LiveChannelQualityTier.low:
        return 360;
      case LiveChannelQualityTier.standard:
        return 540;
      case LiveChannelQualityTier.hd:
        return 720;
      case LiveChannelQualityTier.fullHd:
        return mode == LiveQualityMode.bestQuality ? 1080 : 900;
      case LiveChannelQualityTier.ultraHd:
        return 2160;
    }
  }

  bool _advanceToNextVariant() {
    if (_activeChannelIndex + 1 >= _orderedChannels.length) {
      return false;
    }

    _activeChannelIndex++;
    _activeChannel = _orderedChannels[_activeChannelIndex];
    _switchingQuality = true;

    if (mounted) {
      setState(() {
        _opening = true;
        _errorMessage = null;
      });
    }

    return true;
  }


  VlcPlayerController _buildController() {
    _controllerCachingMs = _networkCachingMs;
    _controllerStreamId = _activeChannel.streamId;

    return VlcPlayerController.network(
      _liveUrl,
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
            VlcHttpOptions.httpContinuous(true),
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
    HardwareKeyboard.instance.addHandler(_handleRemoteKey);

    _activeChannel = widget.channel;
    _orderedChannels = _uniqueChannels([
      widget.channel,
      ...widget.channelVariants,
    ]);
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

    if (_controllerCachingMs != _networkCachingMs ||
        _controllerStreamId != _activeChannel.streamId) {
      final replaced = await _replaceControllerBeforeInitialization();

      if (!replaced) {
        return;
      }
    }

    await _initializePlayer();
  }

  Future<void> _loadPlaybackPreferences() async {
    try {
      final preferences = await _preferencesService.load(widget.session);

      if (_isClosing || !mounted) {
        return;
      }

      _networkCachingLevels =
          preferences.stabilityMode.liveCachingLevels;
      _networkCachingIndex = 0;
      _recoveryWarmupDuration =
          preferences.stabilityMode.liveRecoveryWarmup;
      _liveQualityMode = preferences.liveQualityMode;
      _qualityObservations =
          await _qualityObservationService.load(widget.session);

      if (_isClosing || !mounted) {
        return;
      }

      _configureQualityOrder(_liveQualityMode);
    } catch (error) {
      debugPrint(
        'Error cargando estabilidad de TV: $error',
      );
    }
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


  Future<bool> _prepareAndPlayController({bool stabilize = false}) async {
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
        debugPrint('No fue posible silenciar TV durante la estabilización: $error');
      }
    }

    await _controller.play();
    _resetPlaybackWatchdog();
    _scheduleStartupGuard();

    if (stabilize) {
      unawaited(_startRecoveryWarmup());
    }

    return true;
  }

  Future<bool> _recreateController({bool stabilize = true}) async {
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
      return await _prepareAndPlayController(stabilize: stabilize);
    } finally {
      _resettingController = false;
    }
  }

  Future<void> _startRecoveryWarmup() async {
    if (_isClosing || _isInBackground || !mounted) {
      return;
    }

    _recoveryWarmupTimer?.cancel();
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
      final now = DateTime.now();
      final stable = value.isPlaying && !value.isBuffering && !value.hasError;

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
              _recoveryWarmupDuration + const Duration(seconds: 12);

      if (timedOut) {
        if (value.isPlaying) {
          await _finishRecoveryWarmup();
        } else {
          _cancelRecoveryWarmup();
          await _scheduleReconnect(
            'La señal no logró estabilizarse.',
          );
        }
      }
    } finally {
      _warmupCheckInProgress = false;
    }
  }

  Future<void> _finishRecoveryWarmup() async {
    _recoveryWarmupTimer?.cancel();

    try {
      await _controller.setVolume(100);
    } catch (error) {
      debugPrint('No fue posible restaurar el audio de TV: $error');
    }

    if (!mounted || _isClosing) {
      return;
    }

    setState(() {
      _warmingUpAfterRecovery = false;
      _stabilizingConnection = false;
      _switchingQuality = false;
      _opening = false;
      _reconnecting = false;
      _errorMessage = null;
    });

    _resetPlaybackWatchdog();
    _scheduleControlsHide();

    final streamId = _controllerStreamId;
    final observation = streamId == null
        ? null
        : _qualityObservations[streamId];

    if (_liveQualityMode == LiveQualityMode.bestQuality &&
        streamId != null &&
        observation != null) {
      unawaited(
        _correctMislabeledQualityIfNeeded(
          streamId,
          observation.displayHeight,
        ),
      );
    }
  }

  void _cancelRecoveryWarmup() {
    _recoveryWarmupTimer?.cancel();
    _warmingUpAfterRecovery = false;
    _warmupCheckInProgress = false;
    _warmupStableSince = null;
    _warmupStartedAt = null;
  }

  Future<void> _initializePlayer() async {
    if (_isClosing) {
      return;
    }

    setState(() {
      _opening = true;
      _errorMessage = null;
    });

    try {
      await _prepareAndPlayController();
    } catch (error) {
      await _scheduleReconnect(
        'No fue posible abrir el canal.',
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
            _errorMessage != null) {
          return;
        }

        final value = _controller.value;
        final position = value.position;
        final now = DateTime.now();

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
        _waitingForNetwork ||
        _reconnecting) {
      return;
    }

    final online = await PlaybackNetworkProbe.canReach(widget.session);

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

      try {
        final recovered = await _recreateController();

        if (recovered) {
          _stabilizingConnection = false;
          _playbackExpected = true;
          _resetPlaybackWatchdog();
          _scheduleStartupGuard();
          return;
        }
      } catch (error) {
        debugPrint('No fue posible aumentar el búfer de TV: $error');
      }

      _stabilizingConnection = false;
    }

    if (_advanceToNextVariant()) {
      _stabilizingConnection = true;

      try {
        final recovered = await _recreateController();

        if (recovered) {
          _playbackExpected = true;
          _resetPlaybackWatchdog();
          _scheduleStartupGuard();
          return;
        }
      } catch (error) {
        debugPrint('No fue posible cambiar la calidad de TV: $error');
      }

      _stabilizingConnection = false;
    }

    await _scheduleReconnect(
      'La conexión del canal se interrumpió.',
    );
  }

  void _waitForNetwork() {
    if (_isClosing || _waitingForNetwork) {
      return;
    }

    _cancelRecoveryWarmup();
    _waitingForNetwork = true;
    _reconnecting = false;
    _startupTimer?.cancel();
    _reconnectTimer?.cancel();
    _networkRecoveryTimer?.cancel();

    if (mounted) {
      setState(() {
        _opening = true;
        _errorMessage = null;
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
    _reconnectAttempt = 0;
    await _reloadLiveStream();
  }

  Future<void> _reloadLiveStream() async {
    if (_isClosing || _isInBackground) {
      return;
    }

    _reconnecting = true;
    _playbackExpected = true;

    if (mounted) {
      setState(() {
        _opening = true;
        _errorMessage = null;
      });
    }

    try {
      final recovered = await _recreateController();

      if (!recovered) {
        throw StateError('No se pudo recrear VLC.');
      }

      _reconnecting = false;
      _resetPlaybackWatchdog();
      _scheduleStartupGuard();
    } catch (error) {
      _reconnecting = false;
      await _scheduleReconnect(
        'No fue posible recuperar la señal.',
        error: error,
      );
    }
  }

  void _scheduleStartupGuard() {
    _startupTimer?.cancel();
    _hasStarted = false;

    final guardSeconds = ((_networkCachingMs + 8000) ~/ 1000)
        .clamp(20, 35)
        .toInt();

    _startupTimer = Timer(
      Duration(seconds: guardSeconds),
      () {
        if (!mounted ||
            _isClosing ||
            _isInBackground ||
            _hasStarted ||
            _reconnecting) {
          return;
        }

        unawaited(_scheduleReconnect('El canal tardó demasiado en responder.'));
      },
    );
  }

  void _onPlayerChanged() {
    if (!mounted || _isClosing || _isInBackground) {
      return;
    }

    final value = _controller.value;
    _observeActiveResolution(value);

    if (value.hasError) {
      final description = value.errorDescription.trim();

      unawaited(
        _scheduleReconnect(
          description.isEmpty || description == VlcPlayerValue.noError
              ? 'La señal del canal se interrumpió.'
              : description,
        ),
      );
      return;
    }

    if (value.isPlaying) {
      _hasStarted = true;
      _playbackExpected = true;
      _waitingForNetwork = false;
      _networkRecoveryTimer?.cancel();

      if (value.position > _lastObservedPosition) {
        _lastObservedPosition = value.position;
        _lastPlaybackAdvanceAt = DateTime.now();
        _observedPlaybackAdvance = true;
      }
      _startupTimer?.cancel();
      _reconnectTimer?.cancel();
      _reconnectAttempt = 0;

      if (!_warmingUpAfterRecovery &&
          (_opening ||
              _reconnecting ||
              _stabilizingConnection ||
              _errorMessage != null)) {
        setState(() {
          _opening = false;
          _reconnecting = false;
          _stabilizingConnection = false;
          _errorMessage = null;
        });
      }
    }
  }

  void _observeActiveResolution(VlcPlayerValue value) {
    if (!value.isInitialized || _controllerStreamId == null) {
      return;
    }

    final width = value.size.width.round();
    final height = value.size.height.round();

    if (width <= 0 || height <= 0) {
      return;
    }

    final streamId = _controllerStreamId!;

    if (_lastRecordedResolutionStreamId == streamId &&
        _lastRecordedResolutionWidth == width &&
        _lastRecordedResolutionHeight == height) {
      return;
    }

    _lastRecordedResolutionStreamId = streamId;
    _lastRecordedResolutionWidth = width;
    _lastRecordedResolutionHeight = height;

    final observation = LiveQualityObservation(
      width: width,
      height: height,
      updatedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
    );
    _qualityObservations = <int, LiveQualityObservation>{
      ..._qualityObservations,
      streamId: observation,
    };

    if (mounted) {
      setState(() {});
    }

    unawaited(_saveObservedResolution(streamId, width, height));

    if (_liveQualityMode == LiveQualityMode.bestQuality) {
      unawaited(
        _correctMislabeledQualityIfNeeded(
          streamId,
          observation.displayHeight,
        ),
      );
    }
  }

  Future<void> _saveObservedResolution(
    int streamId,
    int width,
    int height,
  ) async {
    try {
      await _qualityObservationService.record(
        session: widget.session,
        streamId: streamId,
        width: width,
        height: height,
      );
    } catch (error) {
      debugPrint('No fue posible guardar la resolución del canal: $error');
    }
  }

  Future<void> _correctMislabeledQualityIfNeeded(
    int measuredStreamId,
    int measuredHeight,
  ) async {
    if (_correctingMislabeledQuality ||
        _switchingQuality ||
        _reconnecting ||
        _resettingController ||
        _isClosing ||
        _isInBackground ||
        measuredStreamId != _activeChannel.streamId) {
      return;
    }

    if (!_qualityCorrectionAttemptedStreamIds.add(measuredStreamId)) {
      return;
    }

    final source = _uniqueChannels([
      widget.channel,
      ...widget.channelVariants,
    ]);

    LiveChannel? betterCandidate;
    int bestHeight = measuredHeight;

    for (final candidate in source) {
      if (candidate.streamId == measuredStreamId) {
        continue;
      }

      final candidateHeight = _qualityHeightForOrdering(
        candidate,
        LiveQualityMode.bestQuality,
      );

      if (candidateHeight >= bestHeight + 120) {
        bestHeight = candidateHeight;
        betterCandidate = candidate;
      }
    }

    if (betterCandidate == null) {
      return;
    }

    final selectedCandidate = betterCandidate;
    _correctingMislabeledQuality = true;

    try {
      final reordered = source.toList(growable: false)
        ..sort((a, b) {
          final heightComparison = _qualityHeightForOrdering(
            b,
            LiveQualityMode.bestQuality,
          ).compareTo(
            _qualityHeightForOrdering(
              a,
              LiveQualityMode.bestQuality,
            ),
          );

          if (heightComparison != 0) {
            return heightComparison;
          }

          return a.order.compareTo(b.order);
        });

      _orderedChannels = reordered;
      _activeChannelIndex = reordered.indexWhere(
        (channel) => channel.streamId == selectedCandidate.streamId,
      );
      _activeChannel = selectedCandidate;
      _switchingQuality = true;

      if (mounted) {
        setState(() {
          _opening = true;
          _errorMessage = null;
        });
      }

      final recovered = await _recreateController();

      if (!recovered) {
        throw StateError('No se pudo comprobar una señal de mayor calidad.');
      }
    } catch (error) {
      debugPrint('No fue posible corregir la calidad anunciada: $error');
    } finally {
      _correctingMislabeledQuality = false;
    }
  }

  Future<void> _scheduleReconnect(
    String message, {
    Object? error,
  }) async {
    if (_isClosing ||
        _isInBackground ||
        _reconnecting ||
        _waitingForNetwork) {
      return;
    }

    if (error != null) {
      debugPrint('$message Error: $error');
    }

    final online = await PlaybackNetworkProbe.canReach(widget.session);

    if (!online) {
      _waitForNetwork();
      return;
    }

    final maxReconnectAttempts = _orderedChannels.length > 3
        ? _orderedChannels.length + 1
        : 3;

    if (_reconnectAttempt >= maxReconnectAttempts) {
      if (!mounted || _isClosing) {
        return;
      }

      setState(() {
        _opening = false;
        _reconnecting = false;
        _errorMessage =
            'No fue posible recuperar la señal. Revisa tu conexión o intenta nuevamente.';
      });
      return;
    }

    if (_reconnectAttempt > 0) {
      _advanceToNextVariant();
    }

    _reconnecting = true;
    _reconnectAttempt++;
    _startupTimer?.cancel();
    _reconnectTimer?.cancel();

    if (mounted && !_isClosing) {
      setState(() {
        _opening = true;
        _errorMessage = null;
      });
    }

    final delay = switch (_reconnectAttempt) {
      1 => const Duration(seconds: 1),
      2 => const Duration(seconds: 3),
      _ => const Duration(seconds: 6),
    };

    _reconnectTimer = Timer(delay, () async {
      try {
        if (_isClosing || _isInBackground) {
          _reconnecting = false;
          return;
        }

        final recovered = await _recreateController();

        if (!recovered) {
          throw StateError('No se pudo recrear VLC.');
        }

        _reconnecting = false;
        _playbackExpected = true;
        _resetPlaybackWatchdog();
        _scheduleStartupGuard();
      } catch (reconnectError) {
        _reconnecting = false;
        await _scheduleReconnect(
          'No fue posible reconectar el canal.',
          error: reconnectError,
        );
      }
    });
  }

  Future<void> _retry() async {
    if (_isClosing) {
      return;
    }

    _reconnectAttempt = 0;
    _reconnecting = false;
    _errorMessage = null;
    _startupTimer?.cancel();
    _reconnectTimer?.cancel();
    _networkRecoveryTimer?.cancel();
    _waitingForNetwork = false;

    if (_orderedChannels.isNotEmpty) {
      _activeChannelIndex = 0;
      _activeChannel = _orderedChannels.first;
      _switchingQuality =
          _controllerStreamId != _activeChannel.streamId;
    }

    try {
      final recovered = await _recreateController();

      if (!recovered) {
        throw StateError('No se pudo recrear VLC.');
      }
    } catch (error) {
      await _scheduleReconnect(
        'No fue posible volver a abrir el canal.',
        error: error,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_handleForeground());
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
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
    _playbackExpected = false;
    _resumeOnForeground = _controller.value.isPlaying || _opening;
    _startupTimer?.cancel();
    _reconnectTimer?.cancel();

    try {
      if (_controller.value.isPlaying) {
        await _controller.pause();
      }
    } catch (error) {
      debugPrint('No fue posible pausar el canal al minimizar: $error');
    }
  }

  Future<void> _handleForeground() async {
    if (_isClosing || !_isInBackground) {
      return;
    }

    _isInBackground = false;
    final shouldResume = _resumeOnForeground;
    _resumeOnForeground = false;

    if (!shouldResume) {
      return;
    }

    _playbackExpected = true;

    if (_waitingForNetwork) {
      unawaited(_checkNetworkRecovery());
      return;
    }

    _reconnectAttempt = 0;
    _reconnecting = false;

    try {
      setState(() {
        _opening = true;
        _errorMessage = null;
      });

      final recovered = await _recreateController();

      if (!recovered) {
        throw StateError('No se pudo recrear VLC.');
      }

      _resetPlaybackWatchdog();
      _scheduleStartupGuard();
    } catch (error) {
      await _scheduleReconnect(
        'No fue posible recuperar el canal.',
        error: error,
      );
    }
  }

  bool _handleRemoteKey(KeyEvent event) {
    if (event is! KeyDownEvent || _isClosing) {
      return false;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.mediaPlayPause) {
      unawaited(_togglePlayback());
      return true;
    }

    final isActivationKey = key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space;
    final isDirectionKey = key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;

    if (!_controlsVisible && (isActivationKey || isDirectionKey)) {
      _showControls();
      return true;
    }

    return false;
  }

  Future<void> _togglePlayback() async {
    _showControls();

    try {
      if (_controller.value.isPlaying) {
        _playbackExpected = false;
        await _controller.pause();
      } else if (_controller.value.isInitialized) {
        _playbackExpected = true;
        _resetPlaybackWatchdog();
        await _controller.play();
      } else {
        await _initializePlayer();
      }
    } catch (error) {
      await _scheduleReconnect(
        'No fue posible cambiar la reproducción.',
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
        if (!mounted || _isClosing || _errorMessage != null) {
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

    _isClosing = true;
    _controlsTimer?.cancel();
    _startupTimer?.cancel();
    _reconnectTimer?.cancel();
    _recoveryWarmupTimer?.cancel();

    try {
      await _controller.stop();
    } catch (_) {
      // VLC puede estar cerrándose.
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _disposePlayer() async {
    if (_disposeStarted) {
      return;
    }

    _disposeStarted = true;

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

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await DeviceOrientationService.restoreSavedMode();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleRemoteKey);
    _isClosing = true;
    _controlsTimer?.cancel();
    _startupTimer?.cancel();
    _reconnectTimer?.cancel();
    _watchdogTimer?.cancel();
    _networkRecoveryTimer?.cancel();
    _recoveryWarmupTimer?.cancel();
    _controller.removeListener(_onPlayerChanged);
    unawaited(_disposePlayer());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_closePlayer());
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
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
                    placeholder: const ColoredBox(color: Colors.black),
                  ),
                )
              else
                const ColoredBox(color: Colors.black),
              if (_warmingUpAfterRecovery)
                const ColoredBox(color: Colors.black),
              if (_controllerMounted)
                ValueListenableBuilder<VlcPlayerValue>(
                  valueListenable: _controller,
                builder: (context, value, child) {
                  final showLoading = _opening ||
                      _reconnecting ||
                      _warmingUpAfterRecovery ||
                      (value.isBuffering && !value.isPlaying);

                  if (!showLoading || _errorMessage != null) {
                    return const SizedBox.shrink();
                  }

                  return _LiveLoadingOverlay(
                    message: _waitingForNetwork
                        ? 'Sin conexión. Esperando internet...'
                        : _switchingQuality
                            ? 'Cambiando a $_qualityLabel...'
                        : _warmingUpAfterRecovery
                            ? 'Estabilizando señal...'
                        : _stabilizingConnection
                            ? 'Ajustando búfer...'
                        : _reconnecting
                            ? 'Reconectando canal...'
                            : 'Abriendo canal...',
                  );
                },
              ),
              if (_errorMessage != null)
                _LivePlayerError(
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
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: _LiveControls(
                      controller: _controller,
                      title: _displayTitle,
                      qualityLabel:
                          '$_qualityLabel · ${_liveQualityMode.label}',
                      onBack: () {
                        unawaited(_closePlayer());
                      },
                      onPlayPause: () {
                        unawaited(_togglePlayback());
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveControls extends StatelessWidget {
  const _LiveControls({
    required this.controller,
    required this.title,
    required this.qualityLabel,
    required this.onBack,
    required this.onPlayPause,
  });

  final VlcPlayerController controller;
  final String title;
  final String qualityLabel;
  final VoidCallback onBack;
  final VoidCallback onPlayPause;

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
                Color(0xCC000000),
              ],
              stops: [0, 0.3, 0.7, 1],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              children: [
                Row(
                  children: [
                    _LiveRoundButton(
                      icon: Icons.arrow_back_rounded,
                      onPressed: onBack,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xAA17213B),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        qualityLabel,
                        style: const TextStyle(
                          color: Color(0xFFD8E0FF),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xAA000000),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.circle,
                            color: Color(0xFFFF5E69),
                            size: 9,
                          ),
                          SizedBox(width: 7),
                          Text(
                            'EN VIVO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                ValueListenableBuilder<VlcPlayerValue>(
                  valueListenable: controller,
                  builder: (context, value, child) {
                    return _LiveLargeButton(
                      icon: value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      onPressed: onPlayPause,
                    );
                  },
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LiveRoundButton extends StatelessWidget {
  const _LiveRoundButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x99000000),
      shape: const CircleBorder(),
      child: InkWell(
        focusColor: const Color(0x995B7CFF),
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _LiveLargeButton extends StatelessWidget {
  const _LiveLargeButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xBB000000),
      shape: const CircleBorder(),
      child: InkWell(
        autofocus: true,
        focusColor: const Color(0x995B7CFF),
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 76,
          height: 76,
          child: Icon(icon, color: Colors.white, size: 44),
        ),
      ),
    );
  }
}

class _LiveLoadingOverlay extends StatelessWidget {
  const _LiveLoadingOverlay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0x66000000),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xDD111620),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 38,
                height: 38,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LivePlayerError extends StatelessWidget {
  const _LivePlayerError({
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
            constraints: const BoxConstraints(maxWidth: 440),
            margin: const EdgeInsets.all(28),
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: const Color(0xFF111620),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF252C38)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.live_tv_outlined,
                  color: Color(0xFFFF7D8A),
                  size: 50,
                ),
                const SizedBox(height: 18),
                const Text(
                  'No se pudo reproducir',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF98A2B3)),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onClose,
                        child: const Text('REGRESAR'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: onRetry,
                        child: const Text('REINTENTAR'),
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
