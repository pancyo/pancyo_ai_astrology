import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:pancyo_ai_astrology/swiss_ephemeris_bridge.dart';

// Opt-in: real sky data, no fictional profile, no phone, and no substitute engine.
void main() {
 TestWidgetsFlutterBinding.ensureInitialized();
 test('real Swiss calendar month and boundaries, complete save/readback', () {
  final env=Platform.environment;
  final dll=ffi.DynamicLibrary.open(env['PANCYO_CALENDAR_PC_LIBRARY']!);
  final calls=dll.lookupFunction<ffi.Uint64 Function(),int Function()>('pancyo_pc_audit_call_count');
  final bad=dll.lookupFunction<ffi.Uint64 Function(),int Function()>('pancyo_pc_audit_bad_count');
  final flags=dll.lookupFunction<ffi.Int32 Function(),int Function()>('pancyo_pc_audit_last_flags');
  expect(SwissEphemerisBridge.isAvailable,isTrue);
  expect(SwissEphemerisBridge.julianDayUtc(2000,1,1,12),2451545.0);
  final output=Directory(env['PANCYO_CALENDAR_NATIVE_OUTPUT']!);
  expect(output.existsSync(),isFalse,reason:'Never overwrite an earlier run');
  output.createSync(recursive:true);
  final dates=[
    for(var date=DateTime.utc(2026,9,30);!date.isAfter(DateTime.utc(2026,11,1));date=date.add(const Duration(days:1))) date.toIso8601String().substring(0,10),
    '2024-02-29','2024-03-01','2026-12-31','2027-01-01',
  ];
  final records=<Map<String,Object?>>[];
  final stopwatch=Stopwatch()..start();
  for(final date in dates) {
    final day=calculateAstrologyCalendarDay(date);
    expect(day.targetDateJst,date);
    expect(day.usesHighPrecisionAstroData,isTrue);
    expect(day.providerName,'Swiss Ephemeris Free Edition');
    final message=day.toMessage();
    final file=File('${output.path}/$date.json');
    file.writeAsStringSync(jsonEncode(message),flush:true);
    final read=AstrologyCalendarDay.fromMessage(jsonDecode(file.readAsStringSync()));
    expect(read.toMessage(),message);
    final keys=day.events.map((e)=>jsonEncode(e.toMessage())).toList();
    expect(keys.toSet().length,keys.length);
    records.add({'date':date,'events':day.events.length,'void_intervals':day.events.where((e)=>e.kind==AstrologyCalendarEventKind.voidMoon).length});
    print('REAL_SWISS_CALENDAR $date events=${day.events.length}');
  }
  expect(bad(),0);expect(flags() & 7,4);
  File('${output.path}/run.json').writeAsStringSync(jsonEncode({
    'generated_at_utc':DateTime.now().toUtc().toIso8601String(),'data_type':'actual astronomical calculation; no profile',
    'method':'Swiss 2.10.03 explicit Moshier, existing PC library','native_calls':calls(),'bad_or_substituted_calls':bad(),'last_flags':flags(),
    'days':records,'elapsed_ms':stopwatch.elapsedMilliseconds,'mobile_or_adb':false,'readback':'all identical',
  }),flush:true);
 },skip:Platform.environment['PANCYO_CALENDAR_PC_LIBRARY']==null,timeout:const Timeout(Duration(minutes:8)));
}
