import 'dart:typed_data';

class PickedAttachment {
  final Uint8List bytes;
  final String name;

  const PickedAttachment({required this.bytes, required this.name});
}

Future<PickedAttachment?> pickPostAttachment(String type) async => null;
