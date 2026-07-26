import 'dart:io';

import 'package:flutter/services.dart';

class DownloadForegroundService {
  DownloadForegroundService._();

  static const MethodChannel _channel = MethodChannel(
    'com.fdezdev.fdezplay/background_download',
  );

  static Future<void> start({int active = 1}) async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      await _channel.invokeMethod<bool>('start', <String, Object?>{
        'active': active,
      });
    } catch (_) {
      // La descarga Dart continúa aunque el servicio nativo no pueda iniciarse.
    }
  }

  static Future<void> update({int active = 1}) async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      await _channel.invokeMethod<bool>('update', <String, Object?>{
        'active': active,
      });
    } catch (_) {
      // Evita romper la descarga por errores de canal nativo.
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (_) {
      // No se propaga el error porque el cierre del servicio es auxiliar.
    }
  }
}
