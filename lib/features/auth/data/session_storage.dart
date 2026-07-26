import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/auth_session.dart';

class StoredSessionCredentials {
  const StoredSessionCredentials({
    required this.username,
    required this.password,
    required this.server,
  });

  final String username;
  final String password;
  final String server;
}

class SessionStorage {
  SessionStorage._();

  static final SessionStorage instance = SessionStorage._();

  static const String _usernameKey = 'fdezplay_session_username';
  static const String _passwordKey = 'fdezplay_session_password';
  static const String _serverKey = 'fdezplay_session_server';

  final FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  Future<void> save(AuthSession session) async {
    await Future.wait<void>([
      _storage.write(
        key: _usernameKey,
        value: session.username,
      ),
      _storage.write(
        key: _passwordKey,
        value: session.password,
      ),
      _storage.write(
        key: _serverKey,
        value: session.server,
      ),
    ]);
  }

  Future<StoredSessionCredentials?> read() async {
    final values = await Future.wait<String?>([
      _storage.read(key: _usernameKey),
      _storage.read(key: _passwordKey),
      _storage.read(key: _serverKey),
    ]);

    final username = values[0]?.trim() ?? '';
    final password = values[1] ?? '';
    final server = values[2]?.trim() ?? '';

    if (username.isEmpty || password.isEmpty) {
      if (username.isNotEmpty || password.isNotEmpty || server.isNotEmpty) {
        await clear();
      }

      return null;
    }

    return StoredSessionCredentials(
      username: username,
      password: password,
      server: server,
    );
  }

  Future<bool> hasSession() async {
    return await read() != null;
  }

  Future<void> clear() async {
    await Future.wait<void>([
      _storage.delete(key: _usernameKey),
      _storage.delete(key: _passwordKey),
      _storage.delete(key: _serverKey),
    ]);
  }
}
