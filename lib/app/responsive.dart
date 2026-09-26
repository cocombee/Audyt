import 'dart:math' as math;

import 'package:flutter/material.dart';

enum AccountingWidthBand { compact, medium, expanded, wide }

enum AccountingNavigationMode { drawer, compactRail, extendedRail }

final class AccountingResponsive {
  AccountingResponsive._();

  static const compactMaxWidth = 600.0;
  static const expandedMinWidth = 960.0;
  static const wideMinWidth = 1280.0;
  static const compactRailWidth = 92.0;
  static const extendedRailMinWidth = 220.0;
  static const extendedRailMaxWidth = 270.0;
  static const extendedRailResizableMaxWidth = extendedRailMaxWidth * 1.3;
  static const navigationDividerWidth = 1.0;
  static const navigationDividerDragWidth = 8.0;
  static const drawerMaxWidth = 320.0;
  static const pageMaxWidth = 1280.0;
  static const recordExpenseMaxWidth = 720.0;
  static const cardMinWidth = 220.0;
  static const pageHeaderDescriptionMaxWidth = 760.0;
  static const fieldMinWidth = 240.0;
  static const sectionGap = 20.0;
  static const groupGap = 20.0;
  // Keep the page usable before reducing the desktop sidebar to its icon rail.
  // The page can then reflow its own sections only when their content and the
  // shared 20px gap no longer fit.
  static const desktopMainContentMinWidth = 620.0;
  static const actionGap = 8.0;
  static const titleSubtitleGap = 6.0;
  static const pageTitleOuterGap = 34.0;
  static const topBarTopInset = 18.0;
  static const topBarBottomInset = 8.0;
  static const tabStripTopInset = 8.0;

  static AccountingWidthBand widthBandFor(double width) {
    if (width < compactMaxWidth) {
      return AccountingWidthBand.compact;
    }
    if (width < expandedMinWidth) {
      return AccountingWidthBand.medium;
    }
    if (width < wideMinWidth) {
      return AccountingWidthBand.expanded;
    }
    return AccountingWidthBand.wide;
  }

  static AccountingNavigationMode navigationModeFor(
    double width, {
    double mainContentMinWidth = desktopMainContentMinWidth,
  }) {
    return width <
            extendedRailMinWidth + mainContentMinWidth + navigationDividerWidth
        ? AccountingNavigationMode.compactRail
        : AccountingNavigationMode.extendedRail;
  }

  static bool fitsWithContentGap(
    double availableWidth,
    Iterable<double> contentWidths,
  ) {
    final widths = contentWidths.toList();
    if (widths.isEmpty) return true;
    return availableWidth >=
        widths.reduce((sum, width) => sum + width) +
            groupGap * (widths.length - 1);
  }

  static int balancedColumnCount(
    double availableWidth,
    int itemCount, {
    double minItemWidth = cardMinWidth,
  }) {
    if (itemCount <= 0) return 0;
    final maximumColumns =
        ((availableWidth + groupGap) / (minItemWidth + groupGap)).floor().clamp(
          1,
          itemCount,
        );
    final rows = (itemCount / maximumColumns).ceil();
    return (itemCount / rows).ceil();
  }

  static double measuredTextWidth(
    BuildContext context,
    String text,
    TextStyle? style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  static double extendedRailWidthFor(
    double width, {
    double mainContentMinWidth = desktopMainContentMinWidth,
    double? preferredWidth,
  }) {
    final desiredWidth = (preferredWidth ?? extendedRailMaxWidth).clamp(
      extendedRailMinWidth,
      extendedRailResizableMaxWidth,
    );
    return math.min(
      desiredWidth,
      math.max(
        extendedRailMinWidth,
        width - mainContentMinWidth - navigationDividerWidth,
      ),
    );
  }

  static double navigationWidthFor(
    double width,
    AccountingNavigationMode mode, {
    double mainContentMinWidth = desktopMainContentMinWidth,
    double? preferredWidth,
  }) {
    return switch (mode) {
      AccountingNavigationMode.drawer => drawerWidthFor(width),
      AccountingNavigationMode.compactRail => compactRailWidth,
      AccountingNavigationMode.extendedRail => extendedRailWidthFor(
        width,
        mainContentMinWidth: mainContentMinWidth,
        preferredWidth: preferredWidth,
      ),
    };
  }

  static double drawerWidthFor(double availableWidth) {
    return math.min(drawerMaxWidth, math.max(0, availableWidth - 40));
  }

  static double pageInsetFor(double width) {
    return math.min(24, math.max(16, width * 0.025));
  }
}

/// Only controls that wrap within a page get the shorter inter-row gap.
/// Modal form spacing remains owned by its dialog design.
class AccountingPageControlScope extends InheritedWidget {
  const AccountingPageControlScope({super.key, required super.child});
  static bool active(BuildContext context) =>
      (context
                  .dependOnInheritedWidgetOfExactType<
                    AccountingPageControlScope
                  >() !=
              null ||
          ModalRoute.of(context) is PageRoute) &&
      ModalRoute.of(context) is! DialogRoute &&
      context.findAncestorWidgetOfExactType<Dialog>() == null &&
      context.findAncestorWidgetOfExactType<AlertDialog>() == null;
  static double runGapOf(BuildContext context) =>
      active(context) ? 10 : AccountingResponsive.groupGap;
  @override
  bool updateShouldNotify(AccountingPageControlScope oldWidget) => false;
}
