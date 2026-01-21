import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/provider_config.dart';
import '../models/custom_action.dart';
import '../models/language.dart';
import '../services/translation_service.dart';
import '../services/engines/openai_compatible_engine.dart';

/// Main settings provider for the application
/// Manages AI providers, custom actions, and user preferences
class SettingsProvider extends ChangeNotifier {
  static const String _providersKey = 'providers';
  static const String _actionsKey = 'custom_actions';
  static const String _defaultProviderKey = 'default_provider_id';
  static const String _sourceLanguageKey = 'source_language';
  static const String _targetLanguageKey = 'target_language';
  static const String _defaultModeKey = 'default_mode';
  static const String _fontSizeKey = 'font_size';

  SharedPreferences? _prefs;
  List<ProviderConfig> _providers = [];
  List<CustomAction> _customActions = [];
  String? _defaultProviderId;
  String _sourceLanguage = 'auto';
  String _targetLanguage = 'zh';
  TranslateMode _defaultMode = TranslateMode.translate;
  double _fontSize = 16.0;

  final TranslationService _translationService;

  SettingsProvider({TranslationService? translationService})
      : _translationService = translationService ?? TranslationService();

  // Getters
  List<ProviderConfig> get providers => List.unmodifiable(_providers);
  List<ProviderConfig> get enabledProviders => _providers.where((p) => p.enabled).toList();
  List<CustomAction> get customActions => List.unmodifiable(_customActions);
  List<CustomAction> get enabledActions => _customActions.where((a) => a.enabled).toList();
  String get sourceLanguage => _sourceLanguage;
  String get targetLanguage => _targetLanguage;
  TranslateMode get defaultMode => _defaultMode;
  double get fontSize => _fontSize;
  TranslationService get translationService => _translationService;

  /// Get the default provider (must be enabled)
  ProviderConfig? get defaultProvider {
    // First try to find the explicitly set default provider (if enabled)
    if (_defaultProviderId != null) {
      try {
        final provider = _providers.firstWhere((p) => p.id == _defaultProviderId);
        if (provider.enabled) return provider;
      } catch (_) {}
    }
    // Fall back to first enabled provider
    final enabled = enabledProviders;
    return enabled.isNotEmpty ? enabled.first : null;
  }

  bool get hasProvider => enabledProviders.isNotEmpty;

  /// Initialize settings from persistent storage
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadSettings();
    
    // Set up translation service with default provider
    final provider = defaultProvider;
    if (provider != null) {
      _translationService.setProvider(provider);
    }
  }

  Future<void> _loadSettings() async {
    if (_prefs == null) return;

    // Load providers
    final providersJson = _prefs!.getString(_providersKey);
    if (providersJson != null) {
      _providers = ProviderConfig.decodeList(providersJson);
    }

    // Load custom actions
    final actionsJson = _prefs!.getString(_actionsKey);
    if (actionsJson != null) {
      _customActions = CustomAction.decodeList(actionsJson);
    }

    // Load preferences
    _defaultProviderId = _prefs!.getString(_defaultProviderKey);
    _sourceLanguage = _prefs!.getString(_sourceLanguageKey) ?? 'auto';
    _targetLanguage = _prefs!.getString(_targetLanguageKey) ?? 'zh';
    _fontSize = _prefs!.getDouble(_fontSizeKey) ?? 16.0;
    
    final modeStr = _prefs!.getString(_defaultModeKey);
    if (modeStr != null) {
      _defaultMode = TranslateMode.values.firstWhere(
        (m) => m.name == modeStr,
        orElse: () => TranslateMode.translate,
      );
    }

    notifyListeners();
  }

  Future<void> _saveProviders() async {
    await _prefs?.setString(_providersKey, ProviderConfig.encodeList(_providers));
  }

  Future<void> _saveActions() async {
    await _prefs?.setString(_actionsKey, CustomAction.encodeList(_customActions));
  }

  // Provider management
  Future<void> addProvider(ProviderConfig provider) async {
    _providers.add(provider);
    await _saveProviders();
    
    // If this is the first provider, make it default
    if (_providers.length == 1) {
      await setDefaultProvider(provider.id);
    }
    
    notifyListeners();
  }

  Future<void> updateProvider(ProviderConfig provider) async {
    final index = _providers.indexWhere((p) => p.id == provider.id);
    if (index >= 0) {
      _providers[index] = provider;
      await _saveProviders();
      
      // Update translation service if this is the active provider
      if (provider.id == _defaultProviderId) {
        _translationService.setProvider(provider);
      }
      
      notifyListeners();
    }
  }

  Future<void> removeProvider(String id) async {
    _providers.removeWhere((p) => p.id == id);
    await _saveProviders();
    
    // If we removed the default provider, select a new one
    if (_defaultProviderId == id) {
      _defaultProviderId = _providers.isNotEmpty ? _providers.first.id : null;
      await _prefs?.setString(_defaultProviderKey, _defaultProviderId ?? '');
      
      final provider = defaultProvider;
      if (provider != null) {
        _translationService.setProvider(provider);
      }
    }
    
    notifyListeners();
  }

  Future<void> setDefaultProvider(String id) async {
    _defaultProviderId = id;
    await _prefs?.setString(_defaultProviderKey, id);
    
    final provider = defaultProvider;
    if (provider != null) {
      _translationService.setProvider(provider);
    }
    
    notifyListeners();
  }

  /// Fetch available models from a provider
  Future<List<String>> fetchModels(ProviderConfig provider) async {
    final engine = OpenAICompatibleEngine(config: provider);
    try {
      final models = await engine.fetchModels();
      return models.map((m) => m.id).toList();
    } finally {
      engine.dispose();
    }
  }

  // Custom action management
  Future<void> addAction(CustomAction action) async {
    _customActions.add(action);
    await _saveActions();
    notifyListeners();
  }

  Future<void> updateAction(CustomAction action) async {
    final index = _customActions.indexWhere((a) => a.id == action.id);
    if (index >= 0) {
      _customActions[index] = action;
      await _saveActions();
      notifyListeners();
    }
  }

  Future<void> removeAction(String id) async {
    _customActions.removeWhere((a) => a.id == id);
    await _saveActions();
    notifyListeners();
  }

  Future<void> reorderActions(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex--;
    final action = _customActions.removeAt(oldIndex);
    _customActions.insert(newIndex, action);
    await _saveActions();
    notifyListeners();
  }

  // Language preferences
  Future<void> setSourceLanguage(String code) async {
    _sourceLanguage = code;
    await _prefs?.setString(_sourceLanguageKey, code);
    notifyListeners();
  }

  Future<void> setTargetLanguage(String code) async {
    _targetLanguage = code;
    await _prefs?.setString(_targetLanguageKey, code);
    notifyListeners();
  }

  Future<void> setDefaultMode(TranslateMode mode) async {
    _defaultMode = mode;
    await _prefs?.setString(_defaultModeKey, mode.name);
    notifyListeners();
  }

  Future<void> setFontSize(double size) async {
    _fontSize = size;
    await _prefs?.setDouble(_fontSizeKey, size);
    notifyListeners();
  }

  @override
  void dispose() {
    _translationService.dispose();
    super.dispose();
  }
}
