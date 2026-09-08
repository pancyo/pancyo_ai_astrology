import 'package:flutter_test/flutter_test.dart';

import 'package:pancyo_ai_astrology/main.dart';

void main() {
  test('verified 2026 retrograde windows cover the Uranus station and other planets', () {
    expect(
      DailyAstroEventsCard.verifiedRetrogradesAt(DateTime.utc(2026, 9, 10, 18, 27)),
      contains(AstroPlanet.uranus),
    );
    expect(
      DailyAstroEventsCard.verifiedRetrogradesAt(DateTime.utc(2026, 9, 10, 18, 26)),
      isNot(contains(AstroPlanet.uranus)),
    );

    final autumn = DailyAstroEventsCard.verifiedRetrogradesAt(DateTime.utc(2026, 10, 10));
    expect(autumn, containsAll(<AstroPlanet>[
      AstroPlanet.saturn,
      AstroPlanet.uranus,
      AstroPlanet.neptune,
      AstroPlanet.pluto,
      AstroPlanet.venus,
    ]));
    expect(autumn, isNot(contains(AstroPlanet.mercury)));

    final yearEnd = DailyAstroEventsCard.verifiedRetrogradesAt(DateTime.utc(2026, 12, 13, 10));
    expect(yearEnd, containsAll(<AstroPlanet>[
      AstroPlanet.jupiter,
      AstroPlanet.uranus,
    ]));
    expect(yearEnd, isNot(contains(AstroPlanet.saturn)));
    expect(yearEnd, isNot(contains(AstroPlanet.neptune)));
  });
}
