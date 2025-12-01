import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show Result, Node;

class CustomTextEditingController extends TextEditingController {
  static final RegExp _whitespaceRegex = RegExp(r'[ \t]');
  bool showWhitespaces = false;
  Result? _highlightResult;
  TextSpan? _cachedTextSpan;

  CustomTextEditingController({super.text});

  Result? get highlightResult => _highlightResult;

  set highlightResult(Result? result) {
    _highlightResult = result;
    _cachedTextSpan = null; // Invalidate cache
    notifyListeners();
  }

  @override
  set value(TextEditingValue newValue) {
    if (super.value != newValue) {
      _cachedTextSpan = null; // Invalidate cache on text change
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
    // Return cached span if available and style matches (simplified check)
    // Note: Strictly speaking we should check if style changed, but for now we assume style is relatively stable
    if (_cachedTextSpan != null) {
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
      span = _buildHighlightSpans(_highlightResult!.nodes!, style);
    }

    _cachedTextSpan = span;
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

  TextSpan _buildHighlightSpans(List<Node> nodes, TextStyle? style) {
    List<TextSpan> spans = [];
    for (var node in nodes) {
      spans.add(_convertNodeToSpan(node, style));
    }
    return TextSpan(style: style, children: spans);
  }

  TextSpan _convertNodeToSpan(Node node, TextStyle? style) {
    TextStyle? nodeStyle = style;
    if (node.className != null) {
      nodeStyle = _getThemeStyle(node.className!, style);
    }

    if (node.value != null) {
      if (showWhitespaces) {
        return _buildWhitespaceSpan(node.value!, nodeStyle);
      }
      return TextSpan(text: node.value, style: nodeStyle);
    } else if (node.children != null) {
      return TextSpan(
        children: node.children!
            .map((n) => _convertNodeToSpan(n, nodeStyle))
            .toList(),
        style: nodeStyle,
      );
    }
    return const TextSpan();
  }

  TextStyle? _getThemeStyle(String className, TextStyle? baseStyle) {
    // Simple theme mapping
    // Ideally this should be configurable or load a standard theme
    Color? color;
    FontWeight? fontWeight;
    FontStyle? fontStyle;

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
        // Keep base style
        break;
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
