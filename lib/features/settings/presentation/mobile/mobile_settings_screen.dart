import 'dart:async';

import 'package:flutter/material.dart';

import '../../../auth/data/session_storage.dart';
import '../../../auth/domain/auth_session.dart';
import '../../../auth/presentation/login_screen.dart';
import '../../../device_mode/data/device_mode_storage.dart';
import '../../../device_mode/domain/device_mode.dart';
import '../../../device_mode/presentation/device_mode_screen.dart';
import '../../../downloads/data/offline_download_service.dart';
import '../../../downloads/presentation/mobile/mobile_downloads_screen.dart';
import '../../../favorites/data/local_library_service.dart';
import '../../../../shared/widgets/tv_focusable_surface.dart';
import '../../data/playback_preferences_service.dart';

class MobileSettingsScreen extends StatefulWidget {
  const MobileSettingsScreen({
    required this.session,
    this.enableTvRemoteNavigation = false,
    super.key,
  });

  final AuthSession session;
  final bool enableTvRemoteNavigation;

  @override
  State<MobileSettingsScreen> createState() {
    return _MobileSettingsScreenState();
  }
}

class _MobileSettingsScreenState
    extends State<MobileSettingsScreen> {
  final PlaybackPreferencesService _preferencesService =
      PlaybackPreferencesService.instance;
  final LocalLibraryService _libraryService =
      LocalLibraryService.instance;
  final OfflineDownloadService _downloadService =
      OfflineDownloadService.instance;
  final DeviceModeStorage _deviceModeStorage =
      DeviceModeStorage();

  PlaybackPreferences _preferences =
      const PlaybackPreferences();
  DeviceMode? _deviceMode;

  int _favoriteCount = 0;
  int _progressCount = 0;
  int _downloadCount = 0;
  int _downloadBytes = 0;

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
        _downloadService.loadDownloads(widget.session),
      ]);

      if (!mounted) {
        return;
      }

      final library = results[2] as LocalLibrarySnapshot;
      final downloads = results[3] as List<OfflineDownloadEntry>;
      final downloadBytes = downloads.fold<int>(
        0,
        (total, item) => total + item.sizeBytes,
      );

      setState(() {
        _preferences =
            results[0] as PlaybackPreferences;
        _deviceMode = results[1] as DeviceMode?;
        _favoriteCount = library.favorites.length;
        _progressCount = library.progress.length;
        _downloadCount = downloads.length;
        _downloadBytes = downloadBytes;
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

  Future<void> _openDownloads() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MobileDownloadsScreen(
          session: widget.session,
          enableTvRemoteNavigation: widget.enableTvRemoteNavigation,
        ),
      ),
    );

    if (mounted) {
      unawaited(_load());
    }
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

  String get _downloadsSubtitle {
    if (_downloadCount == 0) {
      return 'Sin contenido descargado';
    }

    return '$_downloadCount elementos · ${_formatBytes(_downloadBytes)}';
  }


  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return SafeArea(
      bottom: false,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF07101F),
              Color(0xFF090D17),
              Color(0xFF05070D),
            ],
          ),
        ),
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : ListView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  20,
                  18,
                  20,
                  28 + bottomPadding,
                ),
                children: [
                  _SettingsHeaderCard(
                    session: widget.session,
                    serverHost: _serverHost,
                    deviceModeLabel: _deviceModeLabel,
                  ),
                  const SizedBox(height: 18),
                  _SettingsStatsGrid(
                    favoriteCount: _favoriteCount,
                    progressCount: _progressCount,
                    downloadCount: _downloadCount,
                  ),
                  const SizedBox(height: 26),
                  const _PremiumSectionTitle(
                    title: 'Reproducción',
                    subtitle: 'Ajusta audio, subtítulos y estabilidad.',
                  ),
                  const SizedBox(height: 12),
                  _PremiumSettingsCard(
                    children: [
                      _PremiumActionTile(
                        icon: Icons.audiotrack_rounded,
                        title: 'Audio preferido',
                        subtitle: _preferences.audioLanguage.label,
                        accentColor: const Color(0xFF7C8CFF),
                        remoteNavigation: widget.enableTvRemoteNavigation,
                        onTap: _selectAudioLanguage,
                      ),
                      _PremiumActionTile(
                        icon: Icons.network_check_rounded,
                        title: 'Estabilidad de reproducción',
                        subtitle: _preferences.stabilityMode.label,
                        accentColor: const Color(0xFF50D5B7),
                        remoteNavigation: widget.enableTvRemoteNavigation,
                        onTap: _selectStabilityMode,
                      ),
                      _PremiumActionTile(
                        icon: Icons.hd_rounded,
                        title: 'Calidad de TV en vivo',
                        subtitle: _preferences.liveQualityMode.label,
                        accentColor: const Color(0xFFFFB86B),
                        remoteNavigation: widget.enableTvRemoteNavigation,
                        onTap: _selectLiveQualityMode,
                      ),
                      _PremiumSwitchTile(
                        icon: Icons.subtitles_rounded,
                        title: 'Subtítulos por defecto',
                        subtitle: _preferences.subtitlesEnabled
                            ? 'Activados cuando existan pistas disponibles'
                            : 'Desactivados al iniciar reproducción',
                        value: _preferences.subtitlesEnabled,
                        enabled: !_savingPreference,
                        remoteNavigation: widget.enableTvRemoteNavigation,
                        onChanged: (value) {
                          unawaited(
                            _updatePreferences(
                              _preferences.copyWith(
                                subtitlesEnabled: value,
                              ),
                            ),
                          );
                        },
                      ),
                      _PremiumSwitchTile(
                        icon: Icons.skip_next_rounded,
                        title: 'Siguiente episodio',
                        subtitle: _preferences.autoPlayNextEpisode
                            ? 'Reproduce automáticamente el siguiente capítulo'
                            : 'Pregunta antes de continuar',
                        value: _preferences.autoPlayNextEpisode,
                        enabled: !_savingPreference,
                        remoteNavigation: widget.enableTvRemoteNavigation,
                        onChanged: (value) {
                          unawaited(
                            _updatePreferences(
                              _preferences.copyWith(
                                autoPlayNextEpisode: value,
                              ),
                            ),
                          );
                        },
                      ),
                      _PremiumActionTile(
                        icon: Icons.restart_alt_rounded,
                        title: 'Restablecer reproducción',
                        subtitle: 'Volver a los valores recomendados',
                        accentColor: const Color(0xFF98A2B3),
                        remoteNavigation: widget.enableTvRemoteNavigation,
                        onTap: _resetPlaybackPreferences,
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  const _PremiumSectionTitle(
                    title: 'Experiencia',
                    subtitle: 'Modo de pantalla y comportamiento de la app.',
                  ),
                  const SizedBox(height: 12),
                  _PremiumSettingsCard(
                    children: [
                      _PremiumActionTile(
                        icon: Icons.devices_rounded,
                        title: 'Modo de dispositivo',
                        subtitle: _deviceModeLabel,
                        accentColor: const Color(0xFF7C8CFF),
                        remoteNavigation: widget.enableTvRemoteNavigation,
                        onTap: _changeExperience,
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  const _PremiumSectionTitle(
                    title: 'Biblioteca local',
                    subtitle: 'Datos guardados en este dispositivo.',
                  ),
                  const SizedBox(height: 12),
                  _PremiumSettingsCard(
                    children: [
                      if (!widget.enableTvRemoteNavigation) ...[
                        _PremiumActionTile(
                          icon: Icons.download_for_offline_rounded,
                          title: 'Mis descargas',
                          subtitle: _downloadsSubtitle,
                          accentColor: const Color(0xFF50D5B7),
                          remoteNavigation: widget.enableTvRemoteNavigation,
                          onTap: _openDownloads,
                        ),
                      ],
                      _PremiumActionTile(
                        icon: Icons.history_rounded,
                        title: 'Limpiar Continuar viendo',
                        subtitle: '$_progressCount elementos guardados',
                        accentColor: const Color(0xFFFFB86B),
                        destructive: true,
                        enabled: _progressCount > 0 && !_clearingData,
                        remoteNavigation: widget.enableTvRemoteNavigation,
                        onTap: _clearProgress,
                      ),
                      _PremiumActionTile(
                        icon: Icons.favorite_rounded,
                        title: 'Eliminar favoritos',
                        subtitle: '$_favoriteCount elementos guardados',
                        accentColor: const Color(0xFFFF7D8A),
                        destructive: true,
                        enabled: _favoriteCount > 0 && !_clearingData,
                        remoteNavigation: widget.enableTvRemoteNavigation,
                        onTap: _clearFavorites,
                      ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  const _PremiumSectionTitle(
                    title: 'Cuenta',
                    subtitle: 'Sesión actual y acceso guardado.',
                  ),
                  const SizedBox(height: 12),
                  _PremiumSettingsCard(
                    children: [
                      _PremiumActionTile(
                        icon: Icons.logout_rounded,
                        title: 'Cerrar sesión',
                        subtitle: widget.session.username,
                        accentColor: const Color(0xFFFF7D8A),
                        destructive: true,
                        remoteNavigation: widget.enableTvRemoteNavigation,
                        onTap: _logout,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const Center(
                    child: Text(
                      'FdezPlay',
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) {
    return '0 MB';
  }

  final mb = bytes / (1024 * 1024);

  if (mb < 1024) {
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }

  final gb = mb / 1024;
  return '${gb.toStringAsFixed(gb >= 10 ? 1 : 2)} GB';
}

class _SettingsHeaderCard extends StatelessWidget {
  const _SettingsHeaderCard({
    required this.session,
    required this.serverHost,
    required this.deviceModeLabel,
  });

  final AuthSession session;
  final String serverHost;
  final String deviceModeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF18213A),
            Color(0xFF101726),
            Color(0xFF0C111D),
          ],
        ),
        border: Border.all(
          color: const Color(0xFF26395F),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 26,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF5878FF),
                      Color(0xFF8C5CFF),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ajustes',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      session.username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB7C2D5),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: session.isActive
                      ? const Color(0x2232D6A2)
                      : const Color(0x22FF7D8A),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: session.isActive
                        ? const Color(0xFF50D5B7)
                        : const Color(0xFFFF7D8A),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: session.isActive
                            ? const Color(0xFF50D5B7)
                            : const Color(0xFFFF7D8A),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      session.isActive ? 'Activa' : 'Inactiva',
                      style: TextStyle(
                        color: session.isActive
                            ? const Color(0xFFB8FFF0)
                            : const Color(0xFFFFCDD4),
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _HeaderPill(
                icon: Icons.event_available_rounded,
                label: 'Vence',
                value: session.expirationLabel,
              ),
              _HeaderPill(
                icon: Icons.link_rounded,
                label: 'Conexiones',
                value:
                    '${session.activeConnections}/${session.maxConnections}',
              ),
              _HeaderPill(
                icon: Icons.devices_rounded,
                label: 'Modo',
                value: deviceModeLabel,
              ),
              _HeaderPill(
                icon: Icons.dns_rounded,
                label: 'Servidor',
                value: serverHost,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x55101627),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF263247)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF7C8CFF), size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8D98AA),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsStatsGrid extends StatelessWidget {
  const _SettingsStatsGrid({
    required this.favoriteCount,
    required this.progressCount,
    required this.downloadCount,
  });

  final int favoriteCount;
  final int progressCount;
  final int downloadCount;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _MiniStatCard(
        icon: Icons.favorite_rounded,
        label: 'Favoritos',
        value: '$favoriteCount',
        color: const Color(0xFFFF7D8A),
      ),
      _MiniStatCard(
        icon: Icons.play_circle_rounded,
        label: 'Continuar',
        value: '$progressCount',
        color: const Color(0xFF6F8CFF),
      ),
      _MiniStatCard(
        icon: Icons.download_done_rounded,
        label: 'Descargas',
        value: '$downloadCount',
        color: const Color(0xFF50D5B7),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 380) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                SizedBox(
                  width: double.infinity,
                  child: cards[i],
                ),
                if (i != cards.length - 1)
                  const SizedBox(height: 10),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              Expanded(child: cards[i]),
              if (i != cards.length - 1)
                const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 108,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111723),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF232B3A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF98A2B3),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PremiumSectionTitle extends StatelessWidget {
  const _PremiumSectionTitle({
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
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF98A2B3),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _PremiumSettingsCard extends StatelessWidget {
  const _PremiumSettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF101620),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF202A3A)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 74,
                endIndent: 18,
                color: Color(0xFF1E2633),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _PremiumActionTile extends StatelessWidget {
  const _PremiumActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.remoteNavigation,
    required this.onTap,
    this.enabled = true,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final bool remoteNavigation;
  final VoidCallback onTap;
  final bool enabled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final content = _PremiumTileBody(
      icon: icon,
      title: title,
      subtitle: subtitle,
      accentColor: accentColor,
      enabled: enabled,
      destructive: destructive,
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Color(0xFF8D98AA),
      ),
    );

    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: TvFocusableSurface(
        enabled: remoteNavigation && enabled,
        borderRadius: BorderRadius.circular(22),
        onPressed: onTap,
        builder: (context, focused) {
          return InkWell(
            canRequestFocus: false,
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(22),
            child: content,
          );
        },
      ),
    );
  }
}

class _PremiumSwitchTile extends StatelessWidget {
  const _PremiumSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.remoteNavigation,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final bool remoteNavigation;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    void toggle() {
      if (enabled) {
        onChanged(!value);
      }
    }

    final content = _PremiumTileBody(
      icon: icon,
      title: title,
      subtitle: subtitle,
      accentColor: const Color(0xFF7C8CFF),
      enabled: enabled,
      trailing: Switch.adaptive(
        value: value,
        activeColor: const Color(0xFF6F8CFF),
        onChanged: enabled ? onChanged : null,
      ),
    );

    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: TvFocusableSurface(
        enabled: remoteNavigation && enabled,
        borderRadius: BorderRadius.circular(22),
        onPressed: toggle,
        builder: (context, focused) {
          return InkWell(
            canRequestFocus: false,
            onTap: toggle,
            borderRadius: BorderRadius.circular(22),
            child: content,
          );
        },
      ),
    );
  }
}

class _PremiumTileBody extends StatelessWidget {
  const _PremiumTileBody({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.trailing,
    this.enabled = true,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final Widget trailing;
  final bool enabled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final titleColor = destructive
        ? const Color(0xFFFFB7BF)
        : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.16),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: accentColor.withOpacity(0.35)),
            ),
            child: Icon(
              icon,
              color: accentColor,
              size: 23,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF98A2B3),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}
