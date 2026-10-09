/// A notice shown before photos go to an AI provider (the physique check's
/// `get_my_photo_ai_notice`, meal analysis's `get_my_meal_photo_ai_notice`),
/// and whether the athlete's newest answer grants this exact version.
class PhotoAiNotice {
  const PhotoAiNotice({
    required this.version,
    required this.providerLabel,
    required this.model,
    required this.body,
    required this.granted,
  });

  final String version;
  final String providerLabel;
  final String model;

  /// Paragraphs separated by blank lines, shown verbatim.
  final String body;
  final bool granted;

  /// Null when the response is not a notice.
  static PhotoAiNotice? fromJson(Object? value) {
    if (value is! Map) return null;
    final version = value['version'];
    final body = value['body'];
    if (version is! String || version.isEmpty) return null;
    if (body is! String || body.trim().isEmpty) return null;
    final provider = value['provider_label'];
    final model = value['model'];
    return PhotoAiNotice(
      version: version,
      providerLabel: provider is String ? provider : '',
      model: model is String ? model : '',
      body: body,
      granted: value['granted'] == true,
    );
  }

  PhotoAiNotice withGranted(bool granted) => PhotoAiNotice(
    version: version,
    providerLabel: providerLabel,
    model: model,
    body: body,
    granted: granted,
  );

  List<String> get paragraphs => body
      .split(RegExp(r'\n\s*\n'))
      .map((paragraph) => paragraph.trim())
      .where((paragraph) => paragraph.isNotEmpty)
      .toList();
}
