import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/config/app_config.dart';
import '../domain/auth_result.dart';

class AuthService {
  Future<AuthResult> login({
    required String username,
    required String password,
    String? preferredServer,
  }) async {
    AuthResult? invalidCredentialsResult;

    for (final server in _orderedServers(preferredServer)) {
      final result = await _tryServer(
        server: server,
        username: username,
        password: password,
      );

      if (result.success) {
        return result;
      }

      if (result.errorType == AuthErrorType.invalidCredentials) {
        invalidCredentialsResult = result;
      }
    }

    if (invalidCredentialsResult != null) {
      return invalidCredentialsResult;
    }

    return AuthResult.failure(
      message: 'No fue posible conectar con los servidores.',
      errorType: AuthErrorType.serverUnavailable,
    );
  }

  List<String> _orderedServers(String? preferredServer) {
    final servers = <String>[];

    void addServer(String? value) {
      final server = value?.trim() ?? '';

      if (server.isEmpty || servers.contains(server)) {
        return;
      }

      servers.add(server);
    }

    addServer(preferredServer);

    for (final server in AppConfig.servers) {
      addServer(server);
    }

    return servers;
  }

  Future<AuthResult> _tryServer({
    required String server,
    required String username,
    required String password,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = AppConfig.connectionTimeout;

    try {
      final uri = Uri.parse('$server/player_api.php').replace(
        queryParameters: {
          'username': username,
          'password': password,
        },
      );

      final request = await client
          .getUrl(uri)
          .timeout(AppConfig.connectionTimeout);

      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json',
      );

      final response = await request
          .close()
          .timeout(AppConfig.connectionTimeout);

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(AppConfig.connectionTimeout);

      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        return AuthResult.failure(
          message: 'Usuario o contraseña incorrectos.',
          errorType: AuthErrorType.invalidCredentials,
        );
      }

      if (response.statusCode != HttpStatus.ok) {
        return AuthResult.failure(
          message: 'El servidor no está disponible.',
          errorType: AuthErrorType.serverUnavailable,
        );
      }

      final decoded = jsonDecode(body);

      if (decoded is! Map<String, dynamic>) {
        return AuthResult.failure(
          message: 'El servidor devolvió una respuesta inválida.',
          errorType: AuthErrorType.serverUnavailable,
        );
      }

      final userInfo = decoded['user_info'];

      if (userInfo is! Map<String, dynamic>) {
        return AuthResult.failure(
          message: 'Usuario o contraseña incorrectos.',
          errorType: AuthErrorType.invalidCredentials,
        );
      }

      final authenticated = userInfo['auth'].toString() == '1';

      if (!authenticated) {
        return AuthResult.failure(
          message: 'Usuario o contraseña incorrectos.',
          errorType: AuthErrorType.invalidCredentials,
        );
      }

      return AuthResult.success(
        server: server,
        data: decoded,
      );
    } on TimeoutException {
      return AuthResult.failure(
        message: 'El servidor tardó demasiado en responder.',
        errorType: AuthErrorType.serverUnavailable,
      );
    } on SocketException {
      return AuthResult.failure(
        message: 'No fue posible conectar con el servidor.',
        errorType: AuthErrorType.serverUnavailable,
      );
    } on FormatException {
      return AuthResult.failure(
        message: 'El servidor devolvió información inválida.',
        errorType: AuthErrorType.serverUnavailable,
      );
    } catch (_) {
      return AuthResult.failure(
        message: 'Ocurrió un error al conectar con el servidor.',
        errorType: AuthErrorType.serverUnavailable,
      );
    } finally {
      client.close(force: true);
    }
  }
}
