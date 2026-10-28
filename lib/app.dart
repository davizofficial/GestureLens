import 'package:flutter/material.dart';
import 'core/constants/app_constants.dart';
import 'features/camera/presentation/camera_screen.dart';
import 'features/welcome/presentation/welcome_screen.dart';
import 'shared/theme/app_theme.dart';

class GestureLensApp extends StatelessWidget {
  final GestureLensSessionController? controller;
  final bool? enforceAndroidLandscapeGateOverride;
  final bool? showWelcomeScreen;

  const GestureLensApp({
    super.key,
    this.controller,
    this.enforceAndroidLandscapeGateOverride,
    this.showWelcomeScreen,
  });

  @override
  Widget build(BuildContext context) {
    final cameraScreen = CameraScreen(
      controller: controller,
      enforceAndroidLandscapeGateOverride:
          enforceAndroidLandscapeGateOverride,
    );

    final shouldShowWelcome = showWelcomeScreen ?? (controller == null);

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: shouldShowWelcome
          ? WelcomeScreen(child: cameraScreen)
          : cameraScreen,
    );
  }
}
