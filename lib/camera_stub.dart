// Stub for web — camera package is unavailable in the browser.
// ignore_for_file: avoid_classes_with_only_static_members

import 'package:flutter/widgets.dart';

enum CameraLensDirection { front, back, external }

enum ResolutionPreset { low, medium, high, veryHigh, ultraHigh, max }

class CameraDescription {
  final CameraLensDirection lensDirection;
  const CameraDescription({this.lensDirection = CameraLensDirection.back});
}

class CameraController {
  CameraController(CameraDescription description, ResolutionPreset preset,
      {bool enableAudio = false});
  Future<void> initialize() async {}
  Future<void> dispose() async {}
}

Future<List<CameraDescription>> availableCameras() async => [];

class CameraPreview extends StatelessWidget {
  final CameraController controller;
  const CameraPreview(this.controller, {super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
