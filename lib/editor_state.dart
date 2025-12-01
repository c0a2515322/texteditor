import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:undo/undo.dart';
import 'package:highlight/highlight.dart' show highlight, Result;
import 'custom_text_editing_controller.dart';

// Top-level function for compute
Result _parseHighlight(Map<String, String> args) {
  return highlight.parse(args['text']!, language: args['language']);
}

class EditorTabState {
  String? filePath;
  String content = '';
  late CustomTextEditingController controller;
  final ChangeStack changeStack = ChangeStack();
  final ScrollController textScrollController = ScrollController();
  final ScrollController lineNumbersScrollController = ScrollController();
  final FocusNode focusNode = FocusNode();

  bool isDirty = false;
  String language = 'plaintext';
  bool enableHighlight = true;

  Timer? _debounceTimer;

  // Cursor position
  int currentLine = 1;
  int currentColumn = 1;
  int characterCount = 0;

  EditorTabState({this.filePath, String initialContent = ''}) {
    content = initialContent;
    controller = CustomTextEditingController(text: initialContent);
    characterCount = initialContent.length;
    _detectLanguage();
    // Initial highlight without debounce
    updateHighlight(immediate: true);
  }

  void _detectLanguage() {
    if (filePath == null) {
      language = 'plaintext';
      return;
    }
    final ext = filePath!.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart':
        language = 'dart';
        break;
      case 'json':
        language = 'json';
        break;
      case 'yaml':
      case 'yml':
        language = 'yaml';
        break;
      case 'xml':
      case 'html':
        language = 'xml';
        break;
      case 'js':
        language = 'javascript';
        break;
      case 'css':
        language = 'css';
        break;
      case 'md':
        language = 'markdown';
        break;
      case 'py':
        language = 'python';
        break;
      case 'java':
        language = 'java';
        break;
      case 'cpp':
      case 'c':
      case 'h':
        language = 'cpp';
        break;
      default:
        language = 'plaintext';
        break;
    }
  }

  void updateHighlight({bool immediate = false}) {
    _debounceTimer?.cancel();

    if (!enableHighlight || language == 'plaintext') {
      if (controller.highlightResult != null) {
        controller.highlightResult = null;
      }
      return;
    }

    Future<void> performUpdate() async {
      try {
        final text = controller.text;
        Result? result;

        if (kIsWeb) {
          // On Web, run on main thread to avoid potential worker limits
          result = highlight.parse(text, language: language);
        } else {
          // On native platforms, use compute to avoid blocking UI
          result = await compute(_parseHighlight, {
            'text': text,
            'language': language,
          });
        }

        // Check if text has changed while we were parsing
        if (controller.text == text) {
          controller.highlightResult = result;
        }
      } catch (e) {
        // Fallback or ignore
      }
    }

    if (immediate) {
      performUpdate();
    } else {
      // Short debounce to balance responsiveness and performance
      _debounceTimer = Timer(const Duration(milliseconds: 75), performUpdate);
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
    controller.dispose();
    textScrollController.dispose();
    lineNumbersScrollController.dispose();
    focusNode.dispose();
    changeStack.clearHistory();
  }
}
