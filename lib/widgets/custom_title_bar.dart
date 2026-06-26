import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class CustomTitleBar extends StatefulWidget implements PreferredSizeWidget {
  const CustomTitleBar({super.key});

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();

  @override
  Size get preferredSize => const Size.fromHeight(32.0);
}

class _CustomTitleBarState extends State<CustomTitleBar> {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    _checkMaximizedState();
  }

  Future<void> _checkMaximizedState() async {
    final max = await windowManager.isMaximized();
    if (mounted && max != _isMaximized) {
      setState(() {
        _isMaximized = max;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32.0,
      color: Colors.transparent,
      child: Row(
        children: [
          // Draggable window area to move window
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (details) {
                windowManager.startDragging();
              },
              onDoubleTap: () async {
                final isMax = await windowManager.isMaximized();
                if (isMax) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
                _checkMaximizedState();
              },
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),
          
          // Window action buttons
          Row(
            children: [
              // Minimize
              _TitleBarButton(
                icon: Icons.remove,
                onPressed: () async {
                  await windowManager.minimize();
                },
                hoverColor: Colors.white10,
                iconSize: 16.0,
              ),
              // Maximize / Restore
              _TitleBarButton(
                icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
                onPressed: () async {
                  final isMax = await windowManager.isMaximized();
                  if (isMax) {
                    await windowManager.unmaximize();
                  } else {
                    await windowManager.maximize();
                  }
                  _checkMaximizedState();
                },
                hoverColor: Colors.white10,
                iconSize: 12.0,
              ),
              // Close
              _TitleBarButton(
                icon: Icons.close,
                onPressed: () async {
                  await windowManager.close();
                },
                hoverColor: Colors.red.withValues(alpha: 0.8),
                hoverIconColor: Colors.white,
                iconSize: 16.0,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TitleBarButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color hoverColor;
  final Color? hoverIconColor;
  final double iconSize;

  const _TitleBarButton({
    required this.icon,
    required this.onPressed,
    required this.hoverColor,
    this.hoverIconColor,
    required this.iconSize,
  });

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 46.0,
          height: 32.0,
          alignment: Alignment.center,
          color: _isHovering ? widget.hoverColor : Colors.transparent,
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: _isHovering && widget.hoverIconColor != null
                ? widget.hoverIconColor
                : Colors.white60,
          ),
        ),
      ),
    );
  }
}
