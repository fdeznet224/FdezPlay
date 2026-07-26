import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PictureInPictureService {
  PictureInPictureService._();

  static const MethodChannel _channel = MethodChannel(
    'com.fdezdev.fdezplay/picture_in_picture',
  );

  static bool? _supported;
  static const String _deviceModeKey = 'device_mode';
  static const String _televisionModeValue = 'television';

  static Future<bool> _isTelevisionMode() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_deviceModeKey) == _televisionModeValue;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isSupported() async {
    if (await _isTelevisionMode()) {
      return false;
    }

    final cached = _supported;
    if (cached != null) {
      return cached;
    }

    try {
      final result = await _channel.invokeMethod<bool>('isSupported');
      _supported = result ?? false;
      return _supported!;
    } on MissingPluginException {
      _supported = false;
      return false;
    } on PlatformException {
      _supported = false;
      return false;
    }
  }

  static Future<void> setActive(
    bool active, {
    int width = 16,
    int height = 9,
  }) async {
    final allowed = !await _isTelevisionMode();

    try {
      await _channel.invokeMethod<void>('setActive', <String, Object>{
        'active': allowed && active,
        'width': width,
        'height': height,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  static Future<bool> enter({
    int width = 16,
    int height = 9,
  }) async {
    if (await _isTelevisionMode()) {
      await setActive(false);
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('enter', <String, Object>{
        'width': width,
        'height': height,
      });
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
