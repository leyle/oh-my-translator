import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'core/providers/history_provider.dart';
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
    
    final historyProvider = HistoryProvider()..init();
    
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: historyProvider),
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
      scaffoldBackgroundColor: const Color(0xFFF0F7FF), // Alice Blue / Very Light Blue
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1D4ED8), // Cobalt Blue / Blue 700
        brightness: Brightness.light,
        surface: Colors.white,
      ),
      fontFamily: '.AppleSystemUIFont',
      // Global Component Themes
      popupMenuTheme: const PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        elevation: 4,
        textStyle: TextStyle(color: Color(0xFF1E293B), fontSize: 13), // Slate 800
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: Color(0xFFE2E8F0)), // Slate 200
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: Color(0xFFE2E8F0)), // Slate 200
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: Color(0xFF1D4ED8), width: 1.5), // Cobalt Blue
        ),
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shadowColor: Color(0x1A000000), // Soft shadow
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        margin: EdgeInsets.zero,
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF1E293B), // Slate 800
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF3B82F6), // Blue 500
        brightness: Brightness.dark,
        surface: const Color(0xFF0F172A), // Slate 900
      ),
      fontFamily: '.AppleSystemUIFont',
      // Global Component Themes
      popupMenuTheme: const PopupMenuThemeData(
        color: Color(0xFF0F172A), // Slate 900
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        elevation: 4,
        textStyle: TextStyle(color: Color(0xFFF1F5F9), fontSize: 13), // Slate 100
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFF0F172A), // Slate 900
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFFF1F5F9)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFF0F172A), // Slate 900
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: Color(0xFF334155)), // Slate 700
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: Color(0xFF334155)), // Slate 700
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: Color(0xFF3B82F6), width: 1.5), // Blue 500
        ),
      ),
      cardTheme: const CardThemeData(
        color: Color(0xFF0F172A), // Slate 900
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        shadowColor: Color(0x4D000000),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        margin: EdgeInsets.zero,
      ),
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
