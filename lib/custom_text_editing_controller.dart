import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show Result, Node;

class CustomTextEditingController extends TextEditingController {
  static final RegExp _whitespaceRegex = RegExp(r'[ \t]');
  bool showWhitespaces = false;
  Result? _highlightResult;
  TextSpan? _cachedTextSpan;
  TextStyle? _cachedStyle;
  String? _cachedText;
  bool? _cachedIsDark;

  CustomTextEditingController({super.text});

  Result? get highlightResult => _highlightResult;

  set highlightResult(Result? result) {
    _highlightResult = result;
    _cachedTextSpan = null; // Invalidate cache
    _cachedText = null;
    _cachedStyle = null;
    _cachedIsDark = null;
    notifyListeners();
  }

  @override
  set value(TextEditingValue newValue) {
    if (super.value != newValue) {
      _cachedTextSpan = null; // Invalidate cache on text change
      _cachedText = null;
      _cachedStyle = null;
      _cachedIsDark = null;
      _highlightResult = null; // Clear stale highlight result
      super.value = newValue;
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Return cached span if available and conditions match
    if (_cachedTextSpan != null &&
        _cachedText == value.text &&
        _cachedStyle == style &&
        _cachedIsDark == isDark) {
      return _cachedTextSpan!;
    }

    TextSpan span;
    // If no highlight result, fallback to simple whitespace visualization or default
    if (_highlightResult == null) {
      if (!showWhitespaces) {
        span = super.buildTextSpan(
          context: context,
          style: style,
          withComposing: withComposing,
        );
      } else {
        span = _buildWhitespaceSpan(value.text, style);
      }
    } else {
      // If highlight result exists, build spans from nodes
      span = _buildHighlightSpans(_highlightResult!.nodes!, style, isDark);
    }

    _cachedTextSpan = span;
    _cachedText = value.text;
    _cachedStyle = style;
    _cachedIsDark = isDark;
    return span;
  }

  TextSpan _buildWhitespaceSpan(String text, TextStyle? style) {
    final List<InlineSpan> children = [];
    text.splitMapJoin(
      _whitespaceRegex,
      onMatch: (Match match) {
        final String matchText = match[0]!;
        String replacement;
        if (matchText == ' ') {
          replacement = '·';
        } else {
          replacement = '→';
        }
        children.add(
          TextSpan(
            text: replacement,
            style: style?.copyWith(
              color: (style.color ?? Colors.grey).withValues(alpha: 0.3),
            ),
          ),
        );
        return '';
      },
      onNonMatch: (String nonMatch) {
        children.add(TextSpan(text: nonMatch, style: style));
        return '';
      },
    );
    return TextSpan(style: style, children: children);
  }

  TextSpan _buildHighlightSpans(
    List<Node> nodes,
    TextStyle? style,
    bool isDark,
  ) {
    List<TextSpan> spans = [];
    for (var node in nodes) {
      spans.add(_convertNodeToSpan(node, style, isDark));
    }
    return TextSpan(style: style, children: spans);
  }

  TextSpan _convertNodeToSpan(Node node, TextStyle? style, bool isDark) {
    TextStyle? nodeStyle = style;
    if (node.className != null) {
      nodeStyle = _getThemeStyle(node.className!, style, isDark);
    }

    if (node.value != null) {
      if (showWhitespaces) {
        return _buildWhitespaceSpan(node.value!, nodeStyle);
      }
      return TextSpan(text: node.value, style: nodeStyle);
    } else if (node.children != null) {
      return TextSpan(
        children: node.children!
            .map((n) => _convertNodeToSpan(n, nodeStyle, isDark))
            .toList(),
        style: nodeStyle,
      );
    }
    return const TextSpan();
  }

  TextStyle? _getThemeStyle(
    String className,
    TextStyle? baseStyle,
    bool isDark,
  ) {
    Color? color;
    FontWeight? fontWeight;
    FontStyle? fontStyle;

    if (isDark) {
      // Dark theme colors
      switch (className) {
        case 'keyword':
        case 'selector-tag':
        case 'section':
        case 'title':
        case 'name':
          color = Colors.purple[300];
          fontWeight = FontWeight.bold;
          break;
        case 'string':
        case 'attr':
          color = Colors.green[400];
          break;
        case 'number':
        case 'literal':
          color = Colors.orange[300];
          break;
        case 'comment':
          color = Colors.grey[500];
          fontStyle = FontStyle.italic;
          break;
        case 'built_in':
        case 'type':
          color = Colors.cyan[300];
          break;
        case 'function':
          color = Colors.amber[300];
          break;
        default:
          break;
      }
    } else {
      // Light theme colors
      switch (className) {
        case 'keyword':
        case 'selector-tag':
        case 'section':
        case 'title':
        case 'name':
          color = Colors.purple[700];
          fontWeight = FontWeight.bold;
          break;
        case 'string':
        case 'attr':
          color = Colors.green[800];
          break;
        case 'number':
        case 'literal':
          color = Colors.orange[900];
          break;
        case 'comment':
          color = Colors.grey[600];
          fontStyle = FontStyle.italic;
          break;
        case 'built_in':
        case 'type':
          color = Colors.blue[800];
          break;
        case 'function':
          color = Colors.brown[700];
          break;
        default:
          break;
      }
    }

    if (color != null || fontWeight != null || fontStyle != null) {
      return baseStyle?.copyWith(
        color: color,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
      );
    }
    return baseStyle;
  }
}
