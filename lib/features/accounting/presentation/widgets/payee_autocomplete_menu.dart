import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/accounting_theme.dart';
import '../../../../app/responsive.dart';
import '../../domain/payee.dart';

/// The existing directory rows own their skin; this owner only measures and
/// positions their scroller. Always pass the complete eligible directory, not
/// the filtered search results, so searching cannot resize the menu.
double payeeAutocompleteMenuWidth(
  BuildContext context,
  Iterable<Payee> candidates, {
  bool badged = true,
  Iterable<String> extraLabels = const [],
}) {
  final textTheme = Theme.of(context).textTheme;
  final nameStyle = textTheme.bodyMedium!;
  final badgeStyle = textTheme.bodySmall!.copyWith(fontWeight: FontWeight.w500);
  double measure(String text, TextStyle style) =>
      AccountingResponsive.measuredTextWidth(context, text, style);
  var width = 0.0;
  for (final payee in candidates) {
    // Badge rows: menu 4+4, row 8+8, peer 8, badge 6+6.
    // Voucher rows retain their existing combined text and 10+10 row inset.
    final rowWidth = badged
        ? 44 +
              measure(payee.name, nameStyle) +
              measure(payee.typeLabel, badgeStyle)
        : 28 + measure('${payee.name} · ${payee.typeLabel}', nameStyle);
    width = math.max(width, rowWidth);
  }
  for (final label in extraLabels) {
    // Existing no-results rows have 12+12 in addition to the menu inset.
    width = math.max(width, 32 + measure(label, nameStyle));
  }
  return width.ceilToDouble();
}

/// RawAutocomplete constrains its options view to the field width. A nested
/// portal gives the existing list a real overlay hit area when it must widen;
/// painting an OverflowBox alone would leave the extra choices unclickable.
/// Lifetime, filtering, keyboard selection and dismissal stay with the owning
/// Autocomplete. This is not a field-row planner or a new payee directory.
class PayeeAutocompleteMenu extends StatefulWidget {
  const PayeeAutocompleteMenu({
    super.key,
    required this.triggerKey,
    required this.surfaceKey,
    required this.contentWidth,
    required this.itemCount,
    required this.itemBuilder,
  });

  final GlobalKey triggerKey;
  final Key surfaceKey;
  final double contentWidth;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<PayeeAutocompleteMenu> createState() => _PayeeAutocompleteMenuState();
}

class _PayeeAutocompleteMenuState extends State<PayeeAutocompleteMenu> {
  final _portal = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    // The controller is not attached yet: pre-showing avoids a delayed second
    // frame and preserves the existing autocomplete's immediate opening.
    _portal.show();
  }

  @override
  Widget build(BuildContext context) => OverlayPortal.overlayChildLayoutBuilder(
    controller: _portal,
    overlayChildBuilder: (context, layout) {
      final trigger = widget.triggerKey.currentContext?.findRenderObject();
      final overlay = Overlay.of(context).context.findRenderObject();
      if (trigger is! RenderBox || overlay is! RenderBox || !trigger.hasSize) {
        return const SizedBox.shrink();
      }
      final rect =
          trigger.localToGlobal(Offset.zero, ancestor: overlay) & trigger.size;
      final media = MediaQuery.of(context);
      final leftLimit = math.max(8.0, media.padding.left);
      final rightLimit =
          layout.overlaySize.width - math.max(8.0, media.padding.right);
      final width = math.min(
        math.max(rect.width, widget.contentWidth),
        math.max(0.0, rightLimit - leftLimit),
      );
      final left = rect.left.clamp(
        leftLimit,
        math.max(leftLimit, rightLimit - width),
      );
      final topLimit = math.max(8.0, media.padding.top);
      final bottomLimit =
          layout.overlaySize.height -
          math.max(8.0, media.padding.bottom + media.viewInsets.bottom);
      final below = math.max(0.0, bottomLimit - rect.bottom);
      final above = math.max(0.0, rect.top - topLimit);
      final opensUp =
          below < math.min(240.0, widget.itemCount * 44.0 + 8) && above > below;
      final height = math.min(240.0, opensUp ? above : below);
      return Positioned(
        left: left.toDouble(),
        width: width,
        top: opensUp ? null : rect.bottom,
        bottom: opensUp ? layout.overlaySize.height - rect.top : null,
        child: TextFieldTapRegion(
          child: Material(
            key: widget.surfaceKey,
            elevation: 4,
            color: AccountingTheme.of(context).card,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: height),
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context)
                    .copyWith(scrollbars: false),
                child: ListView.builder(
                  padding: const EdgeInsets.all(4),
                  shrinkWrap: true,
                  itemCount: widget.itemCount,
                  itemBuilder: widget.itemBuilder,
                ),
              ),
            ),
          ),
        ),
      );
    },
    child: const SizedBox.shrink(),
  );
}
