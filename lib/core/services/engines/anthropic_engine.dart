import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/language.dart';
import '../../models/provider_config.dart';
import '../../models/prompt_templates.dart';
import 'base_engine.dart';

/// Native Anthropic Messages API engine for Claude models.
class AnthropicEngine extends BaseEngine {
  static const String _anthropicVersion = '2023-06-01';
  static const int _defaultMaxTokens = 4096;

  final ProviderConfig config;
  final PromptTemplates promptTemplates;
  http.Client? _client;

  AnthropicEngine({required this.config, PromptTemplates? promptTemplates})
    : promptTemplates = promptTemplates ?? PromptTemplates.defaults();

  http.Client get client => _client ??= http.Client();

  @override
  String get name => config.name;

  @override
  Future<List<ModelInfo>> fetchModels() async {
    final response = await client
        .get(
          Uri.parse(config.modelsUrl),
          headers: _buildHeaders(streaming: false),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return [];
    }

    final data = jsonDecode(response.body);
    final models = (data['data'] as List?) ?? [];
    return [
      for (final model in models)
        if (model is Map && model['id'] is String)
          ModelInfo(
            id: model['id'] as String,
            displayName:
                model['display_name'] as String? ?? model['id'] as String,
          ),
    ];
  }

  @override
  Stream<String> translate({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
    required TranslateMode mode,
  }) {
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

    return _streamMessage(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      temperature: 0.3,
    );
  }

  @override
  Stream<String> explainInContext({
    required String selectedWord,
    required String fullContext,
    required String sourceLanguage,
    required String targetLanguage,
  }) {
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

    return _streamMessage(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      temperature: 0.7,
    );
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
  void dispose() {
    _client?.close();
    _client = null;
  }

  Stream<String> _streamMessage({
    required String systemPrompt,
    required String userPrompt,
    required double temperature,
  }) async* {
    final body = jsonEncode({
      'model': config.model,
      'max_tokens': _defaultMaxTokens,
      'temperature': temperature,
      'system': systemPrompt,
      'messages': [
        {'role': 'user', 'content': userPrompt},
      ],
      'stream': true,
    });

    final response = await _sendWithRetries(body: body);
    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      throw TranslationException(
        message: 'Anthropic API request failed',
        statusCode: response.statusCode,
        responseBody: errorBody,
      );
    }

    var buffer = '';
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer += chunk;

      while (buffer.contains('\n')) {
        final lineEnd = buffer.indexOf('\n');
        final line = buffer.substring(0, lineEnd).trim();
        buffer = buffer.substring(lineEnd + 1);

        if (line.isEmpty || !line.startsWith('data: ')) {
          continue;
        }

        final data = line.substring(6).trim();
        if (data == '[DONE]') {
          return;
        }

        try {
          final event = jsonDecode(data) as Map<String, dynamic>;
          final type = event['type'] as String? ?? '';
          if (type != 'content_block_delta') {
            continue;
          }

          final delta = event['delta'];
          if (delta is! Map<String, dynamic>) {
            continue;
          }

          if (delta['type'] == 'text_delta') {
            final text = delta['text'] as String?;
            if (text != null && text.isNotEmpty) {
              yield text;
            }
          }
        } catch (_) {
          // Ignore malformed SSE events.
        }
      }
    }
  }

  Map<String, String> _buildHeaders({bool streaming = true}) {
    return {
      'content-type': 'application/json',
      'x-api-key': config.apiKey,
      'anthropic-version': _anthropicVersion,
      'accept': streaming ? 'text/event-stream' : 'application/json',
      ...config.customHeaders,
    };
  }

  Future<http.StreamedResponse> _sendWithRetries({
    required String body,
    int maxRetries = 3,
  }) async {
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final request =
            http.Request('POST', Uri.parse(config.chatCompletionsUrl))
              ..headers.addAll(_buildHeaders())
              ..body = body;

        return await client.send(request).timeout(const Duration(seconds: 60));
      } catch (e) {
        final isRetryable =
            e.toString().contains('HandshakeException') ||
            e.toString().contains('Connection terminated') ||
            e.toString().contains('SocketException') ||
            e.toString().contains('Connection reset');

        if (attempt < maxRetries && isRetryable) {
          await Future.delayed(Duration(seconds: attempt));
          continue;
        }

        throw TranslationException(
          message: 'Connection failed after $attempt attempts: $e',
        );
      }
    }

    throw const TranslationException(message: 'Failed to get response');
  }

  /// Get language-specific translation guidance
  String _getLanguageGuidance(String targetLang) {
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
    }
  }

  String _renderTemplate(String template, Map<String, String> values) {
    var result = template;
    values.forEach((key, value) {
      result = result.replaceAll('{$key}', value);
    });
    return result;
  }
}
