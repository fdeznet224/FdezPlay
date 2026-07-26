import 'package:flutter/services.dart';

import '../../features/device_mode/data/device_mode_storage.dart';
import '../../features/device_mode/domain/device_mode.dart';

class DeviceOrientationService {
  DeviceOrientationService._();

  static final DeviceModeStorage _storage = DeviceModeStorage();

  static Future<void> restoreSavedMode() async {
    DeviceMode? mode;

    try {
      mode = await _storage.read();
    } catch (_) {
      mode = DeviceMode.mobile;
    }

    if (mode == DeviceMode.tablet ||
        mode == DeviceMode.television) {
      await SystemChrome.setPreferredOrientations(
        const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      );
      return;
    }

    await SystemChrome.setPreferredOrientations(
      const [DeviceOrientation.portraitUp],
    );
  }
}
