import 'package:flutter/material.dart';
import 'core/constants/app_constants.dart';
import 'features/camera/presentation/camera_screen.dart';
import 'shared/theme/app_theme.dart';

class GestureLensApp extends StatelessWidget {
  final GestureLensSessionController? controller;
  final bool? enforceAndroidLandscapeGateOverride;

  const GestureLensApp({
    super.key,
    this.controller,
    this.enforceAndroidLandscapeGateOverride,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: CameraScreen(
        controller: controller,
        enforceAndroidLandscapeGateOverride:
            enforceAndroidLandscapeGateOverride,
      ),
    );
  }
}
