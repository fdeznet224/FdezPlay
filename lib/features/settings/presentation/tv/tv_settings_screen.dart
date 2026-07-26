import 'dart:async';

import 'package:flutter/material.dart';

import '../../../auth/data/session_storage.dart';
import '../../../auth/domain/auth_session.dart';
import '../../../auth/presentation/login_screen.dart';
import '../../../device_mode/data/device_mode_storage.dart';
import '../../../device_mode/domain/device_mode.dart';
import '../../../device_mode/presentation/device_mode_screen.dart';
import '../../../favorites/data/local_library_service.dart';
import '../../data/playback_preferences_service.dart';

class TvSettingsScreen extends StatefulWidget {
  const TvSettingsScreen({
    required this.session,
    super.key,
  });

  final AuthSession session;

  @override
  State<TvSettingsScreen> createState() {
    return _TvSettingsScreenState();
  }
}

class _TvSettingsScreenState
    extends State<TvSettingsScreen> {
  final PlaybackPreferencesService _preferencesService =
      PlaybackPreferencesService.instance;
  final LocalLibraryService _libraryService =
      LocalLibraryService.instance;
  final DeviceModeStorage _deviceModeStorage =
      DeviceModeStorage();

  PlaybackPreferences _preferences =
      const PlaybackPreferences();
  DeviceMode? _deviceMode;

  int _favoriteCount = 0;
  int _progressCount = 0;

  bool _loading = true;
  bool _savingPreference = false;
  bool _clearingData = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object?>([
        _preferencesService.load(widget.session),
        _deviceModeStorage.read(),
        _libraryService.load(widget.session),
      ]);

      if (!mounted) {
        return;
      }

      final library = results[2] as LocalLibrarySnapshot;

      setState(() {
        _preferences =
            results[0] as PlaybackPreferences;
        _deviceMode = results[1] as DeviceMode?;
        _favoriteCount = library.favorites.length;
        _progressCount = library.progress.length;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _updatePreferences(
    PlaybackPreferences value,
  ) async {
    if (_savingPreference) {
      return;
    }

    setState(() {
      _preferences = value;
      _savingPreference = true;
    });

    try {
      await _preferencesService.save(
        widget.session,
        value,
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingPreference = false;
        });
      }
    }
  }

  Future<void> _selectAudioLanguage() async {
    final selected =
        await showModalBottomSheet<PreferredAudioLanguage>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Material(
            color: const Color(0xFF111620),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(26),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A4352),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Row(
                    children: [
                      Icon(Icons.audiotrack_rounded),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Idioma de audio preferido',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                RadioGroup<PreferredAudioLanguage>(
                  groupValue: _preferences.audioLanguage,
                  onChanged: (value) {
                    if (value != null) {
                      Navigator.of(context).pop(value);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final language
                          in PreferredAudioLanguage.values)
                        RadioListTile<PreferredAudioLanguage>(
                          value: language,
                          title: Text(language.label),
                          subtitle: language ==
                                  PreferredAudioLanguage.automatic
                              ? const Text(
                                  'Usar la pista elegida por el archivo',
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || !mounted) {
      return;
    }

    await _updatePreferences(
      _preferences.copyWith(
        audioLanguage: selected,
      ),
    );
  }

  Future<void> _selectStabilityMode() async {
    final selected =
        await showModalBottomSheet<PlaybackStabilityMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Material(
            color: const Color(0xFF111620),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(26),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A4352),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Row(
                    children: [
                      Icon(Icons.network_check_rounded),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Estabilidad de reproducción',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                RadioGroup<PlaybackStabilityMode>(
                  groupValue: _preferences.stabilityMode,
                  onChanged: (value) {
                    if (value != null) {
                      Navigator.of(context).pop(value);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final mode in PlaybackStabilityMode.values)
                        RadioListTile<PlaybackStabilityMode>(
                          value: mode,
                          title: Text(mode.label),
                          subtitle: Text(mode.description),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || !mounted) {
      return;
    }

    await _updatePreferences(
      _preferences.copyWith(
        stabilityMode: selected,
      ),
    );
  }

  Future<void> _selectLiveQualityMode() async {
    final selected = await showModalBottomSheet<LiveQualityMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Material(
            color: const Color(0xFF111620),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(26),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A4352),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Row(
                    children: [
                      Icon(Icons.hd_rounded),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Calidad de TV en vivo',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                RadioGroup<LiveQualityMode>(
                  groupValue: _preferences.liveQualityMode,
                  onChanged: (value) {
                    if (value != null) {
                      Navigator.of(context).pop(value);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final mode in LiveQualityMode.values)
                        RadioListTile<LiveQualityMode>(
                          value: mode,
                          title: Text(mode.label),
                          subtitle: Text(mode.description),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || !mounted) {
      return;
    }

    await _updatePreferences(
      _preferences.copyWith(
        liveQualityMode: selected,
      ),
    );
  }

  Future<void> _changeExperience() async {
    final confirmed = await _confirm(
      title: 'Cambiar experiencia',
      message:
          'Se abrirá nuevamente el selector de Móvil, Tablet o TV.',
      confirmLabel: 'CONTINUAR',
    );

    if (!confirmed || !mounted) {
      return;
    }

    await Navigator.of(context).pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(
        builder: (_) => DeviceModeScreen(
          session: widget.session,
        ),
      ),
      (route) => false,
    );
  }

  Future<void> _clearProgress() async {
    if (_progressCount == 0 || _clearingData) {
      return;
    }

    final confirmed = await _confirm(
      title: 'Limpiar historial',
      message:
          'Se eliminarán todas las posiciones de Continuar viendo.',
      confirmLabel: 'ELIMINAR',
      destructive: true,
    );

    if (!confirmed) {
      return;
    }

    setState(() {
      _clearingData = true;
    });

    try {
      await _libraryService.clearProgress(widget.session);

      if (!mounted) {
        return;
      }

      setState(() {
        _progressCount = 0;
      });

      _showMessage('Historial eliminado.');
    } finally {
      if (mounted) {
        setState(() {
          _clearingData = false;
        });
      }
    }
  }

  Future<void> _clearFavorites() async {
    if (_favoriteCount == 0 || _clearingData) {
      return;
    }

    final confirmed = await _confirm(
      title: 'Eliminar favoritos',
      message:
          'Se eliminarán todas las películas, series y canales guardados.',
      confirmLabel: 'ELIMINAR',
      destructive: true,
    );

    if (!confirmed) {
      return;
    }

    setState(() {
      _clearingData = true;
    });

    try {
      await _libraryService.clearFavorites(widget.session);

      if (!mounted) {
        return;
      }

      setState(() {
        _favoriteCount = 0;
      });

      _showMessage('Favoritos eliminados.');
    } finally {
      if (mounted) {
        setState(() {
          _clearingData = false;
        });
      }
    }
  }

  Future<void> _resetPlaybackPreferences() async {
    final confirmed = await _confirm(
      title: 'Restablecer reproducción',
      message:
          'Se restaurarán audio automático, estabilidad automática, subtítulos desactivados y siguiente episodio automático.',
      confirmLabel: 'RESTABLECER',
    );

    if (!confirmed) {
      return;
    }

    await _preferencesService.reset(widget.session);

    if (!mounted) {
      return;
    }

    setState(() {
      _preferences = const PlaybackPreferences();
    });

    _showMessage('Preferencias restablecidas.');
  }

  Future<void> _logout() async {
    final confirmed = await _confirm(
      title: 'Cerrar sesión',
      message:
          'Se eliminará el acceso guardado de este dispositivo. Tus favoritos y el progreso permanecerán asociados a esta cuenta.',
      confirmLabel: 'CERRAR SESIÓN',
      destructive: true,
    );

    if (!confirmed || !mounted) {
      return;
    }

    try {
      await SessionStorage.instance.clear();
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'No fue posible eliminar la sesión guardada. Inténtalo nuevamente.',
      );
      return;
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(
        builder: (_) => const LoginScreen(
          initialMessage: 'Sesión cerrada correctamente.',
        ),
      ),
      (route) => false,
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('CANCELAR'),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor:
                          const Color(0xFFC63D4E),
                    )
                  : null,
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String get _serverHost {
    try {
      final host = Uri.parse(widget.session.server).host;
      return host.isEmpty ? widget.session.server : host;
    } catch (_) {
      return widget.session.server;
    }
  }

  String get _deviceModeLabel {
    switch (_deviceMode) {
      case DeviceMode.tablet:
        return 'Tablet';
      case DeviceMode.television:
        return 'TV';
      case DeviceMode.mobile:
      case null:
        return 'Móvil';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                20,
                18,
                20,
                34,
              ),
              children: [
                const Text(
                  'Ajustes de TV',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Cuenta, reproducción, control remoto y almacenamiento',
                  style: TextStyle(
                    color: Color(0xFF98A2B3),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 22),
                _AccountSummaryCard(
                  session: widget.session,
                  serverHost: _serverHost,
                ),
                const SizedBox(height: 28),
                const _SettingsSectionTitle(
                  title: 'Reproducción',
                  subtitle:
                      'Preferencias para TV, películas y series',
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  children: [
                    _SettingsTile(
                      icon: Icons.audiotrack_rounded,
                      title: 'Audio preferido',
                      subtitle:
                          _preferences.audioLanguage.label,
                      onTap: _selectAudioLanguage,
                    ),
                    const Divider(height: 1),
                    _SettingsTile(
                      icon: Icons.network_check_rounded,
                      title: 'Estabilidad de reproducción',
                      subtitle: _preferences.stabilityMode.label,
                      onTap: _selectStabilityMode,
                    ),
                    const Divider(height: 1),
                    _SettingsTile(
                      icon: Icons.hd_rounded,
                      title: 'Calidad de TV en vivo',
                      subtitle: _preferences.liveQualityMode.label,
                      onTap: _selectLiveQualityMode,
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(
                        Icons.subtitles_rounded,
                        color: Color(0xFF6F8CFF),
                      ),
                      title: const Text('Subtítulos por defecto'),
                      subtitle: Text(
                        _preferences.subtitlesEnabled
                            ? 'Activados cuando existan'
                            : 'Desactivados',
                      ),
                      value: _preferences.subtitlesEnabled,
                      onChanged: _savingPreference
                          ? null
                          : (value) {
                              unawaited(
                                _updatePreferences(
                                  _preferences.copyWith(
                                    subtitlesEnabled: value,
                                  ),
                                ),
                              );
                            },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(
                        Icons.skip_next_rounded,
                        color: Color(0xFF6F8CFF),
                      ),
                      title: const Text(
                        'Reproducir siguiente episodio',
                      ),
                      subtitle: const Text(
                        'Continuar automáticamente al terminar',
                      ),
                      value:
                          _preferences.autoPlayNextEpisode,
                      onChanged: _savingPreference
                          ? null
                          : (value) {
                              unawaited(
                                _updatePreferences(
                                  _preferences.copyWith(
                                    autoPlayNextEpisode: value,
                                  ),
                                ),
                              );
                            },
                    ),
                    const Divider(height: 1),
                    _SettingsTile(
                      icon: Icons.restart_alt_rounded,
                      title: 'Restablecer reproducción',
                      subtitle: 'Volver a los valores iniciales',
                      onTap: _resetPlaybackPreferences,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const _SettingsSectionTitle(
                  title: 'Experiencia',
                  subtitle: 'Diseño utilizado por la aplicación',
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  children: [
                    _SettingsTile(
                      icon: Icons.devices_rounded,
                      title: 'Modo de dispositivo',
                      subtitle: _deviceModeLabel,
                      onTap: _changeExperience,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const _SettingsSectionTitle(
                  title: 'Biblioteca local',
                  subtitle:
                      'Datos guardados únicamente en este dispositivo',
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  children: [
                    _SettingsTile(
                      icon: Icons.history_rounded,
                      title: 'Limpiar Continuar viendo',
                      subtitle:
                          '$_progressCount elementos guardados',
                      enabled:
                          _progressCount > 0 && !_clearingData,
                      destructive: true,
                      onTap: _clearProgress,
                    ),
                    const Divider(height: 1),
                    _SettingsTile(
                      icon: Icons.favorite_rounded,
                      title: 'Eliminar favoritos',
                      subtitle:
                          '$_favoriteCount elementos guardados',
                      enabled:
                          _favoriteCount > 0 && !_clearingData,
                      destructive: true,
                      onTap: _clearFavorites,
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                const _SettingsSectionTitle(
                  title: 'Sesión',
                  subtitle: 'Administrar el acceso a la cuenta',
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  children: [
                    _SettingsTile(
                      icon: Icons.logout_rounded,
                      title: 'Cerrar sesión',
                      subtitle: widget.session.username,
                      destructive: true,
                      onTap: _logout,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    'FdezPlay',
                    style: TextStyle(
                      color: Color(0xFF667085),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _AccountSummaryCard extends StatelessWidget {
  const _AccountSummaryCard({
    required this.session,
    required this.serverHost,
  });

  final AuthSession session;
  final String serverHost;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111620),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF232A36),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF17213B),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Color(0xFF6F8CFF),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      session.isActive
                          ? 'Suscripción activa'
                          : 'Suscripción inactiva',
                      style: TextStyle(
                        color: session.isActive
                            ? const Color(0xFF50D5B7)
                            : const Color(0xFFFF7D8A),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SummaryRow(
            label: 'Vencimiento',
            value: session.expirationLabel,
          ),
          const SizedBox(height: 12),
          _SummaryRow(
            label: 'Conexiones',
            value:
                '${session.activeConnections}/${session.maxConnections}',
          ),
          const SizedBox(height: 12),
          _SummaryRow(
            label: 'Servidor',
            value: serverHost,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF98A2B3),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF98A2B3),
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(22);

    return Material(
      color: const Color(0xFF111620),
      clipBehavior: Clip.antiAlias,
      borderRadius: borderRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(
            color: const Color(0xFF232A36),
          ),
        ),
        child: Column(children: children),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? const Color(0xFFFF7D8A)
        : const Color(0xFF6F8CFF);

    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: ListTile(
        enabled: enabled,
        onTap: enabled ? onTap : null,
        leading: Icon(icon, color: color),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: destructive
                ? const Color(0xFFFFA0AA)
                : null,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
        ),
      ),
    );
  }
}
