import 'package:flutter/material.dart';
import '../models/song.dart';
import 'album_artwork.dart';

class MusicTile extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  final Widget? trailing;

  const MusicTile({
    super.key,
    required this.song,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: AlbumArtwork(url: song.coverUrl, width: 48, height: 48),
      title: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing ?? Text(song.durationText),
      onTap: onTap,
    );
  }
}
