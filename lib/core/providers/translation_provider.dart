import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/language.dart';
import '../services/translation_service.dart';
import '../services/shell_executor.dart';
import '../models/custom_action.dart';

/// State for a translation operation
enum TranslationState {
  idle,
  translating,
  completed,
  error,
}

/// Provider for managing translation state and operations
class TranslationProvider extends ChangeNotifier {
  final TranslationService _translationService;
  final ShellExecutor _shellExecutor;

  TranslationState _state = TranslationState.idle;
  String _sourceText = '';
  String _resultText = '';
  String _errorMessage = '';
  TranslateMode _mode = TranslateMode.translate;
  String _sourceLanguage = 'auto';
  String _targetLanguage = 'zh';
  
  // Store last translation result to restore after word explanation
  String? _lastTranslationResult;
  String? _lastTranslationModelKey; // Track model used for last translation
  
  // Track if we're in word explanation mode
  bool _isInWordExplanationMode = false;
  String? _lastExplainedWord;
  String? _lastExplainContext;
  
  // Track last known model for change detection
  String? _lastKnownModelKey;
  
  // LRU Cache for explanations/translations
  // Key format: "${providerName}:${model}:${targetLang}:${sourceText}:${selectedWord}"
  final Map<String, String> _cache = {};
  static const int _cacheMaxSize = 50;
  
  StreamSubscription<String>? _translationSubscription;

  TranslationProvider({
    required TranslationService translationService,
    ShellExecutor? shellExecutor,
  })  : _translationService = translationService,
        _shellExecutor = shellExecutor ?? ShellExecutor();

  // Getters
  TranslationState get state => _state;
  String get sourceText => _sourceText;
  String get resultText => _resultText;
  String get errorMessage => _errorMessage;
  TranslateMode get mode => _mode;
  String get sourceLanguage => _sourceLanguage;
  String get targetLanguage => _targetLanguage;
  bool get isTranslating => _state == TranslationState.translating;
  bool get hasResult => _resultText.isNotEmpty;
  bool get hasError => _state == TranslationState.error;
  
  /// Get current model key for comparison
  String _getCurrentModelKey() {
    final provider = _translationService.activeProvider;
    final providerName = provider?.name ?? 'unknown';
    final model = provider?.model ?? 'unknown';
    return '$providerName:$model';
  }
  
  /// Check if we have a last translation to restore
  bool get hasLastTranslation => _lastTranslationResult != null && _lastTranslationResult!.isNotEmpty;
  
  /// Restore the last translation result (used when deselecting after word explanation)
  /// If model has changed since the translation was saved, re-translate instead
  void restoreLastTranslation() {
    // Clear word explanation mode since we're back to full sentence
    _isInWordExplanationMode = false;
    _lastExplainedWord = null;
    _lastExplainContext = null;
    
    // Check if model has changed since the translation was saved
    if (_lastTranslationModelKey != _getCurrentModelKey()) {
      // Model changed - re-translate instead of restoring stale result
      translate();
      return;
    }
    
    // Model is the same - safe to restore
    if (_lastTranslationResult != null) {
      _resultText = _lastTranslationResult!;
      _state = TranslationState.completed;
      notifyListeners();
    }
  }
  
  /// Check if model changed and auto-refresh the current view
  /// Call this when model selection changes
  void checkModelAndRefresh() {
    final currentModelKey = _getCurrentModelKey();
    
    // If this is the first check, just record the model
    if (_lastKnownModelKey == null) {
      _lastKnownModelKey = currentModelKey;
      return;
    }
    
    // If model hasn't changed, nothing to do
    if (_lastKnownModelKey == currentModelKey) {
      return;
    }
    
    // Model changed - update tracking
    _lastKnownModelKey = currentModelKey;
    
    // Clear cache since model changed
    _cache.clear();
    
    // Auto-refresh based on current mode
    if (_isInWordExplanationMode && _lastExplainedWord != null && _lastExplainContext != null) {
      // Re-explain the word with new model
      explainInContext(
        selectedWord: _lastExplainedWord!,
        fullContext: _lastExplainContext!,
      );
    } else if (_sourceText.isNotEmpty && _state == TranslationState.completed) {
      // Re-translate with new model
      translate();
    }
  }
  
  /// Build cache key from parameters (includes provider+model to invalidate on change)
  String _buildCacheKey(String sourceText, String selectedWord) {
    final provider = _translationService.activeProvider;
    final providerName = provider?.name ?? 'unknown';
    final model = provider?.model ?? 'unknown';
    return '$providerName:$model:$_targetLanguage:$sourceText:$selectedWord';
  }
  
  // Track what model the cache was built for
  String? _lastCacheModelKey;
  
  /// Add to cache with LRU eviction
  void _addToCache(String key, String value) {
    // Track the model this cache is for
    _lastCacheModelKey = _getCurrentModelKey();
    
    // Remove oldest if at max size
    if (_cache.length >= _cacheMaxSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }
  
  /// Get from cache (returns null if not found)
  /// Also clears cache if model has changed
  String? _getFromCache(String key) {
    // If model changed, clear entire cache
    final currentModelKey = _getCurrentModelKey();
    if (_lastCacheModelKey != null && _lastCacheModelKey != currentModelKey) {
      _cache.clear();
      _lastCacheModelKey = currentModelKey;
      return null;
    }
    
    final value = _cache[key];
    if (value != null) {
      // Move to end (most recently used)
      _cache.remove(key);
      _cache[key] = value;
    }
    return value;
  }

  /// Set the source text for translation
  void setSourceText(String text) {
    _sourceText = text.trim();
    notifyListeners();
  }

  /// Set the translation mode
  void setMode(TranslateMode mode) {
    _mode = mode;
    notifyListeners();
  }

  /// Set source language
  void setSourceLanguage(String code) {
    _sourceLanguage = code;
    notifyListeners();
  }

  /// Set target language
  void setTargetLanguage(String code) {
    _targetLanguage = code;
    notifyListeners();
  }

  /// Start translation with current settings
  Future<void> translate() async {
    if (_sourceText.isEmpty) return;
    if (!_translationService.hasProvider) {
      _errorMessage = 'No AI provider configured. Please add a provider in Settings.';
      _state = TranslationState.error;
      notifyListeners();
      return;
    }

    // Cancel any ongoing translation
    await _translationSubscription?.cancel();

    _state = TranslationState.translating;
    _resultText = '';
    _errorMessage = '';
    notifyListeners();

    try {
      final stream = _translationService.translate(
        text: _sourceText,
        sourceLanguage: _sourceLanguage,
        targetLanguage: _targetLanguage,
        mode: _mode,
      );

      _translationSubscription = stream.listen(
        (chunk) {
          _resultText += chunk;
          notifyListeners();
        },
        onDone: () {
          _state = TranslationState.completed;
          // Save translation result for restoration after word explanation
          _lastTranslationResult = _resultText;
          _lastTranslationModelKey = _getCurrentModelKey();
          // Track model for change detection
          _lastKnownModelKey = _getCurrentModelKey();
          // Clear word explanation mode since we're in full sentence mode
          _isInWordExplanationMode = false;
          notifyListeners();
        },
        onError: (error) {
          _errorMessage = error.toString();
          _state = TranslationState.error;
          notifyListeners();
        },
      );
    } catch (e) {
      _errorMessage = e.toString();
      _state = TranslationState.error;
      notifyListeners();
    }
  }

  /// Explain a selected word/phrase in the context of the full sentence
  /// If selectedWord equals fullContext, explains the full sentence
  /// Uses cache to avoid repeat API calls
  Future<void> explainInContext({required String selectedWord, required String fullContext}) async {
    if (selectedWord.isEmpty || fullContext.isEmpty) return;
    if (!_translationService.hasProvider) {
      _errorMessage = 'No AI provider configured. Please add a provider in Settings.';
      _state = TranslationState.error;
      notifyListeners();
      return;
    }
    
    // Track that we're in word explanation mode
    _isInWordExplanationMode = true;
    _lastExplainedWord = selectedWord;
    _lastExplainContext = fullContext;

    // Build cache key
    final cacheKey = _buildCacheKey(fullContext, selectedWord);
    
    // Check cache first
    final cached = _getFromCache(cacheKey);
    if (cached != null) {
      _resultText = cached;
      _state = TranslationState.completed;
      notifyListeners();
      return;
    }

    // Cancel any ongoing translation
    await _translationSubscription?.cancel();

    _state = TranslationState.translating;
    _resultText = '';
    _errorMessage = '';
    notifyListeners();

    try {
      final stream = _translationService.explainInContext(
        selectedWord: selectedWord,
        fullContext: fullContext,
        sourceLanguage: _sourceLanguage,
        targetLanguage: _targetLanguage,
      );

      _translationSubscription = stream.listen(
        (chunk) {
          _resultText += chunk;
          notifyListeners();
        },
        onDone: () {
          _state = TranslationState.completed;
          // Cache the result
          _addToCache(cacheKey, _resultText);
          // Track model for change detection
          _lastKnownModelKey = _getCurrentModelKey();
          notifyListeners();
        },
        onError: (error) {
          _errorMessage = error.toString();
          _state = TranslationState.error;
          notifyListeners();
        },
      );
    } catch (e) {
      _errorMessage = e.toString();
      _state = TranslationState.error;
      notifyListeners();
    }
  }

  /// Stop ongoing translation
  Future<void> stopTranslation() async {
    await _translationSubscription?.cancel();
    _translationSubscription = null;
    if (_state == TranslationState.translating) {
      _state = _resultText.isNotEmpty 
          ? TranslationState.completed 
          : TranslationState.idle;
      notifyListeners();
    }
  }

  /// Clear all state
  void clear() {
    _sourceText = '';
    _resultText = '';
    _errorMessage = '';
    _state = TranslationState.idle;
    notifyListeners();
  }

  /// Execute a custom action on the result text
  Future<void> runAction(CustomAction action) async {
    if (_resultText.isEmpty) return;

    try {
      await _shellExecutor.execute(action.scriptPath, _resultText);
    } catch (e) {
      _errorMessage = 'Action failed: $e';
      notifyListeners();
    }
  }

  /// Execute an action asynchronously (fire and forget)
  Future<void> runActionAsync(CustomAction action) async {
    if (_resultText.isEmpty) return;
    await _shellExecutor.executeAsync(action.scriptPath, _resultText);
  }

  @override
  void dispose() {
    _translationSubscription?.cancel();
    super.dispose();
  }
}
