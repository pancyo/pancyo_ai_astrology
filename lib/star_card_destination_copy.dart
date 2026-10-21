import 'app_language.dart';

/// Localizes the app-authored question prefilled when a decade card opens the
/// reading navigator. This changes display copy only; the decade data and
/// forecast inputs remain untouched.
String starCardDecadeQuestion({
  required int decadeStart,
  required AppLanguage language,
}) {
  if (decadeStart < 0 || decadeStart > 80 || decadeStart % 10 != 0) {
    throw ArgumentError.value(decadeStart, 'decadeStart');
  }

  if (language == AppLanguage.ja) {
    return '${decadeStart}代の人生の流れを、仕事・恋愛・お金の順にもう少し詳しく見て';
  }

  final decade = switch (decadeStart) {
    0 => 'ages 0–9',
    10 => 'the teens',
    _ => 'your ${decadeStart}s',
  };
  return 'Tell me more about the life themes of $decade, focusing on work, love, and money in that order.';
}
