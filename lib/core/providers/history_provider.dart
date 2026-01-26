import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/translation_history.dart';

/// Provider for managing translation history
class HistoryProvider extends ChangeNotifier {
  static const String _historyKey = 'translation_history';
  static const String _maxSizeKey = 'history_max_size';
  static const int _defaultMaxSize = 200;

  SharedPreferences? _prefs;
  List<TranslationHistoryItem> _history = [];
  int _maxSize = _defaultMaxSize;

  // Getters
  List<TranslationHistoryItem> get history => List.unmodifiable(_history);
  int get maxSize => _maxSize;
  bool get isEmpty => _history.isEmpty;
  int get count => _history.length;

  /// Initialize history from persistent storage
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (_prefs == null) return;

    // Load max size
    _maxSize = _prefs!.getInt(_maxSizeKey) ?? _defaultMaxSize;

    // Load history
    final historyJson = _prefs!.getString(_historyKey);
    if (historyJson != null) {
      try {
        _history = TranslationHistoryItem.decodeList(historyJson);
      } catch (e) {
        debugPrint('Failed to load history: $e');
        _history = [];
      }
    }

    notifyListeners();
  }

  Future<void> _saveHistory() async {
    if (_prefs == null) return;
    await _prefs!.setString(_historyKey, TranslationHistoryItem.encodeList(_history));
  }

  /// Add a new translation to history
  /// Automatically removes oldest entries if max size is exceeded
  Future<void> addEntry({
    required String inputText,
    required String outputText,
    required String sourceLanguage,
    required String targetLanguage,
    required String mode,
  }) async {
    // Don't add empty translations
    if (inputText.trim().isEmpty || outputText.trim().isEmpty) return;

    final item = TranslationHistoryItem.create(
      inputText: inputText,
      outputText: outputText,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      mode: mode,
    );

    // Add to beginning (most recent first)
    _history.insert(0, item);

    // Trim to max size
    while (_history.length > _maxSize) {
      _history.removeLast();
    }

    await _saveHistory();
    notifyListeners();
  }

  /// Remove a specific history entry
  Future<void> removeEntry(String id) async {
    _history.removeWhere((item) => item.id == id);
    await _saveHistory();
    notifyListeners();
  }

  /// Clear all history
  Future<void> clearHistory() async {
    _history.clear();
    await _saveHistory();
    notifyListeners();
  }

  /// Set max history size
  Future<void> setMaxSize(int size) async {
    _maxSize = size.clamp(10, 1000); // Min 10, max 1000
    await _prefs?.setInt(_maxSizeKey, _maxSize);

    // Trim if current history exceeds new max
    while (_history.length > _maxSize) {
      _history.removeLast();
    }

    await _saveHistory();
    notifyListeners();
  }
}
