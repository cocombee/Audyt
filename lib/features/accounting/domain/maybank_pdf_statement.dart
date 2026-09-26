import 'dart:typed_data';

import '../../../../core/money/money.dart';
import 'bank_statement_import.dart';

/// Parses the positioned text on Maybank's savings-account statement PDF.
/// The original PDF stays intact; this projection is checked against every
/// printed running balance before it can be imported.
final class MaybankPdfStatement {
  static BankStatementImport parse({
    required String filename,
    required String currency,
    required Uint8List bytes,
    required List<Object?> pages,
    required String expectedAccountNumber,
    required String expectedHolderName,
  }) {
    if (expectedAccountNumber.trim().isEmpty ||
        expectedHolderName.trim().isEmpty) {
      throw const FormatException(
        'Set the bank account number and statement holder name in Edit Account before importing this PDF.',
      );
    }
    final rows = <BankStatementRow>[];
    int? runningMinor;
    var foundOpening = false;
    DateTime? statementDate;
    String? statementHolder;
    String? statementAccount;
    int? openingMinor;
    for (var pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final glyphs = <_Glyph>[];
      for (final item in pages[pageIndex] as List) {
        final fields = item as List;
        glyphs.add(
          _Glyph(
            (fields[0] as num).toDouble() / 10,
            (fields[1] as num).toDouble() / 10,
            (fields[2] as num).toDouble() / 10,
            fields[3] as String,
          ),
        );
      }
      glyphs.sort((a, b) {
        final byY = b.y.compareTo(a.y);
        return byY != 0 ? byY : a.x.compareTo(b.x);
      });
      final lines = <_Line>[];
      for (final glyph in glyphs) {
        final line = lines.isNotEmpty && (lines.last.y - glyph.y).abs() < 4
            ? lines.last
            : null;
        if (line == null) {
          lines.add(_Line(glyph.y, [glyph]));
        } else {
          line.glyphs.add(glyph);
        }
      }
      var inTable = false;
      final leftHeader = StringBuffer();
      final rightHeader = StringBuffer();
      _Pending? pending;
      void finish() {
        final item = pending;
        if (item == null) return;
        if (item.narrative.isEmpty) {
          throw FormatException(
            'Page ${pageIndex + 1} row ${item.date}: transaction description is unreadable.',
          );
        }
        final description = _description(item.narrative);
        if (description.isEmpty) {
          throw FormatException(
            'Page ${pageIndex + 1} row ${item.date}: transaction description is unreadable.',
          );
        }
        rows.add(
          BankStatementRow(
            sourceRow: rows.length + 1,
            sourcePage: pageIndex + 1,
            date: _date(item.date),
            description: description,
            rawNarrative: item.narrative.join('\n'),
            transactionType: _transactionType(item.narrative.first),
            amount: Money.fromMinor(item.amountMinor, currency),
            reference: _reference(item.narrative),
          ),
        );
        pending = null;
      }

      for (final line in lines) {
        final dateText = line.text(30, 85).replaceAll(' ', '');
        final narrative = line.text(85, 325);
        final amountText = line.text(325, 415).replaceAll(' ', '');
        final balanceText = line.text(415, 510).replaceAll(' ', '');
        if (line.text(0, 510).toUpperCase().contains('ENTRY DATE') &&
            line
                .text(0, 510)
                .toUpperCase()
                .contains('TRANSACTION DESCRIPTION')) {
          if (pageIndex == 0) {
            final left = leftHeader.toString();
            final right = rightHeader.toString();
            final expectedNumber = expectedAccountNumber.replaceAll(
              RegExp(r'\D'),
              '',
            );
            final numbers = RegExp(r'\b\d{6}-\d{6}\b').allMatches(right);
            final matchingNumber = numbers
                .where(
                  (match) =>
                      match.group(0)!.replaceAll('-', '') == expectedNumber,
                )
                .firstOrNull;
            if (matchingNumber == null) {
              throw const FormatException(
                'The PDF account number does not match the selected bank account.',
              );
            }
            statementAccount = matchingNumber.group(0)!;
            String normalized(String value) =>
                value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
            if (!normalized(left).contains(normalized(expectedHolderName))) {
              throw const FormatException(
                'The PDF account holder does not match the selected bank account.',
              );
            }
            statementHolder =
                left
                    .split('\n')
                    .where(
                      (line) =>
                          normalized(line)
                              .contains(normalized(expectedHolderName)),
                    )
                    .firstOrNull
                    ?.trim() ??
                expectedHolderName.trim();
            final headerDates = RegExp(r'\b\d{2}/\d{2}/\d{2}\b')
                .allMatches(right);
            if (headerDates.isEmpty) {
              throw const FormatException(
                'The PDF statement date is unreadable.',
              );
            }
            statementDate = _date(headerDates.first.group(0)!);
          }
          inTable = true;
          continue;
        }
        if (!inTable) {
          if (pageIndex == 0) {
            leftHeader.writeln(line.text(70, 315));
            rightHeader.writeln(line.text(315, 510));
          }
          continue;
        }
        if (dateText.contains('Perhation') || dateText.contains('Note')) {
          finish();
          inTable = false;
          continue;
        }
        if (narrative.toUpperCase().contains('BEGINNING BALANCE')) {
          final opening = _minor(balanceText);
          if (foundOpening && opening != runningMinor) {
            throw FormatException(
              'Page ${pageIndex + 1} opening balance does not follow the previous page.',
            );
          }
          runningMinor = opening;
          openingMinor ??= opening;
          foundOpening = true;
          continue;
        }
        if (RegExp(r'^\d{2}/\d{2}/\d{2}$').hasMatch(dateText)) {
          finish();
          if (!foundOpening || amountText.isEmpty || balanceText.isEmpty) {
            throw FormatException(
              'Page ${pageIndex + 1} has an incomplete transaction row.',
            );
          }
          final date = _date(dateText);
          if (statementDate == null ||
              date.isAfter(statementDate) ||
              date.year != statementDate.year ||
              date.month != statementDate.month) {
            throw FormatException(
              'Page ${pageIndex + 1} transaction date is outside the statement month.',
            );
          }
          final amount = _minor(amountText, signed: true);
          final balance = _minor(balanceText);
          if (runningMinor! + amount != balance) {
            throw FormatException(
              'Page ${pageIndex + 1} balance does not agree with a transaction.',
            );
          }
          runningMinor = balance;
          pending = _Pending(dateText, amount, [
            if (narrative.isNotEmpty) narrative,
          ]);
        } else if (pending != null && narrative.isNotEmpty) {
          pending!.narrative.add(narrative);
        }
      }
      finish();
    }
    if (!foundOpening || rows.isEmpty) {
      throw const FormatException(
        'Maybank transaction table or opening balance was not found.',
      );
    }
    if (statementDate == null ||
        statementHolder == null ||
        statementAccount == null ||
        openingMinor == null ||
        runningMinor == null) {
      throw const FormatException(
        'Maybank statement header or balances are incomplete.',
      );
    }
    return BankStatementImport.parsedPdf(
      filename: filename,
      currency: currency,
      bytes: bytes,
      rows: rows,
      statementDate: statementDate,
      accountHolderName: statementHolder,
      accountNumber: statementAccount,
      openingBalance: Money.fromMinor(openingMinor, currency),
      closingBalance: Money.fromMinor(runningMinor, currency),
    );
  }

  static DateTime _date(String value) {
    final parts = value.split('/').map(int.parse).toList();
    final day = DateTime.utc(2000 + parts[2], parts[1], parts[0]);
    if (day.year != 2000 + parts[2] ||
        day.month != parts[1] ||
        day.day != parts[0]) {
      throw FormatException('Invalid statement date $value.');
    }
    return day;
  }

  static int _minor(String value, {bool signed = false}) {
    final expression = signed
        ? RegExp(r'^([\d,]+)\.(\d{2})([+-])$')
        : RegExp(r'^([\d,]+)\.(\d{2})$');
    final match = expression.firstMatch(value);
    if (match == null) {
      throw FormatException('Unreadable statement amount: $value.');
    }
    final units = int.parse(match[1]!.replaceAll(',', ''));
    final cents = int.parse(match[2]!);
    return (units * 100 + cents) * (signed && match[3] == '-' ? -1 : 1);
  }

  static String _description(List<String> narrative) {
    final candidates = <String>[];
    for (final line in narrative) {
      var text = line.trim().replaceAll(RegExp(r'\s+'), ' ');
      text = text.replaceFirst(
        RegExp(
          r'^(?:SALE DEBIT|PAYMENT VIA MYDEBIT|E-GIRO DEBIT|TRANSFER FROM A/C|IBK FUND TFR FR A/C|FPX PAYMENT FR A/|FUND TRANSFER TO A/|CASH WITHDRAWAL)\s*',
          caseSensitive: false,
        ),
        '',
      );
      if (text.isEmpty ||
          RegExp(r'^[A-Z0-9]{8,}$').hasMatch(text) ||
          RegExp(r',\s*MYS$', caseSensitive: false).hasMatch(text) ||
          text.toUpperCase() == 'KUALA LUMPUR' ||
          RegExp(
            r'^(?:DUITNOW QR|SALE DEBIT|PAYMENT VIA MYDEBIT)$',
            caseSensitive: false,
          ).hasMatch(text)) {
        continue;
      }
      if (!candidates.contains(text)) candidates.add(text);
    }
    return candidates.isEmpty ? narrative.first.trim() : candidates.last;
  }

  static String _transactionType(String firstLine) {
    final normalized = firstLine.toUpperCase();
    if (normalized.startsWith('FUND TRANSFER TO A/')) {
      return 'FUND TRANSFER TO A/C';
    }
    if (normalized.startsWith('FPX PAYMENT FR A/')) return 'FPX PAYMENT FR A/C';
    if (normalized.contains('MAYB CHQ DEP')) return 'MAYB CHQ DEP';
    const types = [
      'PAYMENT VIA MYDEBIT',
      'REV PREAUTH MYDEBIT',
      'IBK FUND TFR FR A/C',
      'IBK FUND TFR TO A/C',
      'FUND TRANSFER TO A/C',
      'TRANSFER FROM A/C',
      'FPX PAYMENT FR A/C',
      'E-GIRO DEBIT',
      'ESI PYMT DEBIT',
      'PRE-AUTH MYDEBIT',
      'PRE-AUTH REFUND',
      'PRE-AUTH DEBIT',
      'REFUND SALE',
      'SALE DEBIT',
      'CASH DEPOSIT',
      'PYMT FROM A/C',
      'MAYB CHQ DEP',
      'SVG GIRO CR',
    ];
    for (final type in types) {
      if (normalized.startsWith(type)) return type;
    }
    return 'Other Bank Transaction';
  }

  static String _reference(List<String> narrative) {
    for (final line in narrative) {
      final text = line.trim();
      if (RegExp(r'^(?:QR)?\d{8,20}$', caseSensitive: false).hasMatch(text)) {
        return text;
      }
    }
    return '';
  }
}

final class _Glyph {
  const _Glyph(this.x, this.y, this.width, this.text);
  final double x, y, width;
  final String text;
}

final class _Line {
  _Line(this.y, this.glyphs);
  final double y;
  final List<_Glyph> glyphs;

  String text(double minX, double maxX) {
    final selected =
        glyphs.where((glyph) => glyph.x >= minX && glyph.x < maxX).toList()
          ..sort((a, b) => a.x.compareTo(b.x));
    final result = StringBuffer();
    _Glyph? previous;
    for (final glyph in selected) {
      if (previous != null && glyph.x - (previous.x + previous.width) > 3.5) {
        result.write(' ');
      }
      result.write(glyph.text);
      previous = glyph;
    }
    return result.toString().trim();
  }
}

final class _Pending {
  _Pending(this.date, this.amountMinor, this.narrative);
  final String date;
  final int amountMinor;
  final List<String> narrative;
}
