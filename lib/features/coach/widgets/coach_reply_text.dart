import 'package:flutter/material.dart';
import 'package:tracend/app/theme/tracend_tokens.dart';

/// The Markdown subset a Coach reply may use: bold, italic, inline code,
/// bullet and numbered lists, and headings shown as bold lines. Links show
/// their label only. Anything else, including an unmatched marker, stays as
/// typed, so a reply is never lost to formatting.
enum CoachReplyBlockKind { paragraph, heading, bullet, numbered }

@immutable
class CoachReplySpan {
  const CoachReplySpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool code;

  @override
  bool operator ==(Object other) =>
      other is CoachReplySpan &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic &&
      other.code == code;

  @override
  int get hashCode => Object.hash(text, bold, italic, code);

  @override
  String toString() =>
      'CoachReplySpan($text${bold ? ', bold' : ''}'
      '${italic ? ', italic' : ''}${code ? ', code' : ''})';
}

@immutable
class CoachReplyBlock {
  const CoachReplyBlock(
    this.kind,
    this.spans, {
    this.marker = '',
    this.depth = 0,
  });

  final CoachReplyBlockKind kind;
  final List<CoachReplySpan> spans;

  /// `•` for a bullet item, `3.` for a numbered one, empty otherwise.
  final String marker;

  /// Nesting of a list item: 0, or 1 when indented.
  final int depth;
}

final _bullet = RegExp(r'^(\s*)[-*+•]\s+(.*)$');
final _numbered = RegExp(r'^(\s*)(\d{1,3})[.)]\s+(.*)$');
final _heading = RegExp(r'^\s*#{1,6}\s+(.*?)\s*#*\s*$');
final _rule = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');

final _inline = RegExp(
  // **bold** or __bold__
  r'(\*\*|__)(?=\S)(.+?)(?<=\S)\1'
  // *italic*, not a list marker, a multiplication, or part of **
  r'|(?<![\w*])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![\w*])'
  // _italic_, never inside snake_case
  r'|(?<![\w_])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\w_])'
  // `code`
  r'|`([^`\n]+)`'
  // [label](target) shows the label only
  r'|\[([^\]\n]+)\]\([^)\s]+\)',
);

/// Splits a reply into display blocks.
List<CoachReplyBlock> parseCoachReply(String text) {
  final blocks = <CoachReplyBlock>[];
  final paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(
      CoachReplyBlock(
        CoachReplyBlockKind.paragraph,
        parseCoachInline(paragraph.join('\n')),
      ),
    );
    paragraph.clear();
  }

  for (final line in text.replaceAll('\r\n', '\n').split('\n')) {
    if (line.trim().isEmpty || _rule.hasMatch(line)) {
      flushParagraph();
      continue;
    }
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      flushParagraph();
      blocks.add(
        CoachReplyBlock(
          CoachReplyBlockKind.heading,
          parseCoachInline(heading.group(1)!, bold: true),
        ),
      );
      continue;
    }
    final bullet = _bullet.firstMatch(line);
    if (bullet != null) {
      flushParagraph();
      blocks.add(
        CoachReplyBlock(
          CoachReplyBlockKind.bullet,
          parseCoachInline(bullet.group(2)!),
          marker: '•',
          depth: _depth(bullet.group(1)!),
        ),
      );
      continue;
    }
    final numbered = _numbered.firstMatch(line);
    if (numbered != null) {
      flushParagraph();
      blocks.add(
        CoachReplyBlock(
          CoachReplyBlockKind.numbered,
          parseCoachInline(numbered.group(3)!),
          marker: '${numbered.group(2)}.',
          depth: _depth(numbered.group(1)!),
        ),
      );
      continue;
    }
    paragraph.add(line.trimRight());
  }
  flushParagraph();
  return blocks;
}

int _depth(String indent) =>
    indent.replaceAll('\t', '    ').length >= 2 ? 1 : 0;

/// Splits one block's text into styled spans.
List<CoachReplySpan> parseCoachInline(
  String text, {
  bool bold = false,
  bool italic = false,
}) {
  final spans = <CoachReplySpan>[];
  var start = 0;
  for (final match in _inline.allMatches(text)) {
    if (match.start > start) {
      spans.add(
        CoachReplySpan(
          text.substring(start, match.start),
          bold: bold,
          italic: italic,
        ),
      );
    }
    if (match.group(2) != null) {
      spans.addAll(
        parseCoachInline(match.group(2)!, bold: true, italic: italic),
      );
    } else if (match.group(3) != null || match.group(4) != null) {
      spans.addAll(
        parseCoachInline(
          match.group(3) ?? match.group(4)!,
          bold: bold,
          italic: true,
        ),
      );
    } else if (match.group(5) != null) {
      spans.add(
        CoachReplySpan(match.group(5)!, bold: bold, italic: italic, code: true),
      );
    } else {
      spans.addAll(
        parseCoachInline(match.group(6)!, bold: bold, italic: italic),
      );
    }
    start = match.end;
  }
  if (start < text.length) {
    spans.add(
      CoachReplySpan(text.substring(start), bold: bold, italic: italic),
    );
  }
  return spans;
}

/// A Coach reply rendered from [parseCoachReply]. The whole reply can be
/// selected and copied as displayed, without the Markdown markers.
class CoachReplyText extends StatelessWidget {
  const CoachReplyText(this.text, {required this.style, super.key});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final blocks = parseCoachReply(text);
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, block) in blocks.indexed) ...[
            if (index > 0)
              SizedBox(
                height: _isListItem(block) && _isListItem(blocks[index - 1])
                    ? TracendSpacing.xxs
                    : TracendSpacing.xs,
              ),
            _isListItem(block)
                ? Padding(
                    padding: EdgeInsets.only(
                      left: block.depth * TracendSpacing.md,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: block.kind == CoachReplyBlockKind.numbered
                              ? 26
                              : 16,
                          child: Text(block.marker, style: style),
                        ),
                        Expanded(child: Text.rich(_spans(block), style: style)),
                      ],
                    ),
                  )
                : Text.rich(_spans(block), style: style),
          ],
        ],
      ),
    );
  }

  bool _isListItem(CoachReplyBlock block) =>
      block.kind == CoachReplyBlockKind.bullet ||
      block.kind == CoachReplyBlockKind.numbered;

  TextSpan _spans(CoachReplyBlock block) => TextSpan(
    children: [
      for (final span in block.spans)
        TextSpan(
          text: span.text,
          style: TextStyle(
            fontWeight: span.bold ? FontWeight.w600 : null,
            fontStyle: span.italic ? FontStyle.italic : null,
            fontFamily: span.code ? TracendFonts.monoFamily : null,
          ),
        ),
    ],
  );
}
