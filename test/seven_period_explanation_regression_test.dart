// Synthetic regression reference; no private profile or native precision claim.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:pancyo_ai_astrology/app_language.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('daily and annual explanation stay byte-equivalent to frozen seven-r1', () {
    const profile=AstroProfile(name:'ExplanationRegressionSynthetic',birthDate:'1990/1/2',birthTime:'12:00',birthPlace:'札幌市',theme:'fixture');
    HouseSystemSettings.current.value=HouseSystem.placidus;
    final cache=<DateTime,List<NineAreaPrediction>>{};
    List<NineAreaPrediction> daily(DateTime d) => cache.putIfAbsent(d,()=>NineAreaDailyForecast.fromContext(const AstrologyEngine().buildPreviewContext(profile:profile,date:d)));
    final date=DateTime.utc(2026,10,18,3);
    final year=NineAreaPeriodSummary.build(mode:LongRangeMode.year,month:DateTime.utc(2026),year:2026,legacyScores:{NineAreaKey.overall:60,NineAreaKey.love:60,NineAreaKey.work:60,NineAreaKey.money:60},useGeneralModel:true,dailyFor:daily);
    final samples={for(final d in year.dates) NineAreaPeriodSummary.dateLabel(d):daily(d)};
    final result=<String,Object?>{};
    for(final language in AppLanguage.values) {
      for(final depth in ReadingDepth.values) {
        for(final area in daily(date)) {
          result['day/${language.name}/${depth.name}/${area.key.name}']=ForecastExplanation.forDaily(prediction:area,targetDate:date,strings:AppStrings(language),depth:depth).toJson();
        }
        for(final area in year.areas) {
          result['year/${language.name}/${depth.name}/${area.key.name}']=ForecastExplanation.forPeriod(summary:year,area:area,strings:AppStrings(language),depth:depth,dailySamples:samples).toJson();
        }
      }
    }
    final file=File('test/fixtures/seven_r1_daily_annual_explanations.json');
    if(const bool.fromEnvironment('WRITE_BASELINE_EXPLANATIONS')) {
      file.parent.createSync(recursive:true);file.writeAsStringSync(jsonEncode(result));
    } else {
      expect(jsonEncode(result),file.readAsStringSync());
    }
    expect(result.length,72);
  });
}
