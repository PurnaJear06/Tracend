/// The exercise catalog's muscle vocabulary (`exercise_catalog.primary_muscles`).
///
/// The order is the catalog's display order and breaks ties when two groups
/// carry the same number of sets.
enum MuscleGroup {
  chest('chest', 'Chest'),
  back('back', 'Back'),
  shoulders('shoulders', 'Shoulders'),
  biceps('biceps', 'Biceps'),
  triceps('triceps', 'Triceps'),
  core('core', 'Core'),
  quads('quads', 'Quads'),
  hamstrings('hamstrings', 'Hamstrings'),
  glutes('glutes', 'Glutes'),
  calves('calves', 'Calves');

  const MuscleGroup(this.key, this.label);

  /// The catalog key, as the hub sends it.
  final String key;

  /// The display name, as the muscle chips show it.
  final String label;

  /// The group for a catalog key; null for anything outside the vocabulary,
  /// which is dropped rather than guessed.
  static MuscleGroup? fromKey(Object? key) {
    for (final group in values) {
      if (group.key == key) return group;
    }
    return null;
  }
}
