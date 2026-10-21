// Contract/UI fixtures only. The seed is one calculation for a fictional
// person. Dates, scores and felt labels below are deliberately synthetic, so
// these maps are never evidence of astronomical accuracy or real predictions.
import 'dart:convert';

import 'package:pancyo_ai_astrology/daily_seven_timepoint_plan.dart';
import 'package:pancyo_ai_astrology/main.dart';

import 'monthly_daily_consult_export_test.dart' as original;

const sevenFixtureProfile = original.subject;
const sevenFixtureDetails = UserProfileDetails.empty();
final sevenFixtureGeneratedAt = DateTime.utc(2026, 10, 18, 3);

String fixtureDate(DateTime civil) =>
    '${civil.year.toString().padLeft(4, '0')}-'
    '${civil.month.toString().padLeft(2, '0')}-'
    '${civil.day.toString().padLeft(2, '0')}';

Map<String, Object?> fixtureClone(Map<String, Object?> value) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);

List<dynamic> fixturePoints(Map<String, Object?> day) =>
    (day['intraday_forecasts'] as Map<String, Object?>)['points'] as List<dynamic>;

Map<String, Object?> fixtureSnapshot(Map<String, Object?> day, int index) =>
    Map<String, Object?>.from(
      fixturePoints(day)[index]['nine_area_forecast'] as Map,
    );

WeeklyDailyConsultExportRequest fixtureWeekRequest(
  DateTime first, {
  AstroProfile profile = sevenFixtureProfile,
  UserProfileDetails details = sevenFixtureDetails,
  DateTime? generatedAt,
}) => WeeklyDailyConsultExportRequest(
  startDate: DateTime.utc(first.year, first.month, first.day, 3),
  profile: profile,
  details: details,
  requestedHouseSystem: HouseSystemSettings.current.value,
  sourceName: AstrologyDataSources.current.sourceName,
  requireHighPrecision: AstrologyDataSources.current.usesHighPrecisionAstroData,
  generatedAt: generatedAt ?? sevenFixtureGeneratedAt,
);

MonthlyDailyConsultExportRequest fixtureMonthRequest(
  DateTime month, {
  AstroProfile profile = sevenFixtureProfile,
  UserProfileDetails details = sevenFixtureDetails,
  DateTime? generatedAt,
}) => MonthlyDailyConsultExportRequest(
  startDate: DateTime.utc(month.year, month.month, 1, 3),
  profile: profile,
  details: details,
  requestedHouseSystem: HouseSystemSettings.current.value,
  sourceName: AstrologyDataSources.current.sourceName,
  requireHighPrecision: AstrologyDataSources.current.usesHighPrecisionAstroData,
  generatedAt: generatedAt ?? sevenFixtureGeneratedAt,
);

class SyntheticSevenPeriodFixture {
  SyntheticSevenPeriodFixture()
    : seed = buildDailyConsultDataV4(
        fixtureWeekRequest(DateTime.utc(2026, 12, 28)).dailyRequestAt(0),
      );

  final Map<String, Object?> seed;

  // Different indices intentionally have different scores. Interior midnight
  // samples are high so counting duplicate 24/00 boundaries changes the mean.
  static int scoreAt(int uniqueIndex, String area) {
    final offset = NineAreaKey.values.byName(area).index % 5;
    return uniqueIndex > 0 && uniqueIndex % 6 == 0
        ? 94 + offset
        : 51 + ((uniqueIndex * 3 + offset) % 11);
  }

  static String feltAt(int uniqueIndex) => uniqueIndex < 21
      ? '良い'
      : uniqueIndex < 42
      ? '悪い'
      : '普通';

  Map<String, Object?> week(
    WeeklyDailyConsultExportRequest request, {
    int Function(int, String)? score,
    String Function(int)? felt,
  }) => _wrapper(
    LongRangeMode.week,
    request.dayPlans,
    request.profile,
    request.details,
    request.generatedAt,
    request.requestedHouseSystem,
    request.sourceName,
    request.requireHighPrecision,
    score ?? scoreAt,
    felt ?? feltAt,
  );

  Map<String, Object?> month(
    MonthlyDailyConsultExportRequest request, {
    int Function(int, String)? score,
    String Function(int)? felt,
  }) => _wrapper(
    LongRangeMode.month,
    request.dayPlans,
    request.profile,
    request.details,
    request.generatedAt,
    request.requestedHouseSystem,
    request.sourceName,
    request.requireHighPrecision,
    score ?? scoreAt,
    felt ?? feltAt,
  );

  Map<String, Object?> _wrapper(
    LongRangeMode mode,
    List<DailySevenTimepointPlan> plans,
    AstroProfile profile,
    UserProfileDetails details,
    DateTime generatedAt,
    HouseSystem house,
    String sourceName,
    bool highPrecision,
    int Function(int, String) score,
    String Function(int) felt,
  ) {
    final days = <Map<String, Object?>>[];
    for (var dayIndex = 0; dayIndex < plans.length; dayIndex++) {
      final plan = plans[dayIndex];
      final day = fixtureClone(seed);
      day['generated_at'] = generatedAt.toIso8601String();
      day['date_time_jst'] = '${plan.targetDateJst} 12:00:00+09:00';
      day['synthetic_contract_fixture'] = true;
      (day['profile'] as Map<String, Object?>).addAll(<String, Object?>{
        'name': profile.name,
        'birth_date': profile.birthDate,
        'birth_time': profile.birthTime,
        'birth_place': profile.birthPlace,
        'theme': profile.theme,
        'concerns': details.concerns,
        'reading_style': details.readingStyle,
      });
      (day['house_calculation'] as Map<String, Object?>)['house_system'] =
          house.name;
      for (final field in ['intraday_positions', 'intraday_forecasts']) {
        final group = day[field] as Map<String, Object?>;
        group['target_date_jst'] = plan.targetDateJst;
        group['time_zone'] = 'Asia/Tokyo';
        group['fixed_utc_offset'] = '+09:00';
        if (field == 'intraday_positions') {
          (group['house_calculation'] as Map<String, Object?>)
              .addAll(<String, Object?>{
            'requested_system': house.name,
            'resolved_system': house.name,
          });
          (group['calculation_source'] as Map<String, Object?>)
              .addAll(<String, Object?>{
            'provider': sourceName,
            'provider_uses_high_precision': highPrecision,
          });
        }
        final points = group['points'] as List<dynamic>;
        for (var pointIndex = 0; pointIndex < 7; pointIndex++) {
          final point = points[pointIndex] as Map<String, Object?>;
          point.addAll(plan.points[pointIndex].toJson());
          if (field == 'intraday_forecasts') {
            // Use the same seed snapshot for every constructed instant, then
            // explicitly set synthetic values by unique index. Therefore a
            // day-end and following day-start have fully identical snapshots.
            final snap = fixtureClone(fixtureSnapshot(seed, 3));
            final clock = plan.points[pointIndex];
            final uniqueIndex = dayIndex * 6 + pointIndex;
            snap['target_date_jst'] = fixtureDate(
              clock.instantUtc.add(const Duration(hours: 9)),
            );
            snap['calculation_reference_jst'] = clock.instantJst;
            snap['uses_high_precision_astro_data'] = highPrecision;
            snap['house_system'] = house.name;
            snap['synthetic_contract_fixture'] = true;
            for (final raw in snap['areas'] as List) {
              final area = raw as Map<String, Object?>;
              final key = area['key'] as String;
              area['summary'] = 'Synthetic contract fixture';
              area['explanation'] =
                  'Synthetic contract fixture; no astronomical interpretation.';
              if (key == 'felt') {
                area['score'] = null;
                area['predicted_felt_label'] = felt(uniqueIndex);
              } else {
                area['score'] = score(uniqueIndex, key);
                area['score_breakdown'] = null;
              }
            }
            point['nine_area_forecast'] = snap;
          }
        }
      }
      day['nine_area_daily'] = fixtureClone(fixtureSnapshot(day, 3));
      days.add(day);
    }
    return {
      'schema': mode == LongRangeMode.week
          ? 'pancyo_astrology_weekly_daily_consult_v1'
          : 'pancyo_astrology_monthly_daily_consult_v1',
      'generated_at': generatedAt.toIso8601String(),
      'synthetic_contract_fixture': true,
      mode == LongRangeMode.week ? 'week' : 'month': {
        'start_date_jst': plans.first.targetDateJst,
        'end_date_jst': plans.last.targetDateJst,
        'calculation_reference_time_jst': '12:00',
        'day_count': days.length,
      },
      'timepoint_contract': {
        'time_zone': 'Asia/Tokyo',
        'fixed_utc_offset': '+09:00',
        'times_jst': [
          '00:00',
          '04:00',
          '08:00',
          '12:00',
          '16:00',
          '20:00',
          '24:00',
        ],
        'points_per_day': 7,
        'counted_series': 'days[].intraday_forecasts.points',
        'parallel_position_series':
            'days[].intraday_positions.points has the same clocks and is not counted again',
        'listed_point_count': days.length * 7,
        'unique_instant_count': days.length * 6 + 1,
        'boundary_rule': 'Synthetic contract: 24:00 equals the next 00:00.',
      },
      'completeness': {
        'status': 'complete',
        'day_count': days.length,
        'listed_point_count': days.length * 7,
        'unique_instant_count': days.length * 6 + 1,
      },
      'days': days,
    };
  }
}
