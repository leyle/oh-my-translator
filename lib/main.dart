import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'core/providers/settings_provider.dart';
import 'core/providers/translation_provider.dart';
import 'core/services/cli_args_handler.dart';
import 'features/translate/pages/translate_page.dart';

// Keys for window size persistence
const String _windowWidthKey = 'window_width';
const String _windowHeightKey = 'window_height';
const double _defaultWidth = 1125;
const double _defaultHeight = 812;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize window manager for macOS
  await windowManager.ensureInitialized();
  
  // Load saved window size
  final prefs = await SharedPreferences.getInstance();
  final savedWidth = prefs.getDouble(_windowWidthKey) ?? _defaultWidth;
  final savedHeight = prefs.getDouble(_windowHeightKey) ?? _defaultHeight;

  // Configure window with saved size
  final windowOptions = WindowOptions(
    size: Size(savedWidth, savedHeight),
    minimumSize: const Size(600, 450),
    center: true,
    title: 'Oh-My-Translator',
    titleBarStyle: TitleBarStyle.hidden,
    backgroundColor: Colors.transparent,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  
  // Listen for window resize to save size
  windowManager.addListener(_WindowSizeListener(prefs));

  // Parse CLI arguments (for PopClip integration)
  final cliArgs = CliArgsHandler.parse(args);

  runApp(OhMyTranslatorApp(
    initialText: cliArgs.textToTranslate,
    autoTranslate: cliArgs.hasText,
    targetLanguage: cliArgs.targetLanguage,
  ));
}

class OhMyTranslatorApp extends StatelessWidget {
  final String? initialText;
  final bool autoTranslate;
  final String? targetLanguage;

  const OhMyTranslatorApp({
    super.key,
    this.initialText,
    this.autoTranslate = false,
    this.targetLanguage,
  });

  @override
  Widget build(BuildContext context) {
    final settingsProvider = SettingsProvider()..init();
    
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider(
          create: (_) => TranslationProvider(
            translationService: settingsProvider.translationService,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Oh-My-Translator',
        debugShowCheckedModeBanner: false,
        theme: _buildLightTheme(),
        darkTheme: _buildDarkTheme(),
        themeMode: ThemeMode.system,
        home: TranslatePage(
          initialText: initialText,
          autoTranslate: autoTranslate,
          targetLanguage: targetLanguage,
        ),
      ),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6366F1), // Indigo
        brightness: Brightness.light,
      ),
      fontFamily: '.AppleSystemUIFont',
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6366F1), // Indigo
        brightness: Brightness.dark,
      ),
      fontFamily: '.AppleSystemUIFont',
    );
  }
}

/// Listener to save window size when resized
class _WindowSizeListener extends WindowListener {
  final SharedPreferences prefs;
  
  _WindowSizeListener(this.prefs);
  
  @override
  void onWindowResize() async {
    final size = await windowManager.getSize();
    await prefs.setDouble(_windowWidthKey, size.width);
    await prefs.setDouble(_windowHeightKey, size.height);
  }
  
  @override
  void onWindowClose() async {
    // Also save on close just in case
    final size = await windowManager.getSize();
    await prefs.setDouble(_windowWidthKey, size.width);
    await prefs.setDouble(_windowHeightKey, size.height);
  }
}
