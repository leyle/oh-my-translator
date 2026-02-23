import 'dart:convert';

/// User-configurable prompt templates for all AI request modes.
class PromptTemplates {
  final String translateSystem;
  final String translateUser;

  final String explainSystem;
  final String explainWordUser;
  final String explainPhraseUser;
  final String explainTextUser;

  final String explainInContextSystem;
  final String explainInContextUser;

  final String languageGuidanceDefault;
  final String languageGuidanceChinese;
  final String languageGuidanceJapanese;
  final String languageGuidanceKorean;

  const PromptTemplates({
    required this.translateSystem,
    required this.translateUser,
    required this.explainSystem,
    required this.explainWordUser,
    required this.explainPhraseUser,
    required this.explainTextUser,
    required this.explainInContextSystem,
    required this.explainInContextUser,
    required this.languageGuidanceDefault,
    required this.languageGuidanceChinese,
    required this.languageGuidanceJapanese,
    required this.languageGuidanceKorean,
  });

  factory PromptTemplates.defaults() {
    return const PromptTemplates(
      translateSystem:
          '''You are an expert translator with deep fluency in both {sourceLanguage} and {targetLanguage}.

Your task: Translate the given text from {sourceLanguage} to {targetLanguage}.

Translation guidelines:
- Produce natural, idiomatic translations that sound native
- Preserve the original meaning, tone, emotion, and communicative intent precisely
- **Identify the tone first**: Recognize sarcasm, frustration, humor, formality, criticism, or rhetorical devices (especially rhetorical questions used for criticism or disbelief)
- **Translate the function, not just the words**: If a rhetorical question expresses criticism or disbelief, maintain that function in English
- Use terminology and expressions that native {targetLanguage} speakers would naturally use in the same emotional context
- Match the register: keep informal speech informal, formal speech formal
- Do NOT translate literally if it would sound unnatural or lose the original tone
{languageGuidance}

Output rules:
- Return ONLY the translated text
- No explanations, notes, or additional commentary
- Maintain original formatting (paragraphs, line breaks, etc.)
- Include proper punctuation appropriate for {targetLanguage}''',
      translateUser: '{text}',
      explainSystem: '''You are an expert linguist and language teacher.
Your task is to provide comprehensive explanations in {targetLanguage}.

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
Full translation to {targetLanguage}

### 2. Breakdown
*   **Key Vocabulary**: Definitions
*   **Grammar**: Sentence structure analysis

### 3. Cultural Context
Any cultural nuances or implications.''',
      explainWordUser:
          '''Please provide a comprehensive dictionary-style explanation for this word:

**{text}**

Include pronunciation, all meanings with parts of speech, example sentences, etymology, and related words.''',
      explainPhraseUser: '''Please explain this phrase or expression:

**{text}**

Include the literal meaning, actual/idiomatic meaning, usage context, and example sentences.''',
      explainTextUser:
          '''Please provide a comprehensive explanation of this text:

---
{text}
---

Include translation, vocabulary breakdown, grammar analysis, and cultural context if relevant.''',
      explainInContextSystem:
          '''You are an expert linguist and language teacher.
Your task is to explain a selected word or phrase in the context of a given sentence.
Respond in {targetLanguage}.

Format your response as follows:

**{selectedWord}** · /pronunciation/

**词义（结合句子）**
Explain what "{selectedWord}" means IN THE CONTEXT of this specific sentence.

**句子含义**
"{fullContext}"
Provide the full translation/meaning of the sentence.

**是否为习语**
Indicate whether the word is part of an idiom. If yes, explain the idiom.

---

### 例句（相同含义）
Provide 3-5 example sentences using "{selectedWord}" with the same meaning as in the context.
Include translations for each example.''',
      explainInContextUser:
          '''Please explain the word "{selectedWord}" in the context of this sentence:

"{fullContext}"''',
      languageGuidanceDefault:
          '''- Use natural, idiomatic expressions that native speakers would use
- Maintain appropriate formality level based on the source text''',
      languageGuidanceChinese:
          '''- Use contemporary, natural Chinese expressions that native speakers commonly use
- For technical terms (especially AI/tech), prefer widely-adopted Chinese translations:
  * "agentic AI" → "智能体AI" or "AI智能体" (not "代理式AI")
  * "large language model" → "大语言模型" or "大模型"
  * "machine learning" → "机器学习"
  * "neural network" → "神经网络"
- Maintain proper Chinese punctuation (。，！？etc.)
- Ensure the translation reads naturally to native Chinese speakers''',
      languageGuidanceJapanese:
          '''- Use natural Japanese expressions appropriate to the context
- Choose between formal (です/ます) or casual form based on the source text's tone
- Use appropriate kanji vs hiragana balance for readability
- Maintain proper Japanese punctuation''',
      languageGuidanceKorean: '''- Use natural Korean expressions
- Match the formality level of the source text
- Use appropriate Hangul and proper spacing''',
    );
  }

  PromptTemplates copyWith({
    String? translateSystem,
    String? translateUser,
    String? explainSystem,
    String? explainWordUser,
    String? explainPhraseUser,
    String? explainTextUser,
    String? explainInContextSystem,
    String? explainInContextUser,
    String? languageGuidanceDefault,
    String? languageGuidanceChinese,
    String? languageGuidanceJapanese,
    String? languageGuidanceKorean,
  }) {
    return PromptTemplates(
      translateSystem: translateSystem ?? this.translateSystem,
      translateUser: translateUser ?? this.translateUser,
      explainSystem: explainSystem ?? this.explainSystem,
      explainWordUser: explainWordUser ?? this.explainWordUser,
      explainPhraseUser: explainPhraseUser ?? this.explainPhraseUser,
      explainTextUser: explainTextUser ?? this.explainTextUser,
      explainInContextSystem:
          explainInContextSystem ?? this.explainInContextSystem,
      explainInContextUser: explainInContextUser ?? this.explainInContextUser,
      languageGuidanceDefault:
          languageGuidanceDefault ?? this.languageGuidanceDefault,
      languageGuidanceChinese:
          languageGuidanceChinese ?? this.languageGuidanceChinese,
      languageGuidanceJapanese:
          languageGuidanceJapanese ?? this.languageGuidanceJapanese,
      languageGuidanceKorean:
          languageGuidanceKorean ?? this.languageGuidanceKorean,
    );
  }

  Map<String, dynamic> toJson() => {
    'translateSystem': translateSystem,
    'translateUser': translateUser,
    'explainSystem': explainSystem,
    'explainWordUser': explainWordUser,
    'explainPhraseUser': explainPhraseUser,
    'explainTextUser': explainTextUser,
    'explainInContextSystem': explainInContextSystem,
    'explainInContextUser': explainInContextUser,
    'languageGuidanceDefault': languageGuidanceDefault,
    'languageGuidanceChinese': languageGuidanceChinese,
    'languageGuidanceJapanese': languageGuidanceJapanese,
    'languageGuidanceKorean': languageGuidanceKorean,
  };

  factory PromptTemplates.fromJson(Map<String, dynamic> json) {
    final defaults = PromptTemplates.defaults();
    return PromptTemplates(
      translateSystem:
          json['translateSystem'] as String? ?? defaults.translateSystem,
      translateUser: json['translateUser'] as String? ?? defaults.translateUser,
      explainSystem: json['explainSystem'] as String? ?? defaults.explainSystem,
      explainWordUser:
          json['explainWordUser'] as String? ?? defaults.explainWordUser,
      explainPhraseUser:
          json['explainPhraseUser'] as String? ?? defaults.explainPhraseUser,
      explainTextUser:
          json['explainTextUser'] as String? ?? defaults.explainTextUser,
      explainInContextSystem:
          json['explainInContextSystem'] as String? ??
          defaults.explainInContextSystem,
      explainInContextUser:
          json['explainInContextUser'] as String? ??
          defaults.explainInContextUser,
      languageGuidanceDefault:
          json['languageGuidanceDefault'] as String? ??
          defaults.languageGuidanceDefault,
      languageGuidanceChinese:
          json['languageGuidanceChinese'] as String? ??
          defaults.languageGuidanceChinese,
      languageGuidanceJapanese:
          json['languageGuidanceJapanese'] as String? ??
          defaults.languageGuidanceJapanese,
      languageGuidanceKorean:
          json['languageGuidanceKorean'] as String? ??
          defaults.languageGuidanceKorean,
    );
  }

  static String encode(PromptTemplates templates) =>
      jsonEncode(templates.toJson());

  static PromptTemplates decode(String raw) {
    if (raw.isEmpty) return PromptTemplates.defaults();
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return PromptTemplates.fromJson(map);
    } catch (_) {
      return PromptTemplates.defaults();
    }
  }
}
