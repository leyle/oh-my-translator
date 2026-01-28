import 'package:flutter/material.dart';

/// A TextEditingController that supports highlighting a specific text range
/// with a background color, persisting even when the TextField loses focus.
class HighlightTextEditingController extends TextEditingController {
  TextRange? _highlightRange;
  Color _highlightColor;
  String? _lastText;

  HighlightTextEditingController({
    String? text,
    Color highlightColor = const Color(0xFFB3D9FF), // Light blue to match theme
  })  : _highlightColor = highlightColor,
        _lastText = text,
        super(text: text) {
    // Clear highlight when text content changes (e.g., paste, delete, new input)
    addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (text != _lastText) {
      _lastText = text;
      // Clear stale highlight when text content changes
      if (_highlightRange != null) {
        _highlightRange = null;
        // Note: don't call notifyListeners() here since we're already in a listener
      }
    }
  }

  @override
  void dispose() {
    removeListener(_onTextChanged);
    super.dispose();
  }

  /// Set the range to highlight
  void setHighlight(int start, int end) {
    _highlightRange = TextRange(start: start, end: end);
    notifyListeners();
  }

  /// Clear the highlight
  void clearHighlight() {
    _highlightRange = null;
    notifyListeners();
  }

  /// Check if there's an active highlight
  bool get hasHighlight => _highlightRange != null;

  /// Get the highlighted text
  String? get highlightedText {
    if (_highlightRange == null) return null;
    return text.substring(_highlightRange!.start, _highlightRange!.end);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_highlightRange == null || 
        _highlightRange!.start < 0 || 
        _highlightRange!.end > text.length ||
        _highlightRange!.start >= _highlightRange!.end) {
      // No valid highlight, return normal text
      return TextSpan(text: text, style: style);
    }

    // Build spans with highlight
    final beforeHighlight = text.substring(0, _highlightRange!.start);
    final highlighted = text.substring(_highlightRange!.start, _highlightRange!.end);
    final afterHighlight = text.substring(_highlightRange!.end);

    return TextSpan(
      style: style,
      children: [
        if (beforeHighlight.isNotEmpty) TextSpan(text: beforeHighlight),
        TextSpan(
          text: highlighted,
          style: TextStyle(
            backgroundColor: _highlightColor,
          ),
        ),
        if (afterHighlight.isNotEmpty) TextSpan(text: afterHighlight),
      ],
    );
  }
}
