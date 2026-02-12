import '../models/language.dart';
import '../models/provider_config.dart';
import '../models/prompt_templates.dart';
import 'engines/base_engine.dart';
import 'engines/openai_compatible_engine.dart';

/// Service for managing translation operations
/// Handles engine selection and translation execution
class TranslationService {
  ProviderConfig? _activeProvider;
  BaseEngine? _engine;
  PromptTemplates _promptTemplates = PromptTemplates.defaults();

  PromptTemplates get promptTemplates => _promptTemplates;

  /// Set the active provider for translations
  void setProvider(ProviderConfig provider) {
    _activeProvider = provider;
    _engine?.dispose();
    _engine = OpenAICompatibleEngine(
      config: provider,
      promptTemplates: _promptTemplates,
    );
  }

  /// Set prompt templates and refresh active engine.
  void setPromptTemplates(PromptTemplates templates) {
    _promptTemplates = templates;
    final provider = _activeProvider;
    if (provider != null) {
      _engine?.dispose();
      _engine = OpenAICompatibleEngine(
        config: provider,
        promptTemplates: _promptTemplates,
      );
    }
  }

  /// Get the currently active provider
  ProviderConfig? get activeProvider => _activeProvider;

  /// Check if a provider is configured
  bool get hasProvider => _activeProvider != null && _engine != null;

  /// Translate text using the active provider
  /// Returns a stream of text chunks for real-time display
  Stream<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
    required TranslateMode mode,
  }) {
    if (_engine == null) {
      throw StateError('No provider configured. Call setProvider() first.');
    }

    return _engine!.translate(
      text: text,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      mode: mode,
    );
  }

  /// Explain a selected word/phrase in the context of the full sentence
  Stream<String> explainInContext({
    required String selectedWord,
    required String fullContext,
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    if (_engine == null) {
      throw StateError('No provider configured. Call setProvider() first.');
    }

    return _engine!.explainInContext(
      selectedWord: selectedWord,
      fullContext: fullContext,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
  }

  /// Test the connection to the active provider
  Future<bool> testConnection() async {
    if (_engine == null) return false;
    return await _engine!.testConnection();
  }

  /// Dispose resources
  void dispose() {
    _engine?.dispose();
    _engine = null;
    _activeProvider = null;
  }
}
