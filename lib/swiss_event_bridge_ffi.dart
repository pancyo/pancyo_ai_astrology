import 'dart:convert';
import 'dart:ffi' as ffi;

import 'swiss_event_sample.dart';

typedef _CreateNative =
    ffi.Pointer<ffi.Void> Function(
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Int32,
      ffi.Double,
    );
typedef _CreateDart =
    ffi.Pointer<ffi.Void> Function(int, int, int, int, int, double);
typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Void>);
typedef _IntNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32);
typedef _IntDart = int Function(ffi.Pointer<ffi.Void>, int, int);
typedef _DoubleNative =
    ffi.Double Function(ffi.Pointer<ffi.Void>, ffi.Int32, ffi.Int32);
typedef _DoubleDart = double Function(ffi.Pointer<ffi.Void>, int, int);
typedef _TextNative =
    ffi.Pointer<ffi.Uint8> Function(
      ffi.Pointer<ffi.Void>,
      ffi.Int32,
      ffi.Int32,
    );
typedef _TextDart =
    ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.Void>, int, int);

/// Optional detail ABI. Loading it never touches the legacy bridge state.
/// Older APKs can keep all legacy symbols and still lack this detail API.
class SwissEventBridge implements SwissEventNativeApi {
  SwissEventBridge({ffi.DynamicLibrary? library}) : _providedLibrary = library;
  final ffi.DynamicLibrary? _providedLibrary;
  _CreateDart? _create;
  _FreeDart? _free;
  _IntDart? _int;
  _DoubleDart? _double;
  _TextDart? _text;

  @override
  SwissEventExecutionKind get executionKind =>
      SwissEventExecutionKind.nativeLibrary;

  void _load(DateTime utc) {
    if (_create != null) return;
    try {
      final lib =
          _providedLibrary ?? ffi.DynamicLibrary.open('libpancyo_sweph.so');
      final create = lib.lookupFunction<_CreateNative, _CreateDart>(
        'pancyo_swe_event_sample_create',
      );
      final free = lib.lookupFunction<_FreeNative, _FreeDart>(
        'pancyo_swe_event_sample_free',
      );
      final readInt = lib.lookupFunction<_IntNative, _IntDart>(
        'pancyo_swe_event_sample_int',
      );
      final readDouble = lib.lookupFunction<_DoubleNative, _DoubleDart>(
        'pancyo_swe_event_sample_double',
      );
      final readText = lib.lookupFunction<_TextNative, _TextDart>(
        'pancyo_swe_event_sample_text',
      );
      _free = free;
      _int = readInt;
      _double = readDouble;
      _text = readText;
      _create = create; // Do not commit a partially loaded symbol set.
    } on Object catch (error) {
      throw SwissEventReadFailure(
        'native_detail_api_unavailable',
        '$error',
        utc: utc,
      );
    }
  }

  @override
  SwissEventNativeSample readUtc(DateTime instant) {
    final utc = instant.toUtc();
    if (utc.year < 1 || utc.year > 9999) {
      throw SwissEventReadFailure(
        'unsupported_instant',
        'Gregorian year must be 1..9999',
        utc: utc,
      );
    }
    _load(utc);
    final second =
        utc.second + utc.millisecond / 1000 + utc.microsecond / 1000000;
    final handle = _create!(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      second,
    );
    if (handle.address == 0) {
      throw SwissEventReadFailure(
        'native_allocation_failed',
        'Native create returned NULL',
        utc: utc,
      );
    }
    try {
      int integer(int field, [int planet = 0]) => _int!(handle, field, planet);
      double number(int field, [int planet = 0]) =>
          _double!(handle, field, planet);
      String string(int field, [int planet = 0]) {
        final pointer = _text!(handle, field, planet);
        if (pointer.address == 0) {
          throw SwissEventReadFailure(
            'invalid_native_text',
            'NULL text pointer',
            utc: utc,
          );
        }
        final bytes = <int>[];
        for (var i = 0; i < 256; i++) {
          final byte = pointer[i];
          if (byte == 0) {
            try {
              return utf8.decode(bytes);
            } on FormatException {
              throw SwissEventReadFailure(
                'invalid_native_text',
                'Text is not UTF-8',
                utc: utc,
              );
            }
          }
          bytes.add(byte);
        }
        throw SwissEventReadFailure(
          'invalid_native_text',
          'Missing text terminator',
          utc: utc,
        );
      }

      final abi = integer(0);
      if (abi != 1) {
        throw SwissEventReadFailure(
          'unsupported_abi',
          'Detail ABI $abi',
          utc: utc,
        );
      }
      final echoSecond = number(5);
      if (!echoSecond.isFinite || echoSecond < 0 || echoSecond >= 60) {
        throw SwissEventReadFailure(
          'instant_mismatch',
          'Invalid echoed seconds',
          utc: utc,
        );
      }
      final echoMicroseconds = (echoSecond * 1000000).round();
      if (integer(5) != utc.year ||
          integer(6) != utc.month ||
          integer(7) != utc.day ||
          integer(8) != utc.hour ||
          integer(9) != utc.minute ||
          echoMicroseconds !=
              utc.second * 1000000 + utc.millisecond * 1000 + utc.microsecond) {
        throw SwissEventReadFailure(
          'instant_mismatch',
          'Native input echo differs from requested UTC',
          utc: utc,
        );
      }
      return SwissEventNativeSample(
        utcRequested: utc,
        abiVersion: abi,
        timeStatus: integer(1),
        requestedFlags: integer(2),
        julianDayTt: number(0),
        julianDayUt1: number(1),
        julianDayUt1SpacingSeconds: number(2),
        ephemerisVersion: string(0),
        timeMessage: string(1),
        bodies: [
          for (var i = 0; i < 10; i++)
            SwissEventBodyDiagnostic(
              planetIndex: integer(3, i),
              returnedFlags: integer(4, i),
              longitude: number(3, i),
              longitudeSpeedDegreesPerDay: number(4, i),
              message: string(2, i),
            ),
        ],
      );
    } finally {
      _free!(handle); // Owned strings/positions have already been copied.
    }
  }
}
