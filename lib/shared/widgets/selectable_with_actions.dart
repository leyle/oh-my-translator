import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/models/custom_action.dart';

/// A wrapper widget that provides a floating action bar when text is selected.
/// Shows Copy and configured custom actions (shell scripts).
class SelectableWithActions extends StatefulWidget {
  const SelectableWithActions({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<SelectableWithActions> createState() => _SelectableWithActionsState();
}

class _SelectableWithActionsState extends State<SelectableWithActions> {
  String? _selectedText;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  Timer? _hideTimer;
  Offset? _lastTapPosition;

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  void dispose() {
    _hideOverlay();
    _hideTimer?.cancel();
    super.dispose();
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showActionBar(Offset position) {
    print('_showActionBar called at position: $position');
    _hideOverlay();
    _hideTimer?.cancel();

    final settings = context.read<SettingsProvider>();
    final actions = settings.enabledActions;
    print('Enabled actions count: ${actions.length}');

    _overlayEntry = OverlayEntry(
      builder: (context) => _SelectionActionBar(
        position: position,
        layerLink: _layerLink,
        selectedText: _selectedText ?? '',
        actions: actions,
        onRunAction: _runAction,
        onCopy: _copyToClipboard,
        onDismiss: _hideOverlay,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
    print('Overlay inserted');

    // Auto-hide after 5 seconds of inactivity
    _hideTimer = Timer(const Duration(seconds: 5), _hideOverlay);
  }

  Future<void> _runAction(CustomAction action) async {
    if (_selectedText == null || _selectedText!.isEmpty) return;

    _hideTimer?.cancel();

    try {
      final result = await Process.run(
        action.scriptPath,
        [_selectedText!],
        runInShell: true,
      );
      
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

  void _copyToClipboard() {
    if (_selectedText == null || _selectedText!.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _selectedText!));
    _hideOverlay();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) {
      return widget.child;
    }

    return CompositedTransformTarget(
      link: _layerLink,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          _lastTapPosition = event.position;
        },
        onPointerMove: (event) {
          _lastTapPosition = event.position;
        },
        onPointerUp: (event) {
          _lastTapPosition = event.position;
        },
        child: SelectionArea(
          // Suppress system context menu and PopClip by returning empty widget
          contextMenuBuilder: (context, selectableRegionState) => const SizedBox.shrink(),
          onSelectionChanged: (content) {
            print('onSelectionChanged called: ${content?.plainText}');
            _hideTimer?.cancel();
            
            if (content != null && content.plainText.trim().isNotEmpty) {
              _selectedText = content.plainText;
              final position = _lastTapPosition ?? 
                  Offset(MediaQuery.of(context).size.width / 2, MediaQuery.of(context).size.height / 2);
              print('Selection detected: $_selectedText at $position');
              
              // Debounce to let selection stabilize
              _hideTimer = Timer(const Duration(milliseconds: 150), () {
                if (mounted && _selectedText != null && _selectedText!.isNotEmpty) {
                  _showActionBar(position);
                }
              });
            } else {
              _selectedText = null;
              _hideTimer = Timer(const Duration(milliseconds: 250), () {
                if (_selectedText == null || _selectedText!.isEmpty) {
                  _hideOverlay();
                }
              });
            }
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// The floating action bar that appears on text selection.
class _SelectionActionBar extends StatefulWidget {
  const _SelectionActionBar({
    required this.position,
    required this.layerLink,
    required this.selectedText,
    required this.actions,
    required this.onRunAction,
    required this.onCopy,
    required this.onDismiss,
  });

  final Offset position;
  final LayerLink layerLink;
  final String selectedText;
  final List<CustomAction> actions;
  final Future<void> Function(CustomAction) onRunAction;
  final VoidCallback onCopy;
  final VoidCallback onDismiss;

  @override
  State<_SelectionActionBar> createState() => _SelectionActionBarState();
}

class _SelectionActionBarState extends State<_SelectionActionBar> {
  String? _loadingActionId;
  bool _isHovering = false;

  bool get _isLoading => _loadingActionId != null;

  Future<void> _handleAction(CustomAction action) async {
    if (_isLoading) return;
    
    setState(() {
      _loadingActionId = action.id;
    });
    
    try {
      await widget.onRunAction(action);
      if (mounted) {
        setState(() {
          _loadingActionId = null;
        });
        if (!_isHovering) {
          widget.onDismiss();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingActionId = null;
        });
      }
    }
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
      case 'external_link': return LucideIcons.externalLink;
      default: return LucideIcons.play;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final actionCount = widget.actions.length + 1; // +1 for Copy
    final barWidth = actionCount * 70.0 + 30;

    return Positioned(
      left: (widget.position.dx - barWidth / 2).clamp(10, MediaQuery.of(context).size.width - barWidth - 10),
      top: (widget.position.dy - 50).clamp(10, MediaQuery.of(context).size.height - 60),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: TapRegion(
          onTapOutside: _isLoading ? null : (_) => widget.onDismiss(),
          child: Material(
            type: MaterialType.transparency,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
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
                      // Configured actions
                      for (int i = 0; i < widget.actions.length; i++) ...[
                        _buildActionButton(widget.actions[i], cs),
                        if (i < widget.actions.length) _divider(cs),
                      ],
                      // Built-in Copy action
                      _ActionButton(
                        icon: LucideIcons.copy,
                        label: 'Copy',
                        onTap: widget.onCopy,
                        enabled: !_isLoading,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(CustomAction action, ColorScheme cs) {
    final isLoading = _loadingActionId == action.id;
    
    return _ActionButton(
      icon: isLoading ? null : _getIconForAction(action.iconName),
      isLoading: isLoading,
      label: action.name,
      onTap: () => _handleAction(action),
      enabled: !_isLoading,
    );
  }

  Widget _divider(ColorScheme cs) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: cs.outlineVariant.withOpacity(0.3),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    this.icon,
    required this.label,
    required this.onTap,
    this.isLoading = false,
    this.enabled = true,
  });

  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final bool isLoading;
  final bool enabled;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hovering && widget.enabled
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
                  color: widget.enabled
                      ? cs.onSurface.withOpacity(0.8)
                      : cs.onSurface.withOpacity(0.4),
                ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: widget.enabled
                      ? cs.onSurface.withOpacity(0.9)
                      : cs.onSurface.withOpacity(0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
