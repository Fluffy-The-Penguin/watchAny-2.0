import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Atmospheric Hero Background that displays high-res widescreen banners with full clarity,
/// bright artwork, and dark cloud vignettes strictly around the outer edges/corners.
class DarkCloudHeroBackground extends StatelessWidget {
  final String imageUrl;
  final Widget? child;
  final Alignment imageAlignment;

  const DarkCloudHeroBackground({
    super.key,
    required this.imageUrl,
    this.child,
    this.imageAlignment = Alignment.topRight,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return Container(color: const Color(0xFF07070A), child: child);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Deep Dark Base
        Container(color: const Color(0xFF060609)),

        // 2. High-Quality Crisp Banner Image (Bright, Unblurred & Full Clarity)
        Positioned.fill(
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            alignment: imageAlignment,
            filterQuality: FilterQuality.high,
            placeholder: (context, url) => Container(color: const Color(0xFF07070A)),
            errorWidget: (context, url, err) => Container(color: const Color(0xFF07070A)),
          ),
        ),

        // 3. Left Text Protection Shadow (Soft gradient for title legibility)
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  const Color(0xFF060609).withValues(alpha: 0.95),
                  const Color(0xFF060609).withValues(alpha: 0.70),
                  const Color(0xFF060609).withValues(alpha: 0.25),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.25, 0.48, 0.75],
              ),
            ),
          ),
        ),

        // 4. Dark Cloud Fog on Top & Bottom Outer Edges (Corner / Frame Integration)
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xDD060609), // Top bar dark fog
                  Colors.transparent,
                  Colors.transparent,
                  Color(0xFF060609), // Bottom edge deep fog
                ],
                stops: [0.0, 0.18, 0.72, 1.0],
              ),
            ),
          ),
        ),

        // 5. Corner Vignette Cloud Overlay (Feathers the 4 outer corners seamlessly)
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.15,
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  const Color(0xFF060609).withValues(alpha: 0.65),
                  const Color(0xFF060609),
                ],
                stops: const [0.0, 0.65, 0.88, 1.0],
              ),
            ),
          ),
        ),

        // 6. Floating Overlay Child (Title, Badges, Action Buttons, Switches)
        if (child != null) Positioned.fill(child: child!),
      ],
    );
  }
}
