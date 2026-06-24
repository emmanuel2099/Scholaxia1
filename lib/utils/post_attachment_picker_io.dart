import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'post_attachment_picker_stub.dart';

Future<PickedAttachment?> pickPostAttachment(String type) async {
  final result = await FilePicker.platform.pickFiles(
    type: type == 'photo' ? FileType.image : FileType.custom,
    allowedExtensions: type == 'photo' ? null : ['pdf', 'doc', 'docx'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;

  final file = result.files.first;
  final bytes = file.bytes;
  if (bytes == null) return null;

  return PickedAttachment(
    bytes: Uint8List.fromList(bytes),
    name: file.name,
  );
}
