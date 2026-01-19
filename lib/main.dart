import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
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

// Global key for app state access from tray listener
final GlobalKey<_OhMyTranslatorAppState> appKey = GlobalKey<_OhMyTranslatorAppState>();

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
    title: 'OhMyTranslator',
    titleBarStyle: TitleBarStyle.hidden,
    backgroundColor: Colors.transparent,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  
  // Configure window to hide instead of close
  await windowManager.setPreventClose(true);
  
  // Listen for window resize to save size
  windowManager.addListener(_WindowSizeListener(prefs));

  // Parse CLI arguments (for PopClip integration)
  final cliArgs = CliArgsHandler.parse(args);

  runApp(OhMyTranslatorApp(
    key: appKey,
    initialText: cliArgs.textToTranslate,
    autoTranslate: cliArgs.hasText,
    targetLanguage: cliArgs.targetLanguage,
  ));
}

class OhMyTranslatorApp extends StatefulWidget {
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
  State<OhMyTranslatorApp> createState() => _OhMyTranslatorAppState();
}

class _OhMyTranslatorAppState extends State<OhMyTranslatorApp> with TrayListener, WindowListener {
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    _initTray();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _initTray() async {
    try {
      await trayManager.setIcon('images/tray_icon.png');
      await trayManager.setToolTip('OhMyTranslator');
      
      Menu menu = Menu(
        items: [
          MenuItem(
            key: 'quit',
            label: 'Quit OhMyTranslator',
          ),
        ],
      );
      await trayManager.setContextMenu(menu);
      trayManager.addListener(this);
    } catch (e) {
      debugPrint('Error initializing tray: $e');
    }
  }

  @override
  void onTrayIconMouseDown() {
    // Left click: directly toggle window visibility
    toggleWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    try {
      if (menuItem.key == 'quit') {
        await windowManager.setPreventClose(false);
        await windowManager.close();
        exit(0);
      }
    } catch (e) {
      debugPrint('Error handling menu click: $e');
    }
  }

  @override
  void onWindowClose() async {
    // Hide instead of close
    await windowManager.hide();
    _isVisible = false;
  }

  Future<void> toggleWindow() async {
    try {
      if (_isVisible) {
        await windowManager.hide();
        _isVisible = false;
      } else {
        await windowManager.show();
        await windowManager.focus();
        _isVisible = true;
      }
    } catch (e) {
      debugPrint('Error toggling window: $e');
    }
  }

  void hideWindow() {
    windowManager.hide();
    _isVisible = false;
  }

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
        title: 'OhMyTranslator',
        debugShowCheckedModeBanner: false,
        theme: _buildLightTheme(),
        darkTheme: _buildDarkTheme(),
        themeMode: ThemeMode.system,
        home: CallbackShortcuts(
          bindings: {
            // Cmd+W to hide window (Mac)
            const SingleActivator(LogicalKeyboardKey.keyW, meta: true): hideWindow,
            // Ctrl+W for Windows/Linux
            const SingleActivator(LogicalKeyboardKey.keyW, control: true): hideWindow,
          },
          child: Focus(
            autofocus: true,
            child: TranslatePage(
              initialText: widget.initialText,
              autoTranslate: widget.autoTranslate,
              targetLanguage: widget.targetLanguage,
            ),
          ),
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
