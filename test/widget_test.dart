import 'package:flutter_test/flutter_test.dart';
import 'package:oh_my_translator/core/models/language.dart';

void main() {
  group('LanguageDetector.detect', () {
    test('defaults to English for empty text', () {
      expect(LanguageDetector.detect('   '), 'en');
    });

    test('detects Chinese text', () {
      expect(LanguageDetector.detect('你好，世界'), 'zh');
    });

    test('detects Japanese text with kana', () {
      expect(LanguageDetector.detect('こんにちは世界'), 'ja');
    });

    test('detects Korean text', () {
      expect(LanguageDetector.detect('안녕하세요 세계'), 'ko');
    });
  });
}
