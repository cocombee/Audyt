import 'package:flutter/material.dart';

import 'accounting_color_library.dart';

// Shared content inset, measured from the Home metric card to its icon box.
const double accountingContentInset = 20;
// Outlined Flutter inputs paint text four pixels beyond contentPadding.
// The effective visible inset remains the shared 20px content line.
const double accountingFieldContentInset = accountingContentInset - 4;
// Balance-sheet text rows establish the compact rhythm for rows without
// intervening dividers. Record rows with dividers keep their own group.
const double accountingUndividedRowVerticalInset = 8;
// Text and amount/action pairs share the same compact in-group rhythm.
// The 20px content inset belongs outside each group.
const double accountingRecordInfoLineGap = 4;
// Banking's accepted item-name/status pair establishes the inline row gap.
const double accountingRecordTitleLabelGap = 12;
const double accountingRecordPriceActionGap = accountingRecordInfoLineGap;
const double accountingFieldLabelGap = 8;
const EdgeInsets accountingContentPadding = EdgeInsets.all(
  accountingContentInset,
);
const double accountingControlHeight = 44;
const double accountingSmallControlHeight = 32;
const double accountingControlFontSize = 13;
const double accountingMetricIconExtent = 42;
const double accountingMetricValueFontSize = 22;
// Keep the same visible label/value gap across two-line icon cards. A pixel of
// font rasterization slack lets the pair stay centered inside the 42px icon.
const double accountingMetricLineGap = 6;
const double accountingSmallControlFontSize = 12;
const double accountingControlRadius = 10;
const double accountingFocusedBorderWidth = 1.5;
const double accountingCheckboxBorderWidth = 1.5;
const double accountingCompactDateFieldWidth = 156;
const double accountingSmallRadius = 6;
// Icon buttons are rounded squares, distinct from ordinary input controls.
const double accountingSmallIconRadius = 10;
const double accountingIconRadius = 14;
const double accountingRecordIconGap = 8;
const double accountingRecordVisibleIconExtent = 14.5;
const double accountingSectionRadius = 20;

/// Sideways Details: measured labels, a colon and left-aligned facts.
/// Inherits the accepted record-card inset/rhythm without changing other rows.
final class AccountingSidewaysDetailsTokens {
  const AccountingSidewaysDetailsTokens._();

  static const horizontalInset = accountingContentInset;
  static const rowVerticalInset = accountingContentInset / 2;
  static const edgeVerticalInset = accountingContentInset;
  static const columnGap = 10.0;
  static EdgeInsets rowPadding(int index, int count) => EdgeInsets.only(
    top: index == 0 ? edgeVerticalInset : rowVerticalInset,
    bottom: index == count - 1 ? edgeVerticalInset : rowVerticalInset,
  );
  // Long labels wrap before consuming the value column at desktop minimum.
  static const maximumLabelWidth = 220.0;
  static const separator = ':';
}

/// Round charts measure spacing from their painted circumference. Legend text
/// may use free curved corners; square plot bounds do not own that clearance.
final class AccountingRoundChartTokens {
  const AccountingRoundChartTokens._();

  static const circumferenceClearance = accountingContentInset;
  static const cardPadding = EdgeInsets.all(circumferenceClearance);
}

/// Established popout geometry, shared by forms and fitted document previews.
final class AccountingPopoutTokens {
  const AccountingPopoutTokens._();

  // Shared content-width families. Custom callers declare their measured or
  // transactional width explicitly; they never inherit a field-count rule.
  static const dialogContentWidth = 400.0;
  static const normalContentWidth = 600.0;
  static const widerContentWidth = 728.0;
  static const customContentWidth = 1000.0;

  static double? contentWidthFor(AccountingPopoutWidthFamily family) =>
      switch (family) {
        AccountingPopoutWidthFamily.dialog => dialogContentWidth,
        AccountingPopoutWidthFamily.normal => normalContentWidth,
        AccountingPopoutWidthFamily.wider => widerContentWidth,
        AccountingPopoutWidthFamily.custom => null,
      };

  static const contentInset = 24.0;
  // The accepted ordinary popout keeps the painted Close circle inside the
  // same 20px content boundary, rather than against the rounded corner.
  static const closeInset = accountingContentInset;
  // Existing Material dialog screen clearance, shared with window growth.
  static const windowInsets = EdgeInsets.symmetric(
    horizontal: 40,
    vertical: 24,
  );
  static const titleBottomInset = 4.0;
  static const contentTopInset = 16.0;
  static const contentBottomInset = accountingContentInset;
  static const titleTrailingReserve = 40.0;

  static EdgeInsets titlePadding(double inset) =>
      EdgeInsets.fromLTRB(inset, closeInset, closeInset, titleBottomInset);
  static EdgeInsets contentPadding(double inset) =>
      EdgeInsets.fromLTRB(inset, contentTopInset, inset, contentBottomInset);
}

enum AccountingPopoutWidthFamily { dialog, normal, wider, custom }

/// Only declared ordinary-field popouts consume the row cap. Checkbox groups,
/// transactional lines, buttons, page bodies and embedded Settings are separate.
class AccountingPopoutWidthScope extends InheritedWidget {
  const AccountingPopoutWidthScope({
    super.key,
    required this.family,
    required super.child,
  });
  final AccountingPopoutWidthFamily family;
  static AccountingPopoutWidthFamily? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AccountingPopoutWidthScope>()
      ?.family;
  static int ordinaryFieldCap(BuildContext context) =>
      of(context) == AccountingPopoutWidthFamily.normal ? 2 : 4;
  @override
  bool updateShouldNotify(AccountingPopoutWidthScope oldWidget) =>
      oldWidget.family != family;
}

const double accountingSearchRadius = 12;
const Color accountingNeutralSurface = Color(0xFFF5F6F4);
const Color accountingNeutralHighlight = Color(0xFFF0F2EF);
const Color accountingLightTabBand = Color(0xFFE2E3E3);
// Half the opacity of Flutter's default black menu shadow, shared by popups.
const Color accountingMenuShadowColor = Color(0x80000000);

Color accountingTabBandColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
    ? accountingLightTabBand
    : AccountingTheme.of(context).muted;
const Duration accountingTooltipWaitDuration = Duration(milliseconds: 350);
const EdgeInsets accountingTooltipPadding = EdgeInsets.symmetric(
  horizontal: 8,
  vertical: 6,
);
final BoxDecoration accountingTooltipDecoration = BoxDecoration(
  color: Colors.black.withValues(alpha: 0.8),
  borderRadius: BorderRadius.circular(accountingControlRadius),
);

@immutable
class AccountingTokens extends ThemeExtension<AccountingTokens> {
  const AccountingTokens({
    required this.background,
    required this.foreground,
    required this.card,
    required this.cardForeground,
    required this.muted,
    required this.mutedForeground,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.secondaryForeground,
    required this.accent,
    required this.accentForeground,
    required this.destructive,
    required this.border,
    required this.input,
    required this.ring,
    required this.sidebar,
    required this.sidebarForeground,
    required this.sidebarPrimary,
    required this.sidebarPrimaryForeground,
    required this.sidebarAccent,
    required this.sidebarAccentForeground,
    required this.sidebarBorder,
    required this.sidebarRing,
  });

  static const light = AccountingTokens(
    // The note's light UI uses a quiet canvas behind white working surfaces.
    // Keep grouping and hierarchy intact while making surfaces distinguishable.
    background: accountingNeutralSurface,
    foreground: Color(0xFF4C4A4A),
    card: Color(0xFFFFFFFF),
    cardForeground: Color(0xFF4C4A4A),
    muted: accountingNeutralSurface,
    mutedForeground: Color(0xFF797979),
    primary: AccountingColorLibrary.primaryGreen,
    primaryForeground: Colors.white,
    secondary: accountingNeutralSurface,
    secondaryForeground: Color(0xFF4C4A4A),
    accent: accountingNeutralHighlight,
    accentForeground: Color(0xFF4C4A4A),
    destructive: AccountingColorLibrary.grapefruit,
    border: Color(0xFFEBEBEB),
    input: Color(0xFFEBEBEB),
    ring: Color(0xFFA3A3A3),
    sidebar: Color(0xFFFFFFFF),
    sidebarForeground: Color(0xFF4C4A4A),
    sidebarPrimary: AccountingColorLibrary.primaryGreen,
    sidebarPrimaryForeground: Colors.white,
    sidebarAccent: AccountingColorLibrary.primaryGreen,
    sidebarAccentForeground: Colors.white,
    sidebarBorder: Color(0xFFEBEBEB),
    sidebarRing: Color(0xFFA3A3A3),
  );

  static const dark = AccountingTokens(
    background: Color(0xFF252525),
    foreground: Color(0xFFF8F8F8),
    card: Color(0xFF333333),
    cardForeground: Color(0xFFF8F8F8),
    muted: Color(0xFF444444),
    mutedForeground: Color(0xFFB5B5B5),
    primary: AccountingColorLibrary.primaryGreen,
    primaryForeground: Colors.white,
    secondary: Color(0xFF444444),
    secondaryForeground: Color(0xFFF8F8F8),
    accent: Color(0xFF444444),
    accentForeground: Color(0xFFF8F8F8),
    destructive: AccountingColorLibrary.grapefruit,
    border: Color(0xFF5A5A5A),
    input: Color(0xFF626262),
    ring: Color(0xFF8A8A8A),
    sidebar: Color(0xFF333333),
    sidebarForeground: Color(0xFFF8F8F8),
    sidebarPrimary: AccountingColorLibrary.primaryGreen,
    sidebarPrimaryForeground: Colors.white,
    sidebarAccent: Color(0xFF444444),
    sidebarAccentForeground: Color(0xFFF8F8F8),
    sidebarBorder: Color(0xFF5A5A5A),
    sidebarRing: Color(0xFF8A8A8A),
  );

  final Color background;
  final Color foreground;
  final Color card;
  final Color cardForeground;
  final Color muted;
  final Color mutedForeground;
  final Color primary;
  final Color primaryForeground;
  final Color secondary;
  final Color secondaryForeground;
  final Color accent;
  final Color accentForeground;
  final Color destructive;
  final Color border;
  final Color input;
  final Color ring;
  final Color sidebar;
  final Color sidebarForeground;
  final Color sidebarPrimary;
  final Color sidebarPrimaryForeground;
  final Color sidebarAccent;
  final Color sidebarAccentForeground;
  final Color sidebarBorder;
  final Color sidebarRing;

  @override
  AccountingTokens copyWith({
    Color? background,
    Color? foreground,
    Color? card,
    Color? cardForeground,
    Color? muted,
    Color? mutedForeground,
    Color? primary,
    Color? primaryForeground,
    Color? secondary,
    Color? secondaryForeground,
    Color? accent,
    Color? accentForeground,
    Color? destructive,
    Color? border,
    Color? input,
    Color? ring,
    Color? sidebar,
    Color? sidebarForeground,
    Color? sidebarPrimary,
    Color? sidebarPrimaryForeground,
    Color? sidebarAccent,
    Color? sidebarAccentForeground,
    Color? sidebarBorder,
    Color? sidebarRing,
  }) {
    return AccountingTokens(
      background: background ?? this.background,
      foreground: foreground ?? this.foreground,
      card: card ?? this.card,
      cardForeground: cardForeground ?? this.cardForeground,
      muted: muted ?? this.muted,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      primary: primary ?? this.primary,
      primaryForeground: primaryForeground ?? this.primaryForeground,
      secondary: secondary ?? this.secondary,
      secondaryForeground: secondaryForeground ?? this.secondaryForeground,
      accent: accent ?? this.accent,
      accentForeground: accentForeground ?? this.accentForeground,
      destructive: destructive ?? this.destructive,
      border: border ?? this.border,
      input: input ?? this.input,
      ring: ring ?? this.ring,
      sidebar: sidebar ?? this.sidebar,
      sidebarForeground: sidebarForeground ?? this.sidebarForeground,
      sidebarPrimary: sidebarPrimary ?? this.sidebarPrimary,
      sidebarPrimaryForeground:
          sidebarPrimaryForeground ?? this.sidebarPrimaryForeground,
      sidebarAccent: sidebarAccent ?? this.sidebarAccent,
      sidebarAccentForeground:
          sidebarAccentForeground ?? this.sidebarAccentForeground,
      sidebarBorder: sidebarBorder ?? this.sidebarBorder,
      sidebarRing: sidebarRing ?? this.sidebarRing,
    );
  }

  @override
  AccountingTokens lerp(covariant AccountingTokens? other, double t) {
    if (other == null) {
      return this;
    }
    return AccountingTokens(
      background: Color.lerp(background, other.background, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardForeground: Color.lerp(cardForeground, other.cardForeground, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryForeground: Color.lerp(
        primaryForeground,
        other.primaryForeground,
        t,
      )!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      secondaryForeground: Color.lerp(
        secondaryForeground,
        other.secondaryForeground,
        t,
      )!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentForeground: Color.lerp(
        accentForeground,
        other.accentForeground,
        t,
      )!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      border: Color.lerp(border, other.border, t)!,
      input: Color.lerp(input, other.input, t)!,
      ring: Color.lerp(ring, other.ring, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      sidebarForeground: Color.lerp(
        sidebarForeground,
        other.sidebarForeground,
        t,
      )!,
      sidebarPrimary: Color.lerp(sidebarPrimary, other.sidebarPrimary, t)!,
      sidebarPrimaryForeground: Color.lerp(
        sidebarPrimaryForeground,
        other.sidebarPrimaryForeground,
        t,
      )!,
      sidebarAccent: Color.lerp(sidebarAccent, other.sidebarAccent, t)!,
      sidebarAccentForeground: Color.lerp(
        sidebarAccentForeground,
        other.sidebarAccentForeground,
        t,
      )!,
      sidebarBorder: Color.lerp(sidebarBorder, other.sidebarBorder, t)!,
      sidebarRing: Color.lerp(sidebarRing, other.sidebarRing, t)!,
    );
  }
}

final class AccountingTheme {
  AccountingTheme._();

  static AccountingTokens of(BuildContext context) {
    return Theme.of(context).extension<AccountingTokens>() ??
        AccountingTokens.light;
  }

  static ThemeData light() => _build(AccountingTokens.light, Brightness.light);

  static ThemeData dark() => _build(AccountingTokens.dark, Brightness.dark);

  static ThemeData _build(AccountingTokens tokens, Brightness brightness) {
    final colorScheme = brightness == Brightness.light
        ? ColorScheme.light(
            primary: tokens.primary,
            onPrimary: tokens.primaryForeground,
            secondary: tokens.secondary,
            onSecondary: tokens.secondaryForeground,
            error: tokens.destructive,
            onError: tokens.foreground,
            surface: tokens.background,
            onSurface: tokens.foreground,
            outline: tokens.input,
            outlineVariant: tokens.border,
            surfaceContainerHighest: tokens.muted,
          )
        : ColorScheme.dark(
            primary: tokens.primary,
            onPrimary: tokens.primaryForeground,
            secondary: tokens.secondary,
            onSecondary: tokens.secondaryForeground,
            error: tokens.destructive,
            onError: tokens.foreground,
            surface: tokens.background,
            onSurface: tokens.foreground,
            outline: tokens.input,
            outlineVariant: tokens.border,
            surfaceContainerHighest: tokens.muted,
          );

    const sansFallback = <String>[
      'Inter',
      'SF Pro Text',
      'SF Pro Display',
      'Arial',
      'Helvetica Neue',
      'Roboto',
      'sans-serif',
    ];
    final baseText = TextStyle(
      color: tokens.foreground,
      fontFamily: 'Inter',
      fontFamilyFallback: sansFallback,
      fontSize: accountingControlFontSize,
      height: 1.43,
    );
    final controlBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(accountingControlRadius),
      borderSide: BorderSide(color: tokens.input),
    );
    final helperTextStyle = baseText.copyWith(
      fontSize: accountingSmallControlFontSize,
      height: 1.3,
      fontWeight: FontWeight.w400,
      color: tokens.mutedForeground,
    );
    final tooltipTextStyle = helperTextStyle.copyWith(color: Colors.white);
    final controlDecoration = InputDecorationTheme(
      filled: true,
      fillColor: tokens.card,
      hoverColor: Colors.transparent,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: accountingFieldContentInset,
        vertical: 12,
      ),
      constraints: const BoxConstraints(minHeight: accountingControlHeight),
      border: controlBorder,
      enabledBorder: controlBorder,
      disabledBorder: controlBorder.copyWith(
        borderSide: BorderSide(color: tokens.input.withValues(alpha: 0.65)),
      ),
      focusedBorder: controlBorder.copyWith(
        borderSide: BorderSide(
          color: tokens.primary,
          width: accountingFocusedBorderWidth,
        ),
      ),
      errorBorder: controlBorder.copyWith(
        borderSide: BorderSide(color: tokens.destructive),
      ),
      focusedErrorBorder: controlBorder.copyWith(
        borderSide: BorderSide(color: tokens.destructive, width: 2),
      ),
      hintStyle: baseText.copyWith(
        fontSize: accountingControlFontSize,
        color: tokens.mutedForeground,
        letterSpacing: 0,
      ),
      helperStyle: helperTextStyle,
      errorStyle: helperTextStyle.copyWith(color: tokens.destructive),
      labelStyle: baseText.copyWith(
        fontSize: accountingControlFontSize,
        height: 1.33,
        fontWeight: FontWeight.w600,
        color: tokens.cardForeground,
      ),
    );
    final controlMenuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll<Color?>(tokens.card),
      surfaceTintColor: WidgetStatePropertyAll<Color?>(tokens.card),
      elevation: const WidgetStatePropertyAll<double>(6),
      shadowColor: const WidgetStatePropertyAll<Color>(
        accountingMenuShadowColor,
      ),
      side: WidgetStatePropertyAll<BorderSide>(
        BorderSide(color: tokens.border),
      ),
      shape: WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(accountingControlRadius),
        ),
      ),
      padding: const WidgetStatePropertyAll<EdgeInsets>(
        EdgeInsets.symmetric(vertical: 4),
      ),
    );

    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.background,
      hoverColor: brightness == Brightness.light
          ? accountingNeutralHighlight
          : Colors.white.withValues(alpha: 0.04),
      fontFamily: 'Inter',
      fontFamilyFallback: sansFallback,
      iconTheme: const IconThemeData(size: 18, weight: 300),
      textTheme: TextTheme(
        bodyLarge: baseText,
        bodyMedium: baseText,
        bodySmall: baseText.copyWith(
          fontSize: accountingControlFontSize,
          height: 1.3,
        ),
        labelLarge: baseText.copyWith(
          fontSize: 12,
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: baseText.copyWith(
          fontSize: accountingControlFontSize,
          height: 1.3,
        ),
        labelSmall: baseText.copyWith(fontSize: 11, height: 1.2),
        titleLarge: baseText.copyWith(
          fontSize: 16,
          height: 1.33,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: baseText.copyWith(
          fontSize: accountingControlFontSize,
          height: 1.43,
        ),
        titleSmall: baseText.copyWith(fontSize: 12, height: 1.33),
        headlineMedium: baseText.copyWith(
          fontSize: 30,
          height: 1.13,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.6,
        ),
        headlineSmall: baseText.copyWith(
          fontSize: 24,
          height: 1.17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
        displaySmall: baseText.copyWith(
          fontSize: 30,
          height: 1.13,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.6,
        ),
      ),
      useMaterial3: true,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: WidgetStateBorderSide.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return BorderSide.none;
          return BorderSide(
            color: states.contains(WidgetState.disabled)
                ? tokens.mutedForeground.withValues(alpha: 0.5)
                : tokens.foreground,
            width: accountingCheckboxBorderWidth,
          );
        }),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return Colors.transparent;
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused) ||
              states.contains(WidgetState.pressed)) {
            return tokens.primary.withValues(alpha: 0.12);
          }
          return Colors.transparent;
        }),
      ),
      inputDecorationTheme: controlDecoration,
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(accountingControlRadius),
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(accountingControlRadius),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(accountingControlRadius),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: tokens.card,
        surfaceTintColor: tokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(accountingSectionRadius),
          side: BorderSide(color: tokens.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        clipBehavior: Clip.antiAlias,
        backgroundColor: tokens.card,
        surfaceTintColor: tokens.card,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(accountingSectionRadius),
        ),
        titleTextStyle: baseText.copyWith(
          fontSize: 16,
          height: 1.33,
          fontWeight: FontWeight.w600,
          color: tokens.cardForeground,
        ),
        contentTextStyle: baseText.copyWith(
          fontSize: 12,
          height: 1.43,
          color: tokens.mutedForeground,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: controlDecoration,
        menuStyle: controlMenuStyle,
        textStyle: baseText.copyWith(fontSize: accountingControlFontSize),
      ),
      menuTheme: MenuThemeData(style: controlMenuStyle),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.card,
        surfaceTintColor: tokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(accountingControlRadius),
        ),
        elevation: 6,
        shadowColor: accountingMenuShadowColor,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: accountingTooltipWaitDuration,
        padding: accountingTooltipPadding,
        textStyle: tooltipTextStyle,
        decoration: accountingTooltipDecoration,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: accountingButtonHover(
          FilledButton.styleFrom(
            minimumSize: const Size(
              accountingControlHeight,
              accountingControlHeight,
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 11.2),
            backgroundColor: tokens.primary,
            foregroundColor: tokens.primaryForeground,
            disabledBackgroundColor: tokens.primary.withValues(alpha: 0.45),
            disabledForegroundColor: tokens.primaryForeground.withValues(
              alpha: 0.80,
            ),
            overlayColor: tokens.primaryForeground.withValues(alpha: 0.14),
            textStyle: baseText.copyWith(
              fontSize: accountingControlFontSize,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(accountingControlRadius),
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: accountingButtonHover(
          OutlinedButton.styleFrom(
            minimumSize: const Size(
              accountingControlHeight,
              accountingControlHeight,
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 9.8),
            foregroundColor: tokens.foreground,
            disabledForegroundColor: tokens.mutedForeground,
            side: BorderSide(color: tokens.input),
            overlayColor: tokens.accent,
            textStyle: baseText.copyWith(
              fontSize: accountingControlFontSize,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(accountingControlRadius),
            ),
          ),
          hoverColor: tokens.accent,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: accountingButtonHover(
          TextButton.styleFrom(
            minimumSize: const Size(
              accountingControlHeight,
              accountingControlHeight,
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            foregroundColor: tokens.foreground,
            disabledForegroundColor: tokens.mutedForeground,
            overlayColor: tokens.accent,
            textStyle: baseText.copyWith(
              fontSize: accountingControlFontSize,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(accountingControlRadius),
            ),
          ),
          hoverColor: tokens.accent,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: accountingButtonHover(
          IconButton.styleFrom(
            minimumSize: const Size(44, 44),
            maximumSize: const Size(44, 44),
            padding: EdgeInsets.zero,
            foregroundColor: tokens.foreground,
            disabledForegroundColor: tokens.mutedForeground,
            overlayColor: tokens.accent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(accountingControlRadius),
            ),
          ),
          hoverColor: tokens.accent,
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[tokens],
    );
  }
}

/// Subtle fill response for semantic and other controls that keep their
/// foreground on hover. Neutral buttons use their green hover treatment.
ButtonStyle accountingButtonHover(ButtonStyle style, {Color? hoverColor}) =>
    style.copyWith(
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return Colors.transparent;
        if (states.contains(WidgetState.pressed)) {
          return hoverColor ?? Colors.black.withValues(alpha: 0.08);
        }
        if (states.contains(WidgetState.hovered)) {
          return hoverColor ?? Colors.black.withValues(alpha: 0.04);
        }
        return Colors.transparent;
      }),
    );
