import 'dart:convert';
import 'package:uuid/uuid.dart';

enum ProviderApiKind { openAiCompatible, anthropic }

/// AI Provider configuration supporting OpenAI and OpenAI-compatible APIs
/// Works with: OpenAI, OpenRouter, Gemini (OpenAI-compatible), Vercel AI Gateway,
/// and any compatible endpoint.
class ProviderConfig {
  final String id;
  final String name;
  final String apiUrl; // e.g., "https://api.openai.com/v1"
  final String apiPath; // e.g., "/chat/completions"
  final String apiKey;
  final String model; // Default/primary model
  final ProviderApiKind apiKind;
  final List<String> selectedModels; // Multiple selected models
  final Map<String, String>
  customHeaders; // For OpenRouter's X-Title, HTTP-Referer, etc.
  final bool isDefault;
  final bool enabled;

  const ProviderConfig({
    required this.id,
    required this.name,
    required this.apiUrl,
    this.apiPath = '/chat/completions',
    required this.apiKey,
    required this.model,
    this.apiKind = ProviderApiKind.openAiCompatible,
    this.selectedModels = const [],
    this.customHeaders = const {},
    this.isDefault = false,
    this.enabled = true,
  });

  String get normalizedApiPath =>
      apiPath.startsWith('/') ? apiPath : '/$apiPath';

  bool get usesAnthropicMessagesApi => apiKind == ProviderApiKind.anthropic;

  static ProviderApiKind inferApiKind({
    required String apiUrl,
    required String apiPath,
    required String model,
    String? name,
  }) {
    final normalizedPath = apiPath.startsWith('/') ? apiPath : '/$apiPath';
    final modelLower = model.trim().toLowerCase();
    final nameLower = name?.trim().toLowerCase() ?? '';
    final host = Uri.tryParse(apiUrl)?.host.toLowerCase() ?? '';

    if (normalizedPath.toLowerCase().endsWith('/messages') ||
        modelLower.startsWith('claude') ||
        nameLower.contains('claude') ||
        nameLower.contains('anthropic') ||
        host == 'api.anthropic.com') {
      return ProviderApiKind.anthropic;
    }

    return ProviderApiKind.openAiCompatible;
  }

  /// Create a new provider with a generated UUID
  factory ProviderConfig.create({
    required String name,
    required String apiUrl,
    String apiPath = '/chat/completions',
    required String apiKey,
    required String model,
    ProviderApiKind? apiKind,
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
      apiKind:
          apiKind ??
          inferApiKind(
            apiUrl: apiUrl,
            apiPath: apiPath,
            model: model,
            name: name,
          ),
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
    ProviderApiKind? apiKind,
    List<String>? selectedModels,
    Map<String, String>? customHeaders,
    bool? isDefault,
    bool? enabled,
  }) {
    final nextName = name ?? this.name;
    final nextApiUrl = apiUrl ?? this.apiUrl;
    final nextApiPath = apiPath ?? this.apiPath;
    final nextModel = model ?? this.model;
    final shouldReinferApiKind =
        name != null || apiUrl != null || apiPath != null || model != null;

    return ProviderConfig(
      id: id,
      name: nextName,
      apiUrl: nextApiUrl,
      apiPath: nextApiPath,
      apiKey: apiKey ?? this.apiKey,
      model: nextModel,
      apiKind:
          apiKind ??
          (shouldReinferApiKind
              ? inferApiKind(
                  apiUrl: nextApiUrl,
                  apiPath: nextApiPath,
                  model: nextModel,
                  name: nextName,
                )
              : this.apiKind),
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
    final path = normalizedApiPath;
    return '$baseUrl$path';
  }

  /// Get the models endpoint URL
  String get modelsUrl {
    final baseUrl = apiUrl.endsWith('/')
        ? apiUrl.substring(0, apiUrl.length - 1)
        : apiUrl;
    final path = normalizedApiPath;

    // Derive models path from chat completion path when possible.
    // Example: /openai/chat/completions -> /openai/models (Gemini OpenAI-compatible API)
    if (path.endsWith('/chat/completions')) {
      final prefix = path.substring(
        0,
        path.length - '/chat/completions'.length,
      );
      return '$baseUrl${prefix.isEmpty ? '' : prefix}/models';
    }

    if (path.endsWith('/messages')) {
      final prefix = path.substring(0, path.length - '/messages'.length);
      return '$baseUrl${prefix.isEmpty ? '' : prefix}/models';
    }

    return '$baseUrl/models';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'apiUrl': apiUrl,
    'apiPath': apiPath,
    'apiKey': apiKey,
    'model': model,
    'apiKind': apiKind.name,
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
      apiKind: _parseApiKind(
        json['apiKind'] as String?,
        apiUrl: json['apiUrl'] as String,
        apiPath: json['apiPath'] as String? ?? '/chat/completions',
        model: json['model'] as String,
        name: json['name'] as String,
      ),
      selectedModels:
          (json['selectedModels'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      customHeaders:
          (json['customHeaders'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v.toString()),
          ) ??
          {},
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
      return [
        for (final e in arr) ProviderConfig.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  static ProviderApiKind _parseApiKind(
    String? raw, {
    required String apiUrl,
    required String apiPath,
    required String model,
    required String name,
  }) {
    if (raw != null) {
      for (final value in ProviderApiKind.values) {
        if (value.name == raw) {
          return value;
        }
      }
    }

    return inferApiKind(
      apiUrl: apiUrl,
      apiPath: apiPath,
      model: model,
      name: name,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProviderConfig &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
