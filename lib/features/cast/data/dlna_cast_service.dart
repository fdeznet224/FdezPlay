import 'dart:convert';
import 'dart:io';

import '../domain/cast_device.dart';

class DlnaCastService {
  DlnaCastService._();

  static final DlnaCastService instance = DlnaCastService._();

  Future<void> play({
    required FdezCastDevice device,
    required FdezCastMedia media,
  }) async {
    await _sendSoap(
      device: device,
      action: 'SetAVTransportURI',
      body: '''
<u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
  <InstanceID>0</InstanceID>
  <CurrentURI>${_xml(media.url)}</CurrentURI>
  <CurrentURIMetaData>${_xml(_buildMetadata(media))}</CurrentURIMetaData>
</u:SetAVTransportURI>
''',
    );

    await Future<void>.delayed(const Duration(milliseconds: 350));

    await _sendSoap(
      device: device,
      action: 'Play',
      body: '''
<u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
  <InstanceID>0</InstanceID>
  <Speed>1</Speed>
</u:Play>
''',
    );

    if (!media.isLive && media.startPosition.inSeconds > 5) {
      await Future<void>.delayed(const Duration(milliseconds: 350));

      try {
        await seek(device: device, position: media.startPosition);
      } catch (_) {
        // No todos los televisores aceptan Seek por DLNA.
      }
    }
  }

  Future<void> pause({required FdezCastDevice device}) {
    return _sendSoap(
      device: device,
      action: 'Pause',
      body: '''
<u:Pause xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
  <InstanceID>0</InstanceID>
</u:Pause>
''',
    );
  }

  Future<void> stop({required FdezCastDevice device}) {
    return _sendSoap(
      device: device,
      action: 'Stop',
      body: '''
<u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
  <InstanceID>0</InstanceID>
</u:Stop>
''',
    );
  }

  Future<void> seek({
    required FdezCastDevice device,
    required Duration position,
  }) {
    return _sendSoap(
      device: device,
      action: 'Seek',
      body: '''
<u:Seek xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
  <InstanceID>0</InstanceID>
  <Unit>REL_TIME</Unit>
  <Target>${fdezCastDurationToDlnaTime(position)}</Target>
</u:Seek>
''',
    );
  }

  Future<void> _sendSoap({
    required FdezCastDevice device,
    required String action,
    required String body,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);

    try {
      final envelope = '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope
  xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
  s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    $body
  </s:Body>
</s:Envelope>
''';

      final payload = utf8.encode(envelope);
      final request = await client.postUrl(device.avTransportControlUrl);

      request.headers
        ..set(
          HttpHeaders.contentTypeHeader,
          'text/xml; charset="utf-8"',
        )
        ..set(
          'SOAPACTION',
          '"urn:schemas-upnp-org:service:AVTransport:1#$action"',
        )
        ..set(HttpHeaders.userAgentHeader, 'FdezPlay/1.0')
        ..set(HttpHeaders.contentLengthHeader, payload.length);

      request.add(payload);

      final response = await request.close().timeout(
            const Duration(seconds: 10),
          );

      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DlnaCastException(
          'La TV rechazó la acción $action (${response.statusCode}). $responseBody',
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  String _buildMetadata(FdezCastMedia media) {
    final title = _xml(media.title);
    final url = _xml(media.url);
    final mimeType = _xml(media.mimeType);

    return '''
<DIDL-Lite
  xmlns:dc="http://purl.org/dc/elements/1.1/"
  xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"
  xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">
  <item id="0" parentID="0" restricted="1">
    <dc:title>$title</dc:title>
    <upnp:class>object.item.videoItem</upnp:class>
    <res protocolInfo="http-get:*:$mimeType:*">$url</res>
  </item>
</DIDL-Lite>
''';
  }

  String _xml(String value) {
    return const HtmlEscape(HtmlEscapeMode.element).convert(value);
  }
}

class DlnaCastException implements Exception {
  const DlnaCastException(this.message);

  final String message;

  @override
  String toString() => message;
}
