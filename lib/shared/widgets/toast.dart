import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A subtle, elegant toast notification that appears at the bottom center.
/// Much less intrusive than standard SnackBars.
class Toast {
  static OverlayEntry? _currentEntry;
  static Timer? _hideTimer;

  /// Show a success toast with a checkmark icon
  static void show(BuildContext context, String message, {Duration duration = const Duration(seconds: 1, milliseconds: 500)}) {
    _show(context, message, LucideIcons.check, duration: duration);
  }

  /// Show an error toast with an X icon
  static void error(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    _show(context, message, LucideIcons.x, isError: true, duration: duration);
  }

  static void _show(
    BuildContext context,
    String message,
    IconData icon, {
    bool isError = false,
    required Duration duration,
  }) {
    // Remove any existing toast
    _hide();

    final overlay = Overlay.of(context);
    
    _currentEntry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        icon: icon,
        isError: isError,
      ),
    );

    overlay.insert(_currentEntry!);

    _hideTimer = Timer(duration, _hide);
  }

  static void _hide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

class _ToastWidget extends StatefulWidget {
  const _ToastWidget({
    required this.message,
    required this.icon,
    this.isError = false,
  });

  final String message;
  final IconData icon;
  final bool isError;

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = widget.isError ? Colors.red[400] : cs.primary;

    return Positioned(
      bottom: 60,
      left: 0,
      right: 0,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.15)
                          : Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(24),
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
                        Icon(
                          widget.icon,
                          size: 16,
                          color: isDark ? iconColor : (widget.isError ? Colors.red[300] : Colors.white),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.message,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white.withOpacity(0.9) : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
