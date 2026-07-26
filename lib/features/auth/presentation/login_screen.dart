import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/widgets/tv_focusable_surface.dart';

import '../../device_mode/data/device_mode_storage.dart';
import '../../device_mode/domain/device_mode.dart';
import '../../device_mode/presentation/device_mode_screen.dart';
import '../../home/presentation/home_screen.dart';
import '../data/auth_service.dart';
import '../data/session_storage.dart';
import '../domain/auth_session.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    this.initialMessage,
    super.key,
  });

  final String? initialMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  late final FocusNode _usernameFocusNode;
  late final FocusNode _passwordFocusNode;
  late final FocusNode _passwordVisibilityFocusNode;
  late final FocusNode _loginButtonFocusNode;

  final AuthService _authService = AuthService();
  final SessionStorage _sessionStorage = SessionStorage.instance;

  bool _hidePassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    _usernameFocusNode = FocusNode(
      debugLabel: 'login-username',
      onKeyEvent: _handleUsernameKey,
    );
    _passwordFocusNode = FocusNode(
      debugLabel: 'login-password',
      onKeyEvent: _handlePasswordKey,
    );
    _passwordVisibilityFocusNode = FocusNode(
      debugLabel: 'login-password-visibility',
      onKeyEvent: _handlePasswordVisibilityKey,
    );
    _loginButtonFocusNode = FocusNode(
      debugLabel: 'login-button',
      onKeyEvent: _handleLoginButtonKey,
    );

    unawaited(
      SystemChrome.setPreferredOrientations(
        const <DeviceOrientation>[],
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      if (!_usernameFocusNode.hasFocus &&
          !_passwordFocusNode.hasFocus &&
          !_passwordVisibilityFocusNode.hasFocus &&
          !_loginButtonFocusNode.hasFocus) {
        _usernameFocusNode.requestFocus();
      }
    });

    final message = widget.initialMessage?.trim() ?? '';

    if (message.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _passwordVisibilityFocusNode.dispose();
    _loginButtonFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submitLogin() async {
    FocusScope.of(context).unfocus();

    if (_isLoading) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final result = await _authService.login(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) {
      return;
    }

    if (!result.success) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message ?? 'No fue posible iniciar sesión.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        if (_passwordController.text.isNotEmpty) {
          _passwordFocusNode.requestFocus();
        } else {
          _usernameFocusNode.requestFocus();
        }
      });

      return;
    }

    final session = AuthSession.fromResponse(
      server: result.server!,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      data: result.data!,
    );

    try {
      await _sessionStorage.save(session);
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No fue posible guardar la sesión de forma segura. Inténtalo nuevamente.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return;
    }

    if (!mounted) {
      return;
    }

    await _openAuthenticatedApp(session);
  }

  Future<void> _openAuthenticatedApp(AuthSession session) async {
    final mode = await DeviceModeStorage().read();

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

    if (mode == DeviceMode.mobile) {
      await SystemChrome.setPreferredOrientations(
        const [DeviceOrientation.portraitUp],
      );
    } else {
      await SystemChrome.setPreferredOrientations(
        const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      );
    }

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


  void _togglePasswordVisibility() {
    if (_isLoading) {
      return;
    }

    setState(() {
      _hidePassword = !_hidePassword;
    });

    _passwordVisibilityFocusNode.requestFocus();
  }

  bool _isSelectKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;
  }

  Future<void> _showKeyboardFor(FocusNode focusNode) async {
    if (_isLoading) {
      return;
    }

    focusNode.requestFocus();
    await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  Future<void> _hideKeyboard() async {
    await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  KeyEventResult _handleUsernameKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _isLoading) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown) {
      _passwordFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (_isSelectKey(key)) {
      unawaited(_showKeyboardFor(_usernameFocusNode));
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handlePasswordKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _isLoading) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowUp) {
      _usernameFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      unawaited(_hideKeyboard());
      _loginButtonFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      unawaited(_hideKeyboard());
      _passwordVisibilityFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (_isSelectKey(key)) {
      unawaited(_showKeyboardFor(_passwordFocusNode));
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handlePasswordVisibilityKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _isLoading) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowLeft) {
      _passwordFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      _usernameFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      _loginButtonFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (_isSelectKey(key)) {
      _togglePasswordVisibility();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleLoginButtonKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _isLoading) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowUp) {
      _passwordFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (_isSelectKey(key)) {
      unawaited(_submitLogin());
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleLoginRemoteKey(
    FocusNode node,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent || _isLoading) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown) {
      if (_usernameFocusNode.hasFocus) {
        _passwordFocusNode.requestFocus();
        return KeyEventResult.handled;
      }

      if (_passwordFocusNode.hasFocus || _passwordVisibilityFocusNode.hasFocus) {
        unawaited(_hideKeyboard());
        _loginButtonFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      if (_loginButtonFocusNode.hasFocus) {
        _passwordFocusNode.requestFocus();
        return KeyEventResult.handled;
      }

      if (_passwordFocusNode.hasFocus || _passwordVisibilityFocusNode.hasFocus) {
        _usernameFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.arrowRight && _passwordFocusNode.hasFocus) {
      unawaited(_hideKeyboard());
      _passwordVisibilityFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowLeft && _passwordVisibilityFocusNode.hasFocus) {
      _passwordFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (_isSelectKey(key)) {
      if (_usernameFocusNode.hasFocus) {
        unawaited(_showKeyboardFor(_usernameFocusNode));
        return KeyEventResult.handled;
      }

      if (_passwordFocusNode.hasFocus) {
        unawaited(_showKeyboardFor(_passwordFocusNode));
        return KeyEventResult.handled;
      }

      if (_passwordVisibilityFocusNode.hasFocus) {
        _togglePasswordVisibility();
        return KeyEventResult.handled;
      }

      if (_loginButtonFocusNode.hasFocus) {
        unawaited(_submitLogin());
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleLoginRemoteKey,
      child: Scaffold(
        body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 32,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 420,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.play_circle_fill_rounded,
                      size: 82,
                      color: Color(0xFF4F7CFF),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'FdezPlay',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Inicia sesión para continuar',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                    const SizedBox(height: 36),
                    TextFormField(
                      controller: _usernameController,
                      focusNode: _usernameFocusNode,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) {
                        _passwordFocusNode.requestFocus();
                        unawaited(_showKeyboardFor(_passwordFocusNode));
                      },
                      autocorrect: false,
                      enabled: !_isLoading,
                      decoration: InputDecoration(
                        labelText: 'Usuario',
                        prefixIcon: const Icon(
                          Icons.person_outline_rounded,
                        ),
                        border: const OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: kTvFocusNeonColor,
                            width: 3.2,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Ingresa tu usuario';
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordFocusNode,
                      obscureText: _hidePassword,
                      textInputAction: TextInputAction.done,
                      enabled: !_isLoading,
                      onFieldSubmitted: (_) {
                        unawaited(_hideKeyboard());
                        _loginButtonFocusNode.requestFocus();
                      },
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(
                          Icons.lock_outline_rounded,
                        ),
                        suffixIcon: IconButton(
                          focusNode: _passwordVisibilityFocusNode,
                          onPressed: _isLoading ? null : _togglePasswordVisibility,
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                        border: const OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: kTvFocusNeonColor,
                            width: 3.2,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Ingresa tu contraseña';
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      height: 54,
                      child: FilledButton(
                        focusNode: _loginButtonFocusNode,
                        onPressed: _isLoading ? null : _submitLogin,
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                ),
                              )
                            : const Text(
                                'INICIAR SESIÓN',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
