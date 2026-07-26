enum AuthErrorType {
  invalidCredentials,
  serverUnavailable,
}

class AuthResult {
  const AuthResult._({
    required this.success,
    this.server,
    this.data,
    this.message,
    this.errorType,
  });

  final bool success;
  final String? server;
  final Map<String, dynamic>? data;
  final String? message;
  final AuthErrorType? errorType;

  factory AuthResult.success({
    required String server,
    required Map<String, dynamic> data,
  }) {
    return AuthResult._(
      success: true,
      server: server,
      data: data,
    );
  }

  factory AuthResult.failure({
    required String message,
    required AuthErrorType errorType,
  }) {
    return AuthResult._(
      success: false,
      message: message,
      errorType: errorType,
    );
  }
}