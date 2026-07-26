import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Mantiene la pantalla encendida mientras hay reproducción activa.
///
/// Se usa solo en los reproductores. Al salir o mandar la app al fondo, se
/// desactiva para no consumir batería innecesariamente.
class ScreenAwakeService {
  const ScreenAwakeService._();

  static bool _enabled = false;

  static Future<void> enable() async {
    if (_enabled) {
      return;
    }

    try {
      await WakelockPlus.enable();
      _enabled = true;
    } catch (error) {
      debugPrint('No fue posible mantener la pantalla encendida: $error');
    }
  }

  static Future<void> disable() async {
    if (!_enabled) {
      return;
    }

    try {
      await WakelockPlus.disable();
      _enabled = false;
    } catch (error) {
      debugPrint('No fue posible liberar el bloqueo de pantalla: $error');
    }
  }
}
