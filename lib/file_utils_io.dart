import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';

Future<void> saveFile(String content, String? path, String fileName) async {
  if (path == null) {
    throw Exception('Path cannot be null for IO save');
  }
  final file = File(path);
  await file.writeAsString(content);
}

Future<void> saveFileMobile(String content, String fileName) async {
  final directory = await getTemporaryDirectory();
  final path = '${directory.path}${Platform.pathSeparator}$fileName';
  final file = File(path);
  await file.writeAsString(content);

  final params = SaveFileDialogParams(sourceFilePath: path);
  await FlutterFileDialog.saveFile(params: params);
}

Future<String> readFile(PlatformFile file) async {
  if (file.path != null) {
    return await File(file.path!).readAsString();
  }
  throw Exception('File path is null');
}

Future<String> renameFile(String oldPath, String newName) async {
  final file = File(oldPath);
  if (!await file.exists()) {
    throw Exception('File not found');
  }
  // Simple directory extraction, assuming standard path separators
  final lastSeparator = oldPath.lastIndexOf(Platform.pathSeparator);
  final dirPath = lastSeparator == -1
      ? '.'
      : oldPath.substring(0, lastSeparator);
  final newPath = '$dirPath${Platform.pathSeparator}$newName';

  await file.rename(newPath);
  return newPath;
}

String get pathSeparator => Platform.pathSeparator;
