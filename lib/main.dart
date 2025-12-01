import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:undo/undo.dart';
import 'file_utils.dart';
import 'editor_state.dart';

void main() {
  runApp(const TextEditorApp());
}

class TextEditorApp extends StatefulWidget {
  const TextEditorApp({super.key});

  static void setThemeMode(BuildContext context, ThemeMode mode) {
    final state = context.findAncestorStateOfType<_TextEditorAppState>();
    state?.setThemeMode(mode);
  }

  static ThemeMode getThemeMode(BuildContext context) {
    final state = context.findAncestorStateOfType<_TextEditorAppState>();
    return state?._themeMode ?? ThemeMode.system;
  }

  @override
  State<TextEditorApp> createState() => _TextEditorAppState();
}

class _TextEditorAppState extends State<TextEditorApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void setThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Text Editor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      themeMode: _themeMode,
      home: const TextEditorPage(),
    );
  }
}

class TextEditorPage extends StatefulWidget {
  const TextEditorPage({super.key});

  @override
  State<TextEditorPage> createState() => _TextEditorPageState();
}

class IndentIntent extends Intent {
  const IndentIntent();
}

class SaveIntent extends Intent {
  const SaveIntent();
}

class OpenIntent extends Intent {
  const OpenIntent();
}

class UndoIntent extends Intent {
  const UndoIntent();
}

class RedoIntent extends Intent {
  const RedoIntent();
}

class SearchIntent extends Intent {
  const SearchIntent();
}

class NewTabIntent extends Intent {
  const NewTabIntent();
}

class _TextEditorPageState extends State<TextEditorPage>
    with TickerProviderStateMixin {
  final List<EditorTabState> _tabs = [];
  late TabController _tabController;

  // Settings
  String _fontFamily = 'Monospace';
  double _fontSize = 16.0;
  bool _isWordWrap = true;
  double _contentWidth = 0.0;
  bool _showLineNumbers = true;
  bool _showWhitespaces = false;
  bool _enableHighlight = true;

  // Search
  bool _isSearchVisible = false;
  final TextEditingController _searchController = TextEditingController();

  // Debounce timer for content width calculation
  Timer? _contentWidthTimer;

  @override
  void initState() {
    super.initState();
    _addNewTab();
  }

  @override
  void dispose() {
    _contentWidthTimer?.cancel();
    for (var tab in _tabs) {
      tab.dispose();
    }
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _addNewTab({String? filePath, String content = ''}) {
    final newTab = EditorTabState(filePath: filePath, initialContent: content);
    newTab.enableHighlight = _enableHighlight;
    newTab.controller.showWhitespaces = _showWhitespaces;
    newTab.controller.addListener(() => _onTextChanged(newTab));
    newTab.textScrollController.addListener(() => _onTextScroll(newTab));
    newTab.lineNumbersScrollController.addListener(
      () => _onLineNumberScroll(newTab),
    );

    setState(() {
      _tabs.add(newTab);
      _tabController = TabController(length: _tabs.length, vsync: this);
      _tabController.animateTo(_tabs.length - 1);
    });
  }

  void _closeTab(int index) async {
    if (_tabs[index].isDirty) {
      final shouldDiscard = await _checkUnsavedChanges(index);
      if (!shouldDiscard) return;
    }

    setState(() {
      _tabs[index].dispose();
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        _addNewTab();
      } else {
        _tabController = TabController(
          length: _tabs.length,
          vsync: this,
          initialIndex: max(0, index - 1),
        );
      }
    });
  }

  // Scroll synchronization flags to prevent infinite loops
  bool _isSyncingScroll = false;

  void _onTextScroll(EditorTabState tab) {
    if (_isSyncingScroll) return;
    if (tab.lineNumbersScrollController.hasClients &&
        tab.textScrollController.hasClients) {
      if (tab.lineNumbersScrollController.offset !=
          tab.textScrollController.offset) {
        _isSyncingScroll = true;
        tab.lineNumbersScrollController.jumpTo(tab.textScrollController.offset);
        _isSyncingScroll = false;
      }
    }
  }

  void _onLineNumberScroll(EditorTabState tab) {
    if (_isSyncingScroll) return;
    if (tab.textScrollController.hasClients &&
        tab.lineNumbersScrollController.hasClients) {
      if (tab.textScrollController.offset !=
          tab.lineNumbersScrollController.offset) {
        _isSyncingScroll = true;
        tab.textScrollController.jumpTo(tab.lineNumbersScrollController.offset);
        _isSyncingScroll = false;
      }
    }
  }

  void _onTextChanged(EditorTabState tab) {
    // Update UI state (char count, cursor, etc.)
    _updateTabState(tab);

    // Skip Undo/Redo logic if composing (IME is active)
    if (tab.controller.value.composing.isValid) {
      return;
    }

    // Undo/Redo logic with debounce to batch rapid changes
    if (tab.controller.text != tab.content) {
      final newText = tab.controller.text;

      // Store the pending text for debounced undo
      tab.pendingUndoText ??= tab.content;

      tab.undoDebounceTimer?.cancel();
      tab.undoDebounceTimer = Timer(const Duration(milliseconds: 500), () {
        if (tab.pendingUndoText != null && tab.pendingUndoText != newText) {
          final oldText = tab.pendingUndoText!;
          tab.changeStack.add(
            Change<String>(
              oldText,
              () {
                if (tab.controller.text != newText) {
                  tab.controller.text = newText;
                }
                tab.content = newText;
                _updateTabState(tab);
              },
              (oldVal) {
                tab.controller.text = oldVal;
                tab.content = oldVal;
                _updateTabState(tab);
              },
            ),
          );
        }
        tab.pendingUndoText = null;
      });

      tab.content = newText;
    }
  }

  void _updateTabState(EditorTabState tab) {
    tab.characterCount = tab.controller.text.length;
    tab.lineCount = tab.controller.text.isEmpty
        ? 1
        : tab.controller.text.split('\n').length;
    tab.isDirty = true;
    _updateCursorPosition(tab);
    tab.updateHighlight();
    // Only call setState to update the status bar, not the entire widget
    if (mounted) {
      setState(() {});
    }
    if (!_isWordWrap) {
      _calculateContentWidth(tab);
    }
  }

  void _calculateContentWidth(EditorTabState tab) {
    _contentWidthTimer?.cancel();
    _contentWidthTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      final textSpan = TextSpan(
        text: tab.controller.text,
        style: TextStyle(fontFamily: _fontFamily, fontSize: _fontSize),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final newWidth = textPainter.width + 64.0;

      if (newWidth != _contentWidth) {
        setState(() {
          _contentWidth = newWidth;
        });
      }
      textPainter.dispose();
    });
  }

  void _updateCursorPosition(EditorTabState tab) {
    final selection = tab.controller.selection;
    if (selection.baseOffset == -1) return;

    final text = tab.controller.text;
    final beforeCursor = text.substring(0, selection.baseOffset);
    final lineCount = beforeCursor.split('\n').length;
    final lastNewLineIndex = beforeCursor.lastIndexOf('\n');
    final columnCount = selection.baseOffset - (lastNewLineIndex + 1) + 1;

    tab.currentLine = lineCount;
    tab.currentColumn = columnCount;
  }

  Future<bool> _checkUnsavedChanges(int index) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: Text(
          'Tab ${index + 1} has unsaved changes. Do you want to discard them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> _openFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'txt',
          'md',
          'json',
          'dart',
          'yaml',
          'xml',
          'html',
          'css',
          'js',
          'py',
          'java',
          'cpp',
        ],
        withData: kIsWeb,
      );

      if (result != null) {
        PlatformFile file = result.files.single;
        String content = await readFile(file);

        // Open in new tab
        _addNewTab(filePath: kIsWeb ? file.name : file.path, content: content);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error opening file: $e')));
      }
    }
  }

  Future<void> _saveFile() async {
    final index = _tabController.index;
    final tab = _tabs[index];

    try {
      String? path = tab.filePath;
      String fileName = 'untitled.txt';

      if (kIsWeb) {
        fileName = tab.filePath ?? 'untitled.txt';
        await saveFile(tab.controller.text, null, fileName);
      } else if (Platform.isAndroid || Platform.isIOS) {
        final TextEditingController nameController = TextEditingController(
          text: tab.filePath?.split(pathSeparator).last ?? 'untitled.txt',
        );

        final String? newName = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Save File'),
            content: TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Filename'),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(nameController.text),
                child: const Text('Save'),
              ),
            ],
          ),
        );

        if (newName == null || newName.isEmpty) return;

        await saveFileMobile(tab.controller.text, newName);
      } else {
        if (path == null) {
          String? outputFile = await FilePicker.platform.saveFile(
            dialogTitle: 'Save File',
            fileName: 'untitled.txt',
          );
          if (outputFile == null) return;
          path = outputFile;
          tab.filePath = path;
        }
        await saveFile(tab.controller.text, path, fileName);
      }

      setState(() {
        tab.isDirty = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File saved successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving file: $e')));
      }
    }
  }

  Future<void> _renameFile(EditorTabState tab) async {
    final TextEditingController nameController = TextEditingController(
      text: kIsWeb
          ? (tab.filePath ?? 'untitled.txt')
          : (tab.filePath?.split(pathSeparator).last ?? 'untitled.txt'),
    );

    final String? newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename File'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'New Filename'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(nameController.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty) return;

    if (kIsWeb) {
      setState(() {
        tab.filePath = newName;
      });
    } else {
      if (tab.filePath == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please save the file first.')),
          );
        }
        return;
      }
      try {
        String newPath = await renameFile(tab.filePath!, newName);
        setState(() {
          tab.filePath = newPath;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error renaming file: $e')));
        }
      }
    }
  }

  void _showSettings() {
    final index = _tabController.index;
    final tab = _tabs[index];
    ThemeMode currentTheme = TextEditorApp.getThemeMode(context);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Editor Settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Theme Mode
                    Row(
                      children: [
                        const Text('Theme: '),
                        const SizedBox(width: 8),
                        DropdownButton<ThemeMode>(
                          value: currentTheme,
                          items: const [
                            DropdownMenuItem(
                              value: ThemeMode.system,
                              child: Text('System'),
                            ),
                            DropdownMenuItem(
                              value: ThemeMode.light,
                              child: Text('Light'),
                            ),
                            DropdownMenuItem(
                              value: ThemeMode.dark,
                              child: Text('Dark'),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setStateDialog(() => currentTheme = val);
                              TextEditorApp.setThemeMode(this.context, val);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Font Family: '),
                        DropdownButton<String>(
                          value: _fontFamily,
                          items: ['Monospace', 'Roboto', 'Serif', 'Sans-serif']
                              .map(
                                (f) =>
                                    DropdownMenuItem(value: f, child: Text(f)),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setStateDialog(() => _fontFamily = val);
                              setState(() => _fontFamily = val);
                              if (!_isWordWrap) _calculateContentWidth(tab);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Font Size: '),
                        Expanded(
                          child: Slider(
                            value: _fontSize,
                            min: 10,
                            max: 32,
                            divisions: 22,
                            label: _fontSize.round().toString(),
                            onChanged: (val) {
                              setStateDialog(() => _fontSize = val);
                              setState(() => _fontSize = val);
                              if (!_isWordWrap) _calculateContentWidth(tab);
                            },
                          ),
                        ),
                        Text('${_fontSize.round()}'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Word Wrap'),
                      value: _isWordWrap,
                      onChanged: (val) {
                        setStateDialog(() => _isWordWrap = val);
                        setState(() => _isWordWrap = val);
                        if (!val) {
                          _calculateContentWidth(tab);
                        }
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Show Line Numbers'),
                      value: _showLineNumbers,
                      onChanged: (val) {
                        setStateDialog(() => _showLineNumbers = val);
                        setState(() => _showLineNumbers = val);
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Show Whitespaces'),
                      value: _showWhitespaces,
                      onChanged: (val) {
                        setStateDialog(() => _showWhitespaces = val);
                        setState(() {
                          _showWhitespaces = val;
                          for (var t in _tabs) {
                            t.controller.showWhitespaces = val;
                            // Force redraw
                            final text = t.controller.text;
                            t.controller.text = text;
                          }
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Enable Syntax Highlighting'),
                      value: _enableHighlight,
                      onChanged: (val) {
                        setStateDialog(() => _enableHighlight = val);
                        setState(() {
                          _enableHighlight = val;
                          for (var t in _tabs) {
                            t.enableHighlight = val;
                            t.updateHighlight(immediate: true);
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleIndent(EditorTabState tab) {
    final selection = tab.controller.selection;
    if (!selection.isValid) return;

    const indent = '  ';
    final newText = tab.controller.text.replaceRange(
      selection.start,
      selection.end,
      indent,
    );

    tab.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + indent.length,
      ),
    );
    // _onTextChanged will be called by listener
  }

  void _undo() {
    final index = _tabController.index;
    final tab = _tabs[index];
    if (tab.changeStack.canUndo) {
      tab.changeStack.undo();
    }
  }

  void _redo() {
    final index = _tabController.index;
    final tab = _tabs[index];
    if (tab.changeStack.canRedo) {
      tab.changeStack.redo();
    }
  }

  void _copyAll() {
    final index = _tabController.index;
    final tab = _tabs[index];
    Clipboard.setData(ClipboardData(text: tab.controller.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied all text to clipboard')),
    );
  }

  void _performSearch() {
    final query = _searchController.text;
    if (query.isEmpty) return;

    final index = _tabController.index;
    final tab = _tabs[index];
    final text = tab.controller.text;

    final matchIndex = text.indexOf(query, tab.controller.selection.end);
    if (matchIndex != -1) {
      tab.controller.selection = TextSelection(
        baseOffset: matchIndex,
        extentOffset: matchIndex + query.length,
      );
      tab.focusNode.requestFocus();
    } else {
      // Wrap around
      final wrapIndex = text.indexOf(query);
      if (wrapIndex != -1) {
        tab.controller.selection = TextSelection(
          baseOffset: wrapIndex,
          extentOffset: wrapIndex + query.length,
        );
        tab.focusNode.requestFocus();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Text not found')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS):
            const SaveIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyO):
            const OpenIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyZ):
            const UndoIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyY):
            const RedoIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
            const SearchIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN):
            const NewTabIntent(),
      },
      child: Actions(
        actions: {
          SaveIntent: CallbackAction<SaveIntent>(
            onInvoke: (intent) => _saveFile(),
          ),
          OpenIntent: CallbackAction<OpenIntent>(
            onInvoke: (intent) => _openFile(),
          ),
          UndoIntent: CallbackAction<UndoIntent>(onInvoke: (intent) => _undo()),
          RedoIntent: CallbackAction<RedoIntent>(onInvoke: (intent) => _redo()),
          SearchIntent: CallbackAction<SearchIntent>(
            onInvoke: (intent) {
              setState(() {
                _isSearchVisible = !_isSearchVisible;
              });
              return null;
            },
          ),
          NewTabIntent: CallbackAction<NewTabIntent>(
            onInvoke: (intent) => _addNewTab(),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              title: _tabs.isEmpty
                  ? const Text('Text Editor')
                  : TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      onTap: (index) {
                        setState(() {}); // Update UI for active tab
                      },
                      tabs: _tabs.map((tab) {
                        String title = tab.filePath == null
                            ? 'Untitled'
                            : (kIsWeb
                                  ? tab.filePath!
                                  : tab.filePath!.split(pathSeparator).last);
                        if (tab.isDirty) title += '*';
                        return Tab(
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => _renameFile(tab),
                                child: Text(title),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => _closeTab(_tabs.indexOf(tab)),
                                child: const Icon(Icons.close, size: 16),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
              actions: [
                IconButton(
                  icon: const Icon(Icons.note_add_outlined),
                  tooltip: 'New Tab',
                  onPressed: () => _addNewTab(),
                ),
                IconButton(
                  icon: const Icon(Icons.folder_open_outlined),
                  tooltip: 'Open File',
                  onPressed: _openFile,
                ),
                IconButton(
                  icon: const Icon(Icons.save_outlined),
                  tooltip: 'Save File',
                  onPressed: _saveFile,
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                  onPressed: _showSettings,
                ),
              ],
            ),
            body: Column(
              children: [
                // Toolbar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.undo),
                        tooltip: 'Undo',
                        onPressed: _undo,
                      ),
                      IconButton(
                        icon: const Icon(Icons.redo),
                        tooltip: 'Redo',
                        onPressed: _redo,
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_all),
                        tooltip: 'Copy All',
                        onPressed: _copyAll,
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.search),
                        tooltip: 'Search',
                        onPressed: () {
                          setState(() {
                            _isSearchVisible = !_isSearchVisible;
                          });
                        },
                      ),
                      if (_isSearchVisible) ...[
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 200,
                          height: 40,
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search...',
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.arrow_forward),
                                onPressed: _performSearch,
                              ),
                            ),
                            onSubmitted: (_) => _performSearch(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: _tabs.isEmpty
                      ? const Center(child: Text('No tabs open'))
                      : TabBarView(
                          controller: _tabController,
                          physics:
                              const NeverScrollableScrollPhysics(), // Disable swipe
                          children: _tabs.map((tab) {
                            final lineCount = tab.lineCount;
                            final lineHeight = _fontSize * 1.5;
                            final isDark =
                                Theme.of(context).brightness == Brightness.dark;
                            final lineNumberStyle = TextStyle(
                              fontFamily: _fontFamily,
                              fontSize: _fontSize,
                              color: isDark ? Colors.grey[600] : Colors.grey,
                              height: 1.5,
                            );
                            final editorStyle = TextStyle(
                              fontFamily: _fontFamily,
                              fontSize: _fontSize,
                              height: 1.5,
                            );

                            return Column(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 0.0,
                                      vertical: 8.0,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (_showLineNumbers)
                                          Container(
                                            width: 50,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.surfaceContainerLow,
                                            child: ListView.builder(
                                              controller: tab
                                                  .lineNumbersScrollController,
                                              itemExtent: lineHeight,
                                              itemCount: lineCount,
                                              itemBuilder: (context, index) {
                                                return Container(
                                                  height: lineHeight,
                                                  alignment:
                                                      Alignment.centerRight,
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 8.0,
                                                      ),
                                                  child: Text(
                                                    '${index + 1}',
                                                    style: lineNumberStyle,
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              left: 8.0,
                                              right: 16.0,
                                            ),
                                            child: Shortcuts(
                                              shortcuts: {
                                                LogicalKeySet(
                                                  LogicalKeyboardKey.tab,
                                                ): const IndentIntent(),
                                              },
                                              child: Actions(
                                                actions: {
                                                  IndentIntent:
                                                      CallbackAction<
                                                        IndentIntent
                                                      >(
                                                        onInvoke: (intent) =>
                                                            _handleIndent(tab),
                                                      ),
                                                },
                                                child: _isWordWrap
                                                    ? Scrollbar(
                                                        controller: tab
                                                            .textScrollController,
                                                        thumbVisibility: true,
                                                        child: TextField(
                                                          controller:
                                                              tab.controller,
                                                          focusNode:
                                                              tab.focusNode,
                                                          scrollController: tab
                                                              .textScrollController,
                                                          maxLines: null,
                                                          expands: true,
                                                          keyboardType:
                                                              TextInputType
                                                                  .multiline,
                                                          scrollPhysics:
                                                              const AlwaysScrollableScrollPhysics(),
                                                          onTap: () =>
                                                              _updateCursorPosition(
                                                                tab,
                                                              ),
                                                          style: editorStyle,
                                                          decoration:
                                                              const InputDecoration(
                                                                border:
                                                                    InputBorder
                                                                        .none,
                                                                hintText:
                                                                    'Start typing...',
                                                              ),
                                                        ),
                                                      )
                                                    : LayoutBuilder(
                                                        builder: (context, constraints) {
                                                          return Scrollbar(
                                                            controller: tab
                                                                .textScrollController,
                                                            thumbVisibility:
                                                                true,
                                                            child: SingleChildScrollView(
                                                              scrollDirection:
                                                                  Axis.horizontal,
                                                              child: ConstrainedBox(
                                                                constraints: BoxConstraints(
                                                                  minWidth:
                                                                      constraints
                                                                          .maxWidth,
                                                                  maxWidth: max(
                                                                    constraints
                                                                        .maxWidth,
                                                                    _contentWidth,
                                                                  ),
                                                                  minHeight:
                                                                      constraints
                                                                          .maxHeight,
                                                                  maxHeight:
                                                                      constraints
                                                                          .maxHeight,
                                                                ),
                                                                child: TextField(
                                                                  controller: tab
                                                                      .controller,
                                                                  focusNode: tab
                                                                      .focusNode,
                                                                  scrollController:
                                                                      tab.textScrollController,
                                                                  maxLines:
                                                                      null,
                                                                  expands: true,
                                                                  keyboardType:
                                                                      TextInputType
                                                                          .multiline,
                                                                  scrollPhysics:
                                                                      const AlwaysScrollableScrollPhysics(),
                                                                  onTap: () =>
                                                                      _updateCursorPosition(
                                                                        tab,
                                                                      ),
                                                                  style:
                                                                      editorStyle,
                                                                  decoration: const InputDecoration(
                                                                    border:
                                                                        InputBorder
                                                                            .none,
                                                                    hintText:
                                                                        'Start typing...',
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                      ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0,
                                    vertical: 8.0,
                                  ),
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainer,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Ln ${tab.currentLine}, Col ${tab.currentColumn}',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        '${tab.language}  |  UTF-8  |  ${tab.characterCount} chars',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
