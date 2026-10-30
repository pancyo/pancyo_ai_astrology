import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'period_seven_test_fixture.dart';

class _Job implements WeeklyDailyConsultExportOperation {
  final done=Completer<WeeklyDailyConsultExportResult>();
  @override Future<WeeklyDailyConsultExportResult> get result=>done.future;
  @override void cancel() {}
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLanguage previous;
  final date=DateTime.utc(2026,12,28,3);
  late List<NineAreaPrediction> predictions;
  setUpAll(()=>predictions=NineAreaDailyForecast.fromContext(
    const AstrologyEngine().buildPreviewContext(profile:sevenFixtureProfile,date:date)));
  setUp(()=>previous=AppLanguageSettings.current.value);
  tearDown(()=>AppLanguageSettings.current.value=previous);
  Future<void> frames(WidgetTester t)async{for(var i=0;i<6;i++)await t.pump(const Duration(milliseconds:50));}
  Future<void> show(WidgetTester t,Widget child,Size size,AppLanguage language)async{
    AppLanguageSettings.current.value=language;
    t.view.physicalSize=size;t.view.devicePixelRatio=1;
    addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(home:AppLanguageScope(child:MediaQuery(data:MediaQueryData(size:size),
      child:Scaffold(body:SingleChildScrollView(child:child))))));
    await frames(t);
  }
  void verify(WidgetTester t,String prefix,Size size,AppLanguage language){
    final cards=t.widgetList<NineAreaReadingCard>(find.byType(NineAreaReadingCard)).toList();
    expect(cards,hasLength(9));
    for(final key in NineAreaKey.values){
      final f=find.byKey(ValueKey('$prefix-narrative-${key.name}'));
      final text=t.widget<Text>(f);
      final standard=Theme.of(t.element(f)).textTheme.bodyMedium!.fontSize!;
      expect(text.style!.fontSize,standard);
      expect(text.style!.height,1.45);
      final c=cards.singleWhere((c)=>c.valueKey==ValueKey('$prefix-value-${key.name}'));
      expect(text.data,c.narrative);
      // Headings retain the previous large card header size.
      final title=find.descendant(of:find.byWidget(c),matching:find.text(c.title)).last;
      expect(t.widget<Text>(title).style!.fontSize,c.bodySize+4);
      expect(c.badge,isNotNull);
    }
    expect(t.takeException(),isNull);
  }
  for(final language in AppLanguage.values)for(final size in [const Size(412,915),const Size(1200,900)]) {
    testWidgets('daily detailed body matches standard in both languages $language $size',(t)async{
      await show(t,NineAreaGrid(predictions:predictions,targetDate:date,details:sevenFixtureDetails,depth:ReadingDepth.detailed),size,language);
      verify(t,'daily',size,language);
      for(final p in predictions){
        final expected=ForecastExplanation.forDaily(prediction:p,relatedPredictions:predictions,targetDate:date,
          strings:AppStrings(language),depth:ReadingDepth.detailed,supplement:sevenFixtureDetails);
        expect(t.widget<Text>(find.byKey(ValueKey('daily-narrative-${p.key.name}'))).data,expected.narrativeText);
      }
    });
    testWidgets('weekly detailed body matches standard in both languages $language $size',(t)async{
      final fixture=SyntheticSevenPeriodFixture();final job=_Job();late WeeklyDailyConsultExportRequest request;
      await show(t,PeriodSevenOverview(mode:LongRangeMode.week,startDateJst:date,profile:sevenFixtureProfile,
        details:sevenFixtureDetails,depth:ReadingDepth.detailed,startWeeklyJob:(r,p){request=r;return job;}),size,language);
      job.done.complete(WeeklyDailyConsultExportResult.fromData(requestIdentity:request.identity,data:fixture.week(request)));
      await frames(t);verify(t,'period-overview',size,language);
    });
  }
  testWidgets('Japanese phone daily Simple keeps 16dp prose',(t)async{
    const size=Size(412,915);
    await show(t,NineAreaGrid(predictions:predictions,targetDate:date,details:sevenFixtureDetails,depth:ReadingDepth.simple),size,AppLanguage.ja);
    for(final key in NineAreaKey.values){
      final text=t.widget<Text>(find.byKey(ValueKey('daily-narrative-${key.name}')));
      expect(text.style!.fontSize,16);
    }
    expect(t.takeException(),isNull);
  });
  testWidgets('Japanese phone weekly Simple keeps 16dp prose',(t)async{
    final fixture=SyntheticSevenPeriodFixture();final job=_Job();late WeeklyDailyConsultExportRequest request;
    await show(t,PeriodSevenOverview(mode:LongRangeMode.week,startDateJst:date,profile:sevenFixtureProfile,
      details:sevenFixtureDetails,depth:ReadingDepth.simple,startWeeklyJob:(r,p){request=r;return job;}),const Size(412,915),AppLanguage.ja);
    job.done.complete(WeeklyDailyConsultExportResult.fromData(requestIdentity:request.identity,data:fixture.week(request)));
    await frames(t);
    for(final key in NineAreaKey.values){
      final text=t.widget<Text>(find.byKey(ValueKey('period-overview-narrative-${key.name}')));
      expect(text.style!.fontSize,16);
    }
    expect(t.takeException(),isNull);
  });

}
