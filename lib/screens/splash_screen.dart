import 'dart:async';

import 'package:flutter/material.dart';

import '../main.dart';

/// Animated brand splash shown briefly while the app starts up.
///
/// Paints a full-screen indigo → blue gradient (matching the app bar brand)
/// with a subtle looping gradient animation, the MMCal logo/title, and a small
/// loading indicator. After [duration] the host swaps it out for the real UI
/// with a fade.
class SplashScreen extends StatefulWidget {
  final Duration duration;

  /// Called after [duration] elapses so the host can leave the splash.
  final VoidCallback onFinished;

  const SplashScreen({
    super.key,
    this.duration = const Duration(milliseconds: 1100),
    required this.onFinished,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _gradientCtrl;
  late final Animation<Alignment> _begin;
  late final Animation<Alignment> _end;
  Timer? _finishTimer;

  @override
  void initState() {
    super.initState();
    _gradientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    // Animated gradient endpooints give the splash a subtle "living" feel.
    _begin = Tween<Alignment>(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).animate(CurvedAnimation(parent: _gradientCtrl, curve: Curves.easeInOut));
    _end = Tween<Alignment>(
      begin: Alignment.bottomRight,
      end: Alignment.topLeft,
    ).animate(CurvedAnimation(parent: _gradientCtrl, curve: Curves.easeInOut));

    _finishTimer = Timer(widget.duration, widget.onFinished);
  }

  @override
  void dispose() {
    _finishTimer?.cancel();
    _gradientCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = isDark
        ? [AppColors.darkPrimary, AppColors.primary, AppColors.accent]
        : [AppColors.darkPrimary, AppColors.primary, AppColors.accentLight];

    return Scaffold(
      backgroundColor: AppColors.darkPrimary,
      body: AnimatedBuilder(
        animation: _gradientCtrl,
        builder: (context, child) {
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: _begin.value,
                end: _end.value,
                colors: colors,
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
            child: child,
          );
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo mark
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.calculate_outlined,
                  size: 52, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            const Text(
              'MMCal',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Multi-Market Brokerage Calculator',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 40),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
