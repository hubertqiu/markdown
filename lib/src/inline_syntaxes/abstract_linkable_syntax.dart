// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../ast.dart';
import '../inline_parser.dart';
import '../util.dart';
import 'delimiter_syntax.dart';

/// Matches links like `[blah][label]` and `[blah](url)`.
class AbstractLinkableSyntax extends DelimiterSyntax {
  AbstractLinkableSyntax({
    required String pattern,
    required int startCharacter,
  }) : super(pattern, startCharacter: startCharacter);

  @override
  Node? close(
    InlineParser parser,
    covariant SimpleDelimiter opener,
    Delimiter? closer, {
    String? tag,
    required List<Node> Function() getChildren,
  }) {
    return null;
  }

  /// Create the node represented by a Markdown link.
  Node createNode({
    required String destination,
    String? type,
    String? title,
    required List<Node> Function() getChildren,
  }) {
    final children = getChildren();
    final element = Element('linkable', children);
    element.attributes['href'] = escapeAttribute(destination);
    if (type != null && type.isNotEmpty) {
      element.attributes['type'] = escapeAttribute(type);
    }
    if (title != null && title.isNotEmpty) {
      element.attributes['title'] = escapeAttribute(title);
    }
    return element;
  }
}
