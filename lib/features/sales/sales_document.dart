import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as raster;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../app/accounting_theme.dart';
import '../../core/documents/generated_document.dart';
import '../../core/documents/receipt_document.dart';
import '../../core/ids/entity_id.dart';
import '../../core/money/money.dart';
import '../../core/money/currency_presentation.dart';
import '../../core/text/transaction_description.dart';
import '../accounting/domain/company_preferences.dart';
import '../accounting/domain/customer.dart';
import '../accounting/presentation/widgets/accounting_formatters.dart';
import 'domain/estimate.dart';
import 'domain/invoice.dart';
import 'domain/sales_line_item.dart';

// A layout revision of the same approved template, including its page footer.
const salesDocumentTemplateVersion = 12;

/// The approved saved-document layout, formerly only a review PDF builder.
/// Values come from exact domain amounts and the current saved profile/contact.
/// It renders selectable text and vectors; it never photographs the UI.
final class SalesDocumentSnapshot {
  SalesDocumentSnapshot._({
    required this.businessId,
    required this.recordId,
    required this.kind,
    required this.issueDate,
    required this.content,
  });

  factory SalesDocumentSnapshot.invoice({
    required EntityId businessId,
    required Invoice invoice,
    required Customer customer,
    required CompanyPreferences preferences,
  }) => SalesDocumentSnapshot._capture(
    businessId,
    invoice,
    customer,
    preferences,
    GeneratedDocumentKind.invoice,
    invoice.dueDate,
    'Due',
  );

  factory SalesDocumentSnapshot.quotation({
    required EntityId businessId,
    required Estimate quotation,
    required Customer customer,
    required CompanyPreferences preferences,
  }) => SalesDocumentSnapshot._capture(
    businessId,
    quotation.pricingSnapshot(),
    customer,
    preferences,
    GeneratedDocumentKind.quotation,
    quotation.validUntil,
    'Valid until',
  );

  static SalesDocumentSnapshot _capture(
    EntityId businessId,
    Invoice invoice,
    Customer customer,
    CompanyPreferences preferences,
    GeneratedDocumentKind kind,
    DateTime dueDate,
    String dueLabel,
  ) {
    if (customer.id != invoice.customerId) {
      throw StateError('The document customer does not match its record.');
    }
    String profile(String key) => preferences.text('Business Profile', key);
    List<String> address(
      String line1,
      String line2,
      String postcode,
      String city,
      String state,
      String country,
    ) {
      final street = [line1, line2].where((v) => v.isNotEmpty).join(', ');
      final locality = [
        [postcode, city].where((v) => v.isNotEmpty).join(' '),
        state,
        country == 'MY' ? 'Malaysia' : country,
      ].where((v) => v.isNotEmpty).join(', ');
      return [street, locality].where((v) => v.isNotEmpty).toList();
    }

    final billing = customer.billingAddress;
    final subtotal = invoice.lines.isEmpty
        ? invoice.total
        : invoice.lines.fold(
            Money.zero(invoice.total.currency),
            (sum, line) => sum + line.subtotal,
          );
    final tax = invoice.lines.fold(
      Money.zero(invoice.total.currency),
      (sum, line) => sum + line.tax,
    );
    final logo =
        preferences.enabled('Numbering & Document Appearance', 'Show Logo')
        ? profile('_businessLogoBase64')
        : '';
    return SalesDocumentSnapshot._(
      businessId: businessId,
      recordId: invoice.id,
      kind: kind,
      issueDate: invoice.issueDate,
      content: _freeze({
        'schemaVersion': 1,
        'templateVersion': salesDocumentTemplateVersion,
        'heading': kind == GeneratedDocumentKind.invoice
            ? 'Invoice'
            : 'Quotation',
        'number': invoice.documentNumber,
        'issueDate': invoice.issueDate.toIso8601String(),
        'dueDate': dueDate.toIso8601String(),
        'dueLabel': dueLabel,
        'companyName': profile('Business Name'),
        'legalName': profile('Legal Name'),
        'companyDetails': [
          ...address(
            profile('Address Line 1'),
            profile('Address Line 2'),
            profile('Postcode'),
            profile('City'),
            profile('State / Region'),
            profile('Country'),
          ),
        ].where((v) => v.isNotEmpty).toList(),
        'companyTelephone': profile('Telephone'),
        'companyEmail': profile('Email'),
        'logo': logo,
        'contactLabel': kind == GeneratedDocumentKind.invoice
            ? 'Billed to'
            : 'Prepared for',
        'customerName': customer.displayName,
        'customerDetails': [
          if (billing != null)
            ...address(
              billing.line1,
              billing.line2 ?? '',
              billing.postalCode,
              billing.city,
              billing.stateOrProvince ?? '',
              billing.countryCode,
            ),
        ].where((v) => v.isNotEmpty).toList(),
        'customerTelephone': customer.contact.phone ?? '',
        'customerEmail': customer.contact.email ?? '',
        'currency': invoice.total.currency,
        'showTaxBreakdown': preferences.enabled(
          'Numbering & Document Appearance',
          'Show Tax Breakdown',
        ),
        'showQuantity':
            preferences.enabled('Sales Preferences', 'Show Quantity') ||
            preferences.enabled('Sales Preferences', 'Show Rate') ||
            invoice.lines.any(
              (line) => line.quantity != SalesQuantity.fromInt(1),
            ),
        'showRate':
            preferences.enabled('Sales Preferences', 'Show Rate') ||
            invoice.lines.any(
              (line) =>
                  line.rateEnabled && line.quantity != SalesQuantity.fromInt(1),
            ),
        'rows': invoice.lines.isEmpty
            ? [
                {
                  'item': '',
                  'description': invoice.reference,
                  'amount': _amount(invoice.total),
                },
              ]
            : [
                for (final line in invoice.lines)
                  {
                    'lineId': line.id.value,
                    'item':
                        line.catalogue?.itemName ?? line.itemId?.value ?? '',
                    'description': line.description,
                    'amount': _amount(line.total),
                    'quantity': line.quantity.toString(),
                    'rate': line.rateEnabled ? _amount(line.rate) : '',
                    // Keep exact structured values alongside the presentation.
                    'quantityScaledUnits': line.quantity.scaledUnits,
                    'quantityScale': SalesQuantity.scale,
                    'rateMinor': line.rate.minorUnits,
                    'rateEnabled': line.rateEnabled,
                    'pricingAdjustmentMinor': line.pricingAdjustment.minorUnits,
                    if (line.manualAmount != null)
                      'manualAmountMinor': line.manualAmount!.minorUnits,
                    'discountMinor': line.discount.minorUnits,
                    'taxMinor': line.tax.minorUnits,
                    'subtotalMinor': line.subtotal.minorUnits,
                    'totalMinor': line.total.minorUnits,
                    'currency': line.rate.currency,
                    'taxInclusive': line.taxInclusive,
                    if (line.taxRatePercent != null)
                      'taxRatePercent': line.taxRatePercent!,
                    if (line.taxCodeId != null)
                      'taxCodeId': line.taxCodeId!.value,
                  },
              ],
        'subtotal': _amount(subtotal),
        'tax': _amount(tax),
        'total': '${invoice.total.currency} ${_amount(invoice.total)}',
        'subtotalMinor': subtotal.minorUnits,
        'taxMinor': tax.minorUnits,
        'totalMinor': invoice.total.minorUnits,
        'terms': invoice.terms.label,
        'customTerms': invoice.terms.kind == PaymentTermKind.custom,
        'memo': invoice.memo,
        'reference': invoice.reference,
        'message': preferences.text('Sales Preferences', 'Customer Message'),
        'footer': preferences.text('Numbering & Document Appearance', 'Footer'),
      }),
    );
  }

  final EntityId businessId, recordId;
  final GeneratedDocumentKind kind;
  final DateTime issueDate;
  final Map<String, Object> content;
  String get signature =>
      sha256.convert(utf8.encode(jsonEncode(content))).toString();

  // Nested rendering inputs stay immutable while asynchronous generation runs.
  // Keep the immutable data schema independent from visible layout revisions.
  static Map<String, Object> _freeze(Map<String, Object> values) {
    Object freeze(Object value) => switch (value) {
      Map<String, Object> map => _freeze(map),
      List list => List<Object>.unmodifiable(
        list.map((v) => freeze(v as Object)),
      ),
      _ => value,
    };
    return Map.unmodifiable(
      values.map((key, value) => MapEntry(key, freeze(value))),
    );
  }

  static String _amount(Money money) => formatAccountingInputAmount(money)
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
}

// Trim only an empty perimeter for PDF placement. The stored upload and frozen
// snapshot retain the original bytes; the logo's artwork and aspect stay intact.
Uint8List _trimLogoPadding(Uint8List bytes) {
  final image = raster.decodeImage(bytes);
  if (image == null) return bytes;
  bool white(raster.Pixel p) =>
      p.a >= 250 && p.r >= 250 && p.g >= 250 && p.b >= 250;
  final whiteBackground = [
    image.getPixel(0, 0),
    image.getPixel(image.width - 1, 0),
    image.getPixel(0, image.height - 1),
    image.getPixel(image.width - 1, image.height - 1),
  ].every(white);
  var left = image.width;
  var top = image.height;
  var right = -1;
  var bottom = -1;
  for (final pixel in image) {
    if (pixel.a == 0 || (whiteBackground && white(pixel))) continue;
    left = math.min(left, pixel.x);
    top = math.min(top, pixel.y);
    right = math.max(right, pixel.x);
    bottom = math.max(bottom, pixel.y);
  }
  if (right < left || bottom < top) return bytes;
  if (left == 0 &&
      top == 0 &&
      right == image.width - 1 &&
      bottom == image.height - 1) {
    return bytes;
  }
  return Uint8List.fromList(
    raster.encodePng(
      raster.copyCrop(
        image,
        x: left,
        y: top,
        width: right - left + 1,
        height: bottom - top + 1,
      ),
    ),
  );
}

final class SalesDocumentRenderer {
  const SalesDocumentRenderer();

  Future<ReceiptAttachment> render(
    SalesDocumentSnapshot snapshot, {
    required String filename,
    Iterable<ReceiptAttachment> previouslySaved = const [],
  }) async {
    final provenance = GeneratedDocumentProvenance(
      businessId: snapshot.businessId,
      recordId: snapshot.recordId,
      kind: snapshot.kind,
      contentSha256: snapshot.signature,
      documentDate: snapshot.issueDate,
      templateVersion: salesDocumentTemplateVersion,
    );
    final previous = previouslySaved
        .where(
          (a) =>
              a.originalId == provenance.attachmentId &&
              a.generated?.contentSha256 == snapshot.signature &&
              a.generated?.templateVersion == salesDocumentTemplateVersion &&
              a.originalBytes.isNotEmpty &&
              sha256.convert(a.originalBytes).toString() == a.originalSha256 &&
              a.isPdf &&
              a.status == AttachmentProcessingStatus.ready,
        )
        .firstOrNull;
    // PDF libraries carry unique trailer IDs. Reuse the saved exact output
    // when its rendering inputs agree, including after Remove followed by Save.
    final bytes = previous?.originalBytes ?? await _pdf(snapshot);
    return ReceiptAttachment.generatedPdf(
      provenance: provenance,
      filename: filename,
      bytes: bytes,
    );
  }

  Future<Uint8List> _pdf(SalesDocumentSnapshot snapshot) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-Bold.ttf'),
    );
    final semibold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter-SemiBold.ttf'),
    );
    // Keep the supplied artwork bytes intact in assets. Tight painted viewBoxes
    // own the PDF pair's displayed size, rather than each file's blank canvas.
    final phoneIcon = (await rootBundle.loadString(
      'assets/icons/document-contact-phone.svg',
    )).replaceFirst('viewBox="0 0 24 24"', 'viewBox="2 2 20 20"');
    final emailIcon = (await rootBundle.loadString(
      'assets/icons/document-contact-email.svg',
    )).replaceFirst('viewBox="0 0 24 24"', 'viewBox="1 3.5 22 17"');
    final c = snapshot.content;
    String text(String key) => c[key] as String;
    final currency = CurrencyPresentation.fromCode(text('currency'));
    // Immutable snapshots retain their original ISO identity. Presentation
    // uses the shared short symbol, including when replaying older snapshots.
    final total = text('total');
    final totalLabel = total.startsWith('${currency.code} ')
        ? currencyAmountLabel(
            currency.code,
            total.substring(currency.code.length + 1),
          )
        : total;
    List<String> details(String key) => (c[key] as List).cast<String>();
    final ink = PdfColor.fromInt(AccountingTokens.light.foreground.toARGB32());
    final soft = PdfColor.fromInt(
      AccountingTokens.light.mutedForeground.toARGB32(),
    );
    final highlight = PdfColor.fromInt(accountingNeutralHighlight.toARGB32());
    // Approved A4 review uses a 1240px reference canvas, 104px outer inset,
    // 10pt body / 20pt title and current 20px content rhythm / 10px radius.
    final scale = PdfPageFormat.a4.width / 1240;
    final space = accountingContentInset * scale;
    final pdf = pw.Document(
      title: '${text('heading')} ${text('number')}',
      author: text('companyName'),
    );
    final regularMetrics = regular.getFont(pw.Context(document: pdf.document));
    final boldMetrics = bold.getFont(pw.Context(document: pdf.document));
    final semiboldMetrics = semibold.getFont(
      pw.Context(document: pdf.document),
    );
    const bodyFontSize = 9.0;
    const fontScale = bodyFontSize / 10;
    double width(String value, {bool strong = false}) =>
        (strong ? boldMetrics : regularMetrics)
            .stringMetrics(value)
            .advanceWidth *
        bodyFontSize;
    // The approved painted "1" to "Corporate Video" interval owns this gap.
    // Keep the same gap at both sides of the flexible description column.
    final columnGap =
        56 * scale - regularMetrics.stringMetrics('1').width * bodyFontSize;
    final rows = (c['rows'] as List).cast<Map>();
    // Column choices are frozen with the snapshot. Older structured snapshots
    // still expose non-default saved pricing without inventing manual rates.
    final showRate =
        c['showRate'] == true ||
        (c['showRate'] == null &&
            rows.any(
              (r) =>
                  r['rateEnabled'] == true &&
                  r['quantityScaledUnits'] != r['quantityScale'],
            ));
    final showQuantity =
        showRate ||
        c['showQuantity'] == true ||
        (c['showQuantity'] == null &&
            rows.any(
              (r) =>
                  r['quantityScaledUnits'] != null &&
                  r['quantityScaledUnits'] != r['quantityScale'],
            ));
    String quantityText(Map row) {
      if (row['quantity'] is String) return row['quantity'] as String;
      final units = row['quantityScaledUnits'] as int?;
      if (units == null) return '';
      final scale = row['quantityScale'] as int? ?? SalesQuantity.scale;
      final fraction = (units % scale)
          .toString()
          .padLeft(scale.toString().length - 1, '0')
          .replaceFirst(RegExp(r'0+$'), '');
      return '${units ~/ scale}${fraction.isEmpty ? '' : '.$fraction'}';
    }

    String rateText(Map row) {
      if (row['rate'] is String) return row['rate'] as String;
      final minor = row['rateMinor'] as int?;
      if (minor == null || row['rateEnabled'] == false) return '';
      return SalesDocumentSnapshot._amount(
        Money.fromMinor(minor, row['currency'] as String? ?? text('currency')),
      );
    }

    final quantityIndex = showQuantity ? 2 : -1;
    final rateIndex = showRate ? 2 + (showQuantity ? 1 : 0) : -1;
    final amountIndex = 2 + (showQuantity ? 1 : 0) + (showRate ? 1 : 0);
    double longest(Iterable<String> values, String heading) => math.max(
      width(heading, strong: true),
      values.fold(0.0, (largest, value) => math.max(largest, width(value))),
    );
    final numberWidth = longest([
      for (var n = 1; n <= rows.length; n++) '$n',
    ], 'No.');
    final amountWidth = longest(
      rows.map((r) => r['amount'] as String),
      'Amount (${currency.amountSymbol})',
    );
    final quantityWidth = showQuantity
        ? longest(rows.map(quantityText), 'Quantity')
        : 0.0;
    final rateWidth = showRate
        ? longest(rows.map(rateText), 'Rate (${currency.amountSymbol})')
        : 0.0;
    final pricingWidth = quantityWidth + rateWidth;
    final descriptionWidth =
        PdfPageFormat.a4.width -
        208 * scale -
        numberWidth -
        amountWidth -
        pricingWidth -
        amountIndex * columnGap;
    if (descriptionWidth < width('Item', strong: true)) {
      throw const FormatException(
        'Pricing values leave insufficient PDF item/description space.',
      );
    }
    final style = pw.TextStyle(
      font: regular,
      fontSize: bodyFontSize,
      color: ink,
    );
    final label = style.copyWith(
      fontBold: bold,
      fontWeight: pw.FontWeight.bold,
    );
    pw.Widget line(
      String value, {
      bool muted = false,
      bool strong = false,
      double fontSize = bodyFontSize,
      bool paintedLeft = false,
    }) {
      final child = pw.Text(
        value,
        style: (strong ? label : style).copyWith(
          color: muted ? soft : ink,
          fontSize: fontSize,
        ),
      );
      return paintedLeft
          ? pw.Transform.translate(
              offset: PdfPoint(
                -(strong ? boldMetrics : regularMetrics)
                        .stringMetrics(value)
                        .left *
                    fontSize,
                0,
              ),
              child: child,
            )
          : child;
    }

    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final measureContext = pw.Context(document: pdf.document)
        .inheritFrom(theme);
    final contentWidth = PdfPageFormat.a4.width - 208 * scale;
    double height(pw.Widget widget) {
      widget.layout(measureContext, pw.BoxConstraints(maxWidth: contentWidth));
      return widget.box!.height;
    }

    // Contact details retain the approved baseline interval. Growing
    // description/paragraph spacing must never change company or customer text.
    const contactLineHeight = 14.3319 * fontScale;
    // The PDF contact pair has a clear handset and envelope, matched painted
    // extent and stroke. Other app icon families retain their existing artwork.
    final contactIconSize =
        regularMetrics.stringMetrics('H').height * bodyFontSize;
    pw.Widget block(List<String> values) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final (n, value) in values.indexed)
          if (n == values.length - 1)
            line(value, muted: true, paintedLeft: true)
          else
            pw.SizedBox(
              height: contactLineHeight,
              child: pw.Align(
                alignment: pw.Alignment.topLeft,
                child: line(value, muted: true, paintedLeft: true),
              ),
            ),
      ],
    );
    pw.Widget contactBlock(String prefix) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        block(details('${prefix}Details')),
        if (text('${prefix}Telephone').isNotEmpty ||
            (prefix == 'company' && text('${prefix}Email').isNotEmpty)) ...[
          if (details('${prefix}Details').isNotEmpty)
            pw.SizedBox(
              height:
                  contactLineHeight -
                  height(line(details('${prefix}Details').last, muted: true)),
            ),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (text('${prefix}Telephone').isNotEmpty) ...[
                pw.SvgImage(
                  svg: phoneIcon,
                  width: contactIconSize,
                  height: contactIconSize,
                  colorFilter: soft,
                ),
                pw.SizedBox(width: width(' ')),
                line(text('${prefix}Telephone'), muted: true),
              ],
              if (text('${prefix}Telephone').isNotEmpty &&
                  prefix == 'company' &&
                  text('${prefix}Email').isNotEmpty)
                pw.SizedBox(width: width('    ')),
              if (prefix == 'company' && text('${prefix}Email').isNotEmpty) ...[
                pw.SvgImage(
                  svg: emailIcon,
                  width: contactIconSize,
                  height: contactIconSize,
                  colorFilter: soft,
                ),
                pw.SizedBox(width: width(' ')),
                line(text('${prefix}Email'), muted: true),
              ],
            ],
          ),
        ],
      ],
    );
    String date(String value) {
      final d = DateTime.parse(value);
      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      return '${d.day} ${months[d.month - 1]} ${d.year}';
    }

    // Explicit description intervals; contact geometry remains independent.
    const descriptionLineHeight = 15.0 * fontScale;
    const descriptionParagraphExtra =
        bodyFontSize * transactionDescriptionParagraphHeightFactor -
        descriptionLineHeight;
    pw.Widget spacedDescription(List<DescriptionVisualLine> lines) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final (n, value) in lines.indexed) ...[
          if (n > 0 && value.paragraphStart)
            pw.SizedBox(height: descriptionParagraphExtra),
          pw.SizedBox(
            height: n == lines.length - 1 ? null : descriptionLineHeight,
            child: pw.Stack(
              children: [
                if (value.marker != null) line(value.marker!, muted: true),
                pw.Padding(
                  padding: pw.EdgeInsets.only(left: value.indent),
                  child: line(value.text, muted: true),
                ),
              ],
            ),
          ),
        ],
      ],
    );
    pw.Widget cell(
      String value,
      int index, {
      bool heading = false,
      bool first = true,
      bool last = true,
    }) => pw.Padding(
      padding: pw.EdgeInsets.only(
        top: first ? space : 0,
        bottom: last ? space : 0,
        right: index == amountIndex ? 0 : columnGap,
      ),
      child: pw.Align(
        alignment: index == quantityIndex
            ? pw.Alignment.center
            : index == amountIndex || index == rateIndex
            ? pw.Alignment.centerRight
            : pw.Alignment.centerLeft,
        child: pw.Text(value, style: heading ? label : style),
      ),
    );
    double inkTopInset(String value, double fontSize, {bool strong = false}) {
      final metrics = (strong ? boldMetrics : regularMetrics).stringMetrics(
        value,
      );
      return (metrics.ascent - metrics.bottom) * fontSize;
    }

    double inkBottomInset(
      String value,
      double fontSize, {
      bool strong = false,
      bool itemTitle = false,
    }) {
      final metrics =
          (itemTitle
                  ? semiboldMetrics
                  : strong
                  ? boldMetrics
                  : regularMetrics)
              .stringMetrics(value);
      return (metrics.top - metrics.descent) * fontSize;
    }

    final logoExtent = 146 * scale;
    final companyName = text('companyName').toUpperCase();
    pw.Widget companyBlock() => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        line(companyName, strong: true, paintedLeft: true),
        if (text('legalName').isNotEmpty) ...[
          pw.SizedBox(height: space / 2),
          line(text('legalName'), muted: true, paintedLeft: true),
        ],
        pw.SizedBox(height: space / 2),
        contactBlock('company'),
      ],
    );
    final companyBlockWidth =
        contentWidth -
        (text('logo').isNotEmpty ? logoExtent + space : 0) -
        space -
        regularMetrics.stringMetrics(text('heading')).advanceWidth * 20;
    final measuredCompanyBlock = companyBlock();
    measuredCompanyBlock.layout(
      measureContext,
      pw.BoxConstraints(maxWidth: companyBlockWidth),
    );
    final companyFirstInkInset = inkTopInset(
      companyName,
      bodyFontSize,
      strong: true,
    );
    final hasCompanyContacts =
        text('companyTelephone').isNotEmpty || text('companyEmail').isNotEmpty;
    final companyLastText = hasCompanyContacts
        ? (text('companyEmail').isNotEmpty
              ? text('companyEmail')
              : text('companyTelephone'))
        : (details('companyDetails').isNotEmpty
              ? details('companyDetails').last
              : text('legalName').isNotEmpty
              ? text('legalName')
              : companyName);
    final companyLastInkInset = hasCompanyContacts
        ? math.min(
            inkBottomInset(companyLastText, bodyFontSize),
            (height(line(companyLastText)) - contactIconSize) / 2,
          )
        : inkBottomInset(
            companyLastText,
            bodyFontSize,
            strong: companyLastText == companyName,
          );
    // Keep the logo fixed and center the complete painted company block,
    // including its name, legal name, address and contact row.
    final companyNameTop = text('logo').isNotEmpty && companyName.isNotEmpty
        ? math.max(
            0.0,
            (logoExtent -
                        measuredCompanyBlock.box!.height +
                        companyFirstInkInset +
                        companyLastInkInset) /
                    2 -
                companyFirstInkInset,
          )
        : 0.0;
    final documentTitleTop = math.max(
      0.0,
      companyNameTop +
          inkTopInset(companyName, bodyFontSize, strong: true) -
          inkTopInset(text('heading'), 20),
    );
    // Keep the current header, table and Total owners; paginate their measured
    // geometry, rather than placing wrapped descriptions in separate items.
    pw.Widget header() => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (text('logo').isNotEmpty) ...[
              pw.Image(
                pw.MemoryImage(_trimLogoPadding(base64Decode(text('logo')))),
                width: logoExtent,
                height: logoExtent,
                fit: pw.BoxFit.contain,
                alignment: pw.Alignment.centerLeft,
              ),
              pw.SizedBox(width: space),
            ],
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Padding(
                      padding: pw.EdgeInsets.only(top: companyNameTop),
                      child: companyBlock(),
                    ),
                  ),
                  pw.SizedBox(width: space),
                  pw.Padding(
                    padding: pw.EdgeInsets.only(top: documentTitleTop),
                    child: pw.Text(
                      text('heading'),
                      style: style.copyWith(fontSize: 20),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: space * 3 - contactLineHeight),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  line(
                    text('contactLabel').toUpperCase(),
                    strong: true,
                    paintedLeft: true,
                  ),
                  pw.SizedBox(height: space / 2),
                  pw.SizedBox(
                    height: contactLineHeight,
                    child: pw.Align(
                      alignment: pw.Alignment.topLeft,
                      child: line(text('customerName'), paintedLeft: true),
                    ),
                  ),
                  contactBlock('customer'),
                ],
              ),
            ),
            pw.SizedBox(width: space),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                line('No.  ${text('number')}'),
                pw.SizedBox(height: space / 2),
                line(date(text('issueDate'))),
                pw.SizedBox(height: space / 2),
                line(
                  '${text('dueLabel')}:  ${date(text('dueDate'))}',
                  muted: true,
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: space * 2),
      ],
    );
    // The two requested totals gaps copy the visible paragraph gap, without
    // changing contact intervals, Memo spacing or the rounded Total frame.
    final summaryParagraphGap =
        descriptionLineHeight +
        descriptionParagraphExtra -
        regularMetrics.stringMetrics('Ag').height * bodyFontSize;
    final summaryTopGap =
        summaryParagraphGap -
        inkTopInset('Subtotal', bodyFontSize, strong: true);
    final summaryInnerGap =
        summaryParagraphGap -
        inkBottomInset('Subtotal', bodyFontSize, strong: true) -
        inkTopInset('Tax', bodyFontSize, strong: true);
    pw.Widget summary() => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.SizedBox(
        width: 361 * scale,
        child: pw.Column(
          children: [
            for (final row in [
              if (c['showTaxBreakdown'] != false) ...[
                ('Subtotal', text('subtotal')),
                ('Tax', text('tax')),
              ],
              ('Total', totalLabel),
            ]) ...[
              if (row.$1 == 'Tax') pw.SizedBox(height: summaryInnerGap),
              pw.Container(
                padding: row.$1 == 'Total'
                    ? pw.EdgeInsets.all(space)
                    : pw.EdgeInsets.only(
                        left: space,
                        right: space,
                        bottom: row.$1 == 'Tax' ? space : 0,
                      ),
                decoration: row.$1 == 'Total'
                    ? pw.BoxDecoration(
                        color: highlight,
                        borderRadius: pw.BorderRadius.circular(
                          accountingControlRadius * scale,
                        ),
                      )
                    : null,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    line(row.$1, strong: true),
                    pw.SizedBox(width: space),
                    pw.Flexible(
                      child: pw.Text(
                        row.$2,
                        style: row.$1 == 'Total' ? label : style,
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
    final paymentLineHeight = height(line('Payment terms: Ag'));
    final informationWidth = PdfPageFormat.a4.width * .4;
    List<DescriptionVisualLine> paymentLines(String value, double fontSize) =>
        layoutTransactionDescription(
          value,
          informationWidth,
          (v) => width(v) * fontSize / bodyFontSize,
          markerReserve: ' ',
        );
    String visibleText(DescriptionVisualLine value) =>
        '${value.marker ?? ''}${value.text}';
    pw.Widget paymentText(
      String value, {
      bool memo = false,
      bool customTerms = false,
    }) {
      final fontSize = memo ? 8.0 : bodyFontSize;
      final lines = paymentLines(value, fontSize);
      // The Memo/custom body copies address-line rhythm, including list
      // continuations. Preserve the heading and ordinary payment-line owners.
      final lineHeight = memo || customTerms
          ? contactLineHeight
          : paymentLineHeight;
      return pw.SizedBox(
        width: informationWidth,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final (n, value) in lines.indexed)
              pw.SizedBox(
                height: n == lines.length - 1 && !customTerms
                    ? null
                    : lineHeight,
                child: pw.Stack(
                  children: [
                    if (value.marker != null)
                      line(value.marker!, muted: true, fontSize: fontSize),
                    pw.Padding(
                      padding: pw.EdgeInsets.only(left: value.indent),
                      child: line(value.text, muted: true, fontSize: fontSize),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    final informationHeading = snapshot.kind == GeneratedDocumentKind.invoice
        ? 'Payment Information'
        : 'Quotation Details';
    // Custom text is the former Memo editor's content. Keep its first marker
    // at the text edge so wrapping retains the same hanging-list behaviour.
    final termsText = c['customTerms'] == true
        ? text('terms')
        : 'Payment terms: ${text('terms')}';
    final dueText = '${text('dueLabel')}: ${date(text('dueDate'))}';
    final hasMemo = text('memo').isNotEmpty && c['customTerms'] != true;
    // The user's mark starts at the heading's main letter baseline. Do not
    // let the descender in "Payment" shorten the following Memo's clearance.
    final headingToTermsGap =
        inkBottomInset(
          informationHeading.toUpperCase(),
          bodyFontSize,
          strong: true,
        ) +
        space / 2 +
        inkTopInset(
          visibleText(paymentLines(termsText, bodyFontSize).first),
          bodyFontSize,
        );
    final memoGap = hasMemo
        ? headingToTermsGap -
              inkBottomInset(
                visibleText(paymentLines(dueText, bodyFontSize).last),
                bodyFontSize,
              ) -
              inkTopInset(visibleText(paymentLines(text('memo'), 8).first), 8)
        : 0.0;
    final closingText = text('footer').isNotEmpty
        ? text('footer')
        : hasMemo
        ? text('memo')
        : dueText;
    final closingFontSize = hasMemo && text('footer').isEmpty
        ? 8.0
        : bodyFontSize;
    final closingBottomInset = inkBottomInset(
      visibleText(paymentLines(closingText, closingFontSize).last),
      closingFontSize,
    );
    pw.Widget information() => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (text('message').isNotEmpty) ...[
          paymentText(text('message')),
          pw.SizedBox(height: space * 2),
        ],
        line(informationHeading, strong: true, muted: true),
        pw.SizedBox(height: space / 2),
        paymentText(termsText, customTerms: c['customTerms'] == true),
        paymentText(dueText),
        if (hasMemo) ...[
          pw.SizedBox(height: memoGap),
          paymentText(text('memo'), memo: true),
        ],
        if (text('footer').isNotEmpty) ...[
          pw.SizedBox(height: space / 2),
          paymentText(text('footer')),
        ],
      ],
    );
    pw.TableRow tableHeading() => pw.TableRow(
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: ink, width: 2 * scale),
        ),
      ),
      children: [
        cell('No.', 0, heading: true),
        cell('Item', 1, heading: true),
        if (showQuantity) cell('Quantity', quantityIndex, heading: true),
        if (showRate)
          cell('Rate (${currency.amountSymbol})', rateIndex, heading: true),
        cell('Amount (${currency.amountSymbol})', amountIndex, heading: true),
      ],
    );
    // Copy the established Billed To / customer painted header-to-content
    // clearance. Account for each item title's descenders and wrapping.
    final itemHeaderContentGap =
        inkBottomInset(
          text('contactLabel').toUpperCase(),
          bodyFontSize,
          strong: true,
        ) +
        space / 2 +
        inkTopInset(text('customerName'), bodyFontSize);
    pw.TableRow itemRow(
      int index,
      List<DescriptionVisualLine> lines, {
      bool first = true,
      bool last = true,
    }) {
      final itemName = rows[index]['item'] as String;
      final hasHeader = first && itemName.isNotEmpty;
      final hasDescription = lines.any(
        (v) => v.text.isNotEmpty || v.marker != null,
      );
      final titleLines = hasHeader
          ? wrapDescriptionText(
              itemName,
              descriptionWidth,
              (v) =>
                  semiboldMetrics.stringMetrics(v).advanceWidth * bodyFontSize,
            )
          : const <String>[];
      final contentGap = hasHeader && hasDescription
          ? math.max(
              0.0,
              itemHeaderContentGap -
                  inkBottomInset(
                    titleLines.last,
                    bodyFontSize,
                    itemTitle: true,
                  ) -
                  inkTopInset(visibleText(lines.first), bodyFontSize),
            )
          : 0.0;
      return pw.TableRow(
        decoration: last
            ? pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: soft, width: scale),
                ),
              )
            : null,
        children: [
          cell(first ? '${index + 1}' : '', 0, first: true, last: true),
          pw.Padding(
            padding: pw.EdgeInsets.only(
              top: space,
              bottom: space,
              right: columnGap,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (hasHeader)
                  pw.Text(
                    itemName,
                    style: style.copyWith(fontNormal: semibold),
                  ),
                if (hasHeader && hasDescription)
                  pw.SizedBox(height: contentGap),
                if (hasDescription) spacedDescription(lines),
              ],
            ),
          ),
          if (showQuantity)
            cell(first ? quantityText(rows[index]) : '', quantityIndex),
          if (showRate) cell(first ? rateText(rows[index]) : '', rateIndex),
          cell(first ? rows[index]['amount'] as String : '', amountIndex),
        ],
      );
    }

    pw.Table table(List<pw.TableRow> entries, {bool heading = true}) =>
        pw.Table(
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.top,
          columnWidths: {
            0: pw.FixedColumnWidth(numberWidth + columnGap),
            1: pw.FlexColumnWidth(),
            if (showQuantity)
              quantityIndex: pw.FixedColumnWidth(quantityWidth + columnGap),
            if (showRate) rateIndex: pw.FixedColumnWidth(rateWidth + columnGap),
            amountIndex: pw.FixedColumnWidth(amountWidth),
          },
          children: [if (heading) tableHeading(), ...entries],
        );
    final headerHeight = height(header());
    final tableHeadingHeight = height(table([]));
    final summaryHeight = height(summary());
    final informationHeight = height(information());
    final counterHeight = height(line('1/1'));
    final pageBodyHeight =
        PdfPageFormat.a4.height - 208 * scale - counterHeight - columnGap;
    final finalReserve = summaryHeight + informationHeight + space * 4;
    final pages = <List<pw.TableRow>>[[]];
    var used = headerHeight + tableHeadingHeight;
    void nextPage() {
      pages.add([]);
      used = tableHeadingHeight;
    }

    for (var index = 0; index < rows.length; index++) {
      final lines = layoutTransactionDescription(
        rows[index]['description'] as String,
        descriptionWidth,
        width,
      );
      var start = 0;
      while (start < lines.length) {
        final first = start == 0;
        final remaining = lines.sublist(start);
        final whole = itemRow(index, remaining, first: first);
        final wholeHeight = height(table([whole], heading: false));
        final reserve = index == rows.length - 1 ? finalReserve : 0.0;
        if (used + wholeHeight + reserve <= pageBodyHeight) {
          pages.last.add(whole);
          used += wholeHeight;
          break;
        }
        // A row which fits a fresh page moves intact, including all its text.
        if (tableHeadingHeight + wholeHeight + reserve <= pageBodyHeight) {
          nextPage();
          continue;
        }
        // Only an item taller than a whole page continues. Its number, item and
        // amount appear once; the closing divider belongs to its final fragment.
        var count = 0;
        var fragmentHeight = 0.0;
        for (var n = 1; n < remaining.length; n++) {
          final h = height(
            table([
              itemRow(
                index,
                remaining.take(n).toList(),
                first: first,
                last: false,
              ),
            ], heading: false),
          );
          if (used + h > pageBodyHeight) break;
          count = n;
          fragmentHeight = h;
        }
        if (count == 0) {
          if (pages.last.isEmpty && pages.length > 1) {
            throw const FormatException(
              'A PDF row cannot fit inside the page margins.',
            );
          }
          nextPage();
          continue;
        }
        pages.last.add(
          itemRow(
            index,
            remaining.take(count).toList(),
            first: first,
            last: false,
          ),
        );
        used += fragmentHeight;
        start += count;
        nextPage();
      }
    }
    for (final (index, entries) in pages.indexed) {
      final last = index == pages.length - 1;
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(104 * scale),
          theme: theme,
          build: (_) => pw.Stack(
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  if (index == 0) header(),
                  table(entries),
                  if (last) ...[pw.SizedBox(height: summaryTopGap), summary()],
                ],
              ),
              if (last)
                pw.Positioned(
                  left: 0,
                  right: 0,
                  // Align painted final text bottoms, including the smaller Memo.
                  bottom:
                      inkBottomInset(
                        '${index + 1}/${pages.length}',
                        bodyFontSize,
                      ) -
                      closingBottomInset,
                  child: information(),
                ),
              if (pages.length > 1)
                pw.Positioned(
                  right: 0,
                  bottom: 0,
                  child: line('${index + 1}/${pages.length}'),
                ),
            ],
          ),
        ),
      );
    }
    return pdf.save();
  }
}
