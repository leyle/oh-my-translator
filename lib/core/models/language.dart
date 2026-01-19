/// Language code and display name for translation
class Language {
  final String code;    // ISO 639-1 code (e.g., "en", "zh", "ja")
  final String name;    // Display name (e.g., "English", "中文", "日本語")
  final String nativeName; // Name in the language itself

  const Language({
    required this.code,
    required this.name,
    required this.nativeName,
  });

  @override
  String toString() => '$name ($code)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Language && runtimeType == other.runtimeType && code == other.code;

  @override
  int get hashCode => code.hashCode;
}

/// Translation mode for different use cases
enum TranslateMode {
  translate,  // Basic translation
  explain,    // Context-aware explanation
  polish,     // Improve writing style
}

extension TranslateModeExtension on TranslateMode {
  String get displayName {
    switch (this) {
      case TranslateMode.translate:
        return 'Translate';
      case TranslateMode.explain:
        return 'Explain';
      case TranslateMode.polish:
        return 'Polish';
    }
  }

  String get description {
    switch (this) {
      case TranslateMode.translate:
        return 'Translate text between languages';
      case TranslateMode.explain:
        return 'Explain words or phrases in context';
      case TranslateMode.polish:
        return 'Improve writing clarity and style';
    }
  }
}

/// Commonly used languages for quick access
class SupportedLanguages {
  static const List<Language> all = [
    Language(code: 'en', name: 'English', nativeName: 'English'),
    Language(code: 'zh', name: 'Chinese', nativeName: '中文'),
    Language(code: 'zh-TW', name: 'Chinese (Traditional)', nativeName: '繁體中文'),
    Language(code: 'ja', name: 'Japanese', nativeName: '日本語'),
    Language(code: 'ko', name: 'Korean', nativeName: '한국어'),
    Language(code: 'es', name: 'Spanish', nativeName: 'Español'),
    Language(code: 'fr', name: 'French', nativeName: 'Français'),
    Language(code: 'de', name: 'German', nativeName: 'Deutsch'),
    Language(code: 'it', name: 'Italian', nativeName: 'Italiano'),
    Language(code: 'pt', name: 'Portuguese', nativeName: 'Português'),
    Language(code: 'ru', name: 'Russian', nativeName: 'Русский'),
    Language(code: 'ar', name: 'Arabic', nativeName: 'العربية'),
    Language(code: 'hi', name: 'Hindi', nativeName: 'हिन्दी'),
    Language(code: 'th', name: 'Thai', nativeName: 'ไทย'),
    Language(code: 'vi', name: 'Vietnamese', nativeName: 'Tiếng Việt'),
    Language(code: 'auto', name: 'Auto Detect', nativeName: 'Auto'),
  ];

  static Language? fromCode(String code) {
    try {
      return all.firstWhere((l) => l.code == code);
    } catch (_) {
      return null;
    }
  }

  static const Language english = Language(code: 'en', name: 'English', nativeName: 'English');
  static const Language chinese = Language(code: 'zh', name: 'Chinese', nativeName: '中文');
  static const Language auto = Language(code: 'auto', name: 'Auto Detect', nativeName: 'Auto');
}
