import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'calendar_tablet_fit_test.dart' as f;

Future<void> phone(WidgetTester t, {required Size size, required bool english,
  required double font, required double scale, DateTime? date,
  AstrologyCalendarStarter? start}) async {
  SharedPreferences.setMockInitialValues({AstrologyCalendarTextSettings.storageKey:font});
  t.view.physicalSize=size;t.view.devicePixelRatio=1;
  addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  final language=AppLanguageSettings.current.value;
  addTearDown(()=>AppLanguageSettings.current.value=language);
  AppLanguageSettings.current.value=english?AppLanguage.en:AppLanguage.ja;
  await t.pumpWidget(MaterialApp(theme:ThemeData.dark().copyWith(
    textTheme:ThemeData.dark().textTheme.apply(fontFamily:'WeekRowsTest')),
    home:AppLanguageScope(child:MediaQuery(data:MediaQueryData(size:size,
      textScaler:TextScaler.linear(scale)),child:AstrologyCalendarView(
        initialDate:date??DateTime.utc(2026,10,18),cacheIdentity:UniqueKey().toString(),
        startJob:start??(date,_)=>f.TabletDoneDay(f.tabletFixture(date,busy:date.endsWith('-18'))))))));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Match the Android Latin/digit font on every host. Ahem's full-em clock
    // digits do not represent the real phone layout on a Linux CI runner.
    final flutterRoot=Platform.environment['FLUTTER_ROOT']??r'C:\Users\pancy\flutter';
    final loader=FontLoader('WeekRowsTest');
    for(final name in ['Roboto-Regular.ttf','Roboto-Bold.ttf']) {
      loader.addFont(File('$flutterRoot/bin/cache/artifacts/material_fonts/$name')
        .readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  });
  test('week preserves Monday-Sunday dates across month, leap day and year boundaries',(){
    for(final date in [DateTime.utc(2026,10,29),DateTime.utc(2028,2,29),DateTime.utc(2027,1,1)]) {
      final dates=astrologyCalendarPhoneWeekDates(date);
      expect(dates.length,7);expect(dates.first.weekday,DateTime.monday);
      expect(dates.last.weekday,DateTime.sunday);expect(dates.toSet().length,7);
      expect(dates,contains(date));
      expect(dates.last.difference(dates.first),const Duration(days:6));
    }
    expect(astrologyCalendarPhoneWeekDates(DateTime.utc(2026,10,29)).last,DateTime.utc(2026,11,1));
  });
  for(final size in [const Size(360,800),const Size(412,915)]) {
    for(final english in [false,true])for(final font in [15.0,19.0])for(final scale in [1.0,1.3]) {
      testWidgets('week rows ${size.width} EN=$english font=$font scale=$scale keep signs and clocks whole inside phone', (t)async{
        await phone(t,size:size,english:english,font:font,scale:scale);
        await t.tap(find.byKey(const ValueKey('calendar-phone-week-load')));await t.pumpAndSettle();
        final rows=t.widget<AstrologyCalendarPhoneWeekRows>(find.byType(AstrologyCalendarPhoneWeekRows));
        expect(rows.days.length,7);expect(rows.days.every((d)=>d.data!=null),isTrue);
        expect(rows.fontSize,font);
        expect(t.widgetList<Scrollable>(find.byType(Scrollable)).every((s)=>s.axisDirection==AxisDirection.down),isTrue);
        for(final day in rows.days) {
          final key=day.date.toIso8601String().substring(0,10);
          final cell=find.byKey(ValueKey('astrology-calendar-day-$key'));
          final rect=t.getRect(cell);expect(rect.left,greaterThanOrEqualTo(0));expect(rect.right,lessThanOrEqualTo(size.width));
          for(final element in find.descendant(of:cell,matching:find.byType(RichText)).evaluate()) {
            final p=element.findRenderObject()! as RenderParagraph;
            final text=(element.widget as RichText).text.toPlainText();
            f.within(p.localToGlobal(Offset.zero)&p.size,rect,reason:'$key $text');
            for(final box in p.getBoxesForSelection(TextSelection(baseOffset:0,extentOffset:text.length))) {
              expect(box.left,greaterThanOrEqualTo(-.6),reason:text);
              expect(box.right,lessThanOrEqualTo(p.size.width+.6),reason:text);
            }
            if(RegExp(r'^\d{2}:\d{2}$').hasMatch(text)||['牡羊座','牡牛座'].contains(text)) {
              expect(p.getBoxesForSelection(TextSelection(baseOffset:0,extentOffset:text.length)),hasLength(1),reason:'Do not split $text');
            }
          }
        }
        final busy=find.byKey(const ValueKey('astrology-calendar-day-2026-10-18'));
        await t.ensureVisible(busy);await t.pumpAndSettle();await t.tap(busy);await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('astrology-calendar-day-dialog')),findsOneWidget);
        expect(t.takeException(),isNull);
      });
    }
  }
  testWidgets('week load includes neighboring month, navigation preserves seven rows and full-month export stays separate', (t)async{
    final calls=<String>[];
    await phone(t,size:const Size(390,844),english:false,font:17,scale:1,date:DateTime.utc(2026,10,29),
      start:(date,_){calls.add(date);return f.TabletDoneDay(f.tabletFixture(date));});
    await t.tap(find.byKey(const ValueKey('calendar-phone-week-load')));await t.pumpAndSettle();
    expect(calls.toSet(),{'2026-10-26','2026-10-27','2026-10-28','2026-10-29','2026-10-30','2026-10-31','2026-11-01'});
    expect(find.text('10/26–11/1'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('astrology-calendar-share-preview')));await t.pumpAndSettle();
    expect(find.textContaining('先に「この月のイベントを一覧取得」'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('calendar-phone-next-week')));await t.pumpAndSettle();
    expect(find.text('11/2–11/8'),findsOneWidget);
    expect(t.widget<AstrologyCalendarPhoneWeekRows>(find.byType(AstrologyCalendarPhoneWeekRows)).days.length,7);
    await t.tap(find.byKey(const ValueKey('calendar-phone-previous-week')));await t.pumpAndSettle();
    expect(find.text('10/26–11/1'),findsOneWidget);
    expect(t.takeException(),isNull);
  });
  testWidgets('changing week cancels pending acquisition and ignores late results', (t)async{
    final jobs=<String,_Pending>{};
    await phone(t,size:const Size(390,844),english:true,font:17,scale:1,
      start:(date,_)=>jobs.putIfAbsent(date,()=>_Pending()));
    jobs['2026-10-18']!.done.complete(f.tabletFixture('2026-10-18'));
    await t.pumpAndSettle();await t.tap(find.byKey(const ValueKey('calendar-phone-week-load')));await t.pump();
    final old=jobs['2026-10-12']!;
    await t.tap(find.byKey(const ValueKey('calendar-phone-next-week')));await t.pump();
    expect(old.cancelled,isTrue);
    old.done.complete(f.tabletFixture('2026-10-12'));await t.pump();
    expect(find.text('10/19–10/25'),findsOneWidget);
    final rows=t.widget<AstrologyCalendarPhoneWeekRows>(find.byType(AstrologyCalendarPhoneWeekRows));
    expect(rows.days.every((d)=>d.data==null),isTrue);
    expect(t.takeException(),isNull);
    await t.pumpWidget(const SizedBox());
  });
}
class _Pending implements AstrologyCalendarOperation {
  final done=Completer<AstrologyCalendarDay>();bool cancelled=false;
  @override Future<AstrologyCalendarDay> get result=>done.future;
  @override void cancel()=>cancelled=true;
}
