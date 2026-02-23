import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../models/language.dart';
import '../../models/provider_config.dart';
import '../../models/prompt_templates.dart';
import 'base_engine.dart';

/// Available model info returned from API
class ModelInfo {
  final String id;
  final String displayName;

  const ModelInfo({required this.id, required this.displayName});
}

/// OpenAI-compatible engine that works with:
/// - OpenAI API (api.openai.com)
/// - OpenRouter (openrouter.ai)
/// - Google Gemini OpenAI-compatible API
/// - Vercel AI Gateway
/// - Any OpenAI-compatible endpoint
class OpenAICompatibleEngine extends BaseEngine {
  final ProviderConfig config;
  final PromptTemplates promptTemplates;
  http.Client? _client;

  OpenAICompatibleEngine({
    required this.config,
    PromptTemplates? promptTemplates,
  }) : promptTemplates = promptTemplates ?? PromptTemplates.defaults();

  http.Client get client => _client ??= http.Client();

  @override
  String get name => config.name;

  /// Fetch available models from the provider (with retry)
  Future<List<ModelInfo>> fetchModels() async {
    final url = _buildModelsUrl();
    final headers = _buildHeaders();
    const maxRetries = 3;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final response = await client
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 15));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = jsonDecode(response.body);
          final models = (data['data'] as List?) ?? [];
          return [
            for (final m in models)
              if (m is Map && m['id'] is String)
                ModelInfo(
                  id: m['id'] as String,
                  displayName: m['id'] as String,
                ),
          ];
        }
        return [];
      } catch (e) {
        print('Error fetching models (attempt $attempt/$maxRetries): $e');

        final isRetryable =
            e.toString().contains('HandshakeException') ||
            e.toString().contains('Connection terminated') ||
            e.toString().contains('SocketException') ||
            e.toString().contains('Connection reset');

        if (attempt < maxRetries && isRetryable) {
          await Future.delayed(Duration(seconds: attempt));
          print('Retrying fetch models...');
          continue;
        }

        return [];
      }
    }
    return [];
  }

  @override
  Stream<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
    required TranslateMode mode,
  }) async* {
    final systemPrompt = _buildSystemPrompt(
      mode,
      sourceLanguage,
      targetLanguage,
    );
    final userPrompt = _buildUserPrompt(
      mode,
      text,
      sourceLanguage,
      targetLanguage,
    );

    final url = _buildChatCompletionsUrl();
    final headers = _buildHeaders();
    var requestPayload = <String, dynamic>{
      'model': config.model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      'stream': true,
    };
    if (_supportsCustomTemperature(config.model)) {
      requestPayload['temperature'] = 0.3;
    }
    var body = jsonEncode(requestPayload);

    print('Making request to: $url');
    print('With model: ${config.model}');

    http.StreamedResponse? response;
    const maxRetries = 3;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // Need to recreate request for each retry since it's consumed after send
        final retryRequest = http.Request('POST', Uri.parse(url))
          ..headers.addAll(headers)
          ..body = body;

        response = await client
            .send(retryRequest)
            .timeout(const Duration(seconds: 60));
        break; // Success, exit retry loop
      } catch (e) {
        print('Request error (attempt $attempt/$maxRetries): $e');

        // Check if it's a retryable error
        final isRetryable =
            e.toString().contains('HandshakeException') ||
            e.toString().contains('Connection terminated') ||
            e.toString().contains('SocketException') ||
            e.toString().contains('Connection reset');

        if (attempt < maxRetries && isRetryable) {
          // Wait before retry with exponential backoff
          await Future.delayed(Duration(seconds: attempt));
          print('Retrying...');
          continue;
        }

        throw TranslationException(
          message: 'Connection failed after $attempt attempts: $e',
        );
      }
    }

    // Should never happen, but for null safety
    if (response == null) {
      throw TranslationException(message: 'Failed to get response');
    }

    print('Response status: ${response.statusCode}');

    if (response.statusCode != 200) {
      var responseBody = await response.stream.bytesToString();

      if (_shouldRetryWithoutTemperature(
        response.statusCode,
        responseBody,
        requestPayload,
      )) {
        requestPayload = Map<String, dynamic>.from(requestPayload)
          ..remove('temperature');
        body = jsonEncode(requestPayload);
        response = await _sendWithRetries(
          url: url,
          headers: headers,
          body: body,
          maxRetries: maxRetries,
        );
        if (response.statusCode != 200) {
          responseBody = await response.stream.bytesToString();
          print('Error response: $responseBody');
          throw TranslationException(
            message: 'API request failed',
            statusCode: response.statusCode,
            responseBody: responseBody,
          );
        }
      } else {
        print('Error response: $responseBody');
        throw TranslationException(
          message: 'API request failed',
          statusCode: response.statusCode,
          responseBody: responseBody,
        );
      }
    }

    // Process SSE stream
    String buffer = '';
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer += chunk;

      // Process complete lines
      while (buffer.contains('\n')) {
        final lineEnd = buffer.indexOf('\n');
        final line = buffer.substring(0, lineEnd).trim();
        buffer = buffer.substring(lineEnd + 1);

        if (line.isEmpty) continue;

        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();

          if (data == '[DONE]') {
            return;
          }

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final choices = json['choices'] as List<dynamic>?;
            if (choices != null && choices.isNotEmpty) {
              final delta = choices[0]['delta'] as Map<String, dynamic>?;
              final content = delta?['content'] as String?;
              if (content != null && content.isNotEmpty) {
                yield content;
              }
            }
          } catch (e) {
            // Skip malformed JSON chunks
            print('Parse error for line: $data - $e');
          }
        }
      }
    }
  }

  @override
  Future<bool> testConnection() async {
    try {
      final models = await fetchModels();
      return models.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<String> explainInContext({
    required String selectedWord,
    required String fullContext,
    required String sourceLanguage,
    required String targetLanguage,
  }) async* {
    final systemPrompt =
        _renderTemplate(promptTemplates.explainInContextSystem, {
          'selectedWord': selectedWord,
          'fullContext': fullContext,
          'sourceLanguage': sourceLanguage,
          'targetLanguage': targetLanguage,
        });

    final userPrompt = _renderTemplate(promptTemplates.explainInContextUser, {
      'selectedWord': selectedWord,
      'fullContext': fullContext,
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
    });

    final url = _buildChatCompletionsUrl();
    final headers = _buildHeaders();
    var requestPayload = <String, dynamic>{
      'model': config.model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      'stream': true,
    };
    if (_supportsCustomTemperature(config.model)) {
      requestPayload['temperature'] = 0.7;
    }
    var body = jsonEncode(requestPayload);

    // Make streaming request with retry logic
    const maxRetries = 3;
    var response = await _sendWithRetries(
      url: url,
      headers: headers,
      body: body,
      maxRetries: maxRetries,
    );

    if (response.statusCode != 200) {
      var errorBody = await response.stream.bytesToString();

      if (_shouldRetryWithoutTemperature(
        response.statusCode,
        errorBody,
        requestPayload,
      )) {
        requestPayload = Map<String, dynamic>.from(requestPayload)
          ..remove('temperature');
        body = jsonEncode(requestPayload);
        response = await _sendWithRetries(
          url: url,
          headers: headers,
          body: body,
          maxRetries: maxRetries,
        );

        if (response.statusCode != 200) {
          errorBody = await response.stream.bytesToString();
          throw TranslationException(
            message: 'API request failed',
            statusCode: response.statusCode,
            responseBody: errorBody,
          );
        }
      } else {
        throw TranslationException(
          message: 'API request failed',
          statusCode: response.statusCode,
          responseBody: errorBody,
        );
      }
    }

    // Process SSE stream
    String buffer = '';
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer += chunk;

      while (buffer.contains('\n')) {
        final lineEnd = buffer.indexOf('\n');
        final line = buffer.substring(0, lineEnd).trim();
        buffer = buffer.substring(lineEnd + 1);

        if (line.isEmpty) continue;

        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();

          if (data == '[DONE]') {
            return;
          }

          try {
            final json = jsonDecode(data);
            final delta = json['choices']?[0]?['delta']?['content'];
            if (delta != null && delta is String) {
              yield delta;
            }
          } catch (_) {
            // Ignore malformed JSON
          }
        }
      }
    }
  }

  String _buildChatCompletionsUrl() {
    return config.chatCompletionsUrl;
  }

  String _buildModelsUrl() {
    return config.modelsUrl;
  }

  Map<String, String> _buildHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey}',
      'Accept': 'text/event-stream',
      ...config.customHeaders,
    };

    if (config.apiUrl.contains('aihubmix.com')) {
      headers['APP-Code'] = 'TUCU0341';
    }

    return headers;
  }

  bool _supportsCustomTemperature(String model) {
    final modelLower = model.toLowerCase();
    final host = Uri.tryParse(config.apiUrl)?.host.toLowerCase() ?? '';
    final isOfficialOpenAI =
        host == 'api.openai.com' || host.endsWith('.api.openai.com');

    // OpenAI GPT-5 chat models currently only accept default temperature.
    if (isOfficialOpenAI && modelLower.startsWith('gpt-5')) {
      return false;
    }
    return true;
  }

  bool _shouldRetryWithoutTemperature(
    int statusCode,
    String responseBody,
    Map<String, dynamic> payload,
  ) {
    if (statusCode != 400 || !payload.containsKey('temperature')) {
      return false;
    }

    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) {
        return false;
      }
      final error = decoded['error'];
      if (error is! Map<String, dynamic>) {
        return false;
      }
      final param = error['param']?.toString().toLowerCase() ?? '';
      final code = error['code']?.toString().toLowerCase() ?? '';
      final message = error['message']?.toString().toLowerCase() ?? '';

      return param == 'temperature' &&
          (code == 'unsupported_value' ||
              message.contains('temperature') && message.contains('default'));
    } catch (_) {
      return false;
    }
  }

  Future<http.StreamedResponse> _sendWithRetries({
    required String url,
    required Map<String, String> headers,
    required String body,
    int maxRetries = 3,
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final request = http.Request('POST', Uri.parse(url))
          ..headers.addAll(headers)
          ..body = body;

        return await client.send(request).timeout(const Duration(seconds: 60));
      } catch (e) {
        print('Request error (attempt $attempt/$maxRetries): $e');
        final isRetryable =
            e.toString().contains('HandshakeException') ||
            e.toString().contains('Connection terminated') ||
            e.toString().contains('SocketException') ||
            e.toString().contains('Connection reset');

        if (attempt < maxRetries && isRetryable) {
          await Future.delayed(Duration(seconds: attempt));
          print('Retrying...');
          continue;
        }
        throw TranslationException(
          message: 'Connection failed after $attempt attempts: $e',
        );
      }
    }

    throw TranslationException(message: 'Failed to get response');
  }

  /// Get language-specific translation guidance
  String _getLanguageGuidance(String targetLang) {
    // Provide specific guidance for certain target languages
    final langLower = targetLang.toLowerCase();

    if (langLower.contains('chinese') ||
        langLower == 'zh' ||
        langLower == 'zh-tw') {
      return promptTemplates.languageGuidanceChinese;
    }

    if (langLower.contains('japanese') || langLower == 'ja') {
      return promptTemplates.languageGuidanceJapanese;
    }

    if (langLower.contains('korean') || langLower == 'ko') {
      return promptTemplates.languageGuidanceKorean;
    }

    // Default guidance for other languages
    return promptTemplates.languageGuidanceDefault;
  }

  String _buildSystemPrompt(
    TranslateMode mode,
    String sourceLang,
    String targetLang,
  ) {
    switch (mode) {
      case TranslateMode.translate:
        return _renderTemplate(promptTemplates.translateSystem, {
          'sourceLanguage': sourceLang,
          'targetLanguage': targetLang,
          'languageGuidance': _getLanguageGuidance(targetLang),
        });

      case TranslateMode.explain:
        return _renderTemplate(promptTemplates.explainSystem, {
          'sourceLanguage': sourceLang,
          'targetLanguage': targetLang,
        });

      case TranslateMode.polish:
        return _renderTemplate(promptTemplates.polishSystem, {
          'sourceLanguage': sourceLang,
          'targetLanguage': targetLang,
        });
    }
  }

  String _buildUserPrompt(
    TranslateMode mode,
    String text,
    String sourceLang,
    String targetLang,
  ) {
    switch (mode) {
      case TranslateMode.translate:
        return _renderTemplate(promptTemplates.translateUser, {
          'text': text,
          'sourceLanguage': sourceLang,
          'targetLanguage': targetLang,
        });
      case TranslateMode.explain:
        // Detect if single word, phrase, or sentence
        final trimmedText = text.trim();
        final wordCount = trimmedText.split(RegExp(r'\s+')).length;

        if (wordCount == 1) {
          return _renderTemplate(promptTemplates.explainWordUser, {
            'text': trimmedText,
            'sourceLanguage': sourceLang,
            'targetLanguage': targetLang,
          });
        } else if (wordCount <= 5) {
          return _renderTemplate(promptTemplates.explainPhraseUser, {
            'text': trimmedText,
            'sourceLanguage': sourceLang,
            'targetLanguage': targetLang,
          });
        } else {
          return _renderTemplate(promptTemplates.explainTextUser, {
            'text': trimmedText,
            'sourceLanguage': sourceLang,
            'targetLanguage': targetLang,
          });
        }
      case TranslateMode.polish:
        return _renderTemplate(promptTemplates.polishUser, {
          'text': text,
          'sourceLanguage': sourceLang,
          'targetLanguage': targetLang,
        });
    }
  }

  String _renderTemplate(String template, Map<String, String> variables) {
    return template.replaceAllMapped(RegExp(r'\{([a-zA-Z0-9_]+)\}'), (match) {
      final key = match.group(1);
      if (key == null) return match.group(0) ?? '';
      return variables[key] ?? (match.group(0) ?? '');
    });
  }

  @override
  void dispose() {
    _client?.close();
    _client = null;
  }
}
