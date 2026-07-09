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
  Ticker? _ticker;
  double _lastElapsedSeconds = 0.0;

  @override
  void pointerScroll(double delta) {
    if (!AppSettings().smoothScrollEnabled) {
      // Smooth scroll disabled - fall back to the default jumpTo behaviour.
      super.pointerScroll(delta);
      return;
    }

    if (!hasPixels) return;

    // Sync target with actual pixels if we aren't currently smooth-scrolling
    if (_ticker == null || !_ticker!.isActive || _targetPixels == null) {
      _targetPixels = pixels;
    }

    // Accumulate the delta onto our target pixels for a smooth progressive scroll.
    _targetPixels = clampDouble(
      _targetPixels! + delta * 2.0,
      minScrollExtent,
      maxScrollExtent,
    );

    _startTicker();
  }

  void _startTicker() {
    _lastElapsedSeconds = 0.0;

    _ticker ??= context.vsync.createTicker((Duration elapsed) {
      if (!hasPixels || _targetPixels == null) {
        if (_ticker != null && _ticker!.isActive) {
          _ticker!.stop();
        }
        return;
      }

      final double elapsedSeconds = elapsed.inMicroseconds / 1000000.0;
      final double dt = elapsedSeconds - _lastElapsedSeconds;
      _lastElapsedSeconds = elapsedSeconds;

      if (dt <= 0.0) return;

      final double current = pixels;
      final double target = _targetPixels!;

      // Frame-rate independent exponential decay
      final double lerpFactor = 1.0 - math.exp(-14.0 * dt);
      final double next = current + (target - current) * lerpFactor;

      // Snap to target if very close to prevent micro-movements
      if ((next - target).abs() < 0.5) {
        jumpTo(target);
        if (_ticker != null && _ticker!.isActive) {
          _ticker!.stop();
        }
      } else {
        jumpTo(next);
      }
    });

    if (!_ticker!.isActive) {
      _ticker!.start();
    }
  }

  @override
  void beginActivity(ScrollActivity? newActivity) {
    // If the user starts dragging (scrollbar, touch) or flinging, stop smooth scroll
    if (newActivity != null && newActivity.isScrolling) {
      if (_ticker != null && _ticker!.isActive) {
        _ticker!.stop();
      }
      _targetPixels = null;
    }
    super.beginActivity(newActivity);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
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
