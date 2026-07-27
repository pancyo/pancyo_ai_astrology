import 'package:flutter_test/flutter_test.dart';
import 'package:pancyo_ai_astrology/main.dart';

void main() {
  testWidgets('birth screen renders the app identity', (WidgetTester tester) async {
    await tester.pumpWidget(const PancyoAstrologyApp());
    await tester.pump();

    expect(find.text('ぱんちょ式 超本格占星術占い'), findsWidgets);
    expect(find.text('ホロスコープを読む'), findsOneWidget);
  });
}
