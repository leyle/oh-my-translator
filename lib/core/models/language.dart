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
}

extension TranslateModeExtension on TranslateMode {
  String get displayName {
    switch (this) {
      case TranslateMode.translate:
        return 'Translate';
      case TranslateMode.explain:
        return 'Explain';
    }
  }

  String get description {
    switch (this) {
      case TranslateMode.translate:
        return 'Translate text between languages';
      case TranslateMode.explain:
        return 'Explain words or phrases in context';
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

/// Simple heuristic-based language detector using character patterns.
/// This doesn't require an API call and works for common use cases.
class LanguageDetector {
  /// Detect the likely language of the input text.
  /// Returns a language code like 'en', 'zh', 'ja', 'ko', etc.
  /// Falls back to 'en' if uncertain.
  static String detect(String text) {
    if (text.trim().isEmpty) return 'en';
    
    // Count character types
    int cjkCount = 0;      // Chinese/Japanese/Korean
    int japaneseCount = 0; // Hiragana/Katakana
    int koreanCount = 0;   // Hangul
    int arabicCount = 0;
    int thaiCount = 0;
    int devanagariCount = 0; // Hindi
    int cyrillicCount = 0;   // Russian
    int latinCount = 0;
    int total = 0;
    
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      
      // Skip whitespace and punctuation
      if (code <= 0x40 || (code >= 0x5B && code <= 0x60) || (code >= 0x7B && code <= 0x7F)) {
        continue;
      }
      
      total++;
      
      // CJK Unified Ideographs (Chinese characters, also used in Japanese)
      if ((code >= 0x4E00 && code <= 0x9FFF) ||
          (code >= 0x3400 && code <= 0x4DBF) ||
          (code >= 0x20000 && code <= 0x2A6DF)) {
        cjkCount++;
      }
      // Japanese Hiragana
      else if (code >= 0x3040 && code <= 0x309F) {
        japaneseCount++;
      }
      // Japanese Katakana
      else if (code >= 0x30A0 && code <= 0x30FF) {
        japaneseCount++;
      }
      // Korean Hangul
      else if ((code >= 0xAC00 && code <= 0xD7AF) ||
               (code >= 0x1100 && code <= 0x11FF) ||
               (code >= 0x3130 && code <= 0x318F)) {
        koreanCount++;
      }
      // Arabic
      else if (code >= 0x0600 && code <= 0x06FF) {
        arabicCount++;
      }
      // Thai
      else if (code >= 0x0E00 && code <= 0x0E7F) {
        thaiCount++;
      }
      // Devanagari (Hindi)
      else if (code >= 0x0900 && code <= 0x097F) {
        devanagariCount++;
      }
      // Cyrillic (Russian)
      else if (code >= 0x0400 && code <= 0x04FF) {
        cyrillicCount++;
      }
      // Basic Latin
      else if ((code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A)) {
        latinCount++;
      }
    }
    
    if (total == 0) return 'en';
    
    // Determine language based on character distribution
    final threshold = total * 0.3; // 30% threshold
    
    // Japanese has hiragana/katakana mixed with kanji
    if (japaneseCount > 0 && (japaneseCount + cjkCount) > threshold) {
      return 'ja';
    }
    
    // Korean
    if (koreanCount > threshold) {
      return 'ko';
    }
    
    // Chinese (high CJK without Japanese kana)
    if (cjkCount > threshold && japaneseCount == 0) {
      return 'zh';
    }
    
    // Arabic
    if (arabicCount > threshold) {
      return 'ar';
    }
    
    // Thai
    if (thaiCount > threshold) {
      return 'th';
    }
    
    // Hindi
    if (devanagariCount > threshold) {
      return 'hi';
    }
    
    // Russian
    if (cyrillicCount > threshold) {
      return 'ru';
    }
    
    // Default to English for Latin-based text
    return 'en';
  }
}
