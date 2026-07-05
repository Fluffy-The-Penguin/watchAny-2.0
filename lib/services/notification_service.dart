import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

class AppNotification {
  final String id;
  final String message;
  final bool isError;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.message,
    this.isError = false,
  }) : createdAt = DateTime.now();
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final List<AppNotification> _notifications = [];
  OverlayEntry? _overlayEntry;

  void show(BuildContext context, String message, {bool isError = false}) {
    final notification = AppNotification(
      id: UniqueKey().toString(),
      message: message,
      isError: isError,
    );

    _notifications.add(notification);
    _showOverlay(context);

    // Auto-dismiss after 3.5 seconds
    Timer(const Duration(milliseconds: 3500), () {
      _remove(notification.id);
    });
  }

  void _remove(String id) {
    _notifications.removeWhere((n) => n.id == id);
    if (_notifications.isEmpty) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    } else {
      _overlayEntry?.markNeedsBuild();
    }
  }

  void _showOverlay(BuildContext context) {
    final overlayState = Overlay.of(context, rootOverlay: true);
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          bottom: 24.0,
          right: 24.0,
          width: 340.0,
          child: _NotificationStackWidget(
            notifications: _notifications,
            onDismiss: _remove,
          ),
        );
      },
    );
    overlayState.insert(_overlayEntry!);
  }
}

class _NotificationStackWidget extends StatelessWidget {
  final List<AppNotification> notifications;
  final Function(String) onDismiss;

  const _NotificationStackWidget({
    required this.notifications,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    // Show only the 4 most recent notifications to avoid clutter
    final List<AppNotification> visibleNotifications = notifications.length > 4
        ? notifications.sublist(notifications.length - 4)
        : notifications;

    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: visibleNotifications.map((notif) {
          return Padding(
            key: ValueKey(notif.id),
            padding: const EdgeInsets.only(top: 10.0),
            child: _NotificationCard(
              notification: notif,
              onDismiss: () => onDismiss(notif.id),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _NotificationCard extends StatefulWidget {
  final AppNotification notification;
  final VoidCallback onDismiss;

  const _NotificationCard({
    required this.notification,
    required this.onDismiss,
    super.key,
  });

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _opacityAnimation;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.2, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.linear,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _controller.dispose();
    super.dispose();
  }

  void _handleDismiss() {
    if (_isDisposed) return;
    _controller.reverse().then((_) {
      if (!_isDisposed) {
        widget.onDismiss();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.notification.isError
        ? const Color(0xffef4444)
        : const Color(0xff10b981);

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _opacityAnimation,
        child: Container(
          width: 340.0,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(
              color: colorScheme.withValues(alpha: 0.25),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.withValues(alpha: 0.08),
                blurRadius: 12.0,
                spreadRadius: 1.0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Animated Status indicator
                  Container(
                    width: 8.0,
                    height: 8.0,
                    decoration: BoxDecoration(
                      color: colorScheme,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.withOpacity(0.5),
                          blurRadius: 6.0,
                          spreadRadius: 2.0,
                        )
                      ],
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: Text(
                      widget.notification.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  // Small close button
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.close,
                      color: Colors.white.withOpacity(0.4),
                      size: 16.0,
                    ),
                    hoverColor: Colors.transparent,
                    splashColor: Colors.transparent,
                    onPressed: _handleDismiss,
                  ),
                ],
              ),
            ),
          ),
        );
  }
}
