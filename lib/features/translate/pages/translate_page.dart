import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/models/custom_action.dart';
import '../../../core/models/language.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/translation_provider.dart';
import '../../../shared/widgets/highlight_text_controller.dart';
import '../../../shared/widgets/selectable_with_actions.dart';
import '../../settings/pages/settings_page.dart';

class TranslatePage extends StatefulWidget {
  final String? initialText;
  final bool autoTranslate;
  final String? targetLanguage;

  const TranslatePage({
    super.key,
    this.initialText,
    this.autoTranslate = false,
    this.targetLanguage,
  });

  @override
  State<TranslatePage> createState() => _TranslatePageState();
}

class _TranslatePageState extends State<TranslatePage> {
  late HighlightTextEditingController _inputController;
  final FocusNode _inputFocusNode = FocusNode();
  
  // For floating selection toolbar
  OverlayEntry? _selectionOverlay;
  String? _selectedText;
  Offset? _lastPointerPosition;
  final LayerLink _layerLink = LayerLink();
  TextSelection? _lastSelection; // Store selection range to restore after action
  
  // For URL scheme handling
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _inputController = HighlightTextEditingController(text: widget.initialText ?? '');
    
    // Listen to selection changes
    _inputController.addListener(_onSelectionChanged);
    
    // Initialize URL scheme listener (omt://)
    _appLinks = AppLinks();
    _initDeepLinkListener();

    // Auto-translate if text was passed via CLI/PopClip
    if (widget.autoTranslate && widget.initialText != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final translation = context.read<TranslationProvider>();
        translation.setSourceText(widget.initialText!);
        
        // Set target language if provided
        if (widget.targetLanguage != null) {
          translation.setTargetLanguage(widget.targetLanguage!);
        }
        
        translation.translate();
      });
    }
  }
  
  /// Initialize deep link listener for omt:// URLs
  void _initDeepLinkListener() {
    // Handle initial URI if app was launched via URL (only for fresh launch)
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        _handleUri(uri);
      }
    });
    
    // Handle app links when app is already running (stream fires AFTER initial)
    // We delay subscription slightly to avoid duplicate handling on launch
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
        _handleUri(uri);
      });
    });
  }
  
  /// Parse and handle incoming omt:// URL
  void _handleUri(Uri uri) {
    // Expected format: omt://translate?text=Hello%20World&to=zh&mode=translate
    final text = uri.queryParameters['text'];
    if (text == null || text.isEmpty) return;
    
    final targetLang = uri.queryParameters['to'];
    // final mode = uri.queryParameters['mode'];
    
    // Update input text
    _inputController.text = text;
    
    // Trigger translation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      final translation = context.read<TranslationProvider>();
      translation.setSourceText(text);
      
      if (targetLang != null && targetLang.isNotEmpty) {
        translation.setTargetLanguage(targetLang);
      }
      
      translation.translate();
      
      // Bring window to front
      windowManager.show();
      windowManager.focus();
    });
  }
  
  void _onSelectionChanged() {
    final selection = _inputController.selection;
    if (selection.isCollapsed || selection.start == selection.end) {
      // No selection, hide toolbar and clear selected text
      // Note: Full sentence load is triggered in onPointerDown, not here
      _hideSelectionToolbar();
      _selectedText = null;
    }
    // Toolbar will be shown on pointer up, not here
  }
  
  void _hideSelectionToolbar() {
    _selectionOverlay?.remove();
    _selectionOverlay = null;
  }
  
  void _restoreSelection() {
    if (_lastSelection != null && !_lastSelection!.isCollapsed) {
      // Request focus first, then restore selection
      _inputFocusNode.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _lastSelection != null) {
          _inputController.selection = _lastSelection!;
        }
      });
    }
  }
  
  void _showSelectionToolbar(Offset position, String selectedText) {
    _hideSelectionToolbar();
    
    // Store selected text for deselection detection
    _selectedText = selectedText;
    
    // Store current selection range for restoration and apply highlight
    _lastSelection = _inputController.selection;
    _inputController.setHighlight(_lastSelection!.start, _lastSelection!.end);
    
    final settings = context.read<SettingsProvider>();
    final actions = settings.enabledActions;
    
    _selectionOverlay = OverlayEntry(
      builder: (context) => _SelectionToolbar(
        position: position,
        selectedText: selectedText,
        actions: actions,
        onExplain: () => _explainSelectedText(selectedText),
        onCopy: () => _copySelectedText(selectedText),
        onRunAction: (action) => _runCustomAction(action, selectedText),
        onDismiss: _hideSelectionToolbar,
      ),
    );
    
    Overlay.of(context).insert(_selectionOverlay!);
  }
  
  void _explainSelectedText(String selectedWord) {
    final translation = context.read<TranslationProvider>();
    final fullText = _inputController.text;
    
    // Don't change mode - just explain in context without switching UI mode
    translation.explainInContext(selectedWord: selectedWord, fullContext: fullText);
    
    // Restore selection then hide toolbar
    _restoreSelection();
    Future.delayed(const Duration(milliseconds: 100), () {
      _hideSelectionToolbar();
    });
  }
  
  void _copySelectedText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _restoreSelection();
    _hideSelectionToolbar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _hideSelectionToolbar();
    _inputController.removeListener(_onSelectionChanged);
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Shortcuts(
      shortcuts: {
        // Cmd+Enter on Mac, Ctrl+Enter on Windows/Linux
        SingleActivator(LogicalKeyboardKey.enter, meta: Platform.isMacOS, control: !Platform.isMacOS): const TranslateIntent(),
      },
      child: Actions(
        actions: {
          TranslateIntent: CallbackAction<TranslateIntent>(
            onInvoke: (_) {
              final translation = context.read<TranslationProvider>();
              translation.setSourceText(_inputController.text);
              translation.translate();
              return null;
            },
          ),
        },
        child: Scaffold(
          backgroundColor: cs.surface,
          body: Column(
            children: [
              // Custom title bar for macOS
              _buildTitleBar(context),
              
              // Main content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // Mode and language selectors
                      _buildToolbar(context),
                      const SizedBox(height: 12),
                  
                      // Input area
                      Expanded(
                        flex: 2,
                        child: _buildInputArea(context),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      // Translate button
                      _buildTranslateButton(context),
                      
                      const SizedBox(height: 8),
                      
                      // Output area
                      Expanded(
                        flex: 8,
                        child: _buildOutputArea(context),
                      ),
                      
                      // Bottom status bar with provider/model
                      _buildStatusBar(context),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<SettingsProvider>();
    final provider = settings.defaultProvider;
    final enabledProviders = settings.enabledProviders;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          // Provider/Model selector popup
          PopupMenuButton<String>(
            tooltip: 'Select Provider',
            offset: const Offset(0, -200),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.bot,
                  size: 14,
                  color: cs.onSurface.withOpacity(0.5),
                ),
                const SizedBox(width: 6),
                Text(
                  provider != null 
                      ? '${provider.name} • ${provider.model}'
                      : 'No provider configured',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.5),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  LucideIcons.chevronUp,
                  size: 12,
                  color: cs.onSurface.withOpacity(0.4),
                ),
              ],
            ),
            itemBuilder: (context) {
              final items = <PopupMenuEntry<String>>[];
              
              for (final p in enabledProviders) {
                // Provider header
                items.add(PopupMenuItem<String>(
                  enabled: false,
                  height: 32,
                  child: Text(
                    p.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                      fontSize: 12,
                    ),
                  ),
                ));
                
                // Models for this provider
                final models = p.selectedModels.isNotEmpty 
                    ? p.selectedModels 
                    : [p.model];
                    
                for (final model in models) {
                  final isSelected = provider?.id == p.id && provider?.model == model;
                  items.add(PopupMenuItem<String>(
                    value: '${p.id}:$model',
                    height: 36,
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        if (isSelected)
                          Icon(LucideIcons.check, size: 14, color: cs.primary)
                        else
                          const SizedBox(width: 14),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            model,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ));
                }
                
                // Divider between providers
                if (p != enabledProviders.last) {
                  items.add(const PopupMenuDivider(height: 8));
                }
              }
              
              if (items.isEmpty) {
                items.add(const PopupMenuItem(
                  enabled: false,
                  child: Text('No providers enabled'),
                ));
              }
              
              return items;
            },
            onSelected: (value) {
              final parts = value.split(':');
              if (parts.length >= 2) {
                final providerId = parts[0];
                final modelId = parts.sublist(1).join(':'); // Handle model names with colons
                
                // Update the provider's model and set as default
                final targetProvider = settings.providers.firstWhere((p) => p.id == providerId);
                settings.updateProvider(targetProvider.copyWith(model: modelId));
                settings.setDefaultProvider(providerId);
                
                // Auto-refresh with new model after settings update
                Future.delayed(const Duration(milliseconds: 100), () {
                  final translation = context.read<TranslationProvider>();
                  translation.checkModelAndRefresh();
                });
              }
            },
          ),
          
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 52,
        padding: const EdgeInsets.only(left: 80, right: 12),
        child: Row(
          children: [
            const Expanded(
              child: Center(
                child: Text(
                  'Oh-My-Translator',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF666666),
                  ),
                ),
              ),
            ),
            // Settings button on far right
            IconButton(
              icon: Icon(LucideIcons.settings, size: 18, color: cs.onSurface.withOpacity(0.6)),
              onPressed: () => _openSettings(context),
              tooltip: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Consumer<TranslationProvider>(
      builder: (context, translation, _) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Mode selector
              _buildModeChip(context, TranslateMode.translate, translation),
              const SizedBox(width: 8),
              _buildModeChip(context, TranslateMode.polish, translation),
              
              // Language selectors (only for translate mode)
              if (translation.mode == TranslateMode.translate) ...[
                const SizedBox(width: 16),
                _buildLanguageDropdown(
                  context,
                  translation.sourceLanguage,
                  (code) => translation.setSourceLanguage(code),
                  includeAuto: true,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    LucideIcons.arrowRight,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
                _buildLanguageDropdown(
                  context,
                  translation.targetLanguage,
                  (code) => translation.setTargetLanguage(code),
                  includeAuto: false,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildModeChip(BuildContext context, TranslateMode mode, TranslationProvider translation) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = translation.mode == mode;

    return FilterChip(
      label: Text(mode.displayName),
      selected: isSelected,
      onSelected: (_) => translation.setMode(mode),
      selectedColor: cs.primaryContainer,
      checkmarkColor: cs.primary,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildLanguageDropdown(
    BuildContext context,
    String currentCode,
    void Function(String) onChanged, {
    required bool includeAuto,
  }) {
    final cs = Theme.of(context).colorScheme;
    final languages = includeAuto
        ? SupportedLanguages.all
        : SupportedLanguages.all.where((l) => l.code != 'auto').toList();

    final currentLang = languages.firstWhere(
      (l) => l.code == currentCode,
      orElse: () => languages.first,
    );

    return Container(
      constraints: const BoxConstraints(maxWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButton<String>(
        value: currentCode,
        underline: const SizedBox(),
        isDense: true,
        isExpanded: true,
        style: TextStyle(fontSize: 13, color: cs.onSurface),
        items: languages.map((lang) {
          return DropdownMenuItem(
            value: lang.code,
            child: Text(lang.name, overflow: TextOverflow.ellipsis),
          );
        }).toList(),
        onChanged: (code) {
          if (code != null) onChanged(code);
        },
      ),
    );
  }

  Widget _buildInputArea(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withOpacity(0.2)),
      ),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          // Check if we had a word selected (toolbar showing) and user clicked in input
          // This is a deselection - restore the original translation result and clear highlight
          if (_selectedText != null && _selectedText!.isNotEmpty) {
            _inputController.clearHighlight();
            final translation = context.read<TranslationProvider>();
            if (translation.hasLastTranslation) {
              translation.restoreLastTranslation();
            }
          }
          _lastPointerPosition = event.position;
          _hideSelectionToolbar();
        },
        onPointerMove: (event) {
          _lastPointerPosition = event.position;
        },
        onPointerUp: (event) {
          _lastPointerPosition = event.position;
          
          // Check if there's a selection after a short delay
          Future.delayed(const Duration(milliseconds: 50), () {
            final selection = _inputController.selection;
            if (!selection.isCollapsed && selection.start != selection.end) {
              final selectedText = _inputController.text.substring(
                selection.start,
                selection.end,
              );
              if (selectedText.trim().isNotEmpty) {
                _showSelectionToolbar(_lastPointerPosition!, selectedText);
              }
            }
          });
        },
        child: TextField(
          controller: _inputController,
          focusNode: _inputFocusNode,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: TextStyle(fontSize: 15, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: 'Enter text to translate...',
            hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.4)),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.all(16),
          ),
          // Suppress right-click context menu
          contextMenuBuilder: (context, editableTextState) => const SizedBox.shrink(),
          onChanged: (text) {
            context.read<TranslationProvider>().setSourceText(text);
          },
        ),
      ),
    );
  }

  Widget _buildCustomContextMenu(BuildContext context, EditableTextState editableTextState) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = context.read<SettingsProvider>();
    final actions = settings.enabledActions;
    final selectedText = editableTextState.textEditingValue.selection.textInside(
      editableTextState.textEditingValue.text,
    );

    return AdaptiveTextSelectionToolbar(
      anchors: editableTextState.contextMenuAnchors,
      children: [
        // Custom actions from settings
        for (final action in actions)
          _ContextMenuButton(
            icon: _getContextMenuIcon(action.iconName),
            label: action.name,
            onTap: () {
              ContextMenuController.removeAny();
              _runCustomAction(action, selectedText);
            },
          ),
        // Built-in Copy
        _ContextMenuButton(
          icon: LucideIcons.copy,
          label: 'Copy',
          onTap: () {
            ContextMenuController.removeAny();
            Clipboard.setData(ClipboardData(text: selectedText));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied to clipboard'),
                duration: Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
      ],
    );
  }

  IconData _getContextMenuIcon(String iconName) {
    switch (iconName) {
      case 'volume2': return LucideIcons.volume2;
      case 'languages': return LucideIcons.languages;
      case 'search': return LucideIcons.search;
      case 'sparkles': return LucideIcons.sparkles;
      case 'terminal': return LucideIcons.terminal;
      case 'clipboard': return LucideIcons.clipboard;
      case 'share': return LucideIcons.share;
      case 'wand': return LucideIcons.wand;
      case 'zap': return LucideIcons.zap;
      case 'send': return LucideIcons.send;
      default: return LucideIcons.play;
    }
  }

  Future<void> _runCustomAction(CustomAction action, String selectedText) async {
    if (selectedText.isEmpty) return;

    try {
      final result = await Process.run(
        action.scriptPath,
        [selectedText],
        runInShell: true,
      );
      
      // Restore selection after action completes
      _restoreSelection();
      
      if (result.exitCode != 0 && mounted) {
        final stderr = result.stderr.toString().trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${action.name} error: ${stderr.isNotEmpty ? stderr : 'Exit code ${result.exitCode}'}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _restoreSelection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to run ${action.name}: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildTranslateButton(BuildContext context) {
    return Consumer<TranslationProvider>(
      builder: (context, translation, _) {
        final cs = Theme.of(context).colorScheme;
        final isTranslating = translation.isTranslating;

        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: isTranslating
                ? () => translation.stopTranslation()
                : () {
                    translation.setSourceText(_inputController.text);
                    translation.translate();
                  },
            icon: isTranslating
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.onPrimary,
                    ),
                  )
                : Icon(
                    translation.mode == TranslateMode.translate
                        ? LucideIcons.languages
                        : LucideIcons.sparkles,
                    size: 18,
                  ),
            label: Text(
              isTranslating
                  ? 'Stop'
                  : translation.mode.displayName,
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOutputArea(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Consumer<TranslationProvider>(
      builder: (context, translation, _) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outline.withOpacity(0.2)),
          ),
          child: translation.hasError
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    translation.errorMessage,
                    style: TextStyle(color: cs.error, fontSize: 14),
                  ),
                )
              : translation.hasResult
                  ? SelectableWithActions(
                      child: Markdown(
                        data: translation.resultText,
                        padding: const EdgeInsets.all(16),
                        selectable: true,
                        shrinkWrap: true,
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(fontSize: 15, color: cs.onSurface, height: 1.5),
                          h1: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface),
                          h2: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface),
                          h3: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cs.onSurface),
                          strong: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface),
                          em: TextStyle(fontStyle: FontStyle.italic, color: cs.onSurface),
                          code: TextStyle(
                            backgroundColor: cs.surfaceContainerHighest,
                            fontFamily: 'monospace',
                            fontSize: 14,
                          ),
                          horizontalRuleDecoration: BoxDecoration(
                            border: Border(top: BorderSide(color: cs.outline.withOpacity(0.3))),
                          ),
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Translation will appear here...',
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(0.4),
                          fontSize: 14,
                        ),
                      ),
                    ),
        );
      },
    );
  }

  Widget _buildActionsBar(BuildContext context, TranslationProvider translation) {
    final settings = context.watch<SettingsProvider>();
    final actions = settings.enabledActions;
    
    if (actions.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: actions.map((action) {
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: IconButton(
            icon: Icon(_getIconForAction(action.iconName), size: 16),
            onPressed: () => translation.runActionAsync(action),
            tooltip: action.name,
            style: IconButton.styleFrom(
              backgroundColor: cs.surfaceContainerHighest,
              foregroundColor: cs.onSurface.withOpacity(0.7),
            ),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        );
      }).toList(),
    );
  }

  IconData _getIconForAction(String iconName) {
    switch (iconName) {
      case 'volume2': return LucideIcons.volume2;
      case 'languages': return LucideIcons.languages;
      case 'terminal': return LucideIcons.terminal;
      case 'clipboard': return LucideIcons.clipboard;
      case 'share': return LucideIcons.share;
      case 'sparkles': return LucideIcons.sparkles;
      case 'wand': return LucideIcons.wand;
      case 'zap': return LucideIcons.zap;
      case 'send': return LucideIcons.send;
      case 'external_link': return LucideIcons.externalLink;
      default: return LucideIcons.play;
    }
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const SettingsPage(),
      ),
    );
  }
}

/// Custom button for context menu
class _ContextMenuButton extends StatelessWidget {
  const _ContextMenuButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: cs.onSurface),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating selection toolbar (PopClip-like)
class _SelectionToolbar extends StatefulWidget {
  const _SelectionToolbar({
    required this.position,
    required this.selectedText,
    required this.actions,
    required this.onExplain,
    required this.onCopy,
    required this.onRunAction,
    required this.onDismiss,
  });

  final Offset position;
  final String selectedText;
  final List<CustomAction> actions;
  final VoidCallback onExplain;
  final VoidCallback onCopy;
  final Future<void> Function(CustomAction) onRunAction;
  final VoidCallback onDismiss;

  @override
  State<_SelectionToolbar> createState() => _SelectionToolbarState();
}

class _SelectionToolbarState extends State<_SelectionToolbar> {
  String? _loadingActionId; // null = not loading, 'explain' or action.id = loading that item

  Future<void> _handleExplain() async {
    setState(() => _loadingActionId = 'explain');
    widget.onExplain();
    // Explain is handled by provider streaming, so we just dismiss after a delay
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _loadingActionId = null);
  }

  Future<void> _handleAction(CustomAction action) async {
    setState(() => _loadingActionId = action.id);
    try {
      await widget.onRunAction(action);
    } finally {
      if (mounted) {
        setState(() => _loadingActionId = null);
        widget.onDismiss();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenSize = MediaQuery.of(context).size;
    
    // Calculate toolbar width based on number of items
    final itemCount = 2 + widget.actions.length; // Explain + actions + Copy
    final toolbarWidth = itemCount * 75.0 + 20;

    return Positioned(
      left: (widget.position.dx - toolbarWidth / 2).clamp(10, screenSize.width - toolbarWidth - 10),
      top: (widget.position.dy - 50).clamp(10, screenSize.height - 60),
      child: TapRegion(
        onTapOutside: _loadingActionId != null ? null : (_) => widget.onDismiss(),
        child: Material(
          type: MaterialType.transparency,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withOpacity(0.7)
                      : Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.3),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Explain (first)
                    _ToolbarButton(
                      icon: _loadingActionId == 'explain' ? null : LucideIcons.messageCircleQuestion,
                      label: 'Explain',
                      isLoading: _loadingActionId == 'explain',
                      onTap: _loadingActionId != null ? () {} : _handleExplain,
                    ),
                    _divider(cs),
                    
                    // Custom actions (middle)
                    for (final action in widget.actions) ...[
                      _ToolbarButton(
                        icon: _loadingActionId == action.id ? null : _getIconForAction(action.iconName),
                        label: action.name,
                        isLoading: _loadingActionId == action.id,
                        onTap: _loadingActionId != null ? () {} : () => _handleAction(action),
                      ),
                      _divider(cs),
                    ],
                    
                    // Copy (last)
                    _ToolbarButton(
                      icon: LucideIcons.copy,
                      label: 'Copy',
                      onTap: _loadingActionId != null ? () {} : widget.onCopy,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider(ColorScheme cs) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      color: cs.outlineVariant.withOpacity(0.3),
    );
  }

  IconData _getIconForAction(String iconName) {
    switch (iconName) {
      case 'volume2': return LucideIcons.volume2;
      case 'languages': return LucideIcons.languages;
      case 'search': return LucideIcons.search;
      case 'sparkles': return LucideIcons.sparkles;
      case 'terminal': return LucideIcons.terminal;
      case 'clipboard': return LucideIcons.clipboard;
      case 'share': return LucideIcons.share;
      case 'wand': return LucideIcons.wand;
      case 'zap': return LucideIcons.zap;
      case 'send': return LucideIcons.send;
      default: return LucideIcons.play;
    }
  }
}

/// Button for the floating toolbar
class _ToolbarButton extends StatefulWidget {
  const _ToolbarButton({
    this.icon,
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final bool isLoading;

  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: widget.isLoading ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.isLoading ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hovering && !widget.isLoading
                ? cs.primary.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                )
              else if (widget.icon != null)
                Icon(
                  widget.icon,
                  size: 14,
                  color: cs.onSurface.withOpacity(0.8),
                ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: widget.isLoading
                      ? cs.onSurface.withOpacity(0.5)
                      : cs.onSurface.withOpacity(0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Intent for translate shortcut (Cmd+Enter / Ctrl+Enter)
class TranslateIntent extends Intent {
  const TranslateIntent();
}
