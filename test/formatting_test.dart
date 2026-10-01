import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/shared/formatting.dart';

void main() {
  final now = DateTime(2026, 10, 1, 9);

  test('friendlyDate names today, yesterday, then weekday and date', () {
    expect(friendlyDate(DateTime(2026, 10, 1, 22), now: now), 'Today');
    expect(friendlyDate(DateTime(2026, 9, 30), now: now), 'Yesterday');
    expect(friendlyDate(DateTime(2026, 9, 28), now: now), 'Mon 28 Sep');
    expect(friendlyDate(DateTime(2025, 12, 31), now: now), 'Wed 31 Dec 2025');
  });

  test('shortDate adds the year only when it differs', () {
    expect(shortDate(DateTime(2026, 8, 1), now: now), '1 Aug');
    expect(shortDate(DateTime(2025, 8, 1), now: now), '1 Aug 2025');
  });

  test('kgPerWeek converts the daily slope and signs it', () {
    expect(kgPerWeek(-0.0571), '−0.4 kg/week');
    expect(kgPerWeek(0.03), '+0.2 kg/week');
    expect(kgPerWeek(0.001), '0.0 kg/week');
  });

  test('labels replace stored codes', () {
    expect(mealTypeLabel('lunch'), 'Lunch');
    expect(mealTypeLabel('brunch'), 'Brunch');
    expect(measurementSourceLabel('manual'), 'Entered by you');
    expect(measurementSourceLabel('healthkit'), 'Apple Health');
    expect(periodLabel(28), '4 weeks');
    expect(periodLabel(84), '12 weeks');
    expect(periodLabel(182), '6 months');
  });
}
