part of 'main.dart';

enum AstroContextStage {
  natal,
  transitPlacements,
  retrogrades,
  moonVoid,
  returnsAndAspects,
  assembly,
}

/// 明示した計測呼出だけで使う。時間・件数以外の入力や結果を保持しない。
class AstrologyContextTiming {
  final _microseconds = <AstroContextStage, int>{};
  final _calls = <AstroContextStage, int>{};
  int _completedContexts = 0;

  void _record(AstroContextStage stage, int microseconds) {
    _microseconds.update(
      stage,
      (value) => value + microseconds,
      ifAbsent: () => microseconds,
    );
    _calls.update(stage, (value) => value + 1, ifAbsent: () => 1);
  }

  Map<String, Object> get safeSnapshot => Map.unmodifiable({
    'context_count': _completedContexts,
    'phase_us': Map<String, int>.unmodifiable({
      for (final stage in AstroContextStage.values)
        stage.name: _microseconds[stage] ?? 0,
    }),
    'phase_calls': Map<String, int>.unmodifiable({
      for (final stage in AstroContextStage.values)
        stage.name: _calls[stage] ?? 0,
    }),
  });
}
