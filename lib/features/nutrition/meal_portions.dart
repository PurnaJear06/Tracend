/// Portions of a packaged food on the meal review sheet.
///
/// The server stores a label or pack candidate's nutrients per unit
/// (`meal_analysis_candidates.kcal_per_unit` and the rest) in the unit the
/// label prints (`quantity_unit`: grams, or millilitres for a drink) with its
/// serving and pack sizes. Every portion the athlete picks is recalculated
/// here from those values, the same way
/// `supabase/functions/_shared/meal_vision/packaged.ts` worked out the portion
/// it stored: size times the per-unit value, to one decimal. The labels match
/// too. Millilitres are never shown or typed as grams: a drink offers only its
/// printed serving and pack.
library;

/// Grams or millilitres, as `meal_analysis_candidates.quantity_unit` says.
enum QuantityUnit {
  grams('g'),
  millilitres('ml');

  const QuantityUnit(this.symbol);

  final String symbol;

  static QuantityUnit? parse(Object? value) => switch (value) {
    'g' => grams,
    'ml' => millilitres,
    _ => null,
  };
}

/// Nutrients in one gram (or one millilitre) of the food.
class PerUnitNutrients {
  const PerUnitNutrients({
    required this.kcal,
    required this.protein,
    required this.carbohydrate,
    required this.fat,
  });

  final double kcal;
  final double protein;
  final double carbohydrate;
  final double fat;

  /// A portion of [size] units, each value to one decimal.
  PortionNutrients scale(double size) => PortionNutrients(
    calories: roundToTenth(kcal * size),
    protein: roundToTenth(protein * size),
    carbohydrate: roundToTenth(carbohydrate * size),
    fat: roundToTenth(fat * size),
  );
}

class PortionNutrients {
  const PortionNutrients({
    required this.calories,
    required this.protein,
    required this.carbohydrate,
    required this.fat,
  });

  final double calories;
  final double protein;
  final double carbohydrate;
  final double fat;

  /// Whether one meal row can hold every value (the table's checks).
  bool get storable =>
      calories <= 5000 && protein <= 500 && carbohydrate <= 1000 && fat <= 500;
}

/// [amount] is any weight the athlete types; it is never offered for ml.
enum PortionKind { serving, pack, amount }

class PortionOption {
  const PortionOption(this.kind, this.size, this.unit);

  final PortionKind kind;
  final double size;
  final QuantityUnit unit;

  String get label => portionLabel(kind, size, unit);
}

double roundToTenth(double value) => (value * 10).round() / 10;

/// An amount as a label shows it: up to one decimal, no trailing ".0".
String amountText(double amount) {
  final rounded = roundToTenth(amount);
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
}

String portionLabel(PortionKind kind, double size, QuantityUnit unit) {
  final amount = '${amountText(size)} ${unit.symbol}';
  return switch (kind) {
    PortionKind.serving => '1 serving ($amount)',
    PortionKind.pack => 'Whole pack ($amount)',
    PortionKind.amount => amount,
  };
}

/// One serving and the whole pack, where their sizes are known. A typed
/// amount is offered separately, by weight only.
List<PortionOption> portionOptions({
  required double? servingSize,
  required double? packSize,
  required QuantityUnit unit,
}) => [
  if (servingSize != null)
    PortionOption(PortionKind.serving, servingSize, unit),
  if (packSize != null && packSize != servingSize)
    PortionOption(PortionKind.pack, packSize, unit),
];

/// The option the stored portion is, so the chooser starts on it; a typed
/// amount when it is neither the serving nor the pack (by weight), and none
/// when the values are not a portion the chooser offers.
PortionKind? initialPortionKind({
  required double? portionSize,
  required double? servingSize,
  required double? packSize,
  required QuantityUnit unit,
}) {
  if (portionSize == null) return null;
  if (portionSize == servingSize) return PortionKind.serving;
  if (portionSize == packSize) return PortionKind.pack;
  return unit == QuantityUnit.grams ? PortionKind.amount : null;
}
