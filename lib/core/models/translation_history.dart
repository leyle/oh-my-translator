import 'dart:convert';

/// Represents a single translation history entry
class TranslationHistoryItem {
  final String id;
  final String inputText;
  final String outputText;
  final String sourceLanguage;
  final String targetLanguage;
  final String mode; // 'translate' or 'polish'
  final DateTime timestamp;

  TranslationHistoryItem({
    required this.id,
    required this.inputText,
    required this.outputText,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.mode,
    required this.timestamp,
  });

  /// Create a new history item with auto-generated ID and timestamp
  factory TranslationHistoryItem.create({
    required String inputText,
    required String outputText,
    required String sourceLanguage,
    required String targetLanguage,
    required String mode,
  }) {
    return TranslationHistoryItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      inputText: inputText,
      outputText: outputText,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      mode: mode,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'inputText': inputText,
        'outputText': outputText,
        'sourceLanguage': sourceLanguage,
        'targetLanguage': targetLanguage,
        'mode': mode,
        'timestamp': timestamp.toIso8601String(),
      };

  factory TranslationHistoryItem.fromJson(Map<String, dynamic> json) {
    return TranslationHistoryItem(
      id: json['id'] as String,
      inputText: json['inputText'] as String,
      outputText: json['outputText'] as String,
      sourceLanguage: json['sourceLanguage'] as String,
      targetLanguage: json['targetLanguage'] as String,
      mode: json['mode'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  /// Encode list of history items to JSON string
  static String encodeList(List<TranslationHistoryItem> items) {
    return jsonEncode(items.map((e) => e.toJson()).toList());
  }

  /// Decode JSON string to list of history items
  static List<TranslationHistoryItem> decodeList(String jsonString) {
    final List<dynamic> list = jsonDecode(jsonString);
    return list.map((e) => TranslationHistoryItem.fromJson(e as Map<String, dynamic>)).toList();
  }
}
