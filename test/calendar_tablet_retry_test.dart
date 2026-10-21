import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/app_language.dart';
import 'package:pancyo_ai_astrology/app_language_settings.dart';
import 'package:pancyo_ai_astrology/main.dart';

// Synthetic asynchronous acquisition fixtures; no ephemeris/profile access.
AstrologyCalendarDay retryFixture(String date) => AstrologyCalendarDay(
  targetDateJst: date,
  events: const [],
  moonSignAtNoon: ZodiacSign.taurus,
  providerName: 'SYNTHETIC RETRY SOURCE',
  precisionNotice: 'Synthetic retry test; not astronomical observations.',
  usesHighPrecisionAstroData: false,
);

class RetryControlledDay implements AstrologyCalendarOperation {
  final completer = Completer<AstrologyCalendarDay>();
  bool cancelled = false;
  @override
  Future<AstrologyCalendarDay> get result => completer.future;
  @override
  void cancel() => cancelled = true;
}

class RetryReadyDay implements AstrologyCalendarOperation {
  RetryReadyDay(this.date);
  final String date;
  @override
  Future<AstrologyCalendarDay> get result => Future.value(retryFixture(date));
  @override
  void cancel() {}
}

final retryDialog = find.byKey(const ValueKey('astrology-calendar-day-dialog'));
Finder inRetryDialog(Finder matching) =>
    find.descendant(of: retryDialog, matching: matching);

Future<void> openRetryDay(
  WidgetTester tester, {
  required AstrologyCalendarStarter starter,
  required String identity,
}) async {
  const size = Size(1181.54, 738.46);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final oldLanguage = AppLanguageSettings.current.value;
  AppLanguageSettings.current.value = AppLanguage.ja;
  addTearDown(() => AppLanguageSettings.current.value = oldLanguage);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: AppLanguageScope(
        child: MediaQuery(
          data: const MediaQueryData(
            size: size,
            padding: EdgeInsets.only(top: 24, bottom: 48),
            viewPadding: EdgeInsets.only(top: 24, bottom: 48),
          ),
          child: AstrologyCalendarView(
            initialDate: DateTime.utc(2026, 11, 17),
            initialShowAgenda: false,
            cacheIdentity: identity,
            startJob: starter,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('astrology-calendar-day-2026-11-18')),
  );
  // Do not pumpAndSettle while the intentionally pending operation shows an
  // indeterminate spinner. Advance only the dialog's entrance animation.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(retryDialog, findsOneWidget);
}

void main() {
  testWidgets(
    'dialog asynchronous failure then retry immediately shows spinner, live progress and success',
    (tester) async {
      final jobs = <RetryControlledDay>[];
      final progress = <void Function(int, int)>[];
      await openRetryDay(
        tester,
        identity: 'tablet-retry-async-success',
        starter: (date, callback) {
          if (date != '2026-11-18') return RetryReadyDay(date);
          final job = RetryControlledDay();
          jobs.add(job);
          progress.add(callback);
          return job;
        },
      );
      expect(jobs.length, 1);
      jobs.single.completer.completeError(
        StateError('Synthetic initial asynchronous failure'),
      );
      await tester.pumpAndSettle();
      expect(inRetryDialog(find.text('星の動きを取得できませんでした。')), findsOneWidget);
      expect(inRetryDialog(find.text('再試行')), findsOneWidget);
      expect(
        inRetryDialog(find.byType(CircularProgressIndicator)),
        findsNothing,
      );

      await tester.tap(inRetryDialog(find.text('再試行')));
      await tester.pump();
      expect(jobs.length, 2);
      expect(
        inRetryDialog(find.byType(CircularProgressIndicator)),
        findsOneWidget,
      );
      expect(inRetryDialog(find.text('星の動きを調べています…')), findsOneWidget);
      expect(inRetryDialog(find.text('再試行')), findsNothing);
      expect(inRetryDialog(find.text('星の動きを取得できませんでした。')), findsNothing);
      expect(inRetryDialog(find.byType(LinearProgressIndicator)), findsNothing);

      progress.last(5, 20);
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              inRetryDialog(find.byType(LinearProgressIndicator)),
            )
            .value,
        .25,
      );
      progress.last(17, 20);
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              inRetryDialog(find.byType(LinearProgressIndicator)),
            )
            .value,
        .85,
      );

      jobs.last.completer.complete(retryFixture('2026-11-18'));
      await tester.pumpAndSettle();
      expect(
        inRetryDialog(find.byType(CircularProgressIndicator)),
        findsNothing,
      );
      expect(inRetryDialog(find.byType(LinearProgressIndicator)), findsNothing);
      expect(inRetryDialog(find.text('再試行')), findsNothing);
      expect(inRetryDialog(find.text('月：牡牛座')), findsOneWidget);
      expect(
        inRetryDialog(find.textContaining('SYNTHETIC RETRY SOURCE')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dialog synchronous retry throw keeps failure and retry action visible',
    (tester) async {
      final first = RetryControlledDay();
      var attempts = 0;
      await openRetryDay(
        tester,
        identity: 'tablet-retry-sync-throw',
        starter: (date, callback) {
          if (date != '2026-11-18') return RetryReadyDay(date);
          attempts++;
          if (attempts > 1)
            throw StateError('Synthetic synchronous retry failure');
          return first;
        },
      );
      first.completer.completeError(
        StateError('Synthetic initial asynchronous failure'),
      );
      await tester.pumpAndSettle();
      await tester.tap(inRetryDialog(find.text('再試行')));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(inRetryDialog(find.text('星の動きを取得できませんでした。')), findsOneWidget);
      expect(inRetryDialog(find.text('再試行')), findsOneWidget);
      expect(
        inRetryDialog(find.byType(CircularProgressIndicator)),
        findsNothing,
      );
      expect(inRetryDialog(find.byType(LinearProgressIndicator)), findsNothing);
      expect(inRetryDialog(find.text('なし')), findsNothing);
      expect(
        inRetryDialog(find.textContaining('SYNTHETIC RETRY SOURCE')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closing a pending dialog safely accepts later progress and completion, reopening cached result',
    (tester) async {
      final job = RetryControlledDay();
      late void Function(int, int) progress;
      var requests = 0;
      await openRetryDay(
        tester,
        identity: 'tablet-retry-close-pending',
        starter: (date, callback) {
          if (date != '2026-11-18') return RetryReadyDay(date);
          requests++;
          progress = callback;
          return job;
        },
      );
      await tester.tap(inRetryDialog(find.text('閉じる')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(retryDialog, findsNothing);
      progress(3, 17);
      await tester.pump();
      job.completer.complete(retryFixture('2026-11-18'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.byKey(const ValueKey('astrology-calendar-day-2026-11-18')),
      );
      await tester.pumpAndSettle();
      expect(
        requests,
        1,
        reason: 'The completed result is reused after dialog reopening.',
      );
      expect(inRetryDialog(find.text('月：牡牛座')), findsOneWidget);
      expect(
        inRetryDialog(find.textContaining('SYNTHETIC RETRY SOURCE')),
        findsOneWidget,
      );
      expect(
        inRetryDialog(find.byType(CircularProgressIndicator)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
