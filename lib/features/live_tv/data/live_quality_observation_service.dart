import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/domain/auth_session.dart';

class LiveQualityObservation {
  const LiveQualityObservation({
    required this.width,
    required this.height,
    required this.updatedAtMilliseconds,
  });

  final int width;
  final int height;
  final int updatedAtMilliseconds;

  int get displayHeight {
    const commonHeights = <int>[
      2160,
      1440,
      1080,
      720,
      576,
      540,
      480,
      360,
      240,
    ];

    var closest = height;
    var smallestDifference = 1000000;

    for (final candidate in commonHeights) {
      final difference = (height - candidate).abs();

      if (difference < smallestDifference) {
        smallestDifference = difference;
        closest = candidate;
      }
    }

    return smallestDifference <= 32 ? closest : height;
  }

  String get resolutionLabel {
    if (height <= 0) {
      return 'Calidad detectada';
    }

    return '${displayHeight}p';
  }

  Map<String, dynamic> toJson() {
    return {
      'width': width,
      'height': height,
      'updated_at': updatedAtMilliseconds,
    };
  }

  factory LiveQualityObservation.fromJson(Map<String, dynamic> json) {
    return LiveQualityObservation(
      width: _readInt(json['width']),
      height: _readInt(json['height']),
      updatedAtMilliseconds: _readInt(json['updated_at']),
    );
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class LiveQualityObservationService {
  LiveQualityObservationService._();

  static final LiveQualityObservationService instance =
      LiveQualityObservationService._();

  static const int _maximumEntries = 1200;

  Future<Map<int, LiveQualityObservation>> load(
    AuthSession session,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey(session));

    if (raw == null || raw.trim().isEmpty) {
      return <int, LiveQualityObservation>{};
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! Map) {
        return <int, LiveQualityObservation>{};
      }

      final observations = <int, LiveQualityObservation>{};

      for (final entry in decoded.entries) {
        final streamId = int.tryParse(entry.key.toString());
        final value = entry.value;

        if (streamId == null || value is! Map) {
          continue;
        }

        final observation = LiveQualityObservation.fromJson(
          Map<String, dynamic>.from(value),
        );

        if (observation.width > 0 && observation.height > 0) {
          observations[streamId] = observation;
        }
      }

      return observations;
    } catch (_) {
      return <int, LiveQualityObservation>{};
    }
  }

  Future<void> record({
    required AuthSession session,
    required int streamId,
    required int width,
    required int height,
  }) async {
    if (streamId <= 0 || width <= 0 || height <= 0) {
      return;
    }

    final observations = await load(session);
    final previous = observations[streamId];

    if (previous != null &&
        previous.width == width &&
        previous.height == height) {
      return;
    }

    observations[streamId] = LiveQualityObservation(
      width: width,
      height: height,
      updatedAtMilliseconds: DateTime.now().millisecondsSinceEpoch,
    );

    if (observations.length > _maximumEntries) {
      final oldestFirst = observations.entries.toList()
        ..sort(
          (a, b) => a.value.updatedAtMilliseconds.compareTo(
            b.value.updatedAtMilliseconds,
          ),
        );

      final removeCount = observations.length - _maximumEntries;

      for (int index = 0; index < removeCount; index++) {
        observations.remove(oldestFirst[index].key);
      }
    }

    final encoded = <String, dynamic>{
      for (final entry in observations.entries)
        entry.key.toString(): entry.value.toJson(),
    };

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey(session),
      jsonEncode(encoded),
    );
  }

  String _storageKey(AuthSession session) {
    final identity = '${session.server.trim().toLowerCase()}|'
        '${session.username.trim().toLowerCase()}';
    final encodedIdentity = base64Url.encode(utf8.encode(identity));

    return 'fdezplay.live_quality_observations.$encodedIdentity';
  }
}
