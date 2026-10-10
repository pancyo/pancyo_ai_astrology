/// 専用予測JSONに内訳がある場合、点数まで数値でたどれるかを確認する。
/// 古い予測JSONには内訳を後付けせず、内訳のあるファイルだけに適用する。
class NineAreaScoreAudit {
  const NineAreaScoreAudit._();

  static void validate(Map<String, dynamic> data, int score) {
    final base = _number(data, 'base');
    final factors = data['factors'];
    if (factors is! List) {
      throw const FormatException('点数内訳の要因一覧がありません。');
    }
    var sum = 0.0;
    for (final factor in factors) {
      if (factor is! Map || factor['label'] is! String) {
        throw const FormatException('点数内訳の要因形式が不正です。');
      }
      sum += _number(factor, 'value');
    }
    _same(_number(data, 'unclamped_adjustment'), sum);

    var applied = sum;
    final limits = data['adjustment_limits'];
    if (limits != null) {
      if (limits is! Map) {
        throw const FormatException('点数内訳の補正上限が不正です。');
      }
      final minimum = _number(limits, 'min');
      final maximum = _number(limits, 'max');
      if (minimum > maximum) {
        throw const FormatException('点数内訳の補正上限が逆転しています。');
      }
      applied = sum.clamp(minimum, maximum).toDouble();
    }
    _same(_number(data, 'adjustment'), applied);
    _same(_number(data, 'adjustment_clamp_delta'), applied - sum);
    final raw = _number(data, 'raw_score');
    _same(raw, base + applied);
    final finalScore = data['final_score'];
    if (finalScore is! int ||
        finalScore != score ||
        finalScore != raw.round().clamp(50, 99).toInt()) {
      throw const FormatException('点数内訳と予測点数が一致しません。');
    }
  }

  static double _number(Map data, String key) {
    final value = data[key];
    if (value is! num || !value.isFinite) {
      throw FormatException('点数内訳の $key が有限の数値ではありません。');
    }
    return value.toDouble();
  }

  static void _same(double actual, double expected) {
    if (!actual.isFinite ||
        !expected.isFinite ||
        (actual - expected).abs() > 0.00000001) {
      throw const FormatException('点数内訳の加減点・上限処理が一致しません。');
    }
  }
}
