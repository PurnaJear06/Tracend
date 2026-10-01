/// Human-facing formatting shared by every screen. Values are only
/// reformatted here, never rounded into new meaning: a missing value stays
/// missing and the caller decides how to say so.
library;

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "22 Aug", or "22 Aug 2025" when the year differs from [now].
String shortDate(DateTime date, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final base = '${date.day} ${_months[date.month - 1]}';
  return date.year == reference.year ? base : '$base ${date.year}';
}

/// "Today", "Yesterday", or "Mon 22 Aug" (with the year when it differs).
String friendlyDate(DateTime date, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final day = DateTime(date.year, date.month, date.day);
  final difference = today.difference(day).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  return '${_weekdays[day.weekday - 1]} ${shortDate(day, now: reference)}';
}

/// "Breakfast" for `breakfast`; unknown values are capitalized as-is.
String mealTypeLabel(String type) => switch (type) {
  'breakfast' => 'Breakfast',
  'lunch' => 'Lunch',
  'dinner' => 'Dinner',
  'snack' => 'Snack',
  _ => type.isEmpty ? type : '${type[0].toUpperCase()}${type.substring(1)}',
};

/// Where a body measurement came from, in the user's words.
String measurementSourceLabel(String source) => switch (source) {
  'manual' => 'Entered by you',
  'healthkit' => 'Apple Health',
  _ => 'Recorded',
};

/// Converts a kg/day slope to kg/week ("−0.4 kg/week", "+0.2 kg/week").
/// Uses a true minus sign so the sign reads clearly next to digits.
String kgPerWeek(double kgPerDay) {
  final weekly = kgPerDay * 7;
  final rounded = double.parse(weekly.toStringAsFixed(1));
  if (rounded == 0) return '0.0 kg/week';
  final sign = rounded > 0 ? '+' : '−';
  return '$sign${rounded.abs().toStringAsFixed(1)} kg/week';
}

/// "1 day", "3 weeks", "6 months": the span a period selection covers.
String periodLabel(int days) {
  if (days >= 180) return '${(days / 30.4).round()} months';
  if (days >= 14) return '${(days / 7).round()} weeks';
  return days == 1 ? '1 day' : '$days days';
}
