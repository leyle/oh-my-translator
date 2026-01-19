import 'dart:convert';
import 'package:uuid/uuid.dart';

/// AI Provider configuration supporting OpenAI and OpenAI-compatible APIs
/// Works with: OpenAI, OpenRouter, Vercel AI Gateway, and any compatible endpoint
class ProviderConfig {
  final String id;
  final String name;
  final String apiUrl;        // e.g., "https://api.openai.com/v1"
  final String apiPath;       // e.g., "/chat/completions"
  final String apiKey;
  final String model;         // Default/primary model
  final List<String> selectedModels;  // Multiple selected models
  final Map<String, String> customHeaders;  // For OpenRouter's X-Title, HTTP-Referer, etc.
  final bool isDefault;
  final bool enabled;

  const ProviderConfig({
    required this.id,
    required this.name,
    required this.apiUrl,
    this.apiPath = '/chat/completions',
    required this.apiKey,
    required this.model,
    this.selectedModels = const [],
    this.customHeaders = const {},
    this.isDefault = false,
    this.enabled = true,
  });

  /// Create a new provider with a generated UUID
  factory ProviderConfig.create({
    required String name,
    required String apiUrl,
    String apiPath = '/chat/completions',
    required String apiKey,
    required String model,
    List<String> selectedModels = const [],
    Map<String, String> customHeaders = const {},
    bool isDefault = false,
    bool enabled = true,
  }) {
    return ProviderConfig(
      id: const Uuid().v4(),
      name: name,
      apiUrl: apiUrl,
      apiPath: apiPath,
      apiKey: apiKey,
      model: model,
      selectedModels: selectedModels,
      customHeaders: customHeaders,
      isDefault: isDefault,
      enabled: enabled,
    );
  }

  ProviderConfig copyWith({
    String? name,
    String? apiUrl,
    String? apiPath,
    String? apiKey,
    String? model,
    List<String>? selectedModels,
    Map<String, String>? customHeaders,
    bool? isDefault,
    bool? enabled,
  }) {
    return ProviderConfig(
      id: id,
      name: name ?? this.name,
      apiUrl: apiUrl ?? this.apiUrl,
      apiPath: apiPath ?? this.apiPath,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      selectedModels: selectedModels ?? this.selectedModels,
      customHeaders: customHeaders ?? this.customHeaders,
      isDefault: isDefault ?? this.isDefault,
      enabled: enabled ?? this.enabled,
    );
  }

  /// Get the full chat completions URL
  String get chatCompletionsUrl {
    final baseUrl = apiUrl.endsWith('/') 
        ? apiUrl.substring(0, apiUrl.length - 1) 
        : apiUrl;
    return '$baseUrl$apiPath';
  }

  /// Get the models endpoint URL
  String get modelsUrl {
    final baseUrl = apiUrl.endsWith('/') 
        ? apiUrl.substring(0, apiUrl.length - 1) 
        : apiUrl;
    return '$baseUrl/models';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'apiUrl': apiUrl,
    'apiPath': apiPath,
    'apiKey': apiKey,
    'model': model,
    'selectedModels': selectedModels,
    'customHeaders': customHeaders,
    'isDefault': isDefault,
    'enabled': enabled,
  };

  factory ProviderConfig.fromJson(Map<String, dynamic> json) {
    return ProviderConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      apiUrl: json['apiUrl'] as String,
      apiPath: json['apiPath'] as String? ?? '/chat/completions',
      apiKey: json['apiKey'] as String,
      model: json['model'] as String,
      selectedModels: (json['selectedModels'] as List<dynamic>?)
          ?.map((e) => e.toString()).toList() ?? [],
      customHeaders: (json['customHeaders'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, v.toString())) ?? {},
      isDefault: json['isDefault'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  static String encodeList(List<ProviderConfig> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<ProviderConfig> decodeList(String raw) {
    if (raw.isEmpty) return [];
    try {
      final arr = jsonDecode(raw) as List<dynamic>;
      return [for (final e in arr) ProviderConfig.fromJson(e as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProviderConfig && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
