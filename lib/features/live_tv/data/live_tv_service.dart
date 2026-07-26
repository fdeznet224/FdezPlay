import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/config/app_config.dart';
import '../../../shared/models/iptv_category.dart';
import '../../auth/domain/auth_session.dart';
import '../domain/live_channel.dart';

class LiveTvService {
  Future<List<IptvCategory>> loadCategories(
    AuthSession session,
  ) async {
    final data = await _requestWithFallback(
      session: session,
      action: 'get_live_categories',
    );

    return data
        .map(IptvCategory.fromJson)
        .where(
          (category) =>
              category.id.isNotEmpty &&
              category.name.trim().isNotEmpty,
        )
        .toList();
  }

  Future<List<LiveChannel>> loadChannels({
    required AuthSession session,
    required String categoryId,
  }) async {
    final data = await _requestWithFallback(
      session: session,
      action: 'get_live_streams',
      additionalParameters: {
        'category_id': categoryId,
      },
    );

    return _parseChannels(data);
  }

  Future<List<LiveChannel>> loadAllChannels({
    required AuthSession session,
  }) async {
    final data = await _requestWithFallback(
      session: session,
      action: 'get_live_streams',
    );

    return _parseChannels(data);
  }

  List<LiveChannel> _parseChannels(
    List<Map<String, dynamic>> data,
  ) {
    final channels = data
        .map(LiveChannel.fromJson)
        .where((channel) => channel.isValid)
        .toList();

    channels.sort((first, second) {
      return first.order.compareTo(second.order);
    });

    return channels;
  }

  Future<List<Map<String, dynamic>>> _requestWithFallback({
    required AuthSession session,
    required String action,
    Map<String, String>? additionalParameters,
  }) async {
    Object? lastError;

    for (final server in _serverOrder(session.server)) {
      try {
        final response = await _requestServer(
          server: server,
          session: session,
          action: action,
          additionalParameters: additionalParameters,
        );

        session.updateServer(server);

        return response;
      } catch (error) {
        lastError = error;
      }
    }

    throw Exception(
      'No fue posible conectar con los servidores. $lastError',
    );
  }

  List<String> _serverOrder(String activeServer) {
    return {
      activeServer,
      ...AppConfig.servers,
    }.where((server) => server.trim().isNotEmpty).toList();
  }

  Future<List<Map<String, dynamic>>> _requestServer({
    required String server,
    required AuthSession session,
    required String action,
    Map<String, String>? additionalParameters,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = AppConfig.connectionTimeout;

    try {
      final parameters = <String, String>{
        'username': session.username,
        'password': session.password,
        'action': action,
        ...?additionalParameters,
      };

      final uri = Uri.parse(
        '$server/player_api.php',
      ).replace(
        queryParameters: parameters,
      );

      final request = await client
          .getUrl(uri)
          .timeout(AppConfig.connectionTimeout);

      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json',
      );

      request.headers.set(
        HttpHeaders.userAgentHeader,
        'FdezPlay/1.0',
      );

      final response = await request
          .close()
          .timeout(AppConfig.connectionTimeout);

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(AppConfig.connectionTimeout);

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Error HTTP ${response.statusCode}',
        );
      }

      if (body.trim().isEmpty) {
        throw const FormatException(
          'El servidor devolvió una respuesta vacía.',
        );
      }

      final decoded = jsonDecode(body);

      if (decoded is! List) {
        throw const FormatException(
          'La respuesta del servidor no es una lista.',
        );
      }

      return decoded
          .whereType<Map>()
          .map(
            (item) => Map<String, dynamic>.from(item),
          )
          .toList();
    } on TimeoutException {
      throw Exception(
        'El servidor tardó demasiado en responder.',
      );
    } on SocketException {
      throw Exception(
        'No fue posible conectar con el servidor.',
      );
    } finally {
      client.close(force: true);
    }
  }
}