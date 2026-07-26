import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/cast_device.dart';

class DlnaDiscoveryService {
  DlnaDiscoveryService._();

  static final DlnaDiscoveryService instance = DlnaDiscoveryService._();

  static final InternetAddress _ssdpAddress =
      InternetAddress('239.255.255.250');

  Future<List<FdezCastDevice>> discover({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final locations = <String, String>{};

    RawDatagramSocket? socket;

    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        ttl: 4,
      );

      socket.broadcastEnabled = true;

      final completed = Completer<void>();
      late final StreamSubscription<RawSocketEvent> subscription;

      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) {
          return;
        }

        Datagram? datagram;

        while ((datagram = socket?.receive()) != null) {
          final response = utf8.decode(
            datagram!.data,
            allowMalformed: true,
          );
          final headers = _parseSsdpHeaders(response);
          final location = headers['location'];

          if (location == null || location.trim().isEmpty) {
            continue;
          }

          locations[location.trim()] = headers['usn'] ?? '';
        }
      });

      final timer = Timer(timeout, () {
        if (!completed.isCompleted) {
          completed.complete();
        }
      });

      for (final st in const [
        'urn:schemas-upnp-org:device:MediaRenderer:1',
        'urn:schemas-upnp-org:service:AVTransport:1',
        'ssdp:all',
      ]) {
        final request = _buildSearchRequest(st);
        socket.send(utf8.encode(request), _ssdpAddress, 1900);
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }

      await completed.future;
      timer.cancel();
      await subscription.cancel();
    } catch (_) {
      // Algunos Android/routers bloquean multicast. En ese caso la lista queda vacía.
    } finally {
      socket?.close();
    }

    final futures = locations.entries.map((entry) {
      return _readDeviceDescription(entry.key, usn: entry.value);
    });

    final devices = <FdezCastDevice>[];

    for (final future in futures) {
      final device = await future;

      if (device != null &&
          devices.every(
            (item) =>
                item.avTransportControlUrl != device.avTransportControlUrl,
          )) {
        devices.add(device);
      }
    }

    devices.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    return devices;
  }

  String _buildSearchRequest(String st) {
    return 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: 239.255.255.250:1900\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 2\r\n'
        'ST: $st\r\n'
        'USER-AGENT: Android/13 UPnP/1.1 FdezPlay/1.0\r\n'
        '\r\n';
  }

  Map<String, String> _parseSsdpHeaders(String response) {
    final headers = <String, String>{};
    final lines = const LineSplitter().convert(response);

    for (final line in lines.skip(1)) {
      final separator = line.indexOf(':');

      if (separator <= 0) {
        continue;
      }

      final key = line.substring(0, separator).trim().toLowerCase();
      final value = line.substring(separator + 1).trim();

      headers[key] = value;
    }

    return headers;
  }

  Future<FdezCastDevice?> _readDeviceDescription(
    String location, {
    String? usn,
  }) async {
    Uri locationUri;

    try {
      locationUri = Uri.parse(location);
    } catch (_) {
      return null;
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);

    try {
      final request = await client.getUrl(locationUri);
      request.headers.set(HttpHeaders.userAgentHeader, 'FdezPlay/1.0');

      final response = await request.close().timeout(
            const Duration(seconds: 8),
          );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final body = await utf8.decodeStream(response);

      if (!body.toLowerCase().contains('mediarenderer') &&
          !body.toLowerCase().contains('avtransport')) {
        return null;
      }

      final avTransportUrl = _extractAvTransportControlUrl(
        locationUri,
        body,
      );

      if (avTransportUrl == null) {
        return null;
      }

      final friendlyName =
          _extractTag(body, 'friendlyName')?.trim() ?? 'Smart TV compatible';

      return FdezCastDevice(
        name: friendlyName.isEmpty ? 'Smart TV compatible' : friendlyName,
        location: locationUri,
        avTransportControlUrl: avTransportUrl,
        manufacturer: _extractTag(body, 'manufacturer'),
        modelName: _extractTag(body, 'modelName'),
        usn: usn,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Uri? _extractAvTransportControlUrl(Uri locationUri, String xml) {
    final blockExpression = RegExp(
      r'<service\b[^>]*>[\s\S]*?<serviceType>\s*urn:schemas-upnp-org:service:AVTransport:1\s*</serviceType>[\s\S]*?</service>',
      caseSensitive: false,
    );

    final match = blockExpression.firstMatch(xml);

    if (match == null) {
      return null;
    }

    final block = match.group(0) ?? '';
    final controlUrl = _extractTag(block, 'controlURL')?.trim();

    if (controlUrl == null || controlUrl.isEmpty) {
      return null;
    }

    final urlBase = _extractTag(xml, 'URLBase')?.trim();

    if (urlBase != null && urlBase.isNotEmpty) {
      try {
        return Uri.parse(urlBase).resolve(controlUrl);
      } catch (_) {
        // Si URLBase viene mal formado, continuamos con locationUri.
      }
    }

    return locationUri.resolve(controlUrl);
  }

  String? _extractTag(String xml, String tag) {
    final expression = RegExp(
      '<$tag[^>]*>([\\s\\S]*?)</$tag>',
      caseSensitive: false,
    );
    final match = expression.firstMatch(xml);

    if (match == null) {
      return null;
    }

    return _decodeXml(match.group(1)?.trim() ?? '');
  }

  String _decodeXml(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }
}
