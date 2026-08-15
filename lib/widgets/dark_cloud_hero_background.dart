import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// A premium cinematic hero background that uses dark atmospheric cloud effects,
/// soft ambient color diffusion, and seamless edge-feathering instead of stretching images.
class DarkCloudHeroBackground extends StatelessWidget {
  final String imageUrl;
  final Widget? child;
  final Alignment imageAlignment;
  final bool hasBanner;

  const DarkCloudHeroBackground({
    super.key,
    required this.imageUrl,
    this.child,
    this.imageAlignment = Alignment.topRight,
    this.hasBanner = true,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return Container(color: const Color(0xFF07070A), child: child);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Deepest Base Layer (Pure Obsidian Dark)
        Container(color: const Color(0xFF060609)),

        // 2. Ambient Blurred Color Cloud Layer (Pulls color from image into dark fog)
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 90.0, sigmaY: 90.0),
            child: Transform.scale(
              scale: 1.2,
              child: Opacity(
                opacity: 0.35,
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),

        // 3. Radial Dark Cloud Vignettes (Creates atmospheric smoke/cloud depth)
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.6, -0.4),
                radius: 1.4,
                colors: [
                  const Color(0xFF07070A).withValues(alpha: 0.40),
                  const Color(0xFF07070A).withValues(alpha: 0.85),
                  const Color(0xFF060609),
                ],
                stops: const [0.0, 0.65, 1.0],
              ),
            ),
          ),
        ),

        // 4. Main High-Quality Crisp Image (Faded at edges with Cloud Mask)
        Positioned.fill(
          child: ShaderMask(
            shaderCallback: (rect) {
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.transparent, // Heavy cloud fade over text area (Left)
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.65),
                  Colors.black,       // Full image opacity (Right)
                ],
                stops: const [0.0, 0.25, 0.55, 1.0],
              ).createShader(rect);
            },
            blendMode: BlendMode.dstIn,
            child: ShaderMask(
              shaderCallback: (rect) {
                return const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black,
                    Colors.black,
                    Colors.transparent, // Fade bottom edge into dark clouds
                  ],
                  stops: [0.0, 0.70, 1.0],
                ).createShader(rect);
              },
              blendMode: BlendMode.dstIn,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: hasBanner ? BoxFit.cover : BoxFit.fitHeight,
                alignment: imageAlignment,
                filterQuality: FilterQuality.high,
                placeholder: (context, url) => Container(color: const Color(0xFF07070A)),
                errorWidget: (context, url, err) => Container(color: const Color(0xFF07070A)),
              ),
            ),
          ),
        ),

        // 5. Dark Cloud Overlay & Text Protection Gradients
        // Left Column Dark Cloud Shadow
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  const Color(0xFF060609),
                  const Color(0xFF060609).withValues(alpha: 0.95),
                  const Color(0xFF060609).withValues(alpha: 0.70),
                  const Color(0xFF060609).withValues(alpha: 0.20),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.25, 0.45, 0.70, 1.0],
              ),
            ),
          ),
        ),

        // Top & Bottom Fog Layers for Smooth Navigation & Content Transitions
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xCC060609), // Top bar dark fog
                  Colors.transparent,
                  Colors.transparent,
                  Color(0xFF060609), // Bottom edge deep fog
                ],
                stops: [0.0, 0.20, 0.65, 1.0],
              ),
            ),
          ),
        ),

        // 6. Child Content (Text, Metadata, Actions)
        if (child != null) Positioned.fill(child: child!),
      ],
    );
  }
}
