/// Portions of a packaged food on the meal review sheet.
///
/// The server stores a label or pack candidate's nutrients per gram
/// (`meal_analysis_candidates.kcal_per_g` and the rest) with its serving and
/// pack weights. Every portion the athlete picks is recalculated here from
/// those values, the same way `supabase/functions/_shared/meal_vision/packaged.ts`
/// worked out the portion it stored: grams times the per-gram value, to one
/// decimal. The labels match too, so the stored portion reads the same here.
library;

/// Nutrients in one gram of the food.
class PerGramNutrients {
  const PerGramNutrients({
    required this.kcal,
    required this.protein,
    required this.carbohydrate,
    required this.fat,
  });

  final double kcal;
  final double protein;
  final double carbohydrate;
  final double fat;

  /// A portion of [grams], each value to one decimal.
  PortionNutrients scale(double grams) => PortionNutrients(
    calories: roundToTenth(kcal * grams),
    protein: roundToTenth(protein * grams),
    carbohydrate: roundToTenth(carbohydrate * grams),
    fat: roundToTenth(fat * grams),
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
}

enum PortionKind { serving, pack, grams }

class PortionOption {
  const PortionOption(this.kind, this.grams);

  final PortionKind kind;
  final double grams;

  String get label => portionLabel(kind, grams);
}

double roundToTenth(double value) => (value * 10).round() / 10;

/// Grams as a label shows them: up to one decimal, no trailing ".0".
String gramsText(double grams) {
  final rounded = roundToTenth(grams);
  return rounded == rounded.roundToDouble()
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(1);
}

String portionLabel(PortionKind kind, double grams) => switch (kind) {
  PortionKind.serving => '1 serving (${gramsText(grams)} g)',
  PortionKind.pack => 'Whole pack (${gramsText(grams)} g)',
  PortionKind.grams => '${gramsText(grams)} g',
};

/// One serving and the whole pack, where their weights are known. Any grams
/// can be typed as well.
List<PortionOption> portionOptions({
  required double? servingGrams,
  required double? packGrams,
}) => [
  if (servingGrams != null) PortionOption(PortionKind.serving, servingGrams),
  if (packGrams != null && packGrams != servingGrams)
    PortionOption(PortionKind.pack, packGrams),
];

/// The option the stored portion is, so the chooser starts on it; grams when
/// it is neither the serving nor the pack.
PortionKind initialPortionKind({
  required double? portionGrams,
  required double? servingGrams,
  required double? packGrams,
}) {
  if (portionGrams != null && portionGrams == servingGrams) {
    return PortionKind.serving;
  }
  if (portionGrams != null && portionGrams == packGrams) {
    return PortionKind.pack;
  }
  return PortionKind.grams;
}
