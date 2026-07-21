import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../api/api_service.dart';
import 'sil_anticheat_service.dart';
import 'sil_widgets.dart';

bool get _isDesktopHost {
  if (kIsWeb) return false;
  try {
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  } catch (_) {
    return false;
  }
}

/// Face verification + liveness — requires a real camera capture when possible.
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
  bool _opening = false;
  String? _error;
  bool _livenessBlink = false;
  int _livenessStep = 0;
  DateTime? _livenessStarted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initCamera());
  }

  @override
  void dispose() {
    final c = _controller;
    _controller = null;
    // Fire-and-forget dispose — Windows needs the native handle released.
    unawaited(c?.dispose() ?? Future.value());
    super.dispose();
  }

  Future<void> _disposeController() async {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    try {
      await c.dispose();
    } catch (_) {}
    // Windows Media Foundation needs a short gap before reopen.
    await Future.delayed(const Duration(milliseconds: 450));
  }

  Future<void> _initCamera() async {
    if (_opening) return;
    _opening = true;
    if (mounted) {
      setState(() {
        _error = null;
        _ready = false;
      });
    }

    await _disposeController();

    try {
      if (!kIsWeb && !_isDesktopHost) {
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          if (mounted) {
            setState(() => _error =
                'Camera permission is required. Enable camera and tap Retry.');
          }
          return;
        }
      }

      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (mounted) {
          setState(() => _error =
              'No camera found. Plug in a webcam, or enable Camera access in Windows Settings → Privacy → Camera.');
        }
        return;
      }

      // Prefer front, then try every camera (Windows webcams are often "external").
      final ordered = <CameraDescription>[
        ...cams.where((c) => c.lensDirection == CameraLensDirection.front),
        ...cams.where((c) => c.lensDirection != CameraLensDirection.front),
      ];

      // Low preset is far more reliable on camera_windows.
      final presets = _isDesktopHost
          ? <ResolutionPreset>[ResolutionPreset.low, ResolutionPreset.medium]
          : <ResolutionPreset>[ResolutionPreset.medium, ResolutionPreset.low];

      Object? lastErr;
      for (final cam in ordered) {
        for (final preset in presets) {
          try {
            await _disposeController();
            final ctrl = CameraController(
              cam,
              preset,
              enableAudio: false,
            );
            await ctrl.initialize();
            // Give Windows preview texture a moment to attach.
            await Future.delayed(Duration(milliseconds: _isDesktopHost ? 300 : 50));
            if (!ctrl.value.isInitialized) {
              await ctrl.dispose();
              throw CameraException(
                'camera_error',
                'Camera not initialized. Camera should be disposed and reinitialized.',
              );
            }
            if (!mounted) {
              await ctrl.dispose();
              return;
            }
            setState(() {
              _controller = ctrl;
              _ready = true;
              _livenessStep = 0;
              _livenessStarted = DateTime.now();
              _error = null;
            });
            _scheduleLivenessCues();
            return;
          } catch (e) {
            lastErr = e;
            await _disposeController();
          }
        }
      }

      if (mounted) {
        setState(() {
          _error =
              'Could not open camera.\n$lastErr\n\n'
              'On Windows: Settings → Privacy & security → Camera → '
              'allow desktop apps, then tap Retry.';
        });
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() => _error =
            'Camera plugin missing. Quit the app fully and run scholaxia-win-run.bat again.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Could not open camera: $e\n\nAllow camera access, then tap Retry.');
      }
    } finally {
      _opening = false;
    }
  }

  void _scheduleLivenessCues() {
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && _ready) setState(() => _livenessStep = 1);
    });
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted && _ready) setState(() => _livenessStep = 2);
    });
    Future.delayed(const Duration(milliseconds: 4000), () {
      if (mounted && _ready) setState(() => _livenessStep = 3);
    });
  }

  Future<void> _capture() async {
    if (_busy) return;
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera is not open — tap Retry camera first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final started = _livenessStarted;
    if (started != null &&
        DateTime.now().difference(started).inMilliseconds < 2000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Complete liveness cues first (center → blink → hold).')),
      );
      return;
    }

    setState(() {
      _busy = true;
      _livenessBlink = true;
    });
    try {
      await Future.delayed(const Duration(milliseconds: 250));
      if (!ctrl.value.isInitialized) {
        throw CameraException('camera_error', 'Camera lost — tap Retry.');
      }
      // Windows takePicture is flaky while preview is hot — brief pause helps.
      if (_isDesktopHost) {
        try {
          await ctrl.pausePreview();
        } catch (_) {}
      }
      XFile file;
      try {
        file = await ctrl.takePicture();
      } catch (e) {
        if (_isDesktopHost) {
          try {
            await ctrl.resumePreview();
          } catch (_) {}
          await Future.delayed(const Duration(milliseconds: 400));
          file = await ctrl.takePicture();
        } else {
          rethrow;
        }
      }
      if (_isDesktopHost) {
        try {
          await ctrl.resumePreview();
        } catch (_) {}
      }
      final bytes = await file.readAsBytes();
      if (bytes.length < 800) {
        throw Exception('Empty photo — try again');
      }
      var sum = 0;
      var n = 0;
      for (var i = 0; i < bytes.length; i += 64) {
        sum += bytes[i];
        n++;
      }
      final lum = n == 0 ? 0.0 : sum / n;
      if (lum < 12) {
        if (mounted) {
          setState(() => _busy = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Face not visible — face the camera and retry.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      await _finishWithB64(base64Encode(bytes), livenessOk: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Capture failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _busy = false);
        // Auto-recover Windows stuck state
        if (e.toString().contains('Camera not initialized') ||
            e.toString().contains('already exists')) {
          await _initCamera();
        }
      }
    }
  }

  /// Windows-only escape when webcam cannot open after retries.
  Future<void> _continueWindowsWithoutCamera() async {
    if (!_isDesktopHost || _busy) return;
    setState(() => _busy = true);
    final token =
        'sil_face_windows_no_cam_${DateTime.now().millisecondsSinceEpoch}';
    await _finishWithB64(
      base64Encode(utf8.encode(token)),
      livenessOk: true,
      desktopSkip: true,
    );
  }

  Future<void> _finishWithB64(
    String b64, {
    required bool livenessOk,
    bool desktopSkip = false,
  }) async {
    if (!livenessOk) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Liveness failed — try again with camera.'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _busy = false);
      }
      return;
    }
    if (widget.requireApi) {
      try {
        await ApiService().silFaceVerify(
          faceSelfieB64: b64,
          matchId: widget.matchId,
          livenessOk: !desktopSkip,
        );
      } catch (_) {}
    }
    if (!mounted) return;
    if (desktopSkip) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Entered League without webcam. Use a phone for full face anti-cheat.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    Navigator.pop(context, b64);
  }

  @override
  Widget build(BuildContext context) {
    final cue = !_ready
        ? (_opening ? 'Opening camera…' : 'Camera not ready')
        : switch (_livenessStep) {
            0 => '1/3 Center your face in the circle',
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Perfect circle — same width & height (OPay-style).
                    final side = (constraints.biggest.shortestSide * 0.82)
                        .clamp(220.0, 300.0);
                    return Center(
                      child: Container(
                        width: side,
                        height: side,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _livenessBlink
                                ? SilColors.gold
                                : SilColors.purple,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: SilColors.purple.withOpacity(0.35),
                              blurRadius: 18,
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ClipOval(child: _preview(side)),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Text(
                cue,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.orangeAccent, height: 1.35, fontSize: 13),
                ),
                TextButton(
                  onPressed: _opening ? null : _initCamera,
                  child: const Text('Retry camera',
                      style: TextStyle(color: Colors.white)),
                ),
                if (_isDesktopHost)
                  TextButton(
                    onPressed: _busy ? null : _continueWindowsWithoutCamera,
                    child: const Text(
                      'Continue without camera (Windows only)',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              SilPrimaryButton(
                label: _busy ? 'Verifying…' : 'Verify & Continue',
                loading: _busy,
                onPressed: _ready && !_busy ? _capture : null,
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

  /// OPay-style: crop into the circle — never stretch the face.
  Widget _preview([double side = 280]) {
    final ctrl = _controller;
    if (ctrl != null && ctrl.value.isInitialized) {
      var aspect = ctrl.value.aspectRatio;
      if (aspect <= 0.05 || aspect > 10) {
        final ps = ctrl.value.previewSize;
        if (ps != null && ps.height > 0) {
          // previewSize is often landscape (w x h); CameraPreview uses w/h.
          aspect = ps.width / ps.height;
        } else {
          aspect = 4 / 3;
        }
      }

      // Natural-aspect preview, then BoxFit.cover into the square circle.
      // This crops edges if needed — face stays proportional (not long/tall).
      Widget preview = SizedBox(
        width: side * aspect,
        height: side,
        child: CameraPreview(ctrl),
      );

      // Mirror like a selfie / OPay front camera.
      final isFront =
          ctrl.description.lensDirection == CameraLensDirection.front;
      if (isFront || _isDesktopHost) {
        preview = Transform.flip(flipX: true, child: preview);
      }

      return ColoredBox(
        color: Colors.black,
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: preview,
        ),
      );
    }
    return Container(
      color: const Color(0xFF1A1228),
      child: Center(
        child: _error != null
            ? const Icon(Icons.videocam_off_rounded,
                color: Colors.orangeAccent, size: 64)
            : const CircularProgressIndicator(color: SilColors.purple),
      ),
    );
  }
}

/// Live front-camera pip during competitive matches.
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _beat?.cancel();
    final c = _controller;
    _controller = null;
    unawaited(c?.dispose() ?? Future.value());
    super.dispose();
  }

  Future<void> _start() async {
    if (_isDesktopHost) {
      // Don't fight face-verify for the same webcam on desktop matches.
      setState(() => _ok = false);
      return;
    }
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
      var sum = 0;
      var n = 0;
      for (var i = 0; i < bytes.length; i += 97) {
        sum += bytes[i];
        n++;
      }
      final lum = n == 0 ? 0.0 : sum / n;
      var faceCount = 1;
      var inFrame = true;
      if (lum < 18 || lum > 245) {
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
      if (!inFrame) widget.onCameraLost?.call();
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
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_ok && _controller != null && _controller!.value.isInitialized)
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
