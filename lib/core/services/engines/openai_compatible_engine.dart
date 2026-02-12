import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../models/language.dart';
import '../../models/provider_config.dart';
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
  http.Client? _client;

  OpenAICompatibleEngine({required this.config});

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
        '''You are an expert linguist and language teacher.
Your task is to explain a selected word or phrase in the context of a given sentence.
Respond in $targetLanguage.

Format your response as follows:

**$selectedWord** · /pronunciation/

**词义（结合句子）**
Explain what "$selectedWord" means IN THE CONTEXT of this specific sentence.

**句子含义**
"$fullContext"
Provide the full translation/meaning of the sentence.

**是否为习语**
Indicate whether the word is part of an idiom. If yes, explain the idiom.

---

### 例句（相同含义）
Provide 3-5 example sentences using "$selectedWord" with the same meaning as in the context.
Include translations for each example.''';

    final userPrompt =
        '''Please explain the word "$selectedWord" in the context of this sentence:

"$fullContext"''';

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
      return '''
- Use contemporary, natural Chinese expressions that native speakers commonly use
- For technical terms (especially AI/tech), prefer widely-adopted Chinese translations:
  * "agentic AI" → "智能体AI" or "AI智能体" (not "代理式AI")
  * "large language model" → "大语言模型" or "大模型"
  * "machine learning" → "机器学习"
  * "neural network" → "神经网络"
- Maintain proper Chinese punctuation (。，！？etc.)
- Ensure the translation reads naturally to native Chinese speakers''';
    }

    if (langLower.contains('japanese') || langLower == 'ja') {
      return '''
- Use natural Japanese expressions appropriate to the context
- Choose between formal (です/ます) or casual form based on the source text's tone
- Use appropriate kanji vs hiragana balance for readability
- Maintain proper Japanese punctuation''';
    }

    if (langLower.contains('korean') || langLower == 'ko') {
      return '''
- Use natural Korean expressions
- Match the formality level of the source text
- Use appropriate Hangul and proper spacing''';
    }

    // Default guidance for other languages
    return '''
- Use natural, idiomatic expressions that native speakers would use
- Maintain appropriate formality level based on the source text''';
  }

  String _buildSystemPrompt(
    TranslateMode mode,
    String sourceLang,
    String targetLang,
  ) {
    switch (mode) {
      case TranslateMode.translate:
        final languageGuidance = _getLanguageGuidance(targetLang);
        return '''You are an expert translator with deep fluency in both $sourceLang and $targetLang.

Your task: Translate the given text from $sourceLang to $targetLang.

Translation guidelines:
- Produce natural, idiomatic translations that sound native
- Preserve the original meaning, tone, and intent precisely
- Use terminology and expressions that native $targetLang speakers commonly use
- Do NOT translate literally if it would sound unnatural
$languageGuidance

Output rules:
- Return ONLY the translated text
- No explanations, notes, or additional commentary
- Maintain original formatting (paragraphs, line breaks, etc.)
- Include proper punctuation appropriate for $targetLang''';

      case TranslateMode.explain:
        // Enhanced context-aware explanation
        return '''You are an expert linguist and language teacher. 
Your task is to provide comprehensive explanations in $targetLang.

For SINGLE WORDS, act as a professional dictionary.
Structure your response exactly as follows using Markdown:

### 1. Basic Info
*   **Word**: The word and its original/base form
*   **Pronunciation**: IPA phonetic notation
*   **Language**: The source language

### 2. Meaning & Usage
*   **Parts of Speech**: All senses with their parts of speech
*   **Collocations**: Frequently used word combinations
*   **Etymology**: Brief word origin

### 3. Example Sentences
Provide 3 bilingual examples.
**CRITICAL RULE**: In the examples, **ONLY** bold the specific target word. Do NOT bold the entire sentence.
*   Example: I love **apples** because they are sweet.

For PHRASES or IDIOMS:
### 1. The Phrase
*   **Literal Meaning**: Word-by-word translation
*   **Actual Meaning**: The idiomatic or contextual meaning

### 2. Context
*   **Origin**: Historical or cultural background
*   **Usage**: When and how to use this phrase
*   **Similar Expressions**: Related phrases

### 3. Examples
Provide 2 examples. **ONLY** bold the target phrase.

For SENTENCES:
### 1. Translation
Full translation to $targetLang

### 2. Breakdown
*   **Key Vocabulary**: Definitions
*   **Grammar**: Sentence structure analysis

### 3. Cultural Context
Any cultural nuances or implications.''';

      case TranslateMode.polish:
        return '''You are an expert linguistic engine with two modes of operation based on the language of the input text.

1. **IF THE INPUT IS ENGLISH**:
   Act as an experienced IELTS examiner and English tutor (Band 9.0).
   Your goal is to help the user achieve a Band 7.0+ score.
   
   Output format:
   ### Polished Version
   [Refined English text using academic vocabulary and varied sentence structures]

   ### IELTS Analysis (Band 7.0+)
   *   **Vocabulary**: Explain key word upgrades (e.g., "changed 'good' to 'beneficial'").
   *   **Grammar**: Highlight complex structures used.
   *   **Cohesion**: Note improvements in flow.

   ### Why It's Better
   Brief explanation of score improvement.

2. **IF THE INPUT IS NOT ENGLISH**:
   Act as a professional editor and writing coach.
   Improve the text while maintaining the original language.
   Focus on:
   - Clarity and conciseness
   - Grammar and punctuation
   - Word choice and vocabulary
   - Sentence structure and flow
   - Maintaining the original meaning and tone
   
   Output format:
   [Return ONLY the polished text, no explanations]''';
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
        return text;
      case TranslateMode.explain:
        // Detect if single word, phrase, or sentence
        final trimmedText = text.trim();
        final wordCount = trimmedText.split(RegExp(r'\s+')).length;

        if (wordCount == 1) {
          return '''Please provide a comprehensive dictionary-style explanation for this word:

**$trimmedText**

Include pronunciation, all meanings with parts of speech, example sentences, etymology, and related words.''';
        } else if (wordCount <= 5) {
          return '''Please explain this phrase or expression:

**$trimmedText**

Include the literal meaning, actual/idiomatic meaning, usage context, and example sentences.''';
        } else {
          return '''Please provide a comprehensive explanation of this text:

---
$trimmedText
---

Include translation, vocabulary breakdown, grammar analysis, and cultural context if relevant.''';
        }
      case TranslateMode.polish:
        return text; // System prompt handles the instructions
    }
  }

  @override
  void dispose() {
    _client?.close();
    _client = null;
  }
}
