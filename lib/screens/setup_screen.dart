import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../state/app_settings.dart';
import '../state/navigation_state.dart';
import '../widgets/custom_title_bar.dart';

class SetupScreen extends StatefulWidget {
  final VoidCallback onSetupComplete;

  const SetupScreen({super.key, required this.onSetupComplete});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen>
    with TickerProviderStateMixin {
  final Set<String> _selectedModes = {};
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  bool _isCompleting = false;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _slideController.forward();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _completeSetup() async {
    if (_selectedModes.isEmpty || _isCompleting) return;
    setState(() => _isCompleting = true);

    await AppSettings().setEnabledModes(_selectedModes);
    await AppSettings().completeSetup();

    // Set startup mode to the first selected mode
    final firstMode = AppSettings().enabledModesList.first;
    NavigationState().setMode(firstMode);

    widget.onSetupComplete();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 650;

    return Scaffold(
      backgroundColor: const Color(0xFF08080A),
      body: Column(
        children: [
          // Title bar with window controls on desktop
          if (_isDesktop)
            const CustomTitleBar(),

          Expanded(
            child: Stack(
              children: [
                // Subtle animated background
                Positioned.fill(
                  child: _AnimatedBackground(),
                ),

                // Main content
                SafeArea(
                  top: !_isDesktop,
                  child: Center(
                    child: FadeTransition(
                      opacity: _fadeAnim,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                          child: SingleChildScrollView(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 20.0 : 48.0,
                            vertical: isMobile ? 24.0 : 32.0,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(height: isMobile ? 12 : 24),

                                // Logo
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                                        blurRadius: 28,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 32,
                                  ),
                                ),

                                const SizedBox(height: 20),

                                // Title
                                const Text(
                                  'Welcome to watchAny',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Outfit',
                                    letterSpacing: 0.3,
                                  ),
                                ),

                                const SizedBox(height: 8),

                                // Subtitle
                                Text(
                                  'Choose what you\'d like to explore.\nYou can always change this later in Settings.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    fontSize: 13,
                                    fontFamily: 'Outfit',
                                    height: 1.5,
                                  ),
                                ),

                                const SizedBox(height: 36),

                                // Section cards — 2-column + centered 3rd card on mobile, 3-column row on desktop
                                isMobile
                                    ? LayoutBuilder(
                                        builder: (context, constraints) {
                                          final cardWidth = (constraints.maxWidth - 12) / 2;
                                          return Column(
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  SizedBox(
                                                    width: cardWidth,
                                                    child: _buildCard('anime', 'Anime', 'Stream & track your\nfavorite anime', Icons.tv_rounded, const [Color(0xFF6366F1), Color(0xFF4F46E5)], 0, isMobile),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  SizedBox(
                                                    width: cardWidth,
                                                    child: _buildCard('manga', 'Manga', 'Read manga from\nmultiple sources', Icons.menu_book_rounded, const [Color(0xFFF59E0B), Color(0xFFD97706)], 100, isMobile),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 12),
                                              Center(
                                                child: SizedBox(
                                                  width: cardWidth,
                                                  child: _buildCard('movies', 'Movies & Series', 'Watch movies, TV shows\nand web series', Icons.movie_rounded, const [Color(0xFFEC4899), Color(0xFFDB2777)], 200, isMobile),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      )
                                    : Row(
                                        children: [
                                          Expanded(child: _buildCard('anime', 'Anime', 'Stream and track your\nfavorite anime series', Icons.tv_rounded, const [Color(0xFF6366F1), Color(0xFF4F46E5)], 0, isMobile)),
                                          const SizedBox(width: 12),
                                          Expanded(child: _buildCard('manga', 'Manga', 'Read manga from\nmultiple sources', Icons.menu_book_rounded, const [Color(0xFFF59E0B), Color(0xFFD97706)], 100, isMobile)),
                                          const SizedBox(width: 12),
                                          Expanded(child: _buildCard('movies', 'Movies & Series', 'Watch movies, TV shows\nand web series', Icons.movie_rounded, const [Color(0xFFEC4899), const Color(0xFFDB2777)], 200, isMobile)),
                                        ],
                                      ),

                                const SizedBox(height: 36),

                                // Continue button
                                AnimatedOpacity(
                                  duration: const Duration(milliseconds: 300),
                                  opacity: _selectedModes.isNotEmpty ? 1.0 : 0.35,
                                  child: SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton(
                                      onPressed: _selectedModes.isNotEmpty && !_isCompleting
                                          ? _completeSetup
                                          : null,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF6366F1),
                                        disabledBackgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.25),
                                        foregroundColor: Colors.white,
                                        disabledForegroundColor: Colors.white38,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: _isCompleting
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                              ),
                                            )
                                          : Text(
                                              _selectedModes.isEmpty
                                                  ? 'Select at least one'
                                                  : 'Get Started',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                fontFamily: 'Outfit',
                                              ),
                                            ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(String mode, String title, String description, IconData icon, List<Color> gradient, int delay, bool isMobile) {
    final isSelected = _selectedModes.contains(mode);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 500 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - value)),
            child: child,
          ),
        );
      },
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedModes.remove(mode);
            } else {
              _selectedModes.add(mode);
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.all(isMobile ? 12 : 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? gradient[0].withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.06),
              width: isSelected ? 1.5 : 1.0,
            ),
            color: isSelected
                ? gradient[0].withValues(alpha: 0.1)
                : const Color(0xFF0F0F13),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: gradient[0].withValues(alpha: 0.12),
                      blurRadius: 24,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: isMobile ? 40 : 52,
                height: isMobile ? 40 : 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(isMobile ? 10 : 14),
                  gradient: isSelected
                      ? LinearGradient(
                          colors: gradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isSelected ? null : Colors.white.withValues(alpha: 0.05),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? Colors.white : Colors.white38,
                  size: isMobile ? 20 : 26,
                ),
              ),

              SizedBox(height: isMobile ? 10 : 14),

              // Title
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white60,
                  fontSize: isMobile ? 13.5 : 15,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Outfit',
                ),
              ),

              const SizedBox(height: 6),

              // Description
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.45)
                      : Colors.white.withValues(alpha: 0.25),
                  fontSize: isMobile ? 10.5 : 11.5,
                  fontFamily: 'Outfit',
                  height: 1.4,
                ),
              ),

              SizedBox(height: isMobile ? 10 : 14),

              // Checkmark
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: isMobile ? 20 : 26,
                height: isMobile ? 20 : 26,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(isMobile ? 6 : 8),
                  gradient: isSelected
                      ? LinearGradient(
                          colors: gradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  border: isSelected
                      ? null
                      : Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1.5,
                        ),
                ),
                child: isSelected
                    ? Icon(Icons.check_rounded, color: Colors.white, size: isMobile ? 13 : 16)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Subtle animated background with slowly drifting gradient orbs
class _AnimatedBackground extends StatefulWidget {
  @override
  State<_AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<_AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
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
        final t = _controller.value;
        return CustomPaint(
          painter: _BackgroundPainter(t),
          size: Size.infinite,
        );
      },
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  final double t;
  _BackgroundPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    // Soft indigo orb — top right
    final orb1Center = Offset(
      size.width * 0.75 + sin(t * 2 * pi) * 30,
      size.height * 0.2 + cos(t * 2 * pi) * 20,
    );
    final orb1Paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF6366F1).withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: orb1Center, radius: 200));
    canvas.drawCircle(orb1Center, 200, orb1Paint);

    // Soft pink orb — bottom left
    final orb2Center = Offset(
      size.width * 0.2 + cos(t * 2 * pi + 1) * 25,
      size.height * 0.75 + sin(t * 2 * pi + 1) * 25,
    );
    final orb2Paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFEC4899).withValues(alpha: 0.06),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: orb2Center, radius: 160));
    canvas.drawCircle(orb2Center, 160, orb2Paint);
  }

  @override
  bool shouldRepaint(_BackgroundPainter oldDelegate) => oldDelegate.t != t;
}
