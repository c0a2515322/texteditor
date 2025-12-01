import 'dart:convert';
import 'dart:js_interop';
import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;

Future<void> saveFile(String content, String? path, String fileName) async {
  // On Web, "path" is irrelevant for saving. We trigger a download.
  final bytes = utf8.encode(content);
  // Convert Uint8List to JSUint8Array, then to JSArray for Blob
  final jsData = bytes.toJS;
  final blob = web.Blob([jsData].toJS);
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..style.display = 'none'
    ..download = fileName;

  web.document.body!.appendChild(anchor);
  anchor.click();
  web.document.body!.removeChild(anchor);
  web.URL.revokeObjectURL(url);
}

Future<String> readFile(PlatformFile file) async {
  if (file.bytes != null) {
    return utf8.decode(file.bytes!);
  }
  throw Exception('File bytes are null');
}

Future<String> renameFile(String oldPath, String newName) async {
  throw UnsupportedError('Renaming files is not supported on Web');
}

String get pathSeparator => '/';

Future<void> saveFileMobile(String content, String fileName) async {
  throw UnsupportedError('Mobile save not supported on Web');
}
