import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';

class AlbumArtwork extends StatelessWidget {
  const AlbumArtwork({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  final String url;
  final double width;
  final double height;
  final double borderRadius;

  static String normalizeUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('http://')) {
      return 'https://${trimmed.substring('http://'.length)}';
    }
    return trimmed;
  }

  static String displayUrl(String value) {
    final normalized = normalizeUrl(value);
    final uri = Uri.tryParse(normalized);
    if (uri != null &&
        RegExp(r'^p[1-4]\.music\.126\.net$').hasMatch(uri.host)) {
      return '${AppConfig.baseUrl}/api/music/cover?url=${Uri.encodeQueryComponent(normalized)}';
    }
    return normalized;
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = displayUrl(url);
    final fallback = Container(
      width: width,
      height: height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.album, size: width * .42),
    );

    final uri = Uri.tryParse(imageUrl);
    if (imageUrl.isEmpty ||
        uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius), child: fallback);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }
}
