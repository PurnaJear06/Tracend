/// Display names for AI providers. The owner switches providers by budget,
/// so screens never hard-wire one: they pass the server's provider or model
/// id through [aiProviderDisplayName] and show just "AI" when it gives null.
library;

/// Provider id → the name people see.
const aiProviderDisplayNames = {
  'deepseek': 'DeepSeek',
  'groq': 'Qwen',
  'gemini': 'Gemini',
  'mock': 'Test model',
};

/// The display name for a provider id ("deepseek") or a model id that starts
/// with one ("deepseek-chat", "gemini-3.5-flash"). Null for a blank or
/// unknown id, so a raw id never reaches the screen.
String? aiProviderDisplayName(String? id) {
  final value = id?.trim().toLowerCase() ?? '';
  if (value.isEmpty) return null;
  for (final entry in aiProviderDisplayNames.entries) {
    final key = entry.key;
    if (value == key) return entry.value;
    if (value.startsWith(key) &&
        RegExp(r'[-/._:0-9]').hasMatch(value[key.length])) {
      return entry.value;
    }
  }
  return null;
}
