import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/domain/auth_session.dart';

enum PreferredAudioLanguage {
  automatic,
  spanish,
  english,
}

enum PlaybackStabilityMode {
  automatic,
  lowLatency,
  unstableConnection,
}

enum LiveQualityMode {
  automatic,
  dataSaver,
  bestQuality,
}

class PlaybackPreferences {
  const PlaybackPreferences({
    this.audioLanguage = PreferredAudioLanguage.automatic,
    this.subtitlesEnabled = false,
    this.autoPlayNextEpisode = true,
    this.stabilityMode = PlaybackStabilityMode.automatic,
    this.liveQualityMode = LiveQualityMode.automatic,
  });

  final PreferredAudioLanguage audioLanguage;
  final bool subtitlesEnabled;
  final bool autoPlayNextEpisode;
  final PlaybackStabilityMode stabilityMode;
  final LiveQualityMode liveQualityMode;

  PlaybackPreferences copyWith({
    PreferredAudioLanguage? audioLanguage,
    bool? subtitlesEnabled,
    bool? autoPlayNextEpisode,
    PlaybackStabilityMode? stabilityMode,
    LiveQualityMode? liveQualityMode,
  }) {
    return PlaybackPreferences(
      audioLanguage: audioLanguage ?? this.audioLanguage,
      subtitlesEnabled: subtitlesEnabled ?? this.subtitlesEnabled,
      autoPlayNextEpisode:
          autoPlayNextEpisode ?? this.autoPlayNextEpisode,
      stabilityMode: stabilityMode ?? this.stabilityMode,
      liveQualityMode: liveQualityMode ?? this.liveQualityMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'audio_language': audioLanguage.name,
      'subtitles_enabled': subtitlesEnabled,
      'auto_play_next_episode': autoPlayNextEpisode,
      'stability_mode': stabilityMode.name,
      'live_quality_mode': liveQualityMode.name,
    };
  }

  factory PlaybackPreferences.fromJson(
    Map<String, dynamic> json,
  ) {
    final languageName =
        json['audio_language']?.toString().trim() ?? '';
    final stabilityName =
        json['stability_mode']?.toString().trim() ?? '';
    final liveQualityName =
        json['live_quality_mode']?.toString().trim() ?? '';

    final language = PreferredAudioLanguage.values.firstWhere(
      (item) => item.name == languageName,
      orElse: () => PreferredAudioLanguage.automatic,
    );
    final stabilityMode = PlaybackStabilityMode.values.firstWhere(
      (item) => item.name == stabilityName,
      orElse: () => PlaybackStabilityMode.automatic,
    );
    final liveQualityMode = LiveQualityMode.values.firstWhere(
      (item) => item.name == liveQualityName,
      orElse: () => LiveQualityMode.automatic,
    );

    return PlaybackPreferences(
      audioLanguage: language,
      subtitlesEnabled: json['subtitles_enabled'] == true,
      autoPlayNextEpisode:
          json['auto_play_next_episode'] != false,
      stabilityMode: stabilityMode,
      liveQualityMode: liveQualityMode,
    );
  }
}

class PlaybackPreferencesService {
  PlaybackPreferencesService._();

  static final PlaybackPreferencesService instance =
      PlaybackPreferencesService._();

  Future<PlaybackPreferences> load(
    AuthSession session,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey(session));

    if (raw == null || raw.trim().isEmpty) {
      return const PlaybackPreferences();
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is Map) {
        return PlaybackPreferences.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {
      // Si el valor quedó corrupto se restauran los predeterminados.
    }

    return const PlaybackPreferences();
  }

  Future<void> save(
    AuthSession session,
    PlaybackPreferences value,
  ) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setString(
      _storageKey(session),
      jsonEncode(value.toJson()),
    );
  }

  Future<void> reset(AuthSession session) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey(session));
  }

  String _storageKey(AuthSession session) {
    final encodedUser = base64Url.encode(
      utf8.encode(session.username.trim().toLowerCase()),
    );

    return 'fdezplay.playback_preferences.$encodedUser';
  }
}

extension PreferredAudioLanguageLabel
    on PreferredAudioLanguage {
  String get label {
    switch (this) {
      case PreferredAudioLanguage.automatic:
        return 'Automático';
      case PreferredAudioLanguage.spanish:
        return 'Español';
      case PreferredAudioLanguage.english:
        return 'Inglés';
    }
  }
}

extension PlaybackStabilityModeConfig on PlaybackStabilityMode {
  String get label {
    switch (this) {
      case PlaybackStabilityMode.automatic:
        return 'Automática';
      case PlaybackStabilityMode.lowLatency:
        return 'Baja latencia';
      case PlaybackStabilityMode.unstableConnection:
        return 'Conexión inestable';
    }
  }

  String get description {
    switch (this) {
      case PlaybackStabilityMode.automatic:
        return 'Equilibra retraso y estabilidad con recuperación automática';
      case PlaybackStabilityMode.lowLatency:
        return 'Menor retraso, recomendado para internet estable';
      case PlaybackStabilityMode.unstableConnection:
        return 'Mayor búfer para aguantar mejor microcortes de internet';
    }
  }

  List<int> get liveCachingLevels {
    switch (this) {
      case PlaybackStabilityMode.automatic:
        return const [8000, 15000, 25000];
      case PlaybackStabilityMode.lowLatency:
        return const [5000, 8000];
      case PlaybackStabilityMode.unstableConnection:
        return const [25000, 35000];
    }
  }

  List<int> get vodCachingLevels {
    switch (this) {
      case PlaybackStabilityMode.automatic:
        return const [15000, 25000, 35000];
      case PlaybackStabilityMode.lowLatency:
        return const [8000, 12000];
      case PlaybackStabilityMode.unstableConnection:
        return const [35000, 45000];
    }
  }

  Duration get liveRecoveryWarmup {
    switch (this) {
      case PlaybackStabilityMode.automatic:
        return const Duration(seconds: 7);
      case PlaybackStabilityMode.lowLatency:
        return const Duration(seconds: 4);
      case PlaybackStabilityMode.unstableConnection:
        return const Duration(seconds: 10);
    }
  }

  Duration get vodRecoveryWarmup {
    switch (this) {
      case PlaybackStabilityMode.automatic:
        return const Duration(seconds: 6);
      case PlaybackStabilityMode.lowLatency:
        return const Duration(seconds: 4);
      case PlaybackStabilityMode.unstableConnection:
        return const Duration(seconds: 10);
    }
  }
}


extension LiveQualityModeConfig on LiveQualityMode {
  String get label {
    switch (this) {
      case LiveQualityMode.automatic:
        return 'Automática';
      case LiveQualityMode.dataSaver:
        return 'Ahorro de datos';
      case LiveQualityMode.bestQuality:
        return 'Mejor calidad';
    }
  }

  String get description {
    switch (this) {
      case LiveQualityMode.automatic:
        return 'Busca un equilibrio cercano a 720p y aprende la resolución real';
      case LiveQualityMode.dataSaver:
        return 'Prioriza la señal con menor resolución conocida';
      case LiveQualityMode.bestQuality:
        return 'Prueba la mayor calidad y corrige etiquetas falsas automáticamente';
    }
  }
}
