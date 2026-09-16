import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('birth screen renders the app identity', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PancyoAstrologyApp());
    await tester.pump();

    expect(find.text('ぱんちょ式 超本格占星術占い'), findsWidgets);
    expect(find.text('ホロスコープを読む'), findsOneWidget);
  });

  testWidgets('birth screen restores the most recently saved profile', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'saved_profiles.list': jsonEncode([
        {
          'id': 'profile-older',
          'name': '前の人',
          'birthDate': '1980/9/24',
          'details': {
            'birthTime': '12:00',
            'birthPlace': '北海道札幌市',
            'personality': '',
            'concerns': '',
            'readingStyle': '',
            'useSupplement': true,
          },
          'updatedAt': '2026-09-14T12:00:00.000Z',
        },
        {
          'id': 'profile-latest',
          'name': '今回の人',
          'birthDate': '1990/1/2',
          'details': {
            'birthTime': '08:30',
            'birthPlace': '東京都',
            'personality': '',
            'concerns': '',
            'readingStyle': '',
            'useSupplement': true,
          },
          'updatedAt': '2026-09-15T12:00:00.000Z',
        },
      ]),
    });

    await tester.pumpWidget(const PancyoAstrologyApp());
    await tester.pumpAndSettle();

    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields[0].controller?.text, '今回の人');
    expect(fields[1].controller?.text, '1990/1/2');
    expect(find.text('使用中のプロフィール'), findsOneWidget);
    expect(find.text('このプロフィールで占う'), findsOneWidget);
  });
}
