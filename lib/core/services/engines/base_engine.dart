import '../../models/language.dart';

/// Abstract base class for AI translation engines
/// All engines must implement this interface for consistent behavior
abstract class BaseEngine {
  /// Translate text and return a stream of response chunks (for streaming)
  /// 
  /// Parameters:
  /// - [text]: The text to translate/process
  /// - [sourceLanguage]: Source language code (or 'auto' for detection)
  /// - [targetLanguage]: Target language code
  /// - [mode]: Translation mode (translate, explain, polish)
  /// 
  /// Returns a stream of text chunks for real-time display
  Stream<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
    required TranslateMode mode,
  });

  /// Explain a selected word/phrase in the context of a sentence
  /// 
  /// Parameters:
  /// - [selectedWord]: The word or phrase selected by user
  /// - [fullContext]: The full sentence containing the word
  /// - [sourceLanguage]: Source language code
  /// - [targetLanguage]: Target language for explanation
  /// 
  /// Returns a stream of explanation chunks
  Stream<String> explainInContext({
    required String selectedWord,
    required String fullContext,
    required String sourceLanguage,
    required String targetLanguage,
  });

  /// Test if the engine configuration is valid and API is reachable
  Future<bool> testConnection();

  /// Get the display name of this engine
  String get name;

  /// Dispose of any resources held by the engine
  void dispose() {}
}

/// Exception thrown when translation fails
class TranslationException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  const TranslationException({
    required this.message,
    this.statusCode,
    this.responseBody,
  });

  @override
  String toString() => 'TranslationException: $message (status: $statusCode)';
}
