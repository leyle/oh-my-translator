import 'dart:convert';
import 'package:uuid/uuid.dart';

/// Trigger type for custom actions
enum ActionTrigger {
  manual,         // User clicks the action button
  afterTranslate, // Automatically run after translation completes
}

/// Shell script action for processing text (similar to Kelivo's SelectionAction)
/// Can be used for TTS, clipboard operations, external integrations, etc.
class CustomAction {
  final String id;
  final String name;
  final String iconName;      // Lucide icon name (e.g., 'volume2', 'terminal')
  final String scriptPath;    // Path to shell script
  final ActionTrigger trigger;
  final bool enabled;

  const CustomAction({
    required this.id,
    required this.name,
    required this.iconName,
    required this.scriptPath,
    this.trigger = ActionTrigger.manual,
    this.enabled = true,
  });

  /// Create a new action with a generated UUID
  factory CustomAction.create({
    required String name,
    required String iconName,
    required String scriptPath,
    ActionTrigger trigger = ActionTrigger.manual,
    bool enabled = true,
  }) {
    return CustomAction(
      id: const Uuid().v4(),
      name: name,
      iconName: iconName,
      scriptPath: scriptPath,
      trigger: trigger,
      enabled: enabled,
    );
  }

  CustomAction copyWith({
    String? name,
    String? iconName,
    String? scriptPath,
    ActionTrigger? trigger,
    bool? enabled,
  }) {
    return CustomAction(
      id: id,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      scriptPath: scriptPath ?? this.scriptPath,
      trigger: trigger ?? this.trigger,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'iconName': iconName,
    'scriptPath': scriptPath,
    'trigger': trigger.name,
    'enabled': enabled,
  };

  factory CustomAction.fromJson(Map<String, dynamic> json) {
    return CustomAction(
      id: json['id'] as String,
      name: json['name'] as String,
      iconName: json['iconName'] as String,
      scriptPath: json['scriptPath'] as String,
      trigger: ActionTrigger.values.firstWhere(
        (e) => e.name == json['trigger'],
        orElse: () => ActionTrigger.manual,
      ),
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  static String encodeList(List<CustomAction> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<CustomAction> decodeList(String raw) {
    if (raw.isEmpty) return [];
    try {
      final arr = jsonDecode(raw) as List<dynamic>;
      return [for (final e in arr) CustomAction.fromJson(e as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  /// Available icons for custom actions (Lucide icon names)
  static const List<String> availableIcons = [
    'volume2',       // TTS/Audio
    'languages',     // Translate
    'search',        // Search
    'sparkles',      // AI/Magic
    'brain',         // Brain/AI
    'terminal',      // Command
    'code',          // Code
    'clipboard',     // Clipboard
    'link',          // Link
    'upload',        // Upload
    'bookmark',      // Bookmark
    'zap',           // Quick action
    'wand',          // Magic wand
    'briefcase',     // Work
    'messageCircle', // Chat/Message
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomAction && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
