import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';

/// Welcome / Splash screen displayed when GestureLens launches.
///
/// Features a `#1A1A1A` dark grey canvas with the centered GestureLens
/// "Portal Brackets" vector logo and "GestureLens" title in white using
/// the SF UI Display / SF UI Text font stack.
class WelcomeScreen extends StatefulWidget {
  final Widget child;
  final Duration displayDuration;

  const WelcomeScreen({
    super.key,
    required this.child,
    this.displayDuration = const Duration(milliseconds: 2200),
  });

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  bool _completed = false;
  Timer? _transitionTimer;
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutBack,
      ),
    );
    _animController.forward();

    _transitionTimer = Timer(widget.displayDuration, _finishWelcome);
  }

  void _finishWelcome() {
    if (!mounted || _completed) return;
    setState(() {
      _completed = true;
    });
  }

  @override
  void dispose() {
    _transitionTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_completed) {
      return widget.child;
    }

    return Scaffold(
      key: const Key('welcome_screen'),
      backgroundColor: const Color(0xFF1A1A1A),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finishWelcome,
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const GestureLensLogoWidget(
                    key: Key('welcome_logo'),
                    size: 120,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    AppConstants.appName,
                    key: Key('welcome_title'),
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      fontFamily: 'SF UI Display',
                      fontFamilyFallback: [
                        'SF UI Text',
                        '.SF UI Display',
                        '.SF UI Text',
                        'SF Pro Display',
                        'SF Pro Text',
                        'Inter',
                        'Roboto',
                        'sans-serif',
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pure vector widget rendering the official GestureLens "Portal Brackets" logo
/// (`#0B1021` Deep Space Navy tile, `#00F5D4` Cyan Neon hand brackets & lens iris,
/// and `#F8FAFC` rotated diamond portal).
class GestureLensLogoWidget extends StatelessWidget {
  final double size;

  const GestureLensLogoWidget({
    super.key,
    this.size = 120,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: const _GestureLensLogoPainter(),
    );
  }
}

class _GestureLensLogoPainter extends CustomPainter {
  const _GestureLensLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 256.0;
    canvas.save();
    canvas.scale(scale, scale);

    // 1. Rounded square app-icon tile in Deep Space Navy (#0B1021)
    final tilePaint = Paint()
      ..color = const Color(0xFF0B1021)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 256, 256),
        const Radius.circular(56),
      ),
      tilePaint,
    );

    // Subtle border ring for crisp separation on #1A1A1A background
    final tileBorderPaint = Paint()
      ..color = const Color(0xFF00F5D4).withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..isAntiAlias = true;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(1.5, 1.5, 253, 253),
        const Radius.circular(55),
      ),
      tileBorderPaint,
    );

    // Scale inner mark slightly (0.78) around center (128, 128) to match app icon padding
    canvas.translate(128, 128);
    canvas.scale(0.78, 0.78);
    canvas.translate(-128, -128);

    // 2. Rotated diamond portal ring in Ice White (#F8FAFC) with even-odd cutout
    final portalPath = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(128, 44)
      ..lineTo(212, 128)
      ..lineTo(128, 212)
      ..lineTo(44, 128)
      ..close()
      ..moveTo(128, 80)
      ..lineTo(176, 128)
      ..lineTo(128, 176)
      ..lineTo(80, 128)
      ..close();

    final portalPaint = Paint()
      ..color = const Color(0xFFF8FAFC)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(portalPath, portalPaint);

    // 3. Hand-tracking corner brackets + central lens iris in Cyan Neon (#00F5D4)
    final cyanPaint = Paint()
      ..color = const Color(0xFF00F5D4)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final bracketsPath = Path()
      // Top-left hand bracket
      ..moveTo(28, 28)
      ..lineTo(108, 28)
      ..lineTo(108, 56)
      ..lineTo(56, 56)
      ..lineTo(56, 108)
      ..lineTo(28, 108)
      ..close()
      // Bottom-right hand bracket
      ..moveTo(228, 228)
      ..lineTo(148, 228)
      ..lineTo(148, 200)
      ..lineTo(200, 200)
      ..lineTo(200, 148)
      ..lineTo(228, 148)
      ..close();

    canvas.drawPath(bracketsPath, cyanPaint);
    canvas.drawCircle(const Offset(128, 128), 26, cyanPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GestureLensLogoPainter oldDelegate) => false;
}
