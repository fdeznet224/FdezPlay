class FdezCastDevice {
  const FdezCastDevice({
    required this.name,
    required this.location,
    required this.avTransportControlUrl,
    this.manufacturer,
    this.modelName,
    this.usn,
  });

  final String name;
  final Uri location;
  final Uri avTransportControlUrl;
  final String? manufacturer;
  final String? modelName;
  final String? usn;

  String get subtitle {
    final brand = manufacturer?.trim() ?? '';
    final model = modelName?.trim() ?? '';

    if (brand.isEmpty && model.isEmpty) {
      return location.host;
    }

    if (brand.isNotEmpty && model.isNotEmpty) {
      return '$brand · $model';
    }

    return brand.isNotEmpty ? brand : model;
  }

  @override
  String toString() => 'FdezCastDevice($name, $avTransportControlUrl)';
}

class FdezCastMedia {
  const FdezCastMedia({
    required this.title,
    required this.url,
    required this.mimeType,
    this.startPosition = Duration.zero,
    this.isLive = false,
  });

  final String title;
  final String url;
  final String mimeType;
  final Duration startPosition;
  final bool isLive;
}

String fdezCastMimeTypeFromUrl(String url) {
  final lower = url.split('?').first.toLowerCase();

  if (lower.endsWith('.m3u8')) {
    return 'application/vnd.apple.mpegurl';
  }

  if (lower.endsWith('.ts')) {
    return 'video/mp2t';
  }

  if (lower.endsWith('.mkv')) {
    return 'video/x-matroska';
  }

  if (lower.endsWith('.avi')) {
    return 'video/x-msvideo';
  }

  if (lower.endsWith('.mov')) {
    return 'video/quicktime';
  }

  if (lower.endsWith('.webm')) {
    return 'video/webm';
  }

  return 'video/mp4';
}

String fdezCastDurationToDlnaTime(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final hours = safe.inHours.toString().padLeft(2, '0');
  final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');

  return '$hours:$minutes:$seconds';
}
