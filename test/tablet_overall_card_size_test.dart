import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'period_seven_test_fixture.dart';

class _Week implements WeeklyDailyConsultExportOperation {
  final done=Completer<WeeklyDailyConsultExportResult>();
  @override Future<WeeklyDailyConsultExportResult> get result=>done.future;
  @override void cancel() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLanguage previous;
  final date=DateTime.utc(2026,12,28,3);
  late List<NineAreaPrediction> predictions;
  setUpAll(() async {
    final root=Platform.environment['FLUTTER_ROOT']??r'C:\Users\pancy\flutter';
    final loader=FontLoader('Roboto');
    for(final name in ['Roboto-Regular.ttf','Roboto-Bold.ttf']) {
      loader.addFont(File('$root/bin/cache/artifacts/material_fonts/$name').readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
    predictions=NineAreaDailyForecast.fromContext(const AstrologyEngine().buildPreviewContext(profile:sevenFixtureProfile,date:date));
  });
  setUp(()=>previous=AppLanguageSettings.current.value);
  tearDown(()=>AppLanguageSettings.current.value=previous);
  Future<void> show(WidgetTester t,Widget child,AppLanguage language,Size size) async {
    AppLanguageSettings.current.value=language;
    t.view.physicalSize=size;t.view.devicePixelRatio=1;
    addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(theme:ThemeData.dark().copyWith(textTheme:ThemeData.dark().textTheme.apply(fontFamily:'Roboto')),
      home:AppLanguageScope(child:MediaQuery(data:MediaQueryData(size:size),child:Scaffold(body:SingleChildScrollView(child:child))))));
    await t.pumpAndSettle();
  }
  Finder card(String key)=>find.byWidgetPredicate((w)=>w is NineAreaReadingCard&&w.valueKey==ValueKey(key));
  Future<void> checkScroll(WidgetTester t,Finder overall,String prefix,bool tablet) async {
    expect(find.descendant(of:overall,matching:find.byType(Scrollable)),findsNothing);
    final w=t.widget<NineAreaReadingCard>(overall);
    expect(t.widget<Text>(find.byKey(ValueKey('$prefix-narrative-overall'))).data,w.narrative);
    if(tablet) {
      expect(t.getSize(overall).width,1200);
      expect(t.getSize(card('$prefix-value-love')).width,592);
      expect(t.getTopLeft(card('$prefix-value-love')).dy,t.getTopLeft(card('$prefix-value-work')).dy);
      expect(t.getTopLeft(card('$prefix-value-money')).dy,t.getTopLeft(card('$prefix-value-mental')).dy);
      expect(t.getTopLeft(card('$prefix-value-money')).dy,greaterThan(t.getTopLeft(card('$prefix-value-love')).dy));
      expect(t.getSize(card('$prefix-value-health')).width,592);
      expect(t.getTopLeft(card('$prefix-value-health')).dy,t.getTopLeft(card('$prefix-value-people')).dy);
      expect(t.getTopLeft(card('$prefix-value-love')).dy,greaterThanOrEqualTo(t.getBottomLeft(overall).dy+16));
    }
    await t.ensureVisible(overall);await t.pumpAndSettle();
    final root=t.state<ScrollableState>(find.byType(Scrollable).first).position;
    final before=root.pixels;
    final rect=t.getRect(overall);
    final point=Offset(rect.center.dx,(rect.top+100).clamp(100.0,750.0));
    await t.dragFrom(point,const Offset(0,-180));await t.pumpAndSettle();
    expect(root.pixels,greaterThan(before),reason:'Dragging on Overall must scroll the page');
    final evidence=find.byKey(ValueKey('$prefix-evidence-overall'));
    await t.ensureVisible(evidence);await t.pumpAndSettle();await t.tap(evidence);await t.pumpAndSettle();
    final ledger=find.byKey(ValueKey('$prefix-ledger-overall'));
    expect(t.widget<Text>(ledger).data,w.evidence);
    expect(find.descendant(of:overall,matching:find.byType(Scrollable)),findsNothing);
    await t.ensureVisible(ledger);await t.pumpAndSettle();
    final afterOpen=root.pixels;
    final ledgerRect=t.getRect(ledger);
    final ledgerPoint=Offset(ledgerRect.center.dx,(ledgerRect.top+40).clamp(60.0,750.0));
    await t.dragFrom(ledgerPoint,const Offset(0,-180));await t.pumpAndSettle();
    expect(root.pixels,greaterThan(afterOpen),reason:'Expanded Overall evidence must also scroll with the page');
    expect(t.takeException(),isNull);
  }
  for(final scenario in [
    (AppLanguage.en,ReadingDepth.detailed,const Size(1200,900),true),
    (AppLanguage.ja,ReadingDepth.detailed,const Size(1200,900),true),
    (AppLanguage.en,ReadingDepth.detailed,const Size(412,915),false),
    (AppLanguage.en,ReadingDepth.simple,const Size(1200,900),false),
  ]) {
    testWidgets('daily Overall page drag and grouping ${scenario.$1} ${scenario.$2} ${scenario.$3}',(t) async {
      await show(t,NineAreaGrid(predictions:predictions,targetDate:date,details:sevenFixtureDetails,depth:scenario.$2),scenario.$1,scenario.$3);
      if(scenario.$2==ReadingDepth.simple)return;
      await checkScroll(t,card('daily-value-overall'),'daily',scenario.$4);
    });
  }
  for(final language in AppLanguage.values) {
    testWidgets('weekly $language Overall and expanded evidence drag scroll the page',(t) async {
      final fixture=SyntheticSevenPeriodFixture();final job=_Week();late WeeklyDailyConsultExportRequest request;
      await show(t,PeriodSevenOverview(mode:LongRangeMode.week,startDateJst:date,profile:sevenFixtureProfile,
        details:sevenFixtureDetails,depth:ReadingDepth.detailed,startWeeklyJob:(r,p){request=r;return job;}),language,const Size(1200,900));
      job.done.complete(WeeklyDailyConsultExportResult.fromData(requestIdentity:request.identity,data:fixture.week(request)));
      await t.pumpAndSettle();
      await checkScroll(t,card('period-overview-value-overall'),'period-overview',true);
    });
  }
}
