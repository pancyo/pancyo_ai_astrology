/// DateTimeを「瞬間」としてUTCへ変換してから、ネイティブの暦引数へ渡す。
/// UTC値からさらに9時間引かない。日本時間の暦を保持するだけの値ではない。
class SwissEphemerisUtcArguments {
  const SwissEphemerisUtcArguments(this.year, this.month, this.day, this.hour);

  factory SwissEphemerisUtcArguments.fromInstant(DateTime instant) {
    final utc = instant.toUtc();
    return SwissEphemerisUtcArguments(
      utc.year,
      utc.month,
      utc.day,
      utc.hour +
          utc.minute / 60 +
          utc.second / 3600 +
          utc.millisecond / 3600000 +
          utc.microsecond / 3600000000,
    );
  }

  final int year, month, day;
  final double hour;
}
