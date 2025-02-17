// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:markdown/src/inline_syntaxes/abstract_linkable_syntax.dart';

import '../../markdown.dart';
import '../charcode.dart';
import '../util.dart';

/// Matches style span like `#[blah]` and `#[blah](url)`.
class StyleSpanSyntax extends AbstractLinkableSyntax {
  static final _entirelyWhitespacePattern = RegExp(r'^\s*$');
  StyleSpanSyntax({
    super.pattern = r'#\[',
    super.startCharacter = $hash,
  });

  @override
  Node? close(
    InlineParser parser,
    covariant SimpleDelimiter opener,
    Delimiter? closer, {
    String? tag,
    required List<Node> Function() getChildren,
  }) {
    final text = parser.source.substring(opener.endPos, parser.pos);
    // The current character is the `]` that closed the link text. Examine the
    // next character, to determine what type of link we might have (a '('
    // means a possible inline link; otherwise a possible reference link).
    if (parser.pos + 1 >= parser.source.length) {
      // The `]` is at the end of the document, but this may still be a valid
      // shortcut reference link.
      return _tryCreateSimpleStyleSpan(parser, text, getChildren: getChildren);
    }

    // Peek at the next character; don't advance, so as to avoid later stepping
    // backward.
    final char = parser.charAt(parser.pos + 1);

    if (char == $lparen) {
      // Maybe an inline link, like `[text](destination)`.
      parser.advanceBy(1);
      final leftParenIndex = parser.pos;
      final inlineStyleSpan = _parseInlineStyleSpan(parser);
      if (inlineStyleSpan != null) {
        return _tryCreateComplexStyleSpan(
          parser,
          inlineStyleSpan,
          getChildren: getChildren,
        );
      }
      // At this point, we've matched `[...](`, but that `(` did not pan out to
      // be an inline link. We must now check if `[...]` is simply a shortcut
      // reference link.

      // Reset the parser position.
      parser.pos = leftParenIndex;
      parser.advanceBy(-1);
      return _tryCreateSimpleStyleSpan(parser, text, getChildren: getChildren);
    }
    if (char == $lbracket) {
      parser.advanceBy(1);
      // At this point, we've matched `[...][`. Maybe a *full* reference link,
      // like `[foo][bar]` or a *collapsed* reference link, like `[foo][]`.
      if (parser.pos + 1 < parser.source.length && parser.charAt(parser.pos + 1) == $rbracket) {
        // That opening `[` is not actually part of the link. Maybe a
        // *shortcut* reference link (followed by a `[`).
        parser.advanceBy(1);
        return _tryCreateSimpleStyleSpan(parser, text, getChildren: getChildren);
      }
      final label = _parseReferenceLinkLabel(parser);
      if (label != null) {
        return _tryCreateSimpleStyleSpan(parser, label, getChildren: getChildren);
      }
      return null;
    }

    // The style span text (inside `[...]`) was not followed with a opening `(` nor
    // an opening `[`. Perhaps just a simple shortcut reference link (`[...]`).
    return _tryCreateSimpleStyleSpan(parser, text, getChildren: getChildren);
  }

  /// Parse a reference link label at the current position.
  ///
  /// Specifically, [parser.pos] is expected to be pointing at the `[` which
  /// opens the link label.
  ///
  /// Returns the label if it could be parsed, or `null` if not.
  String? _parseReferenceLinkLabel(InlineParser parser) {
    // Walk past the opening `[`.
    parser.advanceBy(1);
    if (parser.isDone) return null;

    final buffer = StringBuffer();
    while (true) {
      final char = parser.charAt(parser.pos);
      if (char == $backslash) {
        parser.advanceBy(1);
        final next = parser.charAt(parser.pos);
        if (next != $backslash && next != $rbracket) {
          buffer.writeCharCode(char);
        }
        buffer.writeCharCode(next);
      } else if (char == $lbracket) {
        return null;
      } else if (char == $rbracket) {
        break;
      } else {
        buffer.writeCharCode(char);
      }
      parser.advanceBy(1);
      if (parser.isDone) return null;
      // TODO(srawlins): only check 999 characters, for performance reasons?
    }

    final label = buffer.toString();

    // A link label must contain at least one non-whitespace character.
    if (_entirelyWhitespacePattern.hasMatch(label)) return null;

    return label;
  }

  /// Resolve a possible simple style span.
  ///
  /// Uses [linkReferences], [linkResolver], and [createNode] to try to
  /// resolve [label] into a [Node]. If [label] is defined in
  /// [linkReferences] or can be resolved by [linkResolver], returns a [Node]
  /// that links to the resolved URL.
  ///
  /// Otherwise, returns `null`.
  ///
  /// [label] does not need to be normalized.
  Node? _resolveSimpleStyleSpan(
    String label,
    Map<String, LinkReference> linkReferences, {
    required List<Node> Function() getChildren,
  }) {
    final linkReference = linkReferences[normalizeLinkLabel(label)];
    if (linkReference != null) {
      return createNode(
        destination: linkReference.destination,
        title: linkReference.title,
        getChildren: getChildren,
      );
    }
    return createNode(
      destination: null,
      type: null,
      title: null,
      getChildren: getChildren,
    );
  }

  /// Create the node represented by a Markdown link.
  @override
  Node createNode({
    String? destination,
    String? type,
    String? title,
    required List<Node> Function() getChildren,
  }) {
    final children = getChildren();
    final element = Element('span', children);
    if (destination != null && destination.isNotEmpty) {
      element.attributes['href'] = escapeAttribute(destination);
    }
    if (title != null && title.isNotEmpty) {
      element.attributes['title'] = escapeAttribute(title);
    }
    if (type != null && type.isNotEmpty) {
      element.attributes['type'] = escapeAttribute(type);
    }
    return element;
  }

  /// Tries to create a reference link node.
  ///
  /// Returns the link if it was successfully created, `null` otherwise.
  Node? _tryCreateSimpleStyleSpan(
    InlineParser parser,
    String label, {
    required List<Node> Function() getChildren,
  }) {
    return _resolveSimpleStyleSpan(
      label,
      parser.document.linkReferences,
      getChildren: getChildren,
    );
  }

  // Tries to create an inline link node.
  //
  /// Returns the link if it was successfully created, `null` otherwise.
  Node _tryCreateComplexStyleSpan(
    InlineParser parser,
    StyleSpan styleSpan, {
    required List<Node> Function() getChildren,
  }) {
    return createNode(destination: styleSpan.destination, title: styleSpan.title, getChildren: getChildren);
  }

  /// Parse an inline [StyleSpan] at the current position.
  ///
  /// At this point, we have parsed a link's (or image's) opening `[`, and then
  /// a matching closing `]`, and [parser.pos] is pointing at an opening `(`.
  /// This method will then attempt to parse a link destination wrapped in `<>`,
  /// such as `(<http://url>)`, or a bare link destination, such as
  /// `(http://url)`, or a link destination with a title, such as
  /// `(http://url "title")`.
  ///
  /// Returns the [StyleSpan] if one was parsed, or `null` if not.
  StyleSpan? _parseInlineStyleSpan(InlineParser parser) {
    // Start walking to the character just after the opening `(`.
    parser.advanceBy(1);

    _moveThroughWhitespace(parser);
    if (parser.isDone) return null; // EOF. Not a link.

    if (parser.charAt(parser.pos) == $lt) {
      // Maybe a `<...>`-enclosed link destination.
      return _parseInlineBracketedStyleSpan(parser);
    } else {
      return _parseInlineBareDestinationStyleSpan(parser);
    }
  }

  /// Parse an inline link with a bracketed destination (a destination wrapped
  /// in `<...>`). The current position of the parser must be the first
  /// character of the destination.
  ///
  /// Returns the link if it was successfully created, `null` otherwise.
  StyleSpan? _parseInlineBracketedStyleSpan(InlineParser parser) {
    parser.advanceBy(1);

    final buffer = StringBuffer();
    while (true) {
      final char = parser.charAt(parser.pos);
      if (char == $backslash) {
        parser.advanceBy(1);
        final next = parser.charAt(parser.pos);
        // TODO: Follow the backslash spec better here.
        // http://spec.commonmark.org/0.29/#backslash-escapes
        if (next != $backslash && next != $gt) {
          buffer.writeCharCode(char);
        }
        buffer.writeCharCode(next);
      } else if (char == $lf || char == $cr || char == $ff) {
        // Not a link (no line breaks allowed within `<...>`).
        return null;
      } else if (char == $space) {
        buffer.write('%20');
      } else if (char == $gt) {
        break;
      } else {
        buffer.writeCharCode(char);
      }
      parser.advanceBy(1);
      if (parser.isDone) return null;
    }
    final destination = buffer.toString();

    parser.advanceBy(1);
    final char = parser.charAt(parser.pos);
    if (char == $space || char == $lf || char == $cr || char == $ff) {
      final title = _parseTitle(parser);
      if (title == null && (parser.isDone || parser.charAt(parser.pos) != $rparen)) {
        // This looked like an inline link, until we found this $space
        // followed by mystery characters; no longer a link.
        return null;
      }
      return StyleSpan(destination, title: title);
    } else if (char == $rparen) {
      return StyleSpan(destination);
    } else {
      // We parsed something like `[foo](<url>X`. Not a link.
      return null;
    }
  }

  /// Parse an inline link with a "bare" destination (a destination _not_
  /// wrapped in `<...>`). The current position of the parser must be the first
  /// character of the destination.
  ///
  /// Returns the link if it was successfully created, `null` otherwise.
  StyleSpan? _parseInlineBareDestinationStyleSpan(InlineParser parser) {
    // According to
    // [CommonMark](http://spec.commonmark.org/0.28/#link-destination):
    //
    // > A link destination consists of [...] a nonempty sequence of
    // > characters [...], and includes parentheses only if (a) they are
    // > backslash-escaped or (b) they are part of a balanced pair of
    // > unescaped parentheses.
    //
    // We need to count the open parens. We start with 1 for the paren that
    // opened the destination.
    var parenCount = 1;
    final buffer = StringBuffer();

    while (true) {
      final char = parser.charAt(parser.pos);
      switch (char) {
        case $backslash:
          parser.advanceBy(1);
          if (parser.isDone) return null; // EOF. Not a link.
          final next = parser.charAt(parser.pos);
          // Parentheses may be escaped.
          //
          // http://spec.commonmark.org/0.28/#example-467
          if (next != $backslash && next != $lparen && next != $rparen) {
            buffer.writeCharCode(char);
          }
          buffer.writeCharCode(next);
          break;

        case $space:
        case $lf:
        case $cr:
        case $ff:
          final destination = buffer.toString();
          final title = _parseTitle(parser);
          if (title == null && (parser.isDone || parser.charAt(parser.pos) != $rparen)) {
            // This looked like an inline link, until we found this $space
            // followed by mystery characters; no longer a link.
            return null;
          }
          // [_parseTitle] made sure the title was follwed by a closing `)`
          // (but it's up to the code here to examine the balance of
          // parentheses).
          parenCount--;
          if (parenCount == 0) {
            return StyleSpan(destination, title: title);
          }
          break;

        case $lparen:
          parenCount++;
          buffer.writeCharCode(char);
          break;

        case $rparen:
          parenCount--;
          if (parenCount == 0) {
            final destination = buffer.toString();
            return StyleSpan(destination);
          }
          buffer.writeCharCode(char);
          break;

        default:
          buffer.writeCharCode(char);
      }
      parser.advanceBy(1);
      if (parser.isDone) return null; // EOF. Not a link.
    }
  }

  // Walk the parser forward through any whitespace.
  void _moveThroughWhitespace(InlineParser parser) {
    while (!parser.isDone) {
      final char = parser.charAt(parser.pos);
      if (char != $space && char != $tab && char != $lf && char != $vt && char != $cr && char != $ff) {
        return;
      }
      parser.advanceBy(1);
    }
  }

  /// Parses a link title in [parser] at it's current position. The parser's
  /// current position should be a whitespace character that followed a link
  /// destination.
  ///
  /// Returns the title if it was successfully parsed, `null` otherwise.
  String? _parseTitle(InlineParser parser) {
    _moveThroughWhitespace(parser);
    if (parser.isDone) return null;

    // The whitespace should be followed by a title delimiter.
    final delimiter = parser.charAt(parser.pos);
    if (delimiter != $apostrophe && delimiter != $quote && delimiter != $lparen) {
      return null;
    }

    final closeDelimiter = delimiter == $lparen ? $rparen : delimiter;
    parser.advanceBy(1);

    // Now we look for an un-escaped closing delimiter.
    final buffer = StringBuffer();
    while (true) {
      final char = parser.charAt(parser.pos);
      if (char == $backslash) {
        parser.advanceBy(1);
        final next = parser.charAt(parser.pos);
        if (next != $backslash && next != closeDelimiter) {
          buffer.writeCharCode(char);
        }
        buffer.writeCharCode(next);
      } else if (char == closeDelimiter) {
        break;
      } else {
        buffer.writeCharCode(char);
      }
      parser.advanceBy(1);
      if (parser.isDone) return null;
    }
    final title = buffer.toString();

    // Advance past the closing delimiter.
    parser.advanceBy(1);
    if (parser.isDone) return null;
    _moveThroughWhitespace(parser);
    if (parser.isDone) return null;
    if (parser.charAt(parser.pos) != $rparen) return null;
    return title;
  }
}

class StyleSpan {
  final String destination;
  final String? title;
  final String? type;

  StyleSpan(this.destination, {this.title, this.type});
}
