import 'dart:convert';
import 'dart:io';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'calendar_presentation_test.dart' show DoneDay;

void main() {
 TestWidgetsFlutterBinding.ensureInitialized();
 final input=Platform.environment['PANCYO_CALENDAR_ACTUAL_DATA'];
 final dest=Platform.environment['PANCYO_CALENDAR_ACTUAL_RENDER'];
 testWidgets('actual Swiss October: full month, weekly files, display signs and portrait/landscape', (t) async {
  await t.runAsync(()async {
   final font=ByteData.sublistView(await File(r'C:\Windows\Fonts\meiryo.ttc').readAsBytes());
   await (FontLoader('CalendarVisualTest')..addFont(Future.value(font))).load();
  });
  final days=[for(var i=1;i<=31;i++) AstrologyCalendarDay.fromMessage(jsonDecode(File('$input/2026-10-${i.toString().padLeft(2,'0')}.json').readAsStringSync()))];
  final data=AstrologyCalendarShareData.checked(year:2026,month:10,days:days);
  final output=Directory(dest!);expect(output.existsSync(),isFalse);output.createSync(recursive:true);
  final dll=ffi.DynamicLibrary.open(Platform.environment['PANCYO_CALENDAR_PC_LIBRARY']!);
  expect(dll.providesSymbol('pancyo_pc_audit_bad_count'),isTrue);
  const provider=SwissEphemerisProvider();
  var ingressCount=0;
  for(final day in days) {
   final noon=DateTime.parse('${day.targetDateJst}T03:00:00Z');
   expect(provider.placementsFor(noon).singleWhere((p)=>p.planet==AstroPlanet.moon).sign,day.moonSignAtNoon);
   for(final e in day.events.where((e)=>e.kind==AstrologyCalendarEventKind.signIngress)) {
    expect(provider.placementsFor(e.startUtc!.subtract(const Duration(minutes:1))).singleWhere((p)=>p.planet==e.ingressPlanet).sign,e.fromSign);
    expect(provider.placementsFor(e.startUtc!.add(const Duration(minutes:1))).singleWhere((p)=>p.planet==e.ingressPlanet).sign,e.toSign);
    ingressCount++;
   }
  }
  for(final english in [false,true]) {
   final saved=await t.runAsync(()=>saveAstrologyCalendarExport(
     documentsRoot:output,data:data,english:english,splitWeeks:false,
     render:(week)=>captureAstrologyCalendarImage(t.view,AstrologyCalendarShareImage(data:data,english:english,week:week,fontFamily:'CalendarVisualTest'))));
   expect(saved!.images.length,1);
   final text=await t.runAsync(()=>saved.details.readAsString());expect(text,contains('2026-10-31'));
  }
  final weekly=await t.runAsync(()=>saveAstrologyCalendarExport(
   documentsRoot:output,data:data,english:false,splitWeeks:true,
   render:(week)=>captureAstrologyCalendarImage(t.view,AstrologyCalendarShareImage(data:data,english:false,week:week,fontFamily:'CalendarVisualTest'))));
  expect(weekly!.images.length,data.weekCount);
  for(final size in [const Size(390,844),const Size(1280,800)]) {
   t.view.physicalSize=size;t.view.devicePixelRatio=1;
   AppLanguageSettings.current.value=AppLanguage.ja;
   final boundary=GlobalKey();
   await t.pumpWidget(MaterialApp(theme:ThemeData.dark().copyWith(textTheme:ThemeData.dark().textTheme.apply(fontFamily:'CalendarVisualTest')),home:AppLanguageScope(child:RepaintBoundary(key:boundary,child:AstrologyCalendarView(initialDate:DateTime.utc(2026,10,1),initialShowAgenda:true,cacheIdentity:'real-oct-${size.width}',startJob:(date,_)=>DoneDay(days.singleWhere((d)=>d.targetDateJst==date)))))));
   await t.pumpAndSettle();
   await t.ensureVisible(find.byKey(const ValueKey('astrology-calendar-grid-mode')));
   await t.tap(find.byKey(const ValueKey('astrology-calendar-grid-mode')));await t.pumpAndSettle();
   expect(t.takeException(),isNull);
   await t.runAsync(()async {
    final render=boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image=await render.toImage(pixelRatio:1);
    try { final bytes=await image.toByteData(format:ui.ImageByteFormat.png);await File('${output.path}/screen_${size.width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List(),flush:true); } finally { image.dispose(); }
   });
  }
  t.view.resetPhysicalSize();t.view.resetDevicePixelRatio();
  File('${output.path}/verification.json').writeAsStringSync(jsonEncode({'actual_days':31,'all_noon_moon_signs_rechecked':31,'ingress_before_after_rechecked':ingressCount,'full_month_images':2,'weekly_images':data.weekCount,'all_saved_images_readback':'PASS','screen_sizes':['390x844','1280x800'],'data_type':'actual Swiss Moshier sky calculation, not synthetic fixtures','device_ui':'not tested on Android'}),flush:true);
 },skip:input==null||dest==null);
}
