import 'package:args/args.dart';

/// Handles command-line arguments for PopClip integration and direct CLI usage
/// 
/// Usage examples:
/// - PopClip: open -a "Oh-My-Translator" --args "Hello world"
/// - CLI: ./oh_my_translator "Hello world" --to=zh --mode=translate
class CliArgsHandler {
  final String? textToTranslate;
  final String? targetLanguage;
  final String? mode;

  const CliArgsHandler({
    this.textToTranslate,
    this.targetLanguage,
    this.mode,
  });

  /// Parse command-line arguments
  /// 
  /// Supported arguments:
  /// - Positional: text to translate (can be multiple words)
  /// - --to, -t: target language code (e.g., zh, en, ja)
  /// - --mode, -m: translation mode (translate, explain, polish)
  static CliArgsHandler parse(List<String> args) {
    if (args.isEmpty) {
      return const CliArgsHandler();
    }

    final parser = ArgParser()
      ..addOption('to', abbr: 't', help: 'Target language code')
      ..addOption('mode', abbr: 'm', help: 'Translation mode', 
          allowed: ['translate', 'explain', 'polish'],
          defaultsTo: 'translate');

    try {
      final results = parser.parse(args);
      
      // Get positional arguments as the text to translate
      // Join all rest arguments as the text (handles multi-word input)
      final text = results.rest.isNotEmpty ? results.rest.join(' ') : null;
      
      return CliArgsHandler(
        textToTranslate: text,
        targetLanguage: results['to'] as String?,
        mode: results['mode'] as String?,
      );
    } catch (e) {
      // If parsing fails, treat all args as text to translate
      // This handles cases where PopClip passes text without flags
      return CliArgsHandler(
        textToTranslate: args.join(' '),
      );
    }
  }

  /// Check if there's text to translate from CLI
  bool get hasText => textToTranslate != null && textToTranslate!.isNotEmpty;

  @override
  String toString() => 'CliArgsHandler(text: $textToTranslate, to: $targetLanguage, mode: $mode)';
}
