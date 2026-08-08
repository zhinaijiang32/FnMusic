class LyricLine {
  const LyricLine({required this.timestamp, required this.text});

  final Duration timestamp;
  final String text;

  static List<LyricLine> parse(String source) {
    final tag = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]');
    final lines = <LyricLine>[];

    for (final rawLine in source.split(RegExp(r'\r?\n'))) {
      final matches = tag.allMatches(rawLine).toList();
      final text = rawLine.replaceAll(tag, '').trim();
      if (matches.isEmpty || text.isEmpty) continue;

      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final fraction = match.group(3) ?? '0';
        final milliseconds =
            int.parse(fraction.padRight(3, '0').substring(0, 3));
        lines.add(LyricLine(
          timestamp: Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          ),
          text: text,
        ));
      }
    }

    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return lines;
  }
}
