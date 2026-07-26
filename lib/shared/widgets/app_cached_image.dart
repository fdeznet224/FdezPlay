import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class AppCachedImage extends StatelessWidget {
  const AppCachedImage({
    required this.imageUrl,
    required this.fallback,
    super.key,
    this.placeholder,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
  });

  final String imageUrl;
  final Widget fallback;
  final Widget? placeholder;
  final BoxFit fit;
  final Alignment alignment;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = imageUrl.trim();

    if (normalizedUrl.isEmpty) {
      return fallback;
    }

    return CachedNetworkImage(
      imageUrl: normalizedUrl,
      fit: fit,
      alignment: alignment,
      width: width,
      height: height,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      maxWidthDiskCache: cacheWidth,
      maxHeightDiskCache: cacheHeight,
      fadeInDuration: const Duration(milliseconds: 140),
      fadeOutDuration: const Duration(milliseconds: 80),
      placeholder: (_, _) => placeholder ?? fallback,
      errorWidget: (_, _, _) => fallback,
    );
  }
}
