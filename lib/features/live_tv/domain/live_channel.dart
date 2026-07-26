class LiveChannel {
  const LiveChannel({
    required this.streamId,
    required this.name,
    required this.iconUrl,
    required this.categoryId,
    required this.epgChannelId,
    required this.order,
    required this.hasArchive,
    required this.archiveDuration,
  });

  final int streamId;
  final String name;
  final String iconUrl;
  final String categoryId;
  final String epgChannelId;
  final int order;
  final bool hasArchive;
  final int archiveDuration;

  factory LiveChannel.fromJson(Map<String, dynamic> json) {
    return LiveChannel(
      streamId: int.tryParse(
            json['stream_id']?.toString() ?? '',
          ) ??
          0,
      name: json['name']?.toString().trim() ?? 'Canal sin nombre',
      iconUrl: json['stream_icon']?.toString().trim() ?? '',
      categoryId: json['category_id']?.toString() ?? '',
      epgChannelId: json['epg_channel_id']?.toString() ?? '',
      order: int.tryParse(
            json['num']?.toString() ?? '',
          ) ??
          0,
      hasArchive: json['tv_archive']?.toString() == '1',
      archiveDuration: int.tryParse(
            json['tv_archive_duration']?.toString() ?? '',
          ) ??
          0,
    );
  }

  bool get isValid {
    return streamId > 0 && name.isNotEmpty;
  }
}