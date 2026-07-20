import 'dart:math' as math;
import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../state/app_settings.dart';

// ---------------------------------------------------------------------------
// SmoothScrollController + SmoothScrollPosition
//
// Overrides ScrollPosition.pointerScroll so that mouse-wheel events animate
// smoothly using a frame-rate independent LERP ticker instead of jumping
// or starting/canceling animation controllers repeatedly.
// ---------------------------------------------------------------------------

class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return SmoothScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      debugLabel: debugLabel,
      oldPosition: oldPosition,
    );
  }
}

class SmoothScrollPosition extends ScrollPositionWithSingleContext {
  SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.debugLabel,
    super.oldPosition,
  });

  double? _targetPixels;

  @override
  void pointerScroll(double delta) {
    if (!AppSettings().smoothScrollEnabled) {
      super.pointerScroll(delta);
      return;
    }

    if (!hasPixels) return;

    if (_targetPixels == null || (pixels - _targetPixels!).abs() > 300) {
      _targetPixels = pixels;
    }

    _targetPixels = clampDouble(
      _targetPixels! + delta * 1.2,
      minScrollExtent,
      maxScrollExtent,
    );

    if (_targetPixels != pixels) {
      animateTo(
        _targetPixels!,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void beginActivity(ScrollActivity? newActivity) {
    if (newActivity != null && newActivity.isScrolling) {
      _targetPixels = null;
    }
    super.beginActivity(newActivity);
  }
}

// ---------------------------------------------------------------------------
// SmoothScrollArea
//
// A convenience wrapper that creates a SmoothScrollController and hands it
// (along with normal ClampingScrollPhysics) to the builder.
// ---------------------------------------------------------------------------

class SmoothScrollArea extends StatefulWidget {
  final Widget Function(ScrollController controller, ScrollPhysics physics) builder;

  const SmoothScrollArea({super.key, required this.builder});

  @override
  State<SmoothScrollArea> createState() => _SmoothScrollAreaState();
}

class _SmoothScrollAreaState extends State<SmoothScrollArea> {
  final SmoothScrollController _controller = SmoothScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(_controller, const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()));
  }
}
