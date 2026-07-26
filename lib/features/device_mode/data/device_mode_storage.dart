import 'package:shared_preferences/shared_preferences.dart';

import '../domain/device_mode.dart';

class DeviceModeStorage {
  static const String _key = 'device_mode';

  Future<void> save(DeviceMode mode) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setString(
      _key,
      mode.name,
    );
  }

  Future<DeviceMode?> read() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_key);

    if (value == null) {
      return null;
    }

    for (final mode in DeviceMode.values) {
      if (mode.name == value) {
        return mode;
      }
    }

    return null;
  }
}