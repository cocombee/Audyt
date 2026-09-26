/// Shared paragraph-to-font ratio for transaction item Descriptions only.
/// The PDF uses a 17.8pt paragraph advance at 9pt; editors retain their font.
const transactionDescriptionParagraphHeightFactor = 17.8 / 9.0;

/// Plain, portable description text. List markers remain part of saved text;
/// soft wrapping and hanging indents are layout, never inserted whitespace.
class DescriptionParagraph {
  const DescriptionParagraph(this.text, {this.marker});
  final String text;
  final String? marker;

  static DescriptionParagraph parse(String text) {
    final match = RegExp(r'^([-*+•‣◦▪●–—]|(?:\d+|[A-Za-z]+)\.)(?:[ \t]*)(.*)$')
        .firstMatch(text);
    if (match == null) return DescriptionParagraph(text);
    return DescriptionParagraph(match[2]!, marker: match[1]);
  }

  String get plainText => marker == null ? text : '$marker $text';
  String get nextMarker {
    final mark = marker!;
    if (!mark.endsWith('.')) return mark;
    final body = mark.substring(0, mark.length - 1);
    final number = int.tryParse(body);
    if (number != null) return '${number + 1}.';
    final upper = body == body.toUpperCase();
    final lower = body.toLowerCase();
    // Single c/d/l/m are ordinary alphabetic starters. i/v/x and compound
    // Roman markers establish a Roman sequence rather than alphabetic labels.
    if (RegExp(r'^[ivxlcdm]+$').hasMatch(lower) &&
        (lower.length > 1 || 'ivx'.contains(lower))) {
      const values = {
        'i': 1,
        'v': 5,
        'x': 10,
        'l': 50,
        'c': 100,
        'd': 500,
        'm': 1000,
      };
      var total = 0;
      for (var n = 0; n < lower.length; n++) {
        final value = values[lower[n]]!;
        total += n + 1 < lower.length && value < values[lower[n + 1]]!
            ? -value
            : value;
      }
      var next = total + 1;
      var result = '';
      for (final pair in const [
        (1000, 'm'),
        (900, 'cm'),
        (500, 'd'),
        (400, 'cd'),
        (100, 'c'),
        (90, 'xc'),
        (50, 'l'),
        (40, 'xl'),
        (10, 'x'),
        (9, 'ix'),
        (5, 'v'),
        (4, 'iv'),
        (1, 'i'),
      ]) {
        while (next >= pair.$1) {
          result += pair.$2;
          next -= pair.$1;
        }
      }
      return '${upper ? result.toUpperCase() : result}.';
    }
    var ordinal = 0;
    for (final rune in lower.runes) {
      ordinal = ordinal * 26 + rune - 96;
    }
    ordinal++;
    var result = '';
    while (ordinal > 0) {
      ordinal--;
      result = String.fromCharCode(97 + ordinal % 26) + result;
      ordinal ~/= 26;
    }
    return '${upper ? result.toUpperCase() : result}.';
  }
}

class DescriptionVisualLine {
  const DescriptionVisualLine(
    this.text, {
    this.marker,
    this.indent = 0,
    this.paragraphStart = false,
  });
  final String text;
  final String? marker;
  final double indent;
  final bool paragraphStart;
}

List<DescriptionVisualLine> layoutTransactionDescription(
  String value,
  double width,
  double Function(String) measure, {
  String markerReserve = '00 ',
}) {
  final paragraphs = value.split('\n').map(DescriptionParagraph.parse).toList();
  final result = <DescriptionVisualLine>[];
  for (var p = 0; p < paragraphs.length; p++) {
    final paragraph = paragraphs[p];
    var indent = 0.0;
    if (paragraph.marker != null) {
      var start = p, end = p;
      while (start > 0 && paragraphs[start - 1].marker != null) {
        start--;
      }
      while (end + 1 < paragraphs.length &&
          paragraphs[end + 1].marker != null) {
        end++;
      }
      for (var n = start; n <= end; n++) {
        final candidate =
            measure(paragraphs[n].marker!) + measure(markerReserve);
        if (candidate > indent) indent = candidate;
      }
    }
    if (width <= indent) {
      throw const FormatException(
        'Description width is too small for its list marker.',
      );
    }
    final lines = wrapDescriptionText(paragraph.text, width - indent, measure);
    for (var n = 0; n < lines.length; n++) {
      result.add(
        DescriptionVisualLine(
          lines[n],
          marker: n == 0 ? paragraph.marker : null,
          indent: indent,
          paragraphStart: p > 0 && n == 0,
        ),
      );
    }
  }
  return result;
}

List<String> wrapDescriptionText(
  String value,
  double width,
  double Function(String) measure,
) {
  final lines = <String>[];
  for (final paragraph in value.split('\n')) {
    var line = '';
    for (final word
        in paragraph.split(RegExp(r'\s+')).where((s) => s.isNotEmpty)) {
      final candidate = line.isEmpty ? word : '$line $word';
      if (measure(candidate) <= width) {
        line = candidate;
        continue;
      }
      if (line.isNotEmpty) lines.add(line);
      line = '';
      for (final rune in word.runes) {
        final character = String.fromCharCode(rune);
        if (line.isNotEmpty && measure('$line$character') > width) {
          lines.add(line);
          line = '';
        }
        line += character;
      }
    }
    lines.add(line);
  }
  return lines;
}
