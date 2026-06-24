import 'dart:html' as html;
import 'dart:typed_data';

import 'post_attachment_picker_stub.dart';

Future<PickedAttachment?> pickPostAttachment(String type) async {
  final input = html.FileUploadInputElement();
  if (type == 'photo') {
    input.accept = 'image/jpeg,image/png,image/webp';
  } else {
    input.accept = '.pdf,.doc,.docx,application/pdf';
  }
  input.click();

  await input.onChange.first;
  if (input.files == null || input.files!.isEmpty) return null;

  final file = input.files!.first;
  final reader = html.FileReader();
  reader.readAsArrayBuffer(file);
  await reader.onLoad.first;

  final bytes = Uint8List.fromList(reader.result as List<int>);
  return PickedAttachment(bytes: bytes, name: file.name);
}
