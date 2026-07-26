import 'package:flutter/material.dart';

import '../data/dlna_cast_service.dart';
import '../data/dlna_discovery_service.dart';
import '../domain/cast_device.dart';

Future<bool> showFdezCastDeviceSheet(
  BuildContext context, {
  required FdezCastMedia media,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CastDeviceSheet(media: media),
  );

  return result ?? false;
}

class _CastDeviceSheet extends StatefulWidget {
  const _CastDeviceSheet({
    required this.media,
  });

  final FdezCastMedia media;

  @override
  State<_CastDeviceSheet> createState() => _CastDeviceSheetState();
}

class _CastDeviceSheetState extends State<_CastDeviceSheet> {
  bool _loading = true;
  bool _connecting = false;
  String? _errorMessage;
  List<FdezCastDevice> _devices = const [];

  @override
  void initState() {
    super.initState();
    _refreshDevices();
  }

  Future<void> _refreshDevices() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final devices = await DlnaDiscoveryService.instance.discover();

      if (!mounted) {
        return;
      }

      setState(() {
        _devices = devices;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _devices = const [];
        _loading = false;
        _errorMessage = 'No fue posible buscar Smart TVs en la red.';
      });
    }
  }

  Future<void> _castTo(FdezCastDevice device) async {
    if (_connecting) {
      return;
    }

    setState(() {
      _connecting = true;
      _errorMessage = null;
    });

    try {
      await DlnaCastService.instance.play(
        device: device,
        media: widget.media,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _connecting = false;
        _errorMessage =
            'La TV fue encontrada, pero no aceptó este contenido. Prueba otra película o verifica que la TV soporte ese formato.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.86;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0B0F18),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A4352),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF6F8CFF),
                            Color(0xFF50D5B7),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x553EF7C4),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.cast_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Transmitir a Smart TV',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Samsung, LG y TVs compatibles con DLNA',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xFF98A2B3),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Buscar de nuevo',
                      onPressed: _loading || _connecting ? null : _refreshDevices,
                      icon: const Icon(Icons.refresh_rounded),
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF261A1E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFF5E69)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFFFFB3BA),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              Flexible(
                child: _buildBody(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                child: Text(
                  'La TV y el celular deben estar en la misma red WiFi. En algunas TVs debes activar Compartir pantalla, DLNA o Media Renderer.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.48),
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Buscando TVs en la red...',
              style: TextStyle(
                color: Color(0xFFD8E0FF),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    if (_devices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.connected_tv_rounded,
              color: Colors.white.withOpacity(0.35),
              size: 58,
            ),
            const SizedBox(height: 12),
            const Text(
              'No se encontraron Smart TVs compatibles',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Verifica que la TV esté encendida, conectada a la misma red y que acepte reproducción DLNA/UPnP.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF98A2B3),
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      itemCount: _devices.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final device = _devices[index];

        return Material(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: _connecting ? null : () => _castTo(device),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF17213B),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: _connecting
                        ? const Padding(
                            padding: EdgeInsets.all(11),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.tv_rounded,
                            color: Color(0xFF50D5B7),
                          ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          device.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF98A2B3),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF98A2B3),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
