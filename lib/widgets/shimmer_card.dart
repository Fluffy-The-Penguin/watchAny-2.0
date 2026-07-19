import 'package:flutter/material.dart';

class ShimmerCard extends StatefulWidget {
  final double? height;
  final double borderRadius;
  final Widget? child;

  const ShimmerCard({
    super.key,
    this.height = 86.0,
    this.borderRadius = 8.0,
    this.child,
  });

  @override
  State<ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<ShimmerCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double slide = _controller.value;
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(color: Colors.white.withOpacity(0.04)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.02),
                Colors.white.withOpacity(0.08),
                Colors.white.withOpacity(0.02),
              ],
              stops: [
                (slide - 0.25).clamp(0.0, 1.0),
                slide,
                (slide + 0.25).clamp(0.0, 1.0),
              ],
            ),
          ),
          child: widget.child ?? Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mock thumbnail or indicator circle
                Container(
                  width: 40.0,
                  height: 40.0,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12.0),
                // Mock text lines
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 12.0,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Row(
                        children: [
                          Container(
                            width: 60.0,
                            height: 10.0,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(3.0),
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          Container(
                            width: 40.0,
                            height: 10.0,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(3.0),
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          Container(
                            width: 80.0,
                            height: 10.0,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(3.0),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
