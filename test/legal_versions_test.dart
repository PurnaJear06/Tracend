import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/consent/legal_consent.dart';

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// The page's "Last updated" date as an ISO date, the version the app
/// records consent against.
String _pageVersion(String path) {
  final page = File(path).readAsStringSync();
  final dates = RegExp(
    r'<p class="doc-date">Last updated (\d{1,2}) ([A-Za-z]+) (\d{4})</p>',
  ).allMatches(page).toList();
  expect(dates, hasLength(1), reason: '$path needs one "Last updated" date');
  final date = dates.single;
  final month = _months.indexOf(date.group(2)!) + 1;
  expect(month, greaterThan(0), reason: '${date.group(2)} is not a month');
  final day = int.parse(date.group(1)!);
  return '${date.group(3)}-${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}

void main() {
  // Editing a legal page changes its date, and the app must then record and
  // ask for that version: this fails until the constant matches the page.
  test('the beta terms version is the page date', () {
    expect(
      LegalNotices.termsVersion,
      _pageVersion('site/src/pages/beta-terms.astro'),
    );
  });

  test('the privacy version is the page date', () {
    expect(
      LegalNotices.privacyVersion,
      _pageVersion('site/src/pages/privacy.astro'),
    );
  });

  test('health-data consent is given against the privacy notice', () {
    expect(LegalConsent.healthData.version, LegalNotices.privacyVersion);
    expect(LegalConsent.healthData.type, 'health_data');
  });

  test('the app links the pages the versions come from', () {
    expect(
      LegalNotices.termsUrl.toString(),
      'https://tracend.pages.dev/beta-terms/',
    );
    expect(
      LegalNotices.privacyUrl.toString(),
      'https://tracend.pages.dev/privacy/',
    );
  });
}
