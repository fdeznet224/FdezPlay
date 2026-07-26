import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/data/auth_service.dart';
import '../../auth/data/session_storage.dart';
import '../../auth/domain/auth_result.dart';
import '../../auth/domain/auth_session.dart';
import '../../auth/presentation/login_screen.dart';
import '../../device_mode/data/device_mode_storage.dart';
import '../../device_mode/domain/device_mode.dart';
import '../../device_mode/presentation/device_mode_screen.dart';
import '../../home/presentation/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final AuthService _authService = AuthService();
  final SessionStorage _sessionStorage = SessionStorage.instance;
  final DeviceModeStorage _deviceModeStorage = DeviceModeStorage();

  bool _restoringSession = true;
  bool _hasStoredSession = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSession());
  }

  Future<void> _restoreSession() async {
    if (mounted) {
      setState(() {
        _restoringSession = true;
        _errorMessage = null;
      });
    }

    final minimumSplashTime = Future<void>.delayed(
      const Duration(milliseconds: 900),
    );

    StoredSessionCredentials? credentials;

    try {
      credentials = await _sessionStorage.read();
    } catch (_) {
      await minimumSplashTime;

      if (!mounted) {
        return;
      }

      setState(() {
        _restoringSession = false;
        _hasStoredSession = true;
        _errorMessage =
            'No fue posible leer la sesión guardada en este dispositivo.';
      });

      return;
    }

    if (credentials == null) {
      await minimumSplashTime;

      if (!mounted) {
        return;
      }

      await _openLogin();
      return;
    }

    if (mounted) {
      setState(() {
        _hasStoredSession = true;
      });
    }

    final result = await _authService.login(
      username: credentials.username,
      password: credentials.password,
      preferredServer: credentials.server,
    );

    await minimumSplashTime;

    if (!mounted) {
      return;
    }

    if (!result.success) {
      if (result.errorType == AuthErrorType.invalidCredentials) {
        await _sessionStorage.clear();

        if (!mounted) {
          return;
        }

        await _openLogin(
          message:
              'La sesión guardada ya no es válida. Inicia sesión nuevamente.',
        );
        return;
      }

      setState(() {
        _restoringSession = false;
        _errorMessage =
            'No pudimos validar tu sesión. Revisa tu conexión e inténtalo nuevamente.';
      });

      return;
    }

    final session = AuthSession.fromResponse(
      server: result.server!,
      username: credentials.username,
      password: credentials.password,
      data: result.data!,
    );

    if (!session.isActive) {
      await _sessionStorage.clear();

      if (!mounted) {
        return;
      }

      await _openLogin(
        message:
            'La cuenta guardada está inactiva o vencida. Verifica tu suscripción.',
      );
      return;
    }

    try {
      await _sessionStorage.save(session);
    } catch (_) {
      // La sesión ya estaba guardada. El acceso puede continuar aunque no
      // se haya podido actualizar el servidor preferido.
    }

    final mode = await _deviceModeStorage.read();

    if (!mounted) {
      return;
    }

    if (mode == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DeviceModeScreen(
            session: session,
          ),
        ),
      );
      return;
    }

    await _applyOrientation(mode);

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => HomeScreen(
          mode: mode,
          session: session,
        ),
      ),
    );
  }

  Future<void> _applyOrientation(DeviceMode mode) async {
    if (mode == DeviceMode.mobile) {
      await SystemChrome.setPreferredOrientations(
        const [DeviceOrientation.portraitUp],
      );
      return;
    }

    await SystemChrome.setPreferredOrientations(
      const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    );
  }

  Future<void> _openLogin({String? message}) async {
    await SystemChrome.setPreferredOrientations(
      const <DeviceOrientation>[],
    );

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(
          initialMessage: message,
        ),
      ),
    );
  }

  Future<void> _useAnotherAccount() async {
    try {
      await _sessionStorage.clear();
    } catch (_) {
      // Se intenta continuar al Login aunque el almacenamiento no responda.
    }

    if (!mounted) {
      return;
    }

    await _openLogin();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 28,
              vertical: 32,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.play_circle_fill_rounded,
                    size: 96,
                    color: Color(0xFF4F7CFF),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'FdezPlay',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'TV • Películas • Series',
                    style: TextStyle(
                      fontSize: 15,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(height: 30),
                  if (_restoringSession) ...[
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _hasStoredSession
                          ? 'Validando tu sesión...'
                          : 'Preparando FdezPlay...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ] else if (_errorMessage != null) ...[
                    const Icon(
                      Icons.cloud_off_rounded,
                      size: 42,
                      color: Color(0xFFFF7D8A),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFC7CEDA),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: _restoreSession,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('REINTENTAR'),
                      ),
                    ),
                    if (_hasStoredSession) ...[
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _useAnotherAccount,
                        child: const Text('USAR OTRA CUENTA'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
