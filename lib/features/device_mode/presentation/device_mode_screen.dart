import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../auth/domain/auth_session.dart';
import '../../home/presentation/home_screen.dart';
import '../../../shared/widgets/tv_focusable_surface.dart';
import '../data/device_mode_storage.dart';
import '../domain/device_mode.dart';

class DeviceModeScreen extends StatefulWidget {
  const DeviceModeScreen({
    required this.session,
    super.key,
  });

  final AuthSession session;

  @override
  State<DeviceModeScreen> createState() => _DeviceModeScreenState();
}

class _DeviceModeScreenState extends State<DeviceModeScreen> {
  final DeviceModeStorage _storage = DeviceModeStorage();

  DeviceMode? _selectedMode;
  bool _isSaving = false;

  Future<void> _continue() async {
    final selectedMode = _selectedMode;

    if (selectedMode == null || _isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    await _storage.save(selectedMode);

    if (selectedMode == DeviceMode.mobile) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => HomeScreen(
          mode: selectedMode,
          session: widget.session,
        ),
      ),
    );
  }

  void _selectMode(DeviceMode mode) {
    setState(() {
      _selectedMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool isWide = constraints.maxWidth >= 700;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 920,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.play_circle_fill_rounded,
                        size: 68,
                        color: Color(0xFF4F7CFF),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        '¿Dónde usarás FdezPlay?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Puedes cambiar esta opción más adelante.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                      const SizedBox(height: 36),
                      if (isWide)
                        Row(
                          children: [
                            Expanded(
                              child: _ModeCard(
                                mode: DeviceMode.mobile,
                                selectedMode: _selectedMode,
                                icon: Icons.smartphone_rounded,
                                title: 'Celular',
                                description: 'Vertical y táctil',
                                autofocus: true,
                                onPressed: _selectMode,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _ModeCard(
                                mode: DeviceMode.tablet,
                                selectedMode: _selectedMode,
                                icon: Icons.tablet_mac_rounded,
                                title: 'Tablet',
                                description: 'Horizontal y táctil',
                                onPressed: _selectMode,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _ModeCard(
                                mode: DeviceMode.television,
                                selectedMode: _selectedMode,
                                icon: Icons.tv_rounded,
                                title: 'TV',
                                description: 'Horizontal y control remoto',
                                onPressed: _selectMode,
                              ),
                            ),
                          ],
                        )
                      else
                        Column(
                          children: [
                            _ModeCard(
                              mode: DeviceMode.mobile,
                              selectedMode: _selectedMode,
                              icon: Icons.smartphone_rounded,
                              title: 'Celular',
                              description: 'Vertical y táctil',
                              autofocus: true,
                              onPressed: _selectMode,
                            ),
                            const SizedBox(height: 14),
                            _ModeCard(
                              mode: DeviceMode.tablet,
                              selectedMode: _selectedMode,
                              icon: Icons.tablet_mac_rounded,
                              title: 'Tablet',
                              description: 'Horizontal y táctil',
                              onPressed: _selectMode,
                            ),
                            const SizedBox(height: 14),
                            _ModeCard(
                              mode: DeviceMode.television,
                              selectedMode: _selectedMode,
                              icon: Icons.tv_rounded,
                              title: 'TV',
                              description: 'Horizontal y control remoto',
                              onPressed: _selectMode,
                            ),
                          ],
                        ),
                      const SizedBox(height: 32),
                      SizedBox(
                        height: 54,
                        child: FilledButton(
                          onPressed: _selectedMode == null || _isSaving
                              ? null
                              : _continue,
                          child: _isSaving
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                  ),
                                )
                              : const Text(
                                  'CONTINUAR',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.selectedMode,
    required this.icon,
    required this.title,
    required this.description,
    required this.onPressed,
    this.autofocus = false,
  });

  final DeviceMode mode;
  final DeviceMode? selectedMode;
  final IconData icon;
  final String title;
  final String description;
  final ValueChanged<DeviceMode> onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final bool isSelected = selectedMode == mode;

    final radius = BorderRadius.circular(18);

    return TvFocusableSurface(
      enabled: true,
      autofocus: autofocus,
      onPressed: () => onPressed(mode),
      borderRadius: radius,
      builder: (context, focused) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(20),
          decoration: tvFocusedDecoration(
            focused: focused,
            backgroundColor: isSelected
                ? const Color(0xFF17213B)
                : const Color(0xFF11151F),
            borderRadius: radius,
            normalBorderColor: isSelected
                ? const Color(0xFF4F7CFF)
                : const Color(0xFF242A36),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF4F7CFF)
                      : const Color(0xFF1D2330),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: isSelected ? 1 : 0,
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF4F7CFF),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}