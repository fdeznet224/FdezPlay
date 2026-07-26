class AuthSession {
  AuthSession({
    required this.server,
    required this.username,
    required this.password,
    required this.userInfo,
    required this.serverInfo,
  });

  String server;
  final String username;
  final String password;
  final Map<String, dynamic> userInfo;
  final Map<String, dynamic> serverInfo;

  factory AuthSession.fromResponse({
    required String server,
    required String username,
    required String password,
    required Map<String, dynamic> data,
  }) {
    return AuthSession(
      server: server,
      username: username,
      password: password,
      userInfo: _toMap(data['user_info']),
      serverInfo: _toMap(data['server_info']),
    );
  }

  static Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return <String, dynamic>{};
  }

  String get status {
    final value = userInfo['status']?.toString().trim();

    if (value == null || value.isEmpty) {
      return 'Desconocido';
    }

    return value;
  }

  bool get isActive {
    return userInfo['auth']?.toString() == '1' &&
        status.toLowerCase() == 'active';
  }

  int get activeConnections {
    return int.tryParse(
          userInfo['active_cons']?.toString() ?? '',
        ) ??
        0;
  }

  int get maxConnections {
    return int.tryParse(
          userInfo['max_connections']?.toString() ?? '',
        ) ??
        0;
  }

  DateTime? get expirationDate {
    final seconds = int.tryParse(
      userInfo['exp_date']?.toString() ?? '',
    );

    if (seconds == null || seconds <= 0) {
      return null;
    }

    return DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
      isUtc: true,
    ).toLocal();
  }

  String get expirationLabel {
    final date = expirationDate;

    if (date == null) {
      return 'Sin fecha';
    }

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  void updateServer(String value) {
    server = value;
  }
}