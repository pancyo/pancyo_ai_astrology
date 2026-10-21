import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'nine_area_summary.dart';
import 'nine_area_validation.dart';

/// 相談JSONの正午9項目を、現在の登録時刻で新たに固定するPC検証用。
/// 原JSONの発行時刻や本人・出生事実の正しさを復元・証明するものではない。
/// SHA256は同じローカル記録の整合性確認用で、匿名化・第三者時刻証明ではない。
class RegisteredNineAreaValidation {
  const RegisteredNineAreaValidation._();

  static const forecastSchema = 'pancyo_registered_nine_area_forecast_v1';
  static const batchSchema = 'pancyo_registered_nine_area_forecast_batch_v1';
  static const outcomeSchema = 'pancyo_registered_nine_area_outcome_v1';
  static const evaluationSchema = 'pancyo_registered_nine_area_evaluation_v1';
  static const summarySchema = 'pancyo_registered_nine_area_summary_v1';
  static const issuedBasis = 'consult_registration';
  static const _daySchema = 'pancyo_astrology_daily_consult_v4';
  static const _monthSchema = 'pancyo_astrology_external_consult_v3';
  static const _daySnapshotSchema = 'pancyo_nine_area_daily_consult_v1';
  static const _periodSnapshotSchema = 'pancyo_nine_area_period_consult_v1';
  static const _jstOffset = Duration(hours: 9);
  static const _limitation =
      '端末時計で新たに登録した予測。原相談JSONの発行時刻を復元した記録ではない。'
      'ハッシュだけでは第三者時刻証明、匿名化、本人評価や出生情報の真偽、予測力を保証しない。';

  static Map<String, Object?> registerConsult(
    Map<String, dynamic> source, {
    required DateTime registeredAt,
    required String subjectId,
    required String sourceSha256,
  }) {
    final subject = _subject(subjectId);
    final sourceDigest = _digest(sourceSha256);
    final registered = _formatJst(registeredAt);
    final generatedRaw = _string(source, 'generated_at');
    final sourceSchema = _string(source, 'schema');
    final profile = _map(source['profile'], 'profile');
    final profileDigest = canonicalSha256({
      for (final key in ['birth_date', 'birth_time', 'birth_place'])
        key: _string(profile, key),
    });
    late final List<Map<String, dynamic>> snapshots;
    if (sourceSchema == _daySchema) {
      snapshots = [_map(source['nine_area_daily'], 'nine_area_daily')];
    } else if (sourceSchema == _monthSchema) {
      final period = _map(source['period'], 'period');
      final ninePeriod = _map(source['nine_area_period'], 'nine_area_period');
      if (period['type'] != 'month' ||
          ninePeriod['period_type'] != 'month' ||
          ninePeriod['schema'] != _periodSnapshotSchema) {
        throw const FormatException('月の相談JSONだけを日別予測へ登録できます。');
      }
      final raw = ninePeriod['daily_samples'];
      if (raw is! List || raw.isEmpty) {
        throw const FormatException('月の日別9項目がありません。');
      }
      snapshots = [for (final item in raw) _map(item, 'daily_samples')];
      _validateMonthDays(snapshots);
      for (final snapshot in snapshots) {
        if (snapshot['model_version'] != ninePeriod['model_version'] ||
            snapshot['ephemeris_time_contract'] !=
                ninePeriod['ephemeris_time_contract']) {
          throw const FormatException('月の日別9項目と期間の計算版が一致しません。');
        }
      }
    } else {
      throw const FormatException('対応する日v4または月v3の相談JSONではありません。');
    }

    final forecasts = <Map<String, Object?>>[];
    final excluded = <Map<String, Object?>>[];
    final dates = <String>{};
    for (final snapshot in snapshots) {
      if (snapshot['schema'] != _daySnapshotSchema) {
        throw const FormatException('正午の日別9項目スキーマが違います。');
      }
      final target = _string(snapshot, 'target_date_jst');
      final day = _day(target);
      if (!dates.add(target)) {
        throw const FormatException('同じ日の日別9項目が重複しています。');
      }
      if (!registeredAt.toUtc().isBefore(day.subtract(_jstOffset))) {
        excluded.add({
          'target_date_jst': target,
          'reason': 'target_day_already_started',
        });
        continue;
      }
      final forecast = _forecast(snapshot, registered);
      final wrapper = <String, Object?>{
        'schema': forecastSchema,
        'subject_id': subject,
        'profile_sha256': profileDigest,
        'target_date_jst': target,
        'registered_at_jst_device_clock': registered,
        'issued_basis': issuedBasis,
        'source_schema': sourceSchema,
        // Offsetなしのgenerated_atも、そのまま原文として保持する。
        'source_generated_at_raw': generatedRaw,
        'source_sha256': sourceDigest,
        'calculation_context': _context(source, snapshot),
        'forecast': forecast,
        'limitation': _limitation,
      };
      _seal(wrapper);
      validateForecast(wrapper);
      forecasts.add(wrapper);
    }
    return {
      'schema': batchSchema,
      'subject_id': subject,
      'registered_at_jst_device_clock': registered,
      'forecasts': forecasts,
      'excluded': excluded,
      'limitation': _limitation,
    };
  }

  static Map<String, Object?> registerOutcome(
    Map<String, dynamic> outcome, {
    required Map<String, dynamic> registeredForecast,
    required DateTime registeredAt,
    required String sourceSha256,
  }) {
    validateForecast(registeredForecast);
    final recorded = _timestamp(outcome, 'recorded_at_jst_device_clock');
    if (recorded.isAfter(registeredAt.toUtc())) {
      throw const FormatException('登録時点より未来の記録時刻を持つ結果は登録できません。');
    }
    // raw outcome_v1は人物IDを持たない。呼出側の明示的な予測選択で結ぶ。
    // 補助識別子を持つ原結果なら、その不一致も拒否する。
    for (final key in ['subject_id', 'profile_sha256']) {
      if (outcome.containsKey(key) &&
          outcome[key] != registeredForecast[key]) {
        throw const FormatException('結果の人物またはプロフィール識別が一致しません。');
      }
    }
    NineAreaValidation.evaluate(
      _map(registeredForecast['forecast'], 'forecast'),
      outcome,
    );
    final wrapper = <String, Object?>{
      'schema': outcomeSchema,
      'subject_id': registeredForecast['subject_id'],
      'profile_sha256': registeredForecast['profile_sha256'],
      'target_date_jst': registeredForecast['target_date_jst'],
      'registered_at_jst_device_clock': _formatJst(registeredAt),
      'source_sha256': _digest(sourceSha256),
      'forecast_wrapper_sha256': registeredForecast['wrapper_sha256'],
      // evidenceは個人保管のwrapperだけに残し、分析出力には渡さない。
      'outcome': _copy(outcome),
      'limitation': _limitation,
    };
    _seal(wrapper);
    _validateOutcome(wrapper);
    return wrapper;
  }

  static Map<String, Object?> evaluate(
    Map<String, dynamic> forecastWrapper,
    Map<String, dynamic> outcomeWrapper,
  ) {
    validateForecast(forecastWrapper);
    _validateOutcome(outcomeWrapper);
    for (final key in ['subject_id', 'profile_sha256', 'target_date_jst']) {
      if (forecastWrapper[key] != outcomeWrapper[key]) {
        throw const FormatException('予測と結果の人物・出生条件・対象日が一致しません。');
      }
    }
    if (outcomeWrapper['forecast_wrapper_sha256'] !=
        forecastWrapper['wrapper_sha256']) {
      throw const FormatException('結果が結び付く登録予測のハッシュが違います。');
    }
    final outcomeRegistered =
        _timestamp(outcomeWrapper, 'registered_at_jst_device_clock');
    if (outcomeRegistered.isBefore(
      _timestamp(forecastWrapper, 'registered_at_jst_device_clock'),
    )) {
      throw const FormatException('結果登録が予測登録より前です。');
    }
    return {
      'schema': evaluationSchema,
      'subject_id': forecastWrapper['subject_id'],
      'profile_sha256': forecastWrapper['profile_sha256'],
      'target_date_jst': forecastWrapper['target_date_jst'],
      'issued_basis': issuedBasis,
      'forecast_wrapper_sha256': forecastWrapper['wrapper_sha256'],
      'outcome_wrapper_sha256': outcomeWrapper['wrapper_sha256'],
      'calculation_context': _copy(forecastWrapper['calculation_context']),
      'evaluation': NineAreaValidation.evaluate(
        _map(forecastWrapper['forecast'], 'forecast'),
        _map(outcomeWrapper['outcome'], 'outcome'),
      ),
      'limitation': _limitation,
    };
  }

  /// 正式に登録した日を一人一日一件だけ集計する。日内7時点は数えない。
  static Map<String, Object?> summarize(
    Iterable<Map<String, dynamic>> forecasts,
    Iterable<Map<String, dynamic>> outcomes,
  ) {
    final byDigest = <String, Map<String, dynamic>>{};
    final subjectDates = <String>{};
    final groups = <String, _RegisteredGroup>{};
    for (final forecast in forecasts) {
      validateForecast(forecast);
      final subjectDate = jsonEncode([
        forecast['subject_id'],
        forecast['target_date_jst'],
      ]);
      if (!subjectDates.add(subjectDate)) {
        throw const FormatException('同じ人の同じ日の予測が二重登録されています。');
      }
      final digest = _string(forecast, 'wrapper_sha256');
      if (byDigest.containsKey(digest)) {
        throw const FormatException('登録予測のハッシュが重複しています。');
      }
      byDigest[digest] = forecast;
      final identity = _groupIdentity(forecast);
      final groupId = canonicalSha256(identity);
      groups.putIfAbsent(groupId, () => _RegisteredGroup(identity)).forecasts++;
    }
    final recordedOutcomes = <String>{};
    final evaluated = <String>{};
    final notAssessable = <Map<String, Object?>>[];
    for (final outcome in outcomes) {
      _validateOutcome(outcome);
      final digest = _string(outcome, 'forecast_wrapper_sha256');
      final forecast = byDigest[digest];
      if (forecast == null) {
        throw const FormatException('結果に対応する登録予測がありません。');
      }
      if (!recordedOutcomes.add(digest)) {
        throw const FormatException('同じ登録予測に複数の結果が登録されています。');
      }
      final report = evaluate(forecast, outcome);
      final group = groups[canonicalSha256(_groupIdentity(forecast))]!;
      final evaluation = Map<String, Object?>.from(report['evaluation'] as Map);
      // 全未記入の日も結果記録のcoverageへ残す。比較の分母はeligibleだけ。
      group.evaluations.add(evaluation);
      if ((evaluation['eligible_numeric_areas'] as int) +
              (evaluation['eligible_felt_areas'] as int) >
          0) {
        evaluated.add(digest);
        group.eligibleEvaluations++;
      } else {
        notAssessable.add({
          'subject_id': forecast['subject_id'],
          'target_date_jst': forecast['target_date_jst'],
          'forecast_wrapper_sha256': digest,
          'reason': 'no_evaluable_observations',
          'observation_states': {
            for (final item in evaluation['results'] as List)
              (item as Map)['key'] as String: item['observation_state'],
          },
        });
      }
    }
    final pending = <Map<String, Object?>>[
      for (final entry in byDigest.entries)
        if (!recordedOutcomes.contains(entry.key))
          {
            'subject_id': entry.value['subject_id'],
            'target_date_jst': entry.value['target_date_jst'],
            'forecast_wrapper_sha256': entry.key,
            'reason': 'missing_result',
          },
    ]..sort((a, b) {
      final subject = (a['subject_id'] as String).compareTo(
        b['subject_id'] as String,
      );
      return subject != 0
          ? subject
          : (a['target_date_jst'] as String).compareTo(
              b['target_date_jst'] as String,
            );
    });
    final groupIds = groups.keys.toList()..sort();
    return {
      'schema': summarySchema,
      'status': evaluated.isEmpty ? 'not_yet_evaluated' : 'evaluated',
      'forecast_count': byDigest.length,
      'recorded_outcome_count': recordedOutcomes.length,
      'evaluated_count': evaluated.length,
      'pending_count': pending.length,
      'registered_forecast_days': byDigest.length,
      'outcome_days': recordedOutcomes.length,
      'awaiting_outcome_days': pending.length,
      'not_assessable_days': notAssessable.length,
      'eligible_evaluation_days': evaluated.length,
      'pending': pending,
      'not_assessable': notAssessable,
      'groups': [for (final id in groupIds) groups[id]!.toJson()],
      'limitation': _limitation,
    };
  }

  static void validateForecast(Map<String, dynamic> wrapper) {
    if (wrapper['schema'] != forecastSchema ||
        wrapper['issued_basis'] != issuedBasis ||
        !{_daySchema, _monthSchema}.contains(wrapper['source_schema'])) {
      throw const FormatException('登録予測のスキーマまたは登録根拠が違います。');
    }
    _verifySeal(wrapper);
    _subject(_string(wrapper, 'subject_id'));
    _digest(_string(wrapper, 'profile_sha256'));
    _digest(_string(wrapper, 'source_sha256'));
    _string(wrapper, 'source_generated_at_raw');
    final registered = _timestamp(wrapper, 'registered_at_jst_device_clock');
    final forecast = _map(wrapper['forecast'], 'forecast');
    final target = _string(wrapper, 'target_date_jst');
    final day = _day(target);
    if (forecast['target_date_jst'] != target ||
        forecast['issued_at_jst_device_clock'] !=
            wrapper['registered_at_jst_device_clock'] ||
        forecast['issued_basis'] != issuedBasis ||
        !registered.isBefore(day.subtract(_jstOffset))) {
      throw const FormatException('登録時刻・発行根拠・対象日が一致しません。');
    }
    final context = _map(wrapper['calculation_context'], 'calculation_context');
    for (final key in [
      'model_version',
      'house_system',
      'uses_high_precision_astro_data',
      'ephemeris_time_contract',
    ]) {
      if (context[key] != forecast[key]) {
        throw const FormatException('予測と登録計算条件が一致しません。');
      }
    }
    _string(context, 'model_version');
    _string(context, 'house_system');
    _string(context, 'ephemeris_time_contract');
    if (context['uses_high_precision_astro_data'] is! bool ||
        !context.containsKey('provider') ||
        !context.containsKey('requested_house_system') ||
        !context.containsKey('provider_tracking')) {
      throw const FormatException('登録計算条件の形式が不正です。');
    }
    final provider = context['provider'];
    if (provider == null) {
      if (context['provider_tracking'] != 'not_tracked') {
        throw const FormatException('未記録の計算出所を推定しないでください。');
      }
    } else if (provider is! String ||
        provider.trim().isEmpty ||
        context['provider_tracking'] != 'recorded') {
      throw const FormatException('計算出所の形式が不正です。');
    }
    final requested = context['requested_house_system'];
    if (requested != null &&
        (requested is! String || requested.trim().isEmpty)) {
      throw const FormatException('要求ハウス方式の形式が不正です。');
    }
    // 共通の既存validatorを形式検査に使うための未観測データ。
    // 実績・保管・集計には一切入れない。
    NineAreaValidation.evaluate(forecast, {
      'schema': NineAreaValidation.outcomeSchema,
      'target_date_jst': target,
      'recorded_at_jst_device_clock':
          _formatJst(day.add(const Duration(days: 1)).subtract(_jstOffset)),
      'areas': [
        for (final key in NineAreaValidation.areaKeys)
          {
            'key': key,
            'observation_state': 'missing',
            'rating_1_to_5': null,
            'felt_label': null,
            'evidence': '',
          },
      ],
    });
  }

  /// Mapキー順を固定し、JSONで表現できる値だけをハッシュする。
  static String canonicalSha256(Object? value) =>
      sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();

  static Map<String, Object?> _forecast(
    Map<String, dynamic> snapshot,
    String registered,
  ) {
    final rawAreas = snapshot['areas'];
    if (rawAreas is! List) {
      throw const FormatException('正午9項目がありません。');
    }
    final areas = <Map<String, dynamic>>[];
    for (final item in rawAreas) {
      final area = _map(_copy(item), 'areas');
      final score = area['score'];
      if (area['key'] == 'felt') {
        area['predicted_band'] = null;
      } else {
        if (area['status'] == 'not_predicted' && score == null) {
          area['predicted_band'] = null;
          areas.add(area);
          continue;
        }
        if (score is! int) throw const FormatException('数値項目の点数が不正です。');
        area['predicted_band'] = score <= 65
            ? 'low'
            : score >= 80
            ? 'high'
            : 'middle';
      }
      areas.add(area);
    }
    return {
      'schema': NineAreaValidation.forecastSchema,
      'model_version': _string(snapshot, 'model_version'),
      'ephemeris_time_contract': _string(snapshot, 'ephemeris_time_contract'),
      'target_date_jst': _string(snapshot, 'target_date_jst'),
      'calculation_reference_jst': _string(snapshot, 'calculation_reference_jst'),
      'house_system': _string(snapshot, 'house_system'),
      'uses_high_precision_astro_data': snapshot['uses_high_precision_astro_data'],
      'issued_at_jst_device_clock': registered,
      'issued_basis': issuedBasis,
      'forecast_only': true,
      'outcome_included': false,
      'birth_details_included': false,
      'score_bands': {'low': '50-65', 'middle': '66-79', 'high': '80-99'},
      'areas': areas,
    };
  }

  static Map<String, Object?> _context(
    Map<String, dynamic> source,
    Map<String, dynamic> snapshot,
  ) {
    String? requested;
    String? provider;
    // 正午個別出所がnot_trackedなら、7時点を計算したproviderを正午へ転用しない。
    final intraday = source['intraday_positions'];
    if (intraday is Map) {
      final house = intraday['house_calculation'];
      if (house is Map && house['requested_system'] is String) {
        requested = house['requested_system'] as String;
        if (house['resolved_system'] != snapshot['house_system']) {
          throw const FormatException('日内と正午の実ハウス方式が一致しません。');
        }
      }
      final calculation = intraday['calculation_source'];
      if (calculation is Map &&
          calculation['inherited_noon_individual_provenance'] == 'recorded' &&
          calculation['provider'] is String) {
        provider = calculation['provider'] as String;
      }
    }
    return {
      'model_version': snapshot['model_version'],
      'house_system': snapshot['house_system'],
      'requested_house_system': requested,
      'uses_high_precision_astro_data': snapshot['uses_high_precision_astro_data'],
      'provider': provider,
      'provider_tracking': provider == null ? 'not_tracked' : 'recorded',
      'ephemeris_time_contract': snapshot['ephemeris_time_contract'],
    };
  }

  static Map<String, Object?> _groupIdentity(Map<String, dynamic> forecast) {
    final context = _map(forecast['calculation_context'], 'calculation_context');
    return {
      'subject_id': forecast['subject_id'],
      'profile_sha256': forecast['profile_sha256'],
      'model_version': context['model_version'],
      'house_system': context['house_system'],
      'uses_high_precision_astro_data': context['uses_high_precision_astro_data'],
      'provider': context['provider'],
      'provider_tracking': context['provider_tracking'],
      'ephemeris_time_contract': context['ephemeris_time_contract'],
    };
  }

  static void _validateOutcome(Map<String, dynamic> wrapper) {
    if (wrapper['schema'] != outcomeSchema) {
      throw const FormatException('登録結果のスキーマが違います。');
    }
    _verifySeal(wrapper);
    _subject(_string(wrapper, 'subject_id'));
    _digest(_string(wrapper, 'profile_sha256'));
    _digest(_string(wrapper, 'source_sha256'));
    _digest(_string(wrapper, 'forecast_wrapper_sha256'));
    final registered = _timestamp(wrapper, 'registered_at_jst_device_clock');
    final target = _string(wrapper, 'target_date_jst');
    final day = _day(target);
    final outcome = _map(wrapper['outcome'], 'outcome');
    if (outcome['schema'] != NineAreaValidation.outcomeSchema ||
        outcome['target_date_jst'] != target) {
      throw const FormatException('登録結果の対象日または形式が一致しません。');
    }
    for (final key in ['subject_id', 'profile_sha256']) {
      if (outcome.containsKey(key) && outcome[key] != wrapper[key]) {
        throw const FormatException('原結果と登録結果の人物識別が一致しません。');
      }
    }
    final recorded = _timestamp(outcome, 'recorded_at_jst_device_clock');
    if (recorded.isAfter(registered) ||
        recorded.isBefore(day.add(const Duration(days: 1)).subtract(_jstOffset))) {
      throw const FormatException('結果時刻は対象日の翌日以降かつ登録時点までが必要です。');
    }
  }

  static void _validateMonthDays(List<Map<String, dynamic>> snapshots) {
    final first = _day(_string(snapshots.first, 'target_date_jst'));
    final days = DateTime.utc(first.year, first.month + 1).subtract(
      const Duration(days: 1),
    ).day;
    if (first.day != 1 || snapshots.length != days) {
      throw const FormatException('月の日別9項目は全日を日付順で指定してください。');
    }
    for (var i = 0; i < snapshots.length; i++) {
      if (_day(_string(snapshots[i], 'target_date_jst')) !=
          first.add(Duration(days: i))) {
        throw const FormatException('月の日別9項目の日付に欠落または順序違いがあります。');
      }
    }
  }

  static void _seal(Map<String, Object?> wrapper) {
    wrapper['wrapper_sha256'] = canonicalSha256(wrapper);
  }

  static void _verifySeal(Map<String, dynamic> wrapper) {
    final expected = _digest(_string(wrapper, 'wrapper_sha256'));
    final content = Map<String, dynamic>.from(wrapper)..remove('wrapper_sha256');
    if (canonicalSha256(content) != expected) {
      throw const FormatException('登録ファイルのハッシュが一致しません。');
    }
  }

  static Object? _canonical(Object? value) {
    if (value == null || value is bool || value is String || value is int) {
      return value;
    }
    if (value is double && value.isFinite) return value;
    if (value is List) return [for (final item in value) _canonical(item)];
    if (value is Map) {
      if (value.keys.any((key) => key is! String)) {
        throw const FormatException('JSONのMapキーは文字列が必要です。');
      }
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    throw const FormatException('有限なJSON値だけを登録できます。');
  }

  static Object? _copy(Object? value) => jsonDecode(jsonEncode(_canonical(value)));

  static Map<String, dynamic> _map(Object? value, String key) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw FormatException('$key の形式が不正です。');
    }
    return Map<String, dynamic>.from(value);
  }

  static String _string(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key がありません。');
    }
    return value;
  }

  static String _subject(String value) {
    if (value.trim().isEmpty || value != value.trim()) {
      throw const FormatException('人物IDは前後空白のない文字列で指定してください。');
    }
    return value;
  }

  static String _digest(String value) {
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
      throw const FormatException('SHA256は64桁の16進数で指定してください。');
    }
    return value.toLowerCase();
  }

  static DateTime _day(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('対象日はYYYY-MM-DDで指定してください。');
    }
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(5, 7));
    final day = int.parse(value.substring(8, 10));
    final result = DateTime.utc(year, month, day);
    if (year < 1 || result.year != year || result.month != month || result.day != day) {
      throw const FormatException('対象日が存在しません。');
    }
    return result;
  }

  static String _formatJst(DateTime value) {
    final jst = value.toUtc().add(_jstOffset);
    if (jst.year < 1 || jst.year > 9999) {
      throw const FormatException('検証資料の日時は1年から9999年の範囲が必要です。');
    }
    return jst.toIso8601String().replaceFirst(RegExp(r'Z$'), '+09:00');
  }

  static DateTime _timestamp(Map<String, dynamic> data, String key) {
    final value = _string(data, key);
    if (!RegExp(
      r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?\+09:00$',
    ).hasMatch(value)) {
      throw FormatException('$key は時差付きJST日時で指定してください。');
    }
    final instant = DateTime.tryParse(value)?.toUtc();
    if (instant == null) throw FormatException('$key の日時が不正です。');
    final jst = instant.add(_jstOffset);
    if (jst.year < 1 ||
        jst.year != int.parse(value.substring(0, 4)) ||
        jst.month != int.parse(value.substring(5, 7)) ||
        jst.day != int.parse(value.substring(8, 10)) ||
        jst.hour != int.parse(value.substring(11, 13)) ||
        jst.minute != int.parse(value.substring(14, 16)) ||
        jst.second != int.parse(value.substring(17, 19))) {
      throw FormatException('$key の日時が存在しません。');
    }
    return instant;
  }
}

class _RegisteredGroup {
  _RegisteredGroup(this.identity);

  final Map<String, Object?> identity;
  int forecasts = 0;
  int eligibleEvaluations = 0;
  final List<Map<String, Object?>> evaluations = [];

  Map<String, Object?> toJson() => {
    'group': identity,
    'forecast_count': forecasts,
    'recorded_outcome_count': evaluations.length,
    'evaluated_count': eligibleEvaluations,
    'pending_count': forecasts - evaluations.length,
    'registered_forecast_days': forecasts,
    'outcome_days': evaluations.length,
    'awaiting_outcome_days': forecasts - evaluations.length,
    'not_assessable_days': evaluations.length - eligibleEvaluations,
    'eligible_evaluation_days': eligibleEvaluations,
    'status': eligibleEvaluations == 0 ? 'not_yet_evaluated' : 'evaluated',
    'summary': evaluations.isEmpty ? null : NineAreaSummary.summarize(evaluations),
  };
}
