import 'dart:async';
import 'dart:io';

import '../../features/auth/domain/auth_session.dart';

class PlaybackNetworkProbe {
  const PlaybackNetworkProbe._();

  static Future<bool> canReach(
    AuthSession session, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;

    try {
      final server = session.server.replaceFirst(RegExp(r'/+$'), '');
      final uri = Uri.parse('$server/player_api.php').replace(
        queryParameters: {
          'username': session.username,
          'password': session.password,
        },
      );

      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(timeout);
      await response.drain().timeout(timeout);

      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
