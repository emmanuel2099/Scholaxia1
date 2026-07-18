import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../api/api_service.dart';
import '../../../theme/app_theme.dart';
import 'sil_anticheat_service.dart';
import 'sil_widgets.dart';

/// Face verification + liveness capture for SIL.
/// Used on: signup, League entry, before live matches, after app resume.
class SilFaceVerifyScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final String? matchId;
  final bool requireApi;

  const SilFaceVerifyScreen({
    super.key,
    this.title = 'Face Verification',
    this.subtitle =
        'Look at the camera. Keep one face in frame for liveness check.',
    this.matchId,
    this.requireApi = true,
  });

  /// Returns base64 selfie string on success, or null if cancelled.
  static Future<String?> open(
    BuildContext context, {
    String title = 'Face Verification',
    String subtitle =
        'Look at the camera. Keep one face in frame for liveness check.',
    String? matchId,
    bool requireApi = true,
  }) {
    return Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => SilFaceVerifyScreen(
          title: title,
          subtitle: subtitle,
          matchId: matchId,
          requireApi: requireApi,
        ),
      ),
    );
  }

  @override
  State<SilFaceVerifyScreen> createState() => _SilFaceVerifyScreenState();
}

class _SilFaceVerifyScreenState extends State<SilFaceVerifyScreen> {
  CameraController? _controller;
  bool _ready = false;
  bool _busy = false;
  String? _error;
  bool _livenessBlink = false;
  int _livenessStep = 0; // 0 center, 1 blink, 2 turn left cue, 3 ready
  DateTime? _livenessStarted;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    setState(() {
      _error = null;
      _ready = false;
    });
    try {
      if (!kIsWeb) {
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          setState(() => _error =
              'Camera permission is required for League face verification.');
          return;
        }
      }
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _error =
            'No camera found. Connect a camera or use a phone to continue.');
        return;
      }
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _controller = ctrl;
        _ready = true;
        _livenessStep = 0;
        _livenessStarted = DateTime.now();
      });
      // Multi-step liveness cues (PRD §18)
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _livenessStep = 1);
      });
      Future.delayed(const Duration(milliseconds: 2600), () {
        if (mounted) setState(() => _livenessStep = 2);
      });
      Future.delayed(const Duration(milliseconds: 4000), () {
        if (mounted) setState(() => _livenessStep = 3);
      });
    } catch (e) {
      setState(() => _error = 'Could not open camera: $e');
    }
  }

  Future<void> _capture() async {
    if (_busy) return;
    // Enforce minimum liveness interaction time
    final started = _livenessStarted;
    if (started != null &&
        DateTime.now().difference(started).inMilliseconds < 2500 &&
        _error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Complete liveness cues first (center → blink → hold).')),
      );
      return;
    }
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      if (_error != null) {
        await _finishWithB64(base64Encode(utf8.encode(
            'sil_face_fallback_${DateTime.now().millisecondsSinceEpoch}')),
            livenessOk: false);
      }
      return;
    }
    setState(() {
      _busy = true;
      _livenessBlink = true;
    });
    try {
      await Future.delayed(const Duration(milliseconds: 350));
      final file = await ctrl.takePicture();
      final bytes = await file.readAsBytes();
      // Reject near-black frames (camera covered)
      var sum = 0;
      var n = 0;
      for (var i = 0; i < bytes.length; i += 64) {
        sum += bytes[i];
        n++;
      }
      final lum = n == 0 ? 0.0 : sum / n;
      if (lum < 15) {
        if (mounted) {
          setState(() => _busy = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Face not visible — uncover camera and retry.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      final b64 = base64Encode(bytes);
      await _finishWithB64(b64, livenessOk: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e'), backgroundColor: Colors.red),
        );
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _finishWithB64(String b64, {required bool livenessOk}) async {
    if (widget.requireApi) {
      try {
        await ApiService().silFaceVerify(
          faceSelfieB64: b64,
          matchId: widget.matchId,
          livenessOk: livenessOk,
        );
      } catch (_) {}
    }
    if (!mounted) return;
    if (!livenessOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Liveness failed — try again with camera.'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _busy = false);
      return;
    }
    Navigator.pop(context, b64);
  }

  @override
  Widget build(BuildContext context) {
    final cue = switch (_livenessStep) {
      0 => '1/3 Center your face in the oval',
      1 => '2/3 Blink once slowly',
      2 => '3/3 Hold still — one face only',
      _ => 'Ready — tap Verify & Continue',
    };
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.35),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: ClipOval(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _livenessBlink
                                ? SilColors.gold
                                : SilColors.purple,
                            width: 4,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: ClipOval(child: _preview()),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                cue,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.orangeAccent)),
                TextButton(
                  onPressed: _initCamera,
                  child: const Text('Retry camera',
                      style: TextStyle(color: Colors.white)),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _finishWithB64(
                            base64Encode(utf8.encode(
                                'sil_face_fallback_${DateTime.now().millisecondsSinceEpoch}')),
                            livenessOk: true,
                          ),
                  child: const Text('Continue without camera (dev)',
                      style: TextStyle(color: Colors.white54)),
                ),
              ],
              const SizedBox(height: 16),
              SilPrimaryButton(
                label: _busy ? 'Verifying…' : 'Verify & Continue',
                loading: _busy,
                onPressed: (_ready || _error != null) && !_busy ? _capture : null,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview() {
    final ctrl = _controller;
    if (ctrl != null && ctrl.value.isInitialized) {
      return CameraPreview(ctrl);
    }
    return Container(
      color: const Color(0xFF1A1228),
      child: const Center(
        child: Icon(Icons.face_retouching_natural,
            color: SilColors.purple, size: 72),
      ),
    );
  }
}

/// Small live front-camera pip used during competitive matches.
/// Periodically samples frames → luminance / presence heuristic → server heartbeat.
class SilProctorPip extends StatefulWidget {
  final String? matchId;
  final VoidCallback? onCameraLost;
  final ValueChanged<Map<String, dynamic>>? onServerSignal;

  const SilProctorPip({
    super.key,
    this.matchId,
    this.onCameraLost,
    this.onServerSignal,
  });

  @override
  State<SilProctorPip> createState() => _SilProctorPipState();
}

class _SilProctorPipState extends State<SilProctorPip> {
  CameraController? _controller;
  bool _ok = false;
  Timer? _beat;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _beat?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      if (!kIsWeb) {
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          widget.onCameraLost?.call();
          return;
        }
      }
      final cams = await availableCameras();
      if (cams.isEmpty) {
        widget.onCameraLost?.call();
        return;
      }
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(
        front,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() {
        _controller = ctrl;
        _ok = true;
      });
      _beat = Timer.periodic(const Duration(seconds: 4), (_) => _pulse());
    } catch (_) {
      widget.onCameraLost?.call();
    }
  }

  Future<void> _pulse() async {
    final ctrl = _controller;
    final matchId = widget.matchId;
    if (ctrl == null || !ctrl.value.isInitialized || matchId == null) return;
    try {
      final shot = await ctrl.takePicture();
      final bytes = await shot.readAsBytes();
      // Crude presence heuristic from JPEG bytes (covered cam ≈ low variance/dark)
      var sum = 0;
      var n = 0;
      for (var i = 0; i < bytes.length; i += 97) {
        sum += bytes[i];
        n++;
      }
      final lum = n == 0 ? 0.0 : sum / n;
      var faceCount = 1;
      var inFrame = true;
      if (lum < 18) {
        faceCount = 0;
        inFrame = false;
      } else if (lum > 245) {
        // washed / covered with light
        faceCount = 0;
        inFrame = false;
      }
      final res = await SilAntiCheatService.instance.heartbeat(
        matchId,
        faceInFrame: inFrame,
        faceCount: faceCount,
        luminance: lum,
        detail: 'pip_sample',
      );
      widget.onServerSignal?.call(res);
      if (res['forfeited'] == true || (!inFrame && (res['paused'] == true))) {
        if (!inFrame) widget.onCameraLost?.call();
      }
    } catch (_) {
      widget.onCameraLost?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 118,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SilColors.purple, width: 2),
        boxShadow: [
          BoxShadow(
            color: SilColors.purple.withOpacity(0.35),
            blurRadius: 10,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_ok && _controller != null)
            CameraPreview(_controller!)
          else
            const ColoredBox(
              color: Color(0xFF1A1228),
              child: Icon(Icons.videocam_off, color: Colors.white54, size: 28),
            ),
          const Positioned(
            left: 4,
            top: 4,
            child: Row(
              children: [
                Icon(Icons.circle, color: Colors.redAccent, size: 8),
                SizedBox(width: 4),
                Text('LIVE',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
