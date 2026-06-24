// Stub for web — permission_handler is unavailable in the browser.

class PermissionStatus {
  static const granted = PermissionStatus._('granted');
  static const denied = PermissionStatus._('denied');
  final String _v;
  const PermissionStatus._(this._v);
  bool get isGranted => _v == 'granted';
  @override
  String toString() => _v;
}

class _CameraPermission {
  Future<PermissionStatus> request() async => PermissionStatus.granted;
  Future<PermissionStatus> get status async => PermissionStatus.granted;
}

class Permission {
  static final camera = _CameraPermission();
}
