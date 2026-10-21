/// Provenance supplied by the place lookup, never inferred from a city label,
/// coordinates, display language, or the presence of a recorded value.
/// This metadata does not select a location or resolve a birth time zone.
enum BirthPlaceResolutionKind {
  explicitCoordinates('explicit_coordinates'),
  labelMatch('label_match'),
  keywordMatch('keyword_match'),
  prefectureRepresentative('prefecture_representative'),
  emptyInputDefault('empty_input_default'),
  unsupportedPlaceFallback('unsupported_place_fallback');

  const BirthPlaceResolutionKind(this.code);
  final String code;

  bool get usedFallback =>
      this == emptyInputDefault || this == unsupportedPlaceFallback;

  String? get reviewWarningCode => switch (this) {
    emptyInputDefault => ConsultBirthInputQuality.emptyBirthPlaceDefaultWarning,
    unsupportedPlaceFallback =>
      ConsultBirthInputQuality.unsupportedBirthPlaceFallbackWarning,
    _ => null,
  };
}

/// 相談JSONの出生入力を説明するだけで、プロフィールや計算値は変更しない。
class ConsultBirthInputQuality {
  const ConsultBirthInputQuality._();

  static const schema = 'pancyo_consult_birth_input_quality_v1';
  // Stable machine codes for translated UI warnings; never use them as scores.
  static const unsupportedBirthPlaceFallbackWarning =
      'unsupported_birth_place_fallback';
  static const emptyBirthPlaceDefaultWarning = 'empty_birth_place_default';

  static Map<String, Object?> build({
    required String recordedBirthTime,
    required String recordedBirthPlace,
    required String profileBirthDate,
    required String profileBirthTime,
    required String profileBirthPlace,
    required String natalBirthDate,
    required String natalBirthTime,
    required String natalBirthPlace,
    required String calculationPlace,
    required double latitude,
    required double longitude,
    required bool usesHighPrecisionAstroData,
    BirthPlaceResolutionKind? calculationPlaceResolutionKind,
  }) {
    final time = _field(
      recorded: recordedBirthTime,
      exported: profileBirthTime,
      natalBasis: natalBirthTime,
      defaultValue: '12:00',
    );
    final place = _field(
      recorded: recordedBirthPlace,
      exported: profileBirthPlace,
      natalBasis: natalBirthPlace,
      defaultValue: '北海道札幌市',
    );
    final dateMatches = profileBirthDate.trim() == natalBirthDate.trim();
    final timeFormatValid =
        _clockFormatInRange(profileBirthTime) &&
        _clockFormatInRange(natalBirthTime);
    final coordinatesInRange =
        latitude.isFinite &&
        longitude.isFinite &&
        latitude.abs() <= 90 &&
        longitude.abs() <= 180;
    return {
      'schema': schema,
      'scope': 'current_records_and_calculation_basis',
      'birth_facts_verified_by_exporter': false,
      'historical_entry_provenance': 'not_tracked',
      'requires_input_review':
          time['source'] != 'recorded_value' ||
          place['source'] != 'recorded_value' ||
          !dateMatches ||
          !timeFormatValid ||
          !coordinatesInRange ||
          calculationPlaceResolutionKind?.usedFallback == true,
      'input_review_warning_codes': [
        if (calculationPlaceResolutionKind?.reviewWarningCode case final code?)
          code,
      ],
      'assumed_fields_in_current_record': [
        if (time['is_assumed_in_current_record'] == true) 'birth_time',
        if (place['is_assumed_in_current_record'] == true) 'birth_place',
      ],
      'birth_date_matches_natal_basis': dateMatches,
      'birth_time': {
        ...time,
        'exported_clock_format_in_range': _clockFormatInRange(profileBirthTime),
        'natal_clock_format_in_range': _clockFormatInRange(natalBirthTime),
        'note': '時刻の書式・範囲チェックは出生時刻の事実確認ではありません。',
      },
      'birth_place': {
        ...place,
        'calculation_location': {
          'label': calculationPlace,
          'latitude': latitude.isFinite ? latitude : null,
          'longitude': longitude.isFinite ? longitude : null,
          'coordinates_in_range': coordinatesInRange,
          // null means the caller did not supply lookup provenance. It must not
          // become false or be inferred from a genuine Sapporo birthplace.
          'resolution_kind': calculationPlaceResolutionKind?.code,
          'used_fallback': calculationPlaceResolutionKind?.usedFallback,
          'accuracy_independently_verified': false,
          'note':
              '計算コンテキストの地点です。地名の解決には代表地点や既定地点が使われる場合があり、実際の出生座標の正確さを保証しません。',
        },
      },
      'ephemeris': {
        'uses_high_precision_astro_data': usesHighPrecisionAstroData,
        'note': '高精度フラグは星の計算エンジンの区分であり、出生日時・出生地が正しいことの保証ではありません。',
      },
      'interpretation_notes': [
        'recorded_valueは現在の記録欄に値があるという意味で、本人入力や出生事実の正確さを証明しません。',
        'assumed_defaultは現在の記録欄が空で、出力と出生図の基準がともに既定値の12:00／北海道札幌市である場合です。',
        'unverified_profile_valueは記録欄が空でも非既定のプロフィール値が使われ、入力由来を確認できない場合です。',
        'inconsistent_recordsは記録欄・出力プロフィール・出生図基準の値に不一致がある場合です。確定した出生条件として扱わず確認してください。',
        '旧保存・復元処理で仮値が記録欄へ引き継がれたかどうかは、この情報から復元できません。記録済みの12:00／札幌を仮値とも実測値とも断定しません。',
        'requires_input_reviewがfalseでも出生情報の正確さを証明しません。出生図・ハウス・ASC／MCに基づく解釈では入力条件を確認してください。',
      ],
    };
  }

  static Map<String, Object?> _field({
    required String recorded,
    required String exported,
    required String natalBasis,
    required String defaultValue,
  }) {
    final record = recorded.trim();
    final value = exported.trim();
    final basis = natalBasis.trim();
    final basisMatches = value == basis;
    final recordMatches = record.isEmpty ? null : record == value;
    final source = !basisMatches || recordMatches == false
        ? 'inconsistent_records'
        : record.isNotEmpty
        ? 'recorded_value'
        : value == defaultValue
        ? 'assumed_default'
        : 'unverified_profile_value';
    return {
      'recorded_value': record.isEmpty ? null : record,
      'exported_value': exported,
      'natal_basis_value': natalBasis,
      'source': source,
      'is_assumed_in_current_record': switch (source) {
        'assumed_default' => true,
        'recorded_value' => false,
        _ => null,
      },
      'recorded_value_matches_exported': recordMatches,
      'exported_value_matches_natal_basis': basisMatches,
      'verification_status': 'not_independently_verified',
    };
  }

  static bool _clockFormatInRange(String value) {
    final match = RegExp(
      r'^(\d{1,2})(?::|時)(\d{1,2})(?:分)?$',
    ).firstMatch(value.trim());
    if (match == null) return false;
    return int.parse(match.group(1)!) <= 23 && int.parse(match.group(2)!) <= 59;
  }
}
