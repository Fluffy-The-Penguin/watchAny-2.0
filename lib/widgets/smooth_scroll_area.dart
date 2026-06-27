import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart';
import '../state/app_settings.dart';

// ---------------------------------------------------------------------------
// SmoothScrollController + SmoothScrollPosition
//
// Overrides ScrollPosition.pointerScroll so that mouse-wheel events animate
// instead of jumping.  The Scrollable still claims the pointer-signal event
// through the normal resolver path, but our override turns the jumpTo into
// an animateTo.
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
      // Smooth scroll disabled - fall back to the default jumpTo behaviour.
      super.pointerScroll(delta);
      return;
    }

    if (!hasPixels) return;

    // If we are not currently performing a smooth animation, or if the target has not been set yet,
    // sync our target with the current actual pixels (e.g. after dragging or scrollbar usage).
    if (activity is! DrivenScrollActivity || _targetPixels == null) {
      _targetPixels = pixels;
    }

    // Accumulate the delta onto our target pixels for a smooth progressive scroll.
    _targetPixels = clampDouble(
      _targetPixels! + delta * 2.5,
      minScrollExtent,
      maxScrollExtent,
    );

    animateTo(
      _targetPixels!,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
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
    return widget.builder(_controller, const ClampingScrollPhysics());
  }
}
