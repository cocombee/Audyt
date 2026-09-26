import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../../core/money/currency.dart';
import '../../../../core/money/money.dart';

/// An immutable source import. Rows are evidence, not posted transactions.
final class BankStatementImport {
  BankStatementImport._(
    this.filename,
    this.currency,
    Uint8List source,
    this.rows,
    this.parserVersion,
    this.statementDate,
    this.accountHolderName,
    this.accountNumber,
    this.openingBalance,
    this.closingBalance, {
    String? retainedDigest,
  }) : _source = Uint8List.fromList(source),
       digest = retainedDigest ?? sha256.convert(source).toString();
  final String filename;
  final String currency;
  final String digest;
  final Uint8List _source;
  Uint8List get sourceBytes => Uint8List.fromList(_source);
  final List<BankStatementRow> rows;
  final int parserVersion;
  final DateTime? statementDate;
  final String? accountHolderName;
  final String? accountNumber;
  final Money? openingBalance;
  final Money? closingBalance;

  /// Monthly PDF metadata supplies its full period; CSV evidence supplies
  /// the inclusive dates of its actual rows. Never use today's date here.
  ({DateTime start, DateTime end}) get period {
    final dates = rows.map((row) => row.date).toList()..sort();
    final end = statementDate ?? dates.last;
    final start = statementDate == null
        ? dates.first
        : DateTime.utc(end.year, end.month);
    return (start: start, end: end);
  }

  factory BankStatementImport.parsedPdf({
    required String filename,
    required String currency,
    required Uint8List bytes,
    required List<BankStatementRow> rows,
    required DateTime statementDate,
    required String accountHolderName,
    required String accountNumber,
    required Money openingBalance,
    required Money closingBalance,
  }) {
    if (!filename.toLowerCase().endsWith('.pdf') ||
        bytes.length < 5 ||
        bytes.length > 20 * 1024 * 1024 ||
        utf8.decode(bytes.take(5).toList()) != '%PDF-' ||
        rows.isEmpty ||
        rows.length > 100000) {
      throw const FormatException(
        'Choose a readable Maybank PDF statement up to 20 MB.',
      );
    }
    final code = Currency.parse(currency).code;
    if (rows.any(
          (row) => row.amount.currency != code || row.sourcePage == null,
        ) ||
        openingBalance.currency != code ||
        closingBalance.currency != code ||
        accountHolderName.trim().isEmpty ||
        accountNumber.trim().isEmpty) {
      throw const FormatException(
        'The PDF transactions have invalid currency or page evidence.',
      );
    }
    return BankStatementImport._(
      filename.trim(),
      code,
      bytes,
      List.unmodifiable(rows),
      2,
      statementDate,
      accountHolderName.trim(),
      accountNumber.trim(),
      openingBalance,
      closingBalance,
    );
  }

  String get parsedRowsJson => jsonEncode({
    'statementDate': statementDate?.toIso8601String(),
    'accountHolderName': accountHolderName,
    'accountNumber': accountNumber,
    'openingMinor': openingBalance?.minorUnits,
    'closingMinor': closingBalance?.minorUnits,
    'rows': [
      for (final row in rows)
        {
          'sourceRow': row.sourceRow,
          'sourcePage': row.sourcePage,
          'date': row.date.toIso8601String(),
          'description': row.description,
          'rawNarrative': row.rawNarrative,
          'transactionType': row.transactionType,
          'amountMinor': row.amount.minorUnits,
          'reference': row.reference,
        },
    ],
  });

  factory BankStatementImport.restorePdf({
    required String filename,
    required String currency,
    required Uint8List bytes,
    required String parsedRowsJson,
  }) {
    final decoded = jsonDecode(parsedRowsJson) as Map;
    final rows = <BankStatementRow>[
      for (final item in decoded['rows'] as List)
        BankStatementRow(
          sourceRow: (item as Map)['sourceRow'] as int,
          sourcePage: item['sourcePage'] as int,
          date: DateTime.parse(item['date'] as String),
          description: item['description'] as String,
          rawNarrative: item['rawNarrative'] as String,
          transactionType: item['transactionType'] as String,
          amount: Money.fromMinor(item['amountMinor'] as int, currency),
          reference: item['reference'] as String,
        ),
    ];
    return BankStatementImport.parsedPdf(
      filename: filename,
      currency: currency,
      bytes: bytes,
      rows: rows,
      statementDate: DateTime.parse(decoded['statementDate'] as String),
      accountHolderName: decoded['accountHolderName'] as String,
      accountNumber: decoded['accountNumber'] as String,
      openingBalance: Money.fromMinor(decoded['openingMinor'] as int, currency),
      closingBalance: Money.fromMinor(decoded['closingMinor'] as int, currency),
    );
  }

  factory BankStatementImport.metadataOnly({
    required String filename,
    required String currency,
    required String digest,
    required int parserVersion,
    required String parsedRowsJson,
  }) {
    final data = jsonDecode(parsedRowsJson) as Map;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid retained statement checksum.');
    }
    final rows = <BankStatementRow>[
      for (final raw in data['rows'] as List)
        BankStatementRow(
          sourceRow: raw['sourceRow'] as int,
          sourcePage: raw['sourcePage'] as int?,
          date: DateTime.parse(raw['date'] as String),
          description: raw['description'] as String,
          rawNarrative: raw['rawNarrative'] as String,
          transactionType: raw['transactionType'] as String,
          amount: Money.fromMinor(raw['amountMinor'] as int, currency),
          reference: raw['reference'] as String,
        ),
    ];
    if (rows.isEmpty) {
      throw const FormatException('Missing retained statement rows.');
    }
    return BankStatementImport._(
      filename,
      currency,
      Uint8List(0),
      List.unmodifiable(rows),
      parserVersion,
      data['statementDate'] == null
          ? null
          : DateTime.parse(data['statementDate'] as String),
      data['accountHolderName'] as String?,
      data['accountNumber'] as String?,
      data['openingMinor'] == null
          ? null
          : Money.fromMinor(data['openingMinor'] as int, currency),
      data['closingMinor'] == null
          ? null
          : Money.fromMinor(data['closingMinor'] as int, currency),
      retainedDigest: digest,
    );
  }
  bool get sourceAvailable => _source.isNotEmpty;

  factory BankStatementImport.csv({
    required String filename,
    required String currency,
    required Uint8List bytes,
  }) {
    if (filename.trim().isEmpty ||
        bytes.isEmpty ||
        bytes.length > 20 * 1024 * 1024) {
      throw const FormatException('Choose a named CSV file up to 20 MB.');
    }
    final code = Currency.parse(currency).code;
    var text = utf8.decode(bytes);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final records = _csv(text);
    if (records.isEmpty) throw const FormatException('The statement is empty.');
    final headers = records.first.map((v) => v.trim().toLowerCase()).toList();
    if (headers.toSet().length != headers.length ||
        !headers.contains('date') ||
        !headers.contains('description') ||
        !headers.contains('amount')) {
      throw const FormatException(
        'CSV needs unique Date, Description and Amount columns; Reference is optional.',
      );
    }
    final rows = <BankStatementRow>[];
    for (var i = 1; i < records.length; i++) {
      final values = records[i];
      if (values.length == 1 && values.single.isEmpty) continue;
      if (values.length != headers.length) {
        throw FormatException(
          'CSV row ${i + 1} has the wrong number of columns.',
        );
      }
      String value(String key) => values[headers.indexOf(key)].trim();
      final dateText = value('date');
      final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(dateText);
      if (match == null) {
        throw FormatException('CSV row ${i + 1} needs a YYYY-MM-DD date.');
      }
      final year = int.parse(match[1]!);
      final month = int.parse(match[2]!);
      final day = int.parse(match[3]!);
      final date = DateTime.utc(year, month, day);
      if (year < 1 ||
          date.year != year ||
          date.month != month ||
          date.day != day) {
        throw FormatException('CSV row ${i + 1} has an invalid date.');
      }
      final amountText = value('amount');
      final precision = Currency.parse(code).fractionDigits;
      if (!RegExp(r'^[+-]?\d+(?:\.\d+)?$').hasMatch(amountText) ||
          (amountText.contains('.') &&
              amountText.split('.').last.length > precision)) {
        throw FormatException(
          'CSV row ${i + 1} needs an exact amount in $code without grouping separators.',
        );
      }
      final amount = Money.fromDecimal(amountText, code);
      rows.add(
        BankStatementRow(
          sourceRow: i + 1,
          date: date,
          description: value('description'),
          amount: amount,
          reference: headers.contains('reference') ? value('reference') : '',
        ),
      );
      if (rows.length > 100000) {
        throw const FormatException(
          'A statement may contain at most 100,000 rows.',
        );
      }
    }
    if (rows.isEmpty) {
      throw const FormatException('No statement transactions were found.');
    }
    return BankStatementImport._(
      filename.trim(),
      code,
      bytes,
      List.unmodifiable(rows),
      1,
      null,
      null,
      null,
      null,
      null,
    );
  }
}

final class BankStatementRow {
  const BankStatementRow({
    required this.sourceRow,
    required this.date,
    required this.description,
    required this.amount,
    required this.reference,
    this.sourcePage,
    this.rawNarrative = '',
    this.transactionType = '',
  });
  final int sourceRow;
  final DateTime date;
  final String description;
  final Money amount;
  final String reference;
  final int? sourcePage;
  final String rawNarrative;
  final String transactionType;
}

// Strict CSV: supports quoted commas/newlines and escaped double quotes.
List<List<String>> _csv(String text) {
  final records = <List<String>>[];
  var record = <String>[];
  var field = StringBuffer();
  var quoted = false;
  var closed = false;
  void endField() {
    record.add(field.toString());
    field = StringBuffer();
    closed = false;
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else {
        field.write(c);
      }
    } else if (c == ',') {
      endField();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endField();
      records.add(record);
      record = [];
    } else if (c == '"' && field.isEmpty && !closed) {
      quoted = true;
    } else {
      if (closed || c == '"') {
        throw const FormatException('Invalid CSV quoting.');
      }
      field.write(c);
    }
  }
  if (quoted) throw const FormatException('Unclosed CSV quote.');
  if (record.isNotEmpty || field.isNotEmpty || closed) {
    endField();
    records.add(record);
  }
  return records;
}
