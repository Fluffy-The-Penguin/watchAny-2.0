import 'dart:async';
import 'package:flutter/material.dart';

class BrandSplashScreen extends StatefulWidget {
  final Future<void> initFuture;
  final VoidCallback onComplete;

  const BrandSplashScreen({
    super.key,
    required this.initFuture,
    required this.onComplete,
  });

  @override
  State<BrandSplashScreen> createState() => _BrandSplashScreenState();
}

class _BrandSplashScreenState extends State<BrandSplashScreen> with TickerProviderStateMixin {
  late AnimationController _mainController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  late AnimationController _shineController;
  late Animation<double> _shineAnimation;

  late AnimationController _textController;
  late Animation<double> _textFadeAnimation;
  late Animation<double> _textSpacingAnimation;

  @override
  void initState() {
    super.initState();

    // Main logo scale & fade intro (0 to 1.2s)
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scaleAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _mainController, curve: Curves.easeOutBack),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mainController, curve: const Interval(0.0, 0.6, curve: Curves.easeIn)),
    );

    // Glow breathing animation (looping)
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _glowAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    // Shine slash animation (looping every 1.5s)
    _shineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _shineAnimation = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(parent: _shineController, curve: Curves.easeInOut),
    );

    // Text fade and stretch (0.4s to 1.4s)
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeIn),
    );
    _textSpacingAnimation = Tween<double>(begin: 0.0, end: 6.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic),
    );

    // Run animations sequentially
    _mainController.forward().then((_) {
      _glowController.repeat(reverse: true);
      _shineController.repeat();
    });

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _textController.forward();
    });

    // Run initialization future and hold for a minimum of 2.2 seconds to show the animation
    Future.wait([
      widget.initFuture,
      Future.delayed(const Duration(milliseconds: 2200)),
    ]).then((_) {
      if (mounted) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _mainController.dispose();
    _glowController.dispose();
    _shineController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070709),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo area with animated scale, fade, breathing glow, and shine slash
            AnimatedBuilder(
              animation: Listenable.merge([_mainController, _glowController, _shineAnimation]),
              builder: (context, child) {
                final scale = _scaleAnimation.value;
                final fade = _fadeAnimation.value;
                final glow = _glowAnimation.value;

                return Opacity(
                  opacity: fade,
                  child: Transform.scale(
                    scale: scale,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Soft behind-logo glow
                        Container(
                          width: 140 * glow,
                          height: 140 * glow,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                const Color(0xFF6366F1).withValues(alpha: 0.25),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                        // The actual logo with Shine Slash ShaderMask
                        ShaderMask(
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              begin: const Alignment(-2.0, -2.0),
                              end: const Alignment(2.0, 2.0),
                              colors: [
                                Colors.transparent,
                                Colors.white.withValues(alpha: 0.1),
                                Colors.white,
                                Colors.white.withValues(alpha: 0.1),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
                              transform: _SlidingGradientTransform(slidePercent: _shineAnimation.value),
                            ).createShader(bounds);
                          },
                          blendMode: BlendMode.srcATop,
                          child: Image.asset(
                            'assets/logo.png',
                            width: 110,
                            height: 110,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 36.0),

            // Text "watchAny" with animated letter-spacing and fade-in
            AnimatedBuilder(
              animation: _textController,
              builder: (context, child) {
                return Opacity(
                  opacity: _textFadeAnimation.value,
                  child: Text(
                    'watchAny',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30.0,
                      fontWeight: FontWeight.bold,
                      letterSpacing: _textSpacingAnimation.value,
                      fontFamily: 'Outfit',
                      shadows: const [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0.0, 0.0);
  }
}
