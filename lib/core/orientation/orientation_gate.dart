import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

class AndroidLandscapeOrientationGate extends StatefulWidget {
  final Widget landscapeChild;
  final VoidCallback? onEnteredLandscape;
  final VoidCallback? onReturnedToPortrait;
  /// Allows overriding platform detection in widget tests.
  final bool? enforceGateOverride;

  const AndroidLandscapeOrientationGate({
    super.key,
    required this.landscapeChild,
    this.onEnteredLandscape,
    this.onReturnedToPortrait,
    this.enforceGateOverride,
  });

  @override
  State<AndroidLandscapeOrientationGate> createState() =>
      _AndroidLandscapeOrientationGateState();
}

class _AndroidLandscapeOrientationGateState
    extends State<AndroidLandscapeOrientationGate> {
  bool? _wasLandscape;

  bool get _shouldEnforceGate =>
      widget.enforceGateOverride ??
      (defaultTargetPlatform == TargetPlatform.android);

  @override
  Widget build(BuildContext context) {
    if (!_shouldEnforceGate) {
      return widget.landscapeChild;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaOrientation = MediaQuery.orientationOf(context);
        final isLandscape =
            mediaOrientation == Orientation.landscape &&
            constraints.maxWidth >= constraints.maxHeight;

        if (_wasLandscape != isLandscape) {
          final previous = _wasLandscape;
          _wasLandscape = isLandscape;
          if (previous != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (isLandscape) {
                widget.onEnteredLandscape?.call();
              } else {
                widget.onReturnedToPortrait?.call();
              }
            });
          }
        }

        if (!isLandscape) {
          return const _PortraitOrientationGateView();
        }

        return widget.landscapeChild;
      },
    );
  }
}

class _PortraitOrientationGateView extends StatelessWidget {
  const _PortraitOrientationGateView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Horizontal-phone illustration
                Container(
                  width: 148,
                  height: 86,
                  decoration: BoxDecoration(
                    color: const Color(0xFF161F33),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFF00F0FF),
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00F0FF).withValues(alpha: 0.22),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        left: 10,
                        child: Container(
                          width: 6,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.white38,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.screen_rotation_alt_rounded,
                            color: Color(0xFF00F0FF),
                            size: 34,
                          ),
                          SizedBox(width: 8),
                          Icon(
                            Icons.pan_tool_alt_rounded,
                            color: Color(0xFF3CFF82),
                            size: 26,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  AppConstants.orientationGateMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  AppConstants.orientationAutoRotateHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
