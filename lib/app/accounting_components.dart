import 'package:audyt/app/accounting_icons.dart';

import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'accounting_theme.dart';
import 'audyt_date_picker.dart';
import 'accounting_color_library.dart';
import 'field_guidance.dart';
import 'responsive.dart';
import '../core/dates/accounting_date.dart';

enum AccountingButtonVariant { primary, secondary, outline, ghost, destructive }

/// Compact paint keeps the original switch's pointer and keyboard target.
class AccountingSwitch extends StatelessWidget {
  const AccountingSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.alignment = Alignment.centerRight,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Transform.scale(
    scale: 0.65,
    alignment: alignment,
    transformHitTests: false,
    child: Switch.adaptive(
      value: value,
      onChanged: onChanged,
      activeTrackColor: AccountingTheme.of(context).primary,
      activeThumbColor: AccountingTheme.of(context).primaryForeground,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );
}

/// Retains the existing form row, merged switch semantics and label interaction.
class AccountingSwitchListTile extends StatelessWidget {
  const AccountingSwitchListTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final Widget title;

  /// Settings-only rhythm: a 40px row leaves 20px between compact track paint.
  /// Keep the native switch target and the label's pointer/keyboard interaction.
  final bool compact;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: compact ? 40 : null,
      minVerticalPadding: compact ? 0 : null,
      tileColor: Colors.transparent,
      hoverColor: Colors.transparent,
      title: title,
      enabled: onChanged != null,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: ExcludeFocus(
        child: AccountingSwitch(value: value, onChanged: onChanged),
      ),
    ),
  );
}

/// Record-row actions use the smaller button frame; other actions use 44px.
class AccountingButtonSizeScope extends InheritedWidget {
  const AccountingButtonSizeScope({super.key, required super.child});

  static bool isSmall(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountingButtonSizeScope>() !=
      null;

  @override
  bool updateShouldNotify(AccountingButtonSizeScope oldWidget) => false;
}

// Shared geometry for every white form control. Selectors and their temporary
// search fields deliberately use the same height, radius, and one-pixel frame.

/// All action frames share the field height. Compact only adjusts inner width.
class AccountingButtonGroup extends StatelessWidget {
  const AccountingButtonGroup({
    super.key,
    required this.child,
    this.compact = true,
    this.headerAction = false,
  });
  final Widget child;
  final bool compact;
  final bool headerAction;
  static bool isCompact(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_ButtonGroupScope>()
          ?.compact ??
      true;
  static bool isHeaderAction(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_ButtonGroupScope>()
          ?.headerAction ??
      false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final factor = compact ? 0.7 : 1.0;
    ButtonStyle size(ButtonStyle? style, double padding) =>
        (style ?? const ButtonStyle()).copyWith(
          minimumSize: WidgetStatePropertyAll(
            Size(accountingControlHeight, accountingControlHeight),
          ),
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: padding * factor),
          ),
        );
    return _ButtonGroupScope(
      compact: compact,
      headerAction: headerAction,
      child: Theme(
        data: theme.copyWith(
          filledButtonTheme: FilledButtonThemeData(
            style: size(theme.filledButtonTheme.style, 16),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: size(theme.outlinedButtonTheme.style, 14),
          ),
          textButtonTheme: TextButtonThemeData(
            style: size(theme.textButtonTheme.style, 10),
          ),
        ),
        child: child,
      ),
    );
  }
}

class _ButtonGroupScope extends InheritedWidget {
  const _ButtonGroupScope({
    required super.child,
    required this.compact,
    required this.headerAction,
  });
  final bool compact;
  final bool headerAction;
  @override
  bool updateShouldNotify(_ButtonGroupScope oldWidget) =>
      compact != oldWidget.compact || headerAction != oldWidget.headerAction;
}

/// Shared shadcn-style button factories. The returned Material button owns the
/// supplied key so existing route and test-facing keys remain stable.
final class AccountingButton {
  const AccountingButton._();

  /// App-wide Preview actions share the primary face and existing small eye.
  static Widget preview(
    BuildContext context, {
    required Key? key,
    required VoidCallback? onPressed,
    String label = 'Preview',
  }) => primary(
    context,
    key: key,
    onPressed: onPressed,
    leadingIcon: Icons.visibility_outlined,
    child: Text(label),
  );

  static Widget primary(
    BuildContext context, {
    required Key? key,
    required VoidCallback? onPressed,
    required Widget child,
    IconData? leadingIcon,
    IconData? trailingIcon,
    bool fullWidth = false,
  }) {
    return _button(
      context,
      key: key,
      variant: AccountingButtonVariant.primary,
      onPressed: onPressed,
      child: child,
      leadingIcon: leadingIcon,
      trailingIcon: trailingIcon,
      fullWidth: fullWidth,
    );
  }

  static Widget secondary(
    BuildContext context, {
    required Key? key,
    required VoidCallback? onPressed,
    required Widget child,
    IconData? leadingIcon,
    IconData? trailingIcon,
  }) {
    return _button(
      context,
      key: key,
      variant: AccountingButtonVariant.secondary,
      onPressed: onPressed,
      child: child,
      leadingIcon: leadingIcon,
      trailingIcon: trailingIcon,
    );
  }

  static Widget outline(
    BuildContext context, {
    required Key? key,
    required VoidCallback? onPressed,
    required Widget child,
    IconData? leadingIcon,
    IconData? trailingIcon,
  }) {
    return _button(
      context,
      key: key,
      variant: AccountingButtonVariant.outline,
      onPressed: onPressed,
      child: child,
      leadingIcon: leadingIcon,
      trailingIcon: trailingIcon,
    );
  }

  static Widget ghost(
    BuildContext context, {
    required Key? key,
    required VoidCallback? onPressed,
    required Widget child,
    IconData? leadingIcon,
    IconData? trailingIcon,
  }) {
    return _button(
      context,
      key: key,
      variant: AccountingButtonVariant.ghost,
      onPressed: onPressed,
      child: child,
      leadingIcon: leadingIcon,
      trailingIcon: trailingIcon,
    );
  }

  static Widget destructive(
    BuildContext context, {
    required Key? key,
    required VoidCallback? onPressed,
    required Widget child,
    IconData? leadingIcon,
    IconData? trailingIcon,
  }) {
    return _button(
      context,
      key: key,
      variant: AccountingButtonVariant.destructive,
      onPressed: onPressed,
      child: child,
      leadingIcon: leadingIcon,
      trailingIcon: trailingIcon,
    );
  }

  /// Secondary workflow actions retain semantic colour without primary emphasis.
  static Widget workflow(
    BuildContext context, {
    required Key? key,
    required VoidCallback? onPressed,
    required Widget child,
    Color? tone,
  }) {
    return Builder(
      builder: (context) {
        final color = tone ?? AccountingTheme.of(context).primary;
        final small = AccountingButtonSizeScope.isSmall(context);
        return OutlinedButton(
          key: key,
          onPressed: onPressed,
          style: accountingButtonHover(
            OutlinedButton.styleFrom(
              minimumSize: Size(
                0,
                small ? accountingSmallControlHeight : accountingControlHeight,
              ),
              padding: EdgeInsets.symmetric(horizontal: small ? 8 : 16),
              tapTargetSize: small ? MaterialTapTargetSize.shrinkWrap : null,
              foregroundColor: AccountingTheme.of(context).foreground,
              textStyle: AccountingTypography.button(context).copyWith(
                fontSize: small
                    ? accountingSmallControlFontSize
                    : accountingControlFontSize,
              ),
              backgroundColor: color.withValues(alpha: 0.12),
              side: BorderSide(color: color.withValues(alpha: 0.3)),
            ),
          ),
          child: child,
        );
      },
    );
  }

  static Widget iconOnly(
    BuildContext context, {
    required Key? key,
    required VoidCallback? onPressed,
    required IconData icon,
    required String tooltip,
    bool compact = false,
    String? iconAsset,
    double iconPaintedSizeAdjustment = 0,
    Color? tone,
  }) {
    return Builder(
      builder: (context) {
        final tokens = AccountingTheme.of(context);
        final size = compact || AccountingButtonSizeScope.isSmall(context)
            ? accountingSmallControlHeight
            : accountingControlHeight;
        final destructive =
            icon == Icons.delete_outline ||
            icon == Icons.delete_outline_rounded;
        final outlined =
            destructive ||
            icon == Icons.visibility_outlined ||
            icon == Icons.preview_outlined ||
            icon == Icons.edit_outlined ||
            icon == Icons.link_outlined ||
            icon == Icons.link_off_outlined ||
            icon == Icons.download_outlined ||
            icon == Icons.file_upload_outlined ||
            icon == Icons.checklist_outlined ||
            icon == Icons.history_outlined ||
            icon == Icons.restore ||
            icon == Icons.settings_outlined ||
            icon == Icons.call_received_outlined ||
            icon == Icons.attach_money ||
            icon == Icons.note_add_outlined ||
            icon == Icons.receipt_long ||
            icon == Icons.assignment_turned_in_outlined;
        final rowOutlined =
            iconAsset != null ||
            outlined ||
            icon == Icons.image_outlined ||
            icon == Icons.description_outlined ||
            icon == Icons.more_horiz ||
            icon == Icons.pause_outlined ||
            icon == Icons.play_arrow_outlined ||
            icon == Icons.check ||
            icon == Icons.check_circle_outline ||
            icon == Icons.undo ||
            icon == Icons.block ||
            icon == Icons.payment_outlined ||
            icon == Icons.close ||
            icon == Icons.close_rounded;
        final baseStyle = IconButton.styleFrom(
          foregroundColor: tone ?? tokens.foreground,
          disabledForegroundColor: tokens.mutedForeground,
          backgroundColor: tone != null
              ? tone.withValues(alpha: 0.12)
              : rowOutlined
              ? tokens.card
              : Colors.transparent,
          disabledBackgroundColor: tone != null
              ? tone.withValues(alpha: 0.12)
              : rowOutlined
              ? tokens.card
              : Colors.transparent,
          side: tone != null
              ? BorderSide(color: tone.withValues(alpha: 0.3))
              : rowOutlined
              ? BorderSide(color: tokens.input)
              : null,
          minimumSize: Size(size, size),
          maximumSize: Size(size, size),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              size == accountingSmallControlHeight
                  ? accountingSmallIconRadius
                  : accountingIconRadius,
            ),
          ),
        );
        final hoverStyle = destructive
            ? _filledButtonHover(
                baseStyle,
                fill: AccountingColorLibrary.grapefruitDeep,
                foreground: Colors.white,
              )
            : accountingButtonHover(
                baseStyle,
                hoverColor: tone?.withValues(alpha: 0.18) ?? tokens.accent,
              );
        final button = IconButton(
          key: key,
          onPressed: onPressed,
          constraints: BoxConstraints.tightFor(width: size, height: size),
          padding: EdgeInsets.zero,
          style: hoverStyle.copyWith(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: iconAsset != null
              ? Builder(
                  builder: (iconContext) => AccountingSmallAssetIcon(
                    iconAsset,
                    color: IconTheme.of(iconContext).color,
                    paintedSizeAdjustment: iconPaintedSizeAdjustment,
                  ),
                )
              : rowOutlined ||
                    tone != null ||
                    AccountingIcon.assets.containsKey(icon)
              ? Builder(
                  builder: (iconContext) => AccountingIcon.smallAction(
                    icon,
                    color: IconTheme.of(iconContext).color,
                  ),
                )
              : Icon(icon, size: 18),
        );
        final labelled = Semantics(button: true, label: tooltip, child: button);
        return Tooltip(message: tooltip, child: labelled);
      },
    );
  }

  static ButtonStyle selectorTriggerStyle(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    return accountingButtonHover(
      OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, accountingControlHeight),
        padding: const EdgeInsets.symmetric(horizontal: accountingContentInset),
        alignment: AlignmentDirectional.centerStart,
        foregroundColor: tokens.foreground,
        backgroundColor: tokens.card,
        disabledForegroundColor: tokens.mutedForeground,
        disabledBackgroundColor: tokens.muted,
        side: BorderSide(color: tokens.input),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(accountingControlRadius),
        ),
        textStyle: AccountingTypography.control(context),
        overlayColor: tokens.accent,
      ),
      hoverColor: tokens.accent,
    );
  }

  static ButtonStyle outlineStyle(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final textStyle = AccountingTypography.button(context);
    return accountingButtonHover(
      OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        foregroundColor: tokens.foreground,
        backgroundColor: tokens.card,
        disabledForegroundColor: tokens.mutedForeground,
        disabledBackgroundColor: tokens.card,
        side: BorderSide(color: tokens.input),
        overlayColor: tokens.accent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(accountingControlRadius),
        ),
        textStyle: textStyle,
      ),
      hoverColor: tokens.accent,
    );
  }

  static Widget compact(
    BuildContext context, {
    required Key? key,
    required VoidCallback? onPressed,
    required Widget child,
    IconData? leadingIcon,
    IconData? trailingIcon,
    String? semanticsLabel,
  }) {
    final tokens = AccountingTheme.of(context);
    final textStyle = AccountingTypography.button(context)
        .copyWith(fontSize: accountingSmallControlFontSize);
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(0, accountingSmallControlHeight),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      foregroundColor: tokens.foreground,
      disabledForegroundColor: tokens.mutedForeground,
      backgroundColor: Colors.transparent,
      disabledBackgroundColor: tokens.muted,
      side: BorderSide(color: tokens.input),
      overlayColor: tokens.accent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(accountingControlRadius),
      ),
      textStyle: textStyle,
    );
    final button = OutlinedButton(
      key: key,
      onPressed: onPressed,
      style: _neutralButtonGreenHover(style, tokens),
      child: _buttonContent(
        child,
        leadingIcon: leadingIcon,
        trailingIcon: trailingIcon,
        iconSize: 14,
        iconGap: 6,
      ),
    );
    if (semanticsLabel == null) return button;
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: semanticsLabel,
      child: button,
    );
  }

  static Widget _button(
    BuildContext context, {
    required Key? key,
    required AccountingButtonVariant variant,
    required VoidCallback? onPressed,
    required Widget child,
    IconData? leadingIcon,
    IconData? trailingIcon,
    bool fullWidth = false,
  }) {
    if ((variant == AccountingButtonVariant.outline ||
            variant == AccountingButtonVariant.ghost) &&
        leadingIcon == null &&
        trailingIcon == null &&
        child is Text &&
        (child.data == 'View' || child.data == 'Edit')) {
      final view = child.data == 'View';
      return iconOnly(
        context,
        key: key,
        onPressed: onPressed,
        icon: view ? Icons.visibility_outlined : Icons.edit_outlined,
        tooltip: view ? 'View' : 'Edit',
      );
    }
    return _AccountingButtonBuilder(
      actionKey: key,
      actionLabel: leadingIcon == null && trailingIcon == null && child is Text
          ? child.data
          : null,
      onPressed: onPressed,
      builder: (context) {
        final headerAction = AccountingButtonGroup.isHeaderAction(context);
        // Page/tab title actions own their existing primary face and text-only
        // content. This scope never changes ordinary toolbar or popout actions.
        final resolvedVariant =
            headerAction && variant != AccountingButtonVariant.destructive
            ? AccountingButtonVariant.primary
            : variant;
        final small = AccountingButtonSizeScope.isSmall(context);
        final compact = AccountingButtonGroup.isCompact(context);
        final factor = compact ? 0.7 : 1.0;
        // Ordinary bounded actions use the second-to-third content inset.
        // Small record actions retain their established variant padding.
        final primaryInset = small ? 16 * factor : accountingContentInset;
        final outlineInset = small
            ? accountingContentInset * factor
            : accountingContentInset;
        final height = small
            ? accountingSmallControlHeight
            : accountingControlHeight;
        final minimum = Size(height, height);
        final content = _buttonContent(
          child,
          leadingIcon: headerAction ? null : leadingIcon,
          trailingIcon: headerAction ? null : trailingIcon,
        );
        final tokens = AccountingTheme.of(context);
        final textStyle = AccountingTypography.button(context).copyWith(
          fontSize: small
              ? accountingSmallControlFontSize
              : accountingControlFontSize,
        );
        final style = switch (resolvedVariant) {
          AccountingButtonVariant.primary => FilledButton.styleFrom(
            minimumSize: minimum,
            padding: EdgeInsets.symmetric(
              horizontal: headerAction ? accountingContentInset : primaryInset,
            ),
            backgroundColor: tokens.primary,
            foregroundColor: tokens.primaryForeground,
            disabledBackgroundColor: tokens.primary.withValues(alpha: 0.45),
            disabledForegroundColor: tokens.primaryForeground.withValues(
              alpha: 0.80,
            ),
            overlayColor: tokens.primaryForeground.withValues(alpha: 0.14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(accountingControlRadius),
            ),
            textStyle: textStyle,
          ),
          AccountingButtonVariant.secondary => FilledButton.styleFrom(
            minimumSize: minimum,
            padding: EdgeInsets.symmetric(horizontal: primaryInset),
            backgroundColor: tokens.secondary,
            foregroundColor: tokens.secondaryForeground,
            disabledBackgroundColor: tokens.secondary.withValues(alpha: 0.55),
            disabledForegroundColor: tokens.mutedForeground,
            overlayColor: tokens.accent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(accountingControlRadius),
            ),
            textStyle: textStyle,
          ),
          AccountingButtonVariant.outline => OutlinedButton.styleFrom(
            minimumSize: minimum,
            padding: EdgeInsets.symmetric(horizontal: outlineInset),
            backgroundColor: tokens.card,
            disabledBackgroundColor: tokens.card,
            foregroundColor: tokens.foreground,
            disabledForegroundColor: tokens.mutedForeground,
            side: BorderSide(color: tokens.input),
            overlayColor: tokens.accent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(accountingControlRadius),
            ),
            textStyle: textStyle,
          ),
          AccountingButtonVariant.ghost => TextButton.styleFrom(
            minimumSize: minimum,
            padding: EdgeInsets.symmetric(horizontal: 10 * factor),
            foregroundColor: tokens.foreground,
            disabledForegroundColor: tokens.mutedForeground,
            overlayColor: tokens.accent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(accountingControlRadius),
            ),
            textStyle: textStyle,
          ),
          AccountingButtonVariant.destructive => FilledButton.styleFrom(
            minimumSize: minimum,
            padding: EdgeInsets.symmetric(horizontal: primaryInset),
            backgroundColor: AccountingColorLibrary.grapefruit,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AccountingColorLibrary.grapefruit
                .withValues(alpha: 0.25),
            disabledForegroundColor: tokens.foreground.withValues(alpha: 0.80),
            overlayColor: Colors.white.withValues(alpha: 0.14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(accountingControlRadius),
            ),
            textStyle: textStyle,
          ),
        };

        final interactiveStyle = (switch (resolvedVariant) {
          AccountingButtonVariant.secondary ||
          AccountingButtonVariant.outline ||
          AccountingButtonVariant.ghost => _neutralButtonGreenHover(
            style,
            tokens,
          ),
          _ => accountingButtonHover(style),
        }).copyWith(tapTargetSize: MaterialTapTargetSize.shrinkWrap);
        final button = switch (resolvedVariant) {
          AccountingButtonVariant.primary ||
          AccountingButtonVariant.secondary ||
          AccountingButtonVariant.destructive => FilledButton(
            key: key,
            onPressed: onPressed,
            style: interactiveStyle,
            child: content,
          ),
          AccountingButtonVariant.outline => OutlinedButton(
            key: key,
            onPressed: onPressed,
            style: interactiveStyle,
            child: content,
          ),
          AccountingButtonVariant.ghost => TextButton(
            key: key,
            onPressed: onPressed,
            style: interactiveStyle,
            child: content,
          ),
        };
        // Only an explicit owner exception (the authentication Google button)
        // fills its row. Ordinary buttons share field height, not field width.
        if (fullWidth) return SizedBox(width: double.infinity, child: button);
        return Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          heightFactor: 1,
          child: button,
        );
      },
    );
  }

  static Widget _buttonContent(
    Widget child, {
    IconData? leadingIcon,
    IconData? trailingIcon,
    double iconSize = 16,
    double iconGap = 8,
  }) {
    if (leadingIcon == null && trailingIcon == null) {
      return child;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (leadingIcon != null) ...<Widget>[
          Builder(
            builder: (iconContext) => AccountingButtonIcon(
              leadingIcon,
              size: iconSize,
              color: IconTheme.of(iconContext).color,
            ),
          ),
          SizedBox(width: iconGap),
        ],
        Flexible(fit: FlexFit.loose, child: child),
        if (trailingIcon != null) ...<Widget>[
          SizedBox(width: iconGap),
          Builder(
            builder: (iconContext) => AccountingButtonIcon(
              trailingIcon,
              size: iconSize,
              color: IconTheme.of(iconContext).color,
            ),
          ),
        ],
      ],
    );
  }
}

ButtonStyle _neutralButtonGreenHover(
  ButtonStyle style,
  AccountingTokens tokens,
) => _filledButtonHover(
  style,
  fill: tokens.primary,
  foreground: tokens.primaryForeground,
);

ButtonStyle _filledButtonHover(
  ButtonStyle style, {
  required Color fill,
  required Color foreground,
}) {
  bool active(Set<WidgetState> states) =>
      !states.contains(WidgetState.disabled) &&
      (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.pressed));

  return style.copyWith(
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) =>
          active(states) ? fill : style.backgroundColor?.resolve(states),
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) =>
          active(states) ? foreground : style.foregroundColor?.resolve(states),
    ),
    side: style.side == null
        ? null
        : WidgetStateProperty.resolveWith(
            (states) => active(states)
                ? BorderSide(color: fill)
                : style.side?.resolve(states),
          ),
    overlayColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.pressed) &&
              !states.contains(WidgetState.disabled)
          ? foreground.withValues(alpha: 0.14)
          : Colors.transparent,
    ),
  );
}

final class AccountingAddButton {
  const AccountingAddButton._();

  static Widget build(
    BuildContext context, {
    required Key? key,
    // Keep the public named argument while formatting only its display getter.
    required String label,
    required VoidCallback? onPressed,
  }) {
    return AccountingButton.secondary(
      context,
      key: key,
      onPressed: onPressed,
      leadingIcon: Icons.add_rounded,
      child: Text(label),
    );
  }

  static Widget compact(
    BuildContext context, {
    required Key? key,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return AccountingButtonSizeScope(
      child: Builder(
        builder: (buttonContext) => AccountingButton.workflow(
          buttonContext,
          key: key,
          onPressed: onPressed,
          child: Text(label),
        ),
      ),
    );
  }
}

final class AccountingTypography {
  const AccountingTypography._();

  static TextStyle button(BuildContext context) => Theme.of(context)
      .textTheme
      .bodyMedium!
      .copyWith(
        fontSize: accountingControlFontSize,
        fontWeight: FontWeight.w600,
      );

  /// Input and selector values stay regular; field titles carry the emphasis.
  static TextStyle control(BuildContext context) {
    return controlValue(context);
  }

  static TextStyle pageTitle(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.headlineMedium!.copyWith(
      color: AccountingTheme.of(context).foreground,
      fontWeight: FontWeight.w600,
      fontSize: 22,
      letterSpacing: -0.5,
    );
  }

  static TextStyle sectionTitle(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.titleLarge!.copyWith(
      color: AccountingTheme.of(context).cardForeground,
      fontWeight: FontWeight.w500,
      fontSize: 16,
    );
  }

  // Sidebar items and tabs share typography and selected semibold emphasis.
  static TextStyle navigation(BuildContext context, {bool selected = false}) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontSize: accountingControlFontSize,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: selected
            ? AccountingTheme.of(context).foreground
            : AccountingTheme.of(context).mutedForeground,
      );

  static TextStyle fieldLabel(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.labelLarge!.copyWith(
      color: AccountingTheme.of(context).cardForeground,
      fontSize: accountingControlFontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    );
  }

  /// Ordinary column headers retain the Recent Expenses treatment.
  static TextStyle tableHeader(BuildContext context) => Theme.of(context)
      .textTheme
      .bodySmall!
      .copyWith(
        color: AccountingTheme.of(context).mutedForeground,
        fontWeight: FontWeight.w600,
      );

  /// Fact labels share the accepted column-header typography.
  static TextStyle sidewaysDetailsLabel(BuildContext context) =>
      tableHeader(context);

  static TextStyle value(BuildContext context) {
    return Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: AccountingTheme.of(context).foreground,
      fontWeight: FontWeight.w400,
    );
  }

  static TextStyle controlValue(BuildContext context) =>
      value(context).copyWith(fontSize: accountingControlFontSize);

  static TextStyle helper(BuildContext context) {
    return Theme.of(context).textTheme.bodySmall!.copyWith(
      color: AccountingTheme.of(context).mutedForeground,
      fontWeight: FontWeight.w400,
      fontSize: accountingSmallControlFontSize,
      height: 1.25,
    );
  }

  static TextStyle tooltip(BuildContext context) {
    return helper(context).copyWith(
      color: Theme.of(context).brightness == Brightness.light
          ? Colors.white
          : Colors.black,
    );
  }
}

Text accountingPageTitle(BuildContext context, String text, {Key? key}) {
  return Text(
    accountingTitleCase(text),
    key: key,
    style: AccountingTypography.pageTitle(context),
  );
}

Text accountingSectionTitle(BuildContext context, String text, {Key? key}) {
  return Text(
    accountingTitleCase(text),
    key: key,
    style: AccountingTypography.sectionTitle(context),
  );
}

/// Existing chart-legend colour mark, shared with colour selector options.
/// Its painted size follows the ordinary value text rather than action icons.
double accountingColourIndicatorExtent(BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(text: 'Ag', style: Theme.of(context).textTheme.bodyMedium),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final extent = painter.height * 0.9;
  painter.dispose();
  return extent;
}

class AccountingColourIndicator extends StatelessWidget {
  const AccountingColourIndicator({super.key, required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: accountingColourIndicatorExtent(context),
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

/// Width of the complete single-line label, including its actual adornments.
/// Field owners take max(content width, this width), without adding input chrome
/// to the title. Untitled controls retain their own sizing contracts.
double accountingFieldLabelMinimumWidth(
  BuildContext context,
  String text, {
  bool alignToField = false,
  String? guidance,
  bool? hasGuidance,
}) {
  final required = text.trimRight().endsWith(' *');
  final title = required
      ? text.trimRight().substring(0, text.trimRight().length - 2)
      : text;
  final width = AccountingResponsive.measuredTextWidth(
    context,
    accountingTitleCase(title),
    AccountingTypography.fieldLabel(context),
  );
  final markerWidth = required
      ? AccountingResponsive.measuredTextWidth(
              context,
              '*',
              AccountingTypography.fieldLabel(context),
            ) +
            4
      : 0.0;
  final help =
      hasGuidance == true ||
      (guidance ?? accountingFieldGuidance(text)) != null;
  return width +
      markerWidth +
      (help ? 24 : 0) +
      (alignToField ? 0 : accountingContentInset);
}

Widget accountingFieldLabel(
  BuildContext context,
  String text, {
  Key? key,
  bool alignToField = false,
  String? guidance,
}) {
  final help = guidance ?? accountingFieldGuidance(text);
  final required = text.trimRight().endsWith(' *');
  final title = required
      ? text.trimRight().substring(0, text.trimRight().length - 2)
      : text;
  return ConstrainedBox(
    key: key,
    constraints: const BoxConstraints(minHeight: 20),
    child: Padding(
      padding: EdgeInsets.only(left: alignToField ? 0 : accountingContentInset),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              accountingTitleCase(title),
              style: AccountingTypography.fieldLabel(context),
            ),
          ),
          if (required) ...[
            const SizedBox(width: 4),
            Text(
              '*',
              style: AccountingTypography.fieldLabel(context)
                  .copyWith(color: AccountingTheme.of(context).destructive),
            ),
          ],
          if (help != null) ...[
            const SizedBox(width: 4),
            AccountingFieldHelp(label: text, message: help),
          ],
        ],
      ),
    ),
  );
}

class AccountingFieldHelp extends StatefulWidget {
  const AccountingFieldHelp({
    super.key,
    required this.label,
    required this.message,
  });
  final String label, message;
  static const messageConstraints = BoxConstraints(maxWidth: 300);
  @override
  State<AccountingFieldHelp> createState() => _AccountingFieldHelpState();
}

class _AccountingFieldHelpState extends State<AccountingFieldHelp> {
  final _tooltip = GlobalKey<TooltipState>();
  @override
  Widget build(BuildContext context) => Tooltip(
    key: _tooltip,
    message: widget.message,
    constraints: AccountingFieldHelp.messageConstraints,
    child: IconButton(
      onPressed: () {
        // Accessibility/keyboard activation does not emit the pointer event
        // that normally dismisses previously opened tooltips.
        Tooltip.dismissAllToolTips();
        _tooltip.currentState?.ensureTooltipVisible();
      },
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 20, height: 20),
      style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      icon: Icon(
        Icons.help_outline,
        size: 14,
        color: AccountingTheme.of(context).mutedForeground,
        semanticLabel: 'Help for ${widget.label}',
      ),
    ),
  );
}

/// Compact tab group with a persistent selected surface and native keyboard
/// navigation. The same owner is used across the accounting workspace sections.
String accountingNotificationCountLabel(int count) =>
    count > 99 ? '99+' : '$count';

class AccountingTabs extends StatefulWidget {
  const AccountingTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    required this.keyPrefix,
    this.notificationCounts = const {},
    this.embedded = false,
  });
  final bool embedded;
  final List<String> labels;
  final Map<String, int> notificationCounts;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final String keyPrefix;
  @override
  State<AccountingTabs> createState() => _AccountingTabsState();
}

class _AccountingTabsState extends State<AccountingTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(
    length: widget.labels.length,
    initialIndex: widget.selectedIndex,
    vsync: this,
  )..addListener(_changed);
  void _changed() {
    if (_controller.index != widget.selectedIndex) {
      widget.onChanged(_controller.index);
    }
  }

  @override
  void didUpdateWidget(covariant AccountingTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.index != widget.selectedIndex) {
      _controller.animateTo(widget.selectedIndex);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final counts = [
      for (final label in widget.labels) widget.notificationCounts[label] ?? 0,
    ];
    final badgeTextStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(fontWeight: FontWeight.w600);
    final widths = List<double>.generate(widget.labels.length, (index) {
      final painter = TextPainter(
        text: TextSpan(
          text: widget.labels[index],
          style: AccountingTypography.navigation(context, selected: true),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      var width = painter.width + 32;
      if (counts[index] > 0) {
        final badgePainter = TextPainter(
          text: TextSpan(
            text: accountingNotificationCountLabel(counts[index]),
            style: badgeTextStyle,
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        // Keep 16px on both outer sides, 8px between label and badge, and
        // the same 6px inner badge padding used in the sidebar.
        width += 8 + (badgePainter.width + 12).clamp(20.0, double.infinity);
      }
      return width;
    });
    final bar = TabBar(
      controller: _controller,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      // Compact tab buttons retain their established nested spacing.
      // Only the grey band's outer edge participates in page alignment.
      padding: const EdgeInsets.all(2),
      dividerHeight: 0,
      indicatorSize: TabBarIndicatorSize.tab,
      indicatorPadding: EdgeInsets.zero,
      indicator: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(accountingControlRadius),
        border: Border.all(color: tokens.input),
      ),
      labelColor: tokens.foreground,
      unselectedLabelColor: tokens.mutedForeground,
      labelStyle: AccountingTypography.navigation(context, selected: true),
      // Menu labels share the sidebar's regular/semibold state treatment.
      unselectedLabelStyle: AccountingTypography.navigation(context),
      labelPadding: EdgeInsets.symmetric(horizontal: 0),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      splashBorderRadius: BorderRadius.circular(accountingControlRadius),
      tabs: [
        for (var i = 0; i < widget.labels.length; i++)
          Tab(
            key: ValueKey('${widget.keyPrefix}-$i'),
            height: accountingControlHeight,
            child: SizedBox(
              width: widths[i],
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.labels[i]),
                    if (counts[i] > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        constraints: const BoxConstraints(minWidth: 20),
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tokens.primary,
                          borderRadius: BorderRadius.circular(
                            accountingControlRadius,
                          ),
                        ),
                        child: Text(
                          accountingNotificationCountLabel(counts[i]),
                          style: badgeTextStyle?.copyWith(
                            color: tokens.primaryForeground,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(accountingControlRadius),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(accountingControlRadius),
          child: SizedBox(
            width: widths.fold<double>(4, (sum, width) => sum + width),
            child: ColoredBox(
              color: accountingTabBandColor(context),
              child: bar,
            ),
          ),
        ),
      ),
    );
  }
}

Text accountingValueText(
  BuildContext context,
  String text, {
  Key? key,
  int? maxLines,
}) {
  return Text(
    text,
    key: key,
    maxLines: maxLines,
    softWrap: true,
    style: AccountingTypography.value(context),
  );
}

Text accountingHelperText(BuildContext context, String text, {Key? key}) {
  return Text(
    text,
    key: key,
    softWrap: true,
    textHeightBehavior: const TextHeightBehavior(
      applyHeightToFirstAscent: false,
      applyHeightToLastDescent: false,
    ),
    style: AccountingTypography.helper(context)
        .copyWith(height: 17 / accountingSmallControlFontSize),
  );
}

Widget accountingFieldHelper(
  BuildContext context,
  String text, {
  Key? key,
  double top = 8,
}) => Padding(
  key: key,
  padding: EdgeInsets.only(top: top),
  child: accountingHelperText(context, text),
);

/// Shared two-tone progress bar. Both the neutral base and the coloured
/// progress segment use the same rounded ends.
class AccountingProgressBar extends StatelessWidget {
  // Measured from the multicolour expense bars: one text-to-bar gap and one
  // gap between adjacent, undivided bar rows for every progress-bar group.
  static const double labelGap = 4;
  static const double rowGap = 12;

  const AccountingProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 8,
  });
  final double value;
  final Color color;
  final double height;
  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: LinearProgressIndicator(
          value: value.clamp(0, 1),
          backgroundColor: tokens.muted,
          color: color,
          minHeight: height,
        ),
      ),
    );
  }
}

InputDecoration accountingInputDecoration(
  BuildContext context, {
  String? helperText,
  String? errorText,
  String? hintText,
  String? prefixText,
  Key? prefixKey,
  Widget? suffixIcon,
  bool alignLabelWithHint = false,
}) {
  final tokens = AccountingTheme.of(context);
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(accountingControlRadius),
    borderSide: BorderSide(color: tokens.input),
  );
  final focusedBorder = border.copyWith(
    borderSide: BorderSide(
      color: tokens.primary,
      width: accountingFocusedBorderWidth,
    ),
  );
  final errorBorder = border.copyWith(
    borderSide: BorderSide(color: tokens.destructive),
  );
  return InputDecoration(
    helper: helperText == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              helperText,
              style: AccountingTypography.helper(context),
            ),
          ),
    errorText: errorText,
    hintText: hintText,
    hintStyle: AccountingTypography.controlValue(context)
        .copyWith(color: tokens.mutedForeground),
    helperMaxLines: 2,
    errorMaxLines: 3,
    prefixIcon: prefixText == null
        ? null
        : Padding(
            key: prefixKey,
            padding: EdgeInsets.only(
              left: accountingFieldContentInset,
              right: accountingFieldContentInset,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  prefixText,
                  style: AccountingTypography.value(context).copyWith(
                    color: tokens.mutedForeground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: accountingContentInset),
                Container(width: 1, height: 20, color: tokens.input),
              ],
            ),
          ),
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 44),
    suffixIcon: suffixIcon,
    suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    filled: true,
    fillColor: AccountingTheme.of(context).card,
    hoverColor: Colors.transparent,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: accountingFieldContentInset,
      vertical: 12,
    ),
    constraints: const BoxConstraints(minHeight: accountingControlHeight),
    border: border,
    enabledBorder: border,
    disabledBorder: border.copyWith(
      borderSide: BorderSide(color: tokens.input.withValues(alpha: 0.65)),
    ),
    focusedBorder: focusedBorder,
    errorBorder: errorBorder,
    focusedErrorBorder: errorBorder.copyWith(
      borderSide: BorderSide(color: tokens.destructive, width: 2),
    ),
    alignLabelWithHint: alignLabelWithHint,
    labelStyle: AccountingTypography.fieldLabel(context),
    helperStyle: AccountingTypography.helper(context),
    errorStyle: AccountingTypography.helper(context)
        .copyWith(color: tokens.destructive),
  );
}

/// A single-line text field with the same 44px painted frame as selectors.
InputDecoration accountingSingleLineInputDecoration(
  BuildContext context, {
  String? hintText,
  String? prefixText,
}) {
  return accountingInputDecoration(
    context,
    hintText: hintText,
    prefixText: prefixText,
  ).copyWith(
    constraints: const BoxConstraints.tightFor(height: accountingControlHeight),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: accountingFieldContentInset,
      vertical: 12,
    ),
  );
}

/// Calendar affordance shared by editable DD-MM-YYYY fields.
Widget accountingDateFieldFrame({required Widget child}) =>
    SizedBox(width: double.infinity, child: child);

/// Keeps a small secondary hover surface centred on the painted icon. The
/// surrounding control retains its established hit target and layout bounds.
class AccountingMinorHoverHalo extends StatelessWidget {
  const AccountingMinorHoverHalo({
    super.key,
    required this.highlighted,
    required this.child,
    this.dimension = 28,
  });

  final double dimension;
  final bool highlighted;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: highlighted
          ? AccountingTheme.of(context).primary.withValues(alpha: 0.12)
          : Colors.transparent,
      shape: BoxShape.circle,
    ),
    child: SizedBox.square(
      dimension: dimension,
      child: Center(child: child),
    ),
  );
}

class AccountingMinorHoverRegion extends StatefulWidget {
  const AccountingMinorHoverRegion({super.key, required this.builder});
  final Widget Function(BuildContext context, bool highlighted) builder;

  @override
  State<AccountingMinorHoverRegion> createState() =>
      _AccountingMinorHoverRegionState();
}

class _AccountingMinorHoverRegionState
    extends State<AccountingMinorHoverRegion> {
  bool _highlighted = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _highlighted = true),
    onExit: (_) => setState(() => _highlighted = false),
    child: widget.builder(context, _highlighted),
  );
}

Widget accountingCalendarButton(
  BuildContext context, {
  required TextEditingController controller,
  required String label,
  bool enabled = true,
  VoidCallback? onPicked,
  DateTime? firstDate,
  DateTime? lastDate,
  String? helpText,
}) => Semantics(
  button: true,
  label: 'Choose $label',
  child: AccountingMinorHoverRegion(
    builder: (context, highlighted) => IconButton(
      key: ValueKey(
        'calendar-button-${label.toLowerCase().replaceAll(' ', '-')}',
      ),
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: EdgeInsets.zero,
      style:
          IconButton.styleFrom(
            minimumSize: const Size(44, 44),
            maximumSize: const Size(44, 44),
          ).copyWith(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            splashFactory: NoSplash.splashFactory,
          ),
      // Keep the 44px hit target, but place the painted icon on the same 20px
      // right content line as the date text has on the left.
      icon: ExcludeSemantics(
        child: Transform.translate(
          // Keep the original painted right edge while reducing the icon by 15%.
          offset: const Offset(-4.8, 0),
          child: AccountingMinorHoverHalo(
            highlighted: highlighted,
            child: const AccountingIcon(
              Icons.calendar_today_outlined,
              size: 13.6,
            ),
          ),
        ),
      ),
      onPressed: !enabled
          ? null
          : () async {
              controller.selection = TextSelection.collapsed(
                offset: controller.text.length,
              );
              FocusScope.of(context).unfocus();
              final picked = await showAudytDatePicker(
                context: context,
                initialDate:
                    parseAccountingInputDate(controller.text) ?? DateTime.now(),
                firstDate: firstDate ?? DateTime(1900),
                lastDate: lastDate ?? DateTime(2200),
                helpText: accountingDatePickerHelpText(context, helpText),
              );
              if (picked == null || !context.mounted) return;
              final text = formatAccountingInputDate(picked);
              controller.value = TextEditingValue(
                text: text,
                selection: TextSelection.collapsed(offset: text.length),
              );
              onPicked?.call();
            },
    ),
  ),
);

String? accountingDatePickerHelpText(BuildContext context, String? helpText) {
  if (MediaQuery.orientationOf(context) != Orientation.landscape) {
    return helpText;
  }
  // Flutter fixes the landscape header at 16px from the dialog edge. Give
  // its help label extra clearance from the rounded top-left corner.
  return '\u2002\u2009${helpText ?? MaterialLocalizations.of(context).datePickerHelpText}';
}

final class AccountingCard {
  const AccountingCard._();

  static Card surface(
    BuildContext context, {
    required Widget child,
    Key? key,
    EdgeInsetsGeometry? margin,
    Clip clipBehavior = Clip.none,
  }) {
    final tokens = AccountingTheme.of(context);
    return Card(
      key: key,
      margin: margin ?? EdgeInsets.zero,
      elevation: 0,
      color: tokens.card,
      surfaceTintColor: tokens.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(accountingSectionRadius),
        side: BorderSide(color: tokens.border),
      ),
      clipBehavior: clipBehavior,
      child: child,
    );
  }
}

final class AccountingBadge {
  const AccountingBadge._();

  static const _padding = EdgeInsets.symmetric(horizontal: 8, vertical: 2);

  static TextStyle? _labelStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .labelSmall
      ?.copyWith(
        color: AccountingTheme.of(context).foreground,
        fontWeight: FontWeight.w600,
      );

  /// Measure the same label and chrome that the existing badge paints.
  static double measuredWidth(BuildContext context, String label) =>
      AccountingResponsive.measuredTextWidth(
        context,
        accountingTitleCase(label),
        _labelStyle(context) ?? DefaultTextStyle.of(context).style,
      ) +
      _padding.horizontal;

  static Widget build(
    BuildContext context, {
    required String label,
    Key? key,
    AccountingButtonVariant variant = AccountingButtonVariant.secondary,
  }) {
    final tokens = AccountingTheme.of(context);
    final state = label.toLowerCase();
    final background =
        state.contains('awaiting reconciliation') ||
            state == 'awaiting approval'
        ? const Color(0xfffff3d8)
        : state == 'ready' ||
              state == 'active' ||
              state == 'paid' ||
              state == 'connected' ||
              state == 'matched' ||
              state.contains('approved') ||
              state.contains('complete') ||
              state.contains('reconcil')
        ? tokens.primary.withValues(alpha: 0.12)
        : state.contains('inactive') ||
              state.contains('overdue') ||
              state.contains('reject') ||
              state.contains('declin') ||
              state.contains('fail') ||
              state.contains('void') ||
              state.contains('cancel')
        ? const Color(0xfffceae6)
        : state.contains('unpaid') ||
              state.contains('partially') ||
              state.contains('pending') ||
              state.contains('review') ||
              state.contains('due') ||
              state.contains('soon') ||
              state.contains('hold') ||
              state.contains('return')
        ? const Color(0xfffff3d8)
        : tokens.muted;
    return Container(
      key: key,
      constraints: const BoxConstraints(minHeight: 18),
      padding: _padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        accountingTitleCase(label),
        softWrap: true,
        textAlign: TextAlign.center,
        style: _labelStyle(context),
      ),
    );
  }
}

/// A full-size hit target whose visible checkbox stays on the content axis.
class AccountingLeadingCheckbox extends StatelessWidget {
  const AccountingLeadingCheckbox({
    super.key,
    this.hitKey,
    this.checkboxKey,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.undividedRow = false,
  });

  final Key? hitKey;
  final Key? checkboxKey;
  final bool value;
  final ValueChanged<bool?>? onChanged;
  final String? semanticLabel;

  /// Compact text rows share the Recent Expenses rhythm. Keep the painted
  /// square centered with the text and 20px clear of its right-hand text edge.
  final bool undividedRow;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: undividedRow ? 18 + accountingContentInset : accountingControlHeight,
    height: undividedRow ? 18 : accountingControlHeight,
    child: InkWell(
      key: hitKey,
      excludeFromSemantics: true,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SizedBox.square(
          dimension: 18,
          child: Transform.translate(
            // The two-line text group starts at the row's top content inset;
            // align the visible checkbox to its centre without moving text.
            offset: undividedRow ? Offset.zero : const Offset(0, -3),
            child: Checkbox(
              key: checkboxKey,
              value: value,
              onChanged: onChanged,
              semanticLabel: semanticLabel,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
      ),
    ),
  );
}

final class AccountingBreadcrumb {
  const AccountingBreadcrumb._();

  static Widget build(
    BuildContext context, {
    required String root,
    required String current,
  }) {
    final tokens = AccountingTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: 'Breadcrumb: $root / $current',
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: <Widget>[
          Text(
            root,
            style: textTheme.bodySmall?.copyWith(
              color: tokens.mutedForeground,
              fontWeight: FontWeight.w500,
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 14,
            color: tokens.mutedForeground,
          ),
          Text(
            current,
            style: textTheme.bodySmall?.copyWith(
              color: tokens.foreground,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

enum AccountingAlertTone { positive, warning, critical }

final class AccountingAlert {
  const AccountingAlert._();

  static Widget build(
    BuildContext context, {
    required String title,
    required String description,
    Key? key,
    bool destructive = false,
    AccountingAlertTone tone = AccountingAlertTone.positive,
    Widget? action,
    double topGap = 0,
    double bottomGap = 0,
  }) {
    final tokens = AccountingTheme.of(context);
    final effectiveTone = destructive ? AccountingAlertTone.critical : tone;
    final (
      background,
      foreground,
      iconFill,
      iconForeground,
      icon,
    ) = switch (effectiveTone) {
      AccountingAlertTone.positive => (
        tokens.primary.withValues(alpha: 0.12),
        const Color(0xFF28704F),
        tokens.primary,
        Colors.white,
        Icons.info_rounded,
      ),
      AccountingAlertTone.warning => (
        const Color(0xFFFFF6E2),
        const Color(0xFF8B5E00),
        AccountingColorLibrary.sunflowerDeep,
        Colors.white,
        Icons.warning_rounded,
      ),
      AccountingAlertTone.critical => (
        const Color(0xFFFCEAE6),
        tokens.destructive,
        tokens.destructive,
        Colors.white,
        Icons.error_rounded,
      ),
    };
    final surface = Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $description',
      child: Container(
        key: effectiveTone == AccountingAlertTone.warning ? null : key,
        width: double.infinity,
        padding: accountingContentPadding,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(accountingSectionRadius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconFill,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: effectiveTone == AccountingAlertTone.warning
                    ? Transform.translate(
                        offset: const Offset(0.25, 0),
                        child: AccountingIcon(
                          icon,
                          size: 18,
                          color: iconForeground,
                        ),
                      )
                    : AccountingIcon(icon, size: 18, color: iconForeground),
              ),
            ),
            const SizedBox(width: accountingContentInset),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title.endsWith('.') ? title : accountingTitleCase(title),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: AccountingTypography.helper(context)
                        .copyWith(color: foreground),
                  ),
                  if (action != null) ...<Widget>[
                    const SizedBox(height: 8),
                    action,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return effectiveTone == AccountingAlertTone.warning
        ? AccountingTransientWarning(
            key: key,
            identity: '$title|$description',
            topGap: topGap,
            bottomGap: bottomGap,
            child: surface,
          )
        : topGap == 0 && bottomGap == 0
        ? surface
        : Padding(
            padding: EdgeInsets.only(top: topGap, bottom: bottomGap),
            child: surface,
          );
  }
}

/// A visual warning expires without clearing the owner's validation state.
class AccountingTransientWarning extends StatefulWidget {
  const AccountingTransientWarning({
    super.key,
    required this.identity,
    required this.child,
    this.topGap = 0,
    this.bottomGap = 0,
  });
  final String identity;
  final Widget child;
  final double topGap;
  final double bottomGap;
  @override
  State<AccountingTransientWarning> createState() =>
      _AccountingTransientWarningState();
}

class _AccountingTransientWarningState
    extends State<AccountingTransientWarning> {
  Timer? _timer;
  bool _visible = true;
  void _start() {
    _timer?.cancel();
    _visible = true;
    _timer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(AccountingTransientWarning oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _visible
      ? Padding(
          padding: EdgeInsets.only(
            top: widget.topGap,
            bottom: widget.bottomGap,
          ),
          child: widget.child,
        )
      : const SizedBox.shrink();
}

final class AccountingEmptyState {
  const AccountingEmptyState._();

  static Widget card(
    BuildContext context, {
    required String title,
    required String description,
    Key? key,
    IconData icon = Icons.inbox_outlined,
    Widget? action,
  }) {
    final tokens = AccountingTheme.of(context);
    return AccountingCard.surface(
      context,
      key: key,
      child: Padding(
        padding: accountingContentPadding,
        child: Center(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tokens.muted,
                  borderRadius: BorderRadius.circular(accountingControlRadius),
                ),
                child: Icon(icon, size: 18, color: tokens.mutedForeground),
              ),
              const SizedBox(height: 12),
              Text(
                accountingTitleCase(title),
                style: AccountingTypography.sectionTitle(context),
              ),
              const SizedBox(height: AccountingResponsive.titleSubtitleGap),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: accountingHelperText(context, description),
              ),
              if (action != null) ...<Widget>[
                const SizedBox(height: 12),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final class AccountingSkeleton {
  const AccountingSkeleton._();

  static Widget build(
    BuildContext context, {
    required double height,
    required double width,
    Key? key,
  }) {
    final tokens = AccountingTheme.of(context);
    return Semantics(
      excludeSemantics: true,
      child: Container(
        key: key,
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: tokens.muted,
          borderRadius: BorderRadius.circular(accountingControlRadius),
        ),
      ),
    );
  }
}

Widget accountingCompactClose(
  BuildContext context, {
  VoidCallback? onPressed,
  Key? key,
  bool enabled = true,
}) => _accountingDismissControl(
  label: 'Close',
  key: key,
  enabled: enabled,
  onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
);

Widget accountingCompactRemove(
  BuildContext context, {
  required VoidCallback? onPressed,
  Key? key,
  String tooltip = 'Remove',
}) => _accountingDismissControl(
  label: tooltip,
  key: key,
  enabled: onPressed != null,
  onPressed: onPressed,
  remove: true,
);

/// Matches the 28px red inline remove control with the product's green action.
Widget accountingCompactAdd(
  BuildContext context, {
  required VoidCallback? onPressed,
  Key? key,
  String tooltip = 'Add Line',
}) => Semantics(
  label: tooltip,
  button: true,
  child: IconButton(
    key: key,
    tooltip: tooltip,
    style: accountingButtonHover(
      IconButton.styleFrom(
        // The ordinary 44px icon-button theme must not enlarge this compact
        // family. Compact density keeps the established 20px painted circle
        // within its 28px control allocation.
        minimumSize: const Size.square(AccountingDismissIcon.controlExtent),
        maximumSize: const Size.square(AccountingDismissIcon.controlExtent),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const CircleBorder(),
        backgroundColor: AccountingTheme.of(context).primary,
        disabledBackgroundColor: AccountingTheme.of(context).primary
            .withValues(alpha: .4),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(alpha: .6),
        side: BorderSide(color: AccountingTheme.of(context).primary),
      ),
    ),
    onPressed: onPressed,
    icon: const AccountingAddIcon(),
    padding: const EdgeInsets.all(4),
    constraints: const BoxConstraints.tightFor(
      width: AccountingDismissIcon.controlExtent,
      height: AccountingDismissIcon.controlExtent,
    ),
    visualDensity: VisualDensity.compact,
  ),
);

Widget _accountingDismissControl({
  required String label,
  required VoidCallback? onPressed,
  Key? key,
  bool enabled = true,
  bool remove = false,
}) => Semantics(
  container: true,
  label: label,
  button: true,
  enabled: enabled,
  onTap: enabled ? onPressed : null,
  excludeSemantics: true,
  child: IconButton(
    key: key,
    tooltip: remove ? label : null,
    style: accountingButtonHover(
      IconButton.styleFrom(
        // The ordinary 44px icon-button theme must not enlarge this compact
        // family. Compact density keeps the established 20px painted circle
        // within its 28px control allocation.
        minimumSize: const Size.square(AccountingDismissIcon.controlExtent),
        maximumSize: const Size.square(AccountingDismissIcon.controlExtent),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const CircleBorder(),
        backgroundColor: AccountingColorLibrary.grapefruit,
        disabledBackgroundColor: AccountingColorLibrary.grapefruit.withValues(
          alpha: .4,
        ),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(alpha: .6),
        side: const BorderSide(color: AccountingColorLibrary.grapefruit),
      ),
    ),
    onPressed: enabled ? onPressed : null,
    icon: remove ? const AccountingRemoveIcon() : const AccountingCloseIcon(),
    padding: const EdgeInsets.all(4),
    constraints: const BoxConstraints.tightFor(
      width: AccountingDismissIcon.controlExtent,
      height: AccountingDismissIcon.controlExtent,
    ),
    visualDensity: VisualDensity.compact,
  ),
);

Widget accountingDialogHeading(
  BuildContext context,
  String title, {
  bool canClose = true,
  Key? closeKey,
  VoidCallback? onClose,
}) => Row(
  children: [
    Expanded(
      child: Text(title, style: AccountingTypography.sectionTitle(context)),
    ),
    const SizedBox(width: 12),
    accountingCompactClose(
      context,
      key: closeKey,
      enabled: canClose,
      onPressed: onClose,
    ),
  ],
);

/// Preserve action meaning for shared dialog chrome without inspecting a
/// deferred Builder's rendered tree or dropping a caller's close callback.
class _AccountingButtonBuilder extends Builder {
  const _AccountingButtonBuilder({
    required super.builder,
    required this.actionLabel,
    required this.onPressed,
    this.actionKey,
  });
  final String? actionLabel;
  final VoidCallback? onPressed;
  final Key? actionKey;
}

/// Established grey action footer shared by popup and popup settings owners.
Widget accountingFormFooter(
  BuildContext context, {
  Key? key,
  required List<Widget> actions,
  Widget? leading,
}) {
  final tokens = AccountingTheme.of(context);
  return Container(
    key: key,
    width: double.infinity,
    padding: accountingContentPadding,
    decoration: BoxDecoration(
      color: tokens.muted,
      border: Border(top: BorderSide(color: tokens.border)),
    ),
    child: Row(
      children: [
        ?leading,
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AccountingResponsive.actionGap,
            runSpacing: AccountingResponsive.actionGap,
            children: actions,
          ),
        ),
      ],
    ),
  );
}

/// Keep the accepted footer clearance visible at every scroll position.
/// This owner is for popouts with a fixed action footer, not page/tab forms.
class AccountingPopoutScrollBody extends StatelessWidget {
  const AccountingPopoutScrollBody({
    super.key,
    required this.child,
    required this.padding,
    this.scrollKey,
    this.controller,
  });
  final Widget child;
  final EdgeInsets padding;
  final Key? scrollKey;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      bottom: AccountingPopoutTokens.contentBottomInset,
    ),
    child: SingleChildScrollView(
      key: scrollKey,
      controller: controller,
      child: Padding(padding: padding.copyWith(bottom: 0), child: child),
    ),
  );
}

final class AccountingDialog {
  /// Existing edit-session warning, shared without changing the form owner.
  static Future<bool> confirmDiscardChanges(
    BuildContext context, {
    Key? closeKey,
    Key? keepEditingKey,
    Key? discardKey,
  }) async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => alert(
          dialogContext,
          title: 'Discard unsaved changes?',
          onClose: () => Navigator.of(dialogContext).pop(false),
          closeKey: closeKey,
          content: const Text(
            'Your changes haven’t been saved and will be lost.',
          ),
          actions: [
            AccountingButton.ghost(
              dialogContext,
              key: keepEditingKey,
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep Editing'),
            ),
            AccountingButton.destructive(
              dialogContext,
              key: discardKey,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      ) ==
      true;

  const AccountingDialog._();

  static const _windowLayout = MethodChannel('audyt/window-layout');
  static int _widthOwnerSequence = 0;

  static Future<bool> acquireFixedWidth(
    String owner,
    double contentWidth, {
    double contentInset = accountingContentInset,
  }) async {
    try {
      await _windowLayout.invokeMethod<double>('acquirePopoutWidth', {
        'owner': owner,
        'width':
            contentWidth +
            contentInset * 2 +
            AccountingPopoutTokens.windowInsets.horizontal,
      });
      return true;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> releaseFixedWidth(String owner) =>
      _windowLayout.invokeMethod<void>('releasePopoutWidth', {'owner': owner});

  /// Keep a desktop popout's accepted width; widen the native window first.
  /// Height stays unchanged and the dialog's normal vertical scroller owns it.
  static Future<T?> showFixed<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    required double contentWidth,
    double contentInset = AccountingPopoutTokens.contentInset,
    bool barrierDismissible = true,
  }) async {
    final owner = 'popout-${++_widthOwnerSequence}';
    var ownsNativeWidth = false;
    try {
      ownsNativeWidth = await acquireFixedWidth(
        owner,
        contentWidth,
        contentInset: contentInset,
      );
      if (!context.mounted) return null;
      return await showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (_) => _AccountingFixedDialogWidth(
          contentWidth: contentWidth,
          child: Builder(builder: builder),
        ),
      );
    } finally {
      if (ownsNativeWidth) {
        await releaseFixedWidth(owner);
      }
    }
  }

  static Widget _title(
    BuildContext context, {
    required String title,
    String? description,
    String? titleGuidance,
    double contentInset = AccountingPopoutTokens.contentInset,
    double titleTextInset = 0,
    bool preserveTitleCase = false,
    VoidCallback? onClose,
    Key? closeKey,
    bool canClose = true,
  }) {
    final label = Text(
      preserveTitleCase ? title : accountingTitleCase(title),
      style: AccountingTypography.sectionTitle(context),
    );
    return Stack(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(
            left: titleTextInset,
            top: contentInset - AccountingPopoutTokens.closeInset,
            right: AccountingPopoutTokens.titleTrailingReserve,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              titleGuidance == null
                  ? label
                  : Tooltip(
                      message: titleGuidance,
                      constraints: AccountingFieldHelp.messageConstraints,
                      child: label,
                    ),
              if (description != null) ...<Widget>[
                const SizedBox(height: AccountingResponsive.titleSubtitleGap),
                accountingHelperText(context, description),
              ],
            ],
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: accountingCompactClose(
            context,
            key: closeKey,
            enabled: canClose,
            onPressed: onClose,
          ),
        ),
      ],
    );
  }

  /// Shared popout header with a separately fitted, zoomable content area.
  static Dialog fitted(
    BuildContext context, {
    required String title,
    String? description,
    String? titleGuidance,
    required Widget Function(BuildContext, Size) contentBuilder,
    Key? key,
    double maxContentWidth = 960,
    double contentInset = AccountingPopoutTokens.contentInset,
    bool preserveTitleCase = false,
  }) => Dialog(
    key: key,
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxContentWidth + contentInset * 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AccountingPopoutTokens.titlePadding(contentInset),
            child: _title(
              context,
              title: title,
              description: description,
              titleGuidance: titleGuidance,
              contentInset: contentInset,
              preserveTitleCase: preserveTitleCase,
            ),
          ),
          Flexible(
            child: Padding(
              padding: AccountingPopoutTokens.contentPadding(contentInset),
              child: LayoutBuilder(
                key: const ValueKey('accounting-fitted-popout-content'),
                builder: (context, constraints) =>
                    contentBuilder(context, constraints.biggest),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  static AlertDialog alert(
    BuildContext context, {
    required String title,
    required Widget content,
    required List<Widget> actions,
    VoidCallback? onClose,
    Key? closeKey,
    bool canClose = true,
    Key? key,
    String? description,
    String? titleGuidance,
    Key? contentScrollKey,
    double? maxContentWidth,
    double? fixedContentWidth,
    bool scrollable = true,
    bool formFooter = true,
    Widget? footerLeading,
    bool preserveTitleCase = false,
    double contentInset = AccountingPopoutTokens.contentInset,
    double titleTextInset = 0,
    Color? backgroundColor,
  }) {
    // The corner Close owns dismissal. Preserve the former Cancel/Close
    // callback, test key and busy state instead of rendering a duplicate.
    final dismissActions = actions
        .whereType<_AccountingButtonBuilder>()
        .where(
          (action) =>
              action.actionLabel == 'Cancel' ||
              (actions.length == 1 && action.actionLabel == 'Close'),
        )
        .toList();
    if (dismissActions.isNotEmpty) {
      final dismiss = dismissActions.first;
      onClose ??= dismiss.onPressed;
      closeKey ??= dismiss.actionKey;
      canClose = canClose && dismiss.onPressed != null;
      actions = actions
          .where((action) => !dismissActions.contains(action))
          .toList();
    }
    // Read-only popouts retain their top-right Close; no empty grey footer.
    formFooter = formFooter && (actions.isNotEmpty || footerLeading != null);
    // A caller's declared content width owns the popup's preferred width.
    // Constrain the header to it instead of letting explanatory text widen
    // the shell around a narrower field. Only inspect this immediate owner;
    // never discover or rearrange arbitrary custom descendants.
    final declaredWidth = content is SizedBox ? content.width : null;
    final fittedContentWidth =
        declaredWidth != null && declaredWidth.isFinite && declaredWidth > 0
        ? (maxContentWidth == null || declaredWidth < maxContentWidth
              ? declaredWidth
              : maxContentWidth)
        : maxContentWidth;
    // showFixed owns both native accommodation and this route's width. Keep
    // explicit custom/sized content authoritative; nested routes do not inherit
    // this route-local metadata or accidentally acquire their parent's width.
    final effectiveFixedWidth =
        fixedContentWidth ??
        (fittedContentWidth == null
            ? context
                  .dependOnInheritedWidgetOfExactType<
                    _AccountingFixedDialogWidth
                  >()
                  ?.contentWidth
            : null);
    return AlertDialog(
      backgroundColor: backgroundColor,
      clipBehavior: Clip.antiAlias,
      key: key,
      insetPadding: AccountingPopoutTokens.windowInsets,
      constraints: effectiveFixedWidth != null
          ? BoxConstraints.tightFor(
              width: effectiveFixedWidth + contentInset * 2,
            )
          : fittedContentWidth == null
          ? null
          : BoxConstraints(maxWidth: fittedContentWidth + contentInset * 2),
      // The title uses the requested content inset. AlertDialog adds 16px
      // before its content, so the 4px bottom inset makes the content gap 20px.
      titlePadding: AccountingPopoutTokens.titlePadding(contentInset),
      title: _title(
        context,
        title: title,
        description: description,
        titleGuidance: titleGuidance,
        contentInset: contentInset,
        titleTextInset: titleTextInset,
        preserveTitleCase: preserveTitleCase,
        onClose: onClose,
        closeKey: closeKey,
        canClose: canClose,
      ),
      content: formFooter
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: AccountingPopoutScrollBody(
                    scrollKey: contentScrollKey,
                    padding: AccountingPopoutTokens.contentPadding(
                      contentInset,
                    ),
                    child: content,
                  ),
                ),
                accountingFormFooter(
                  context,
                  key: const ValueKey('accounting-form-dialog-footer'),
                  actions: actions,
                  leading: footerLeading,
                ),
              ],
            )
          : scrollable
          ? SingleChildScrollView(key: contentScrollKey, child: content)
          : content,
      // Flutter's scrollable AlertDialog puts the title in the same scroll
      // view as the content. Keep the close control fixed in every dialog.
      scrollable: false,
      actions: formFooter || actions.isEmpty ? null : actions,
      contentPadding: formFooter
          ? EdgeInsets.zero
          : actions.isEmpty
          ? AccountingPopoutTokens.contentPadding(contentInset)
          : null,
    );
  }
}

class _AccountingFixedDialogWidth extends InheritedWidget {
  const _AccountingFixedDialogWidth({
    required this.contentWidth,
    required super.child,
  });

  final double contentWidth;

  @override
  bool updateShouldNotify(_AccountingFixedDialogWidth oldWidget) =>
      contentWidth != oldWidget.contentWidth;
}

/// Shared attachment intake surface used by accounting forms.
final class AccountingDashedBorder extends StatelessWidget {
  const AccountingDashedBorder({
    required this.color,
    required this.backgroundColor,
    required this.child,
    super.key,
  });

  final Color color;
  final Color backgroundColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _AccountingDashedBorderPainter(color: color),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 128),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(accountingControlRadius),
        ),
        child: child,
      ),
    );
  }
}

/// One visual language for document intake in popup forms. The owning form
/// remains responsible for file selection, drag handling, and validation.
final class AccountingAttachmentDropzone extends StatelessWidget {
  const AccountingAttachmentDropzone({
    super.key,
    required this.onChoose,
    required this.prompt,
    required this.formats,
    this.dragOver = false,
    this.surfaceKey,
    this.contentKey,
    this.promptKey,
    this.actionKey,
  });

  final VoidCallback? onChoose;
  final String prompt;
  final String formats;
  final bool dragOver;
  final Key? surfaceKey;
  final Key? contentKey;
  final Key? promptKey;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    return AccountingDashedBorder(
      key: surfaceKey,
      color: dragOver ? tokens.primary : tokens.ring,
      backgroundColor: tokens.muted,
      child: Padding(
        padding: const EdgeInsets.all(accountingContentInset),
        child: Column(
          key: contentKey,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            AccountingIcon(
              Icons.description_outlined,
              size: 20,
              color: tokens.mutedForeground,
            ),
            const SizedBox(height: 12),
            Text(
              prompt,
              key: promptKey,
              textAlign: TextAlign.center,
              softWrap: true,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: tokens.cardForeground,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formats,
              textAlign: TextAlign.center,
              softWrap: true,
              style: AccountingTypography.helper(context),
            ),
            const SizedBox(height: 12),
            AccountingButton.outline(
              context,
              key: actionKey,
              onPressed: onChoose,
              leadingIcon: Icons.file_upload_outlined,
              child: const Text('Choose Files'),
            ),
          ],
        ),
      ),
    );
  }
}

final class _AccountingDashedBorderPainter extends CustomPainter {
  const _AccountingDashedBorderPainter({required this.color})
    : strokeWidth = 0.56;

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
          const Radius.circular(9),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final dashEnd = (distance + 5).clamp(0.0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, dashEnd), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AccountingDashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

String accountingTitleCase(String text) =>
    text.replaceAllMapped(RegExp("[A-Za-z]+(?:['’][A-Za-z]+)*"), (match) {
      final word = match.group(0)!;
      if (word.substring(1).contains(RegExp(r'[A-Z]'))) return word;
      return word[0].toUpperCase() + word.substring(1);
    });

/// A scrolling page can temporarily reserve space beneath a low menu anchor.
/// The page owns scrolling; the popup keeps its accepted below-trigger geometry.
class AccountingMenuViewportScope extends InheritedWidget {
  const AccountingMenuViewportScope({
    super.key,
    required this.reserveBelow,
    required this.release,
    required super.child,
  });
  final Future<void> Function(double clearance) reserveBelow;
  final VoidCallback release;
  static AccountingMenuViewportScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AccountingMenuViewportScope>();
  @override
  bool updateShouldNotify(AccountingMenuViewportScope oldWidget) => false;
}

/// Choice popups retain Material's selection, keyboard and dismissal behavior,
/// but use the space below their trigger instead of flipping above it.
class AccountingMenuAnchor extends StatefulWidget {
  const AccountingMenuAnchor({
    super.key,
    required this.menuWidth,
    required this.menuChildren,
    required this.builder,
    this.controller,
    this.childFocusNode,
    this.style,
    this.maxHeight = 360,
    this.gap = 4,
    this.onOpen,
    this.onClose,
    this.menuChildrenBuilder,
    this.fitTriggerWidth = false,
  });

  final double menuWidth;
  final double maxHeight;
  final double gap;
  final List<Widget> menuChildren;
  final MenuAnchorChildBuilder builder;
  final MenuController? controller;
  final FocusNode? childFocusNode;
  final MenuStyle? style;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;

  /// Ordinary selector popups follow the actual painted trigger after layout.
  /// Keep custom action/grid menus with their existing width owner. Measuring
  /// here avoids LayoutBuilder inside intrinsic-size confirmation dialogs.
  final bool fitTriggerWidth;

  /// Panels with fixed headings can fit their own scrollable body to the
  /// actual space below the anchor, rather than scrolling the whole panel.
  final List<Widget> Function(double width, double height)? menuChildrenBuilder;

  @override
  State<AccountingMenuAnchor> createState() => _AccountingMenuAnchorState();
}

class _AccountingMenuAnchorState extends State<AccountingMenuAnchor> {
  final _triggerKey = GlobalKey();
  Rect? _triggerRect;
  Size? _overlaySize;
  bool _measureScheduled = false;

  void _scheduleTriggerMeasurement() {
    if (!_open || _measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (mounted && _open) _measureTrigger();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleTriggerMeasurement();
  }

  @override
  void didUpdateWidget(covariant AccountingMenuAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleTriggerMeasurement();
  }

  void _measureTrigger() {
    final box = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && overlay != null && overlay.hasSize) {
      final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
      if (_overlaySize == overlay.size && _triggerRect == rect) return;
      setState(() {
        _overlaySize = overlay.size;
        _triggerRect = rect;
      });
    }
  }

  bool _open = false;
  AccountingMenuViewportScope? _pageViewport;
  Future<void> _onOpen() async {
    _open = true;
    _measureTrigger();
    widget.onOpen?.call();
    final viewport = AccountingMenuViewportScope.maybeOf(context);
    final rect = _triggerRect;
    if (viewport == null || rect == null) return;
    final media = MediaQuery.of(context);
    final bottom =
        (_overlaySize?.height ?? media.size.height) -
        media.padding.bottom -
        media.viewInsets.bottom -
        8;
    final minimum = math.min(widget.maxHeight, 140.0);
    final deficit = minimum - (bottom - rect.bottom - widget.gap);
    if (deficit <= 0) return;
    _pageViewport = viewport;
    await viewport.reserveBelow(deficit);
    if (mounted && _open) _measureTrigger();
  }

  void _onClose() {
    _open = false;
    _pageViewport?.release();
    _pageViewport = null;
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final viewport = _overlaySize ?? media.size;
    final width = math.min(
      widget.fitTriggerWidth
          ? math.max(widget.menuWidth, _triggerRect?.width ?? 0)
          : widget.menuWidth,
      math.max(0.0, viewport.width - 16),
    );
    final rect = _triggerRect;
    final bottomLimit =
        viewport.height - media.padding.bottom - media.viewInsets.bottom - 8;
    final availableHeight = math.max(
      0.0,
      bottomLimit - (rect?.bottom ?? 0) - widget.gap,
    );
    final height = math.min(widget.maxHeight, availableHeight);
    final rightAligned = rect != null && rect.center.dx > viewport.width / 2;
    // An absolute alignment keeps screen-left/screen-right anchoring the same
    // in either text direction. Material itself applies the RTL menu offset.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final offsetX = rightAligned ? (rtl ? 0.0 : -width) : (rtl ? width : 0.0);
    final base =
        widget.style ?? accountingSelectorMenuStyle(context, width, height);
    return accountingSelectionMenuScrollbarHidden(
      context,
      child: MenuAnchor(
        controller: widget.controller,
        childFocusNode: widget.childFocusNode,
        crossAxisUnconstrained: false,
        reservedPadding: const EdgeInsets.all(8),
        alignmentOffset: Offset(offsetX, widget.gap),
        style: base.copyWith(
          alignment: rightAligned
              ? Alignment.bottomRight
              : Alignment.bottomLeft,
          minimumSize: WidgetStatePropertyAll(Size(width, 0)),
          maximumSize: WidgetStatePropertyAll(Size(width, height)),
        ),
        onOpen: _onOpen,
        onClose: _onClose,
        menuChildren:
            widget.menuChildrenBuilder?.call(width, height) ??
            widget.menuChildren,
        builder: (context, controller, child) => SizedBox(
          key: _triggerKey,
          child: widget.builder(context, controller, child),
        ),
      ),
    );
  }
}

/// A real record-search field beside labelled filters uses the same label
/// geometry. Searchable selectors and standalone searches never use this.
class AccountingLabelledSearch extends StatelessWidget {
  const AccountingLabelledSearch({
    super.key,
    required this.child,
    this.labelKey,
    this.alignToField = false,
  });
  final Widget child;
  final Key? labelKey;
  final bool alignToField;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      accountingFieldLabel(
        context,
        'Search',
        key: labelKey,
        alignToField: alignToField,
      ),
      const SizedBox(height: accountingFieldLabelGap),
      child,
    ],
  );
}

/// Shared popup and option paint for field and company selectors.
MenuStyle accountingSelectorMenuStyle(
  BuildContext context,
  double width,
  double maxHeight,
) {
  final tokens = AccountingTheme.of(context);
  return MenuStyle(
    alignment: AlignmentDirectional.bottomStart,
    backgroundColor: WidgetStatePropertyAll<Color?>(tokens.card),
    surfaceTintColor: WidgetStatePropertyAll<Color?>(tokens.card),
    elevation: const WidgetStatePropertyAll<double?>(6),
    shadowColor: const WidgetStatePropertyAll<Color?>(
      accountingMenuShadowColor,
    ),
    minimumSize: WidgetStatePropertyAll<Size?>(Size(width, 0)),
    maximumSize: WidgetStatePropertyAll<Size?>(Size(width, maxHeight)),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.all(4),
    ),
    side: WidgetStatePropertyAll<BorderSide?>(BorderSide(color: tokens.border)),
    shape: WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(accountingControlRadius),
      ),
    ),
  );
}

// Flutter's MenuAnchor paints its own always-visible Scrollbar around long
// menus. Suppress that thumb for selection popups while retaining wheel and
// touch scrolling of the choices.
Widget accountingSelectionMenuScrollbarHidden(
  BuildContext context, {
  required Widget child,
}) => ScrollbarTheme(
  data: ScrollbarTheme.of(context).copyWith(
    thumbColor: const WidgetStatePropertyAll<Color?>(Colors.transparent),
    trackColor: const WidgetStatePropertyAll<Color?>(Colors.transparent),
    trackBorderColor: const WidgetStatePropertyAll<Color?>(Colors.transparent),
  ),
  child: child,
);

ButtonStyle accountingSelectorOptionStyle(
  BuildContext context, {
  required bool selected,
  bool hovered = false,
  bool managedHighlight = false,
  bool grouped = false,
}) {
  final tokens = AccountingTheme.of(context);
  return MenuItemButton.styleFrom(
    minimumSize: const Size(double.infinity, 44),
    padding: EdgeInsets.fromLTRB(grouped ? 28 : 12, 5, 12, 5),
    foregroundColor: tokens.foreground,
    disabledForegroundColor: tokens.mutedForeground,
    overlayColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(accountingControlRadius),
    ),
    textStyle: AccountingTypography.value(context)
        .copyWith(color: tokens.foreground),
  ).copyWith(
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (selected) return tokens.primary.withValues(alpha: 0.10);
      return hovered ||
              (!managedHighlight &&
                  (states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)))
          ? tokens.accent
          : Colors.transparent;
    }),
  );
}

/// Action options reuse the field selector's rounded grey hover and insets.
/// Typography and icon artwork retain their own established styles.
ButtonStyle accountingActionMenuItemStyle(BuildContext context) {
  final tokens = AccountingTheme.of(context);
  return ButtonStyle(
    textStyle: WidgetStatePropertyAll(AccountingTypography.value(context)),
    minimumSize: const WidgetStatePropertyAll(Size(double.infinity, 44)),
    padding: const WidgetStatePropertyAll(EdgeInsets.fromLTRB(12, 5, 12, 5)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(accountingControlRadius),
      ),
    ),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)
          ? tokens.accent
          : Colors.transparent,
    ),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  );
}

class AccountingOverflowAction {
  const AccountingOverflowAction({
    required this.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.iconAsset,
    this.iconPaintedSizeAdjustment = 0,
  });
  final Key key;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? iconAsset;
  final double iconPaintedSizeAdjustment;

  double get iconWidth => iconAsset == null
      ? AccountingIcon.rowCanvasSize(icon)
      : AccountingIcon.smallCanvasSizeForAsset(iconAsset!) +
            iconPaintedSizeAdjustment /
                (AccountingIcon.paintedLongestSideFraction[iconAsset!] ?? 1);
}

/// Popup inset (4 each side), item inset (12 each side), and the actual
/// label/adornment widths. Shorter choices share the longest choice's width.
double accountingMenuContentWidth(
  BuildContext context,
  Iterable<({String label, double adornmentWidth})> choices,
) =>
    choices.fold<double>(
      0,
      (width, choice) => math.max(
        width,
        AccountingResponsive.measuredTextWidth(
              context,
              choice.label,
              AccountingTypography.value(context),
            ) +
            choice.adornmentWidth,
      ),
    ) +
    32;

/// Record actions share one popup and align its right edge to the three-dot
/// trigger. The menu opens below the trigger, leaving that button visible.
class AccountingOverflowMenu extends StatelessWidget {
  const AccountingOverflowMenu({
    super.key,
    required this.triggerKey,
    required this.actions,
    this.emptyLabel = 'No further actions',
    this.compact = false,
    this.tooltip = 'More actions',
    this.maxHeight = 360,
    this.bordered = false,
  });
  final Key triggerKey;
  final List<AccountingOverflowAction> actions;
  final String emptyLabel;
  final bool compact;
  final String tooltip;
  final double maxHeight;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    if (actions.length == 1) {
      final action = actions.single;
      return KeyedSubtree(
        key: action.key,
        child: AccountingButton.iconOnly(
          context,
          key: triggerKey,
          compact: compact,
          onPressed: action.onPressed,
          icon: action.icon,
          iconAsset: action.iconAsset,
          iconPaintedSizeAdjustment: action.iconPaintedSizeAdjustment,
          tooltip: action.label,
        ),
      );
    }
    final menuWidth = accountingMenuContentWidth(context, [
      if (actions.isEmpty) (label: emptyLabel, adornmentWidth: 0.0),
      for (final action in actions)
        (label: action.label, adornmentWidth: action.iconWidth + 12),
    ]);
    return AccountingMenuAnchor(
      menuWidth: menuWidth,
      maxHeight: maxHeight,
      style: accountingSelectorMenuStyle(context, menuWidth, maxHeight)
          .copyWith(
            alignment: AlignmentDirectional.bottomEnd,
            padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
            side: WidgetStatePropertyAll(
              bordered
                  ? BorderSide(color: AccountingTheme.of(context).border)
                  : BorderSide.none,
            ),
          ),
      menuChildren: [
        if (actions.isEmpty)
          MenuItemButton(
            onPressed: null,
            style: accountingActionMenuItemStyle(context),
            child: Text(emptyLabel),
          ),
        for (final action in actions)
          MenuItemButton(
            key: action.key,
            leadingIcon: action.iconAsset == null
                ? AccountingIcon.smallAction(action.icon)
                : AccountingSmallAssetIcon(
                    action.iconAsset!,
                    paintedSizeAdjustment: action.iconPaintedSizeAdjustment,
                  ),
            onPressed: action.onPressed,
            style: accountingActionMenuItemStyle(context),
            child: Text(action.label),
          ),
      ],
      builder: (context, controller, child) => AccountingButton.iconOnly(
        context,
        key: triggerKey,
        compact: compact,
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: Icons.more_horiz,
        tooltip: tooltip,
      ),
    );
  }
}

const accountingSelectorChevronHoverExtent = 22.0;
const _selectorChevronPaintedSize = Size(10, 6);
const accountingSelectorLabelGap = 14.0;

class AccountingSelectorChevron extends StatefulWidget {
  const AccountingSelectorChevron({super.key, this.hoverTint = true});

  final bool hoverTint;

  @override
  State<AccountingSelectorChevron> createState() =>
      _AccountingSelectorChevronState();
}

class _AccountingSelectorChevronState extends State<AccountingSelectorChevron> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: accountingSelectorChevronHoverExtent,
      height: accountingSelectorChevronHoverExtent,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.hoverTint && _hovered
            ? AccountingTheme.of(context).primary.withValues(alpha: 0.12)
            : Colors.transparent,
      ),
      child: CustomPaint(
        size: _selectorChevronPaintedSize,
        painter: _TightSelectorChevron(
          AccountingTheme.of(context).mutedForeground,
        ),
      ),
    ),
  );
}

/// The existing first-option creation treatment, also used by searchable payees.
Widget accountingSelectorCreationAction(
  BuildContext context, {
  required Key key,
  required String label,
  required VoidCallback? onPressed,
}) => MenuItemButton(
  key: key,
  style: accountingSelectorOptionStyle(context, selected: false),
  leadingIcon: const AccountingIcon(Icons.add),
  onPressed: onPressed,
  child: Text(
    label,
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.ellipsis,
  ),
);

@immutable
class AccountingSelectorOption<T> {
  const AccountingSelectorOption({
    required this.value,
    required String label,
    this.key,
    this.leading,
    this.leadingWidth = 20,
    this.group,
    this.enabled = true,
    this.preserveLabelCase = false,
    this.selectedLabel,
    this.checked,
    this.onPressed,
    // ignore: prefer_initializing_formals
  }) : _label = label;

  final T value;
  final String _label;
  final bool preserveLabelCase;

  /// Optional short value in the closed field; the menu/search retains [label].
  final String? selectedLabel;

  /// Explicit multiple-choice menu item. Null preserves ordinary selectors.
  /// The caller owns the selected set; activating a checkbox keeps the menu open.
  final bool? checked;
  String get label => preserveLabelCase ? _label : accountingTitleCase(_label);
  final Key? key;
  final Widget? leading;

  /// Actual leading artwork width; popup measurement includes the themed icon-to-label gap.
  final double leadingWidth;
  final String? group;
  final bool enabled;
  // Creation actions stay first and never become selected data values.
  final VoidCallback? onPressed;
}

/// A compact account switcher placed inside a metric card. Its current choice
/// keeps the selector highlight, while the chevron trigger has no green hover.
class AccountingCompactChoiceMenu<T> extends StatelessWidget {
  const AccountingCompactChoiceMenu({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.triggerKey,
    this.tooltip = 'Select account',
    this.iconAsset,
  });

  final List<AccountingSelectorOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final Key triggerKey;
  final String tooltip;
  final String? iconAsset;

  @override
  Widget build(BuildContext context) {
    final width = accountingMenuContentWidth(context, [
      for (final option in options) (label: option.label, adornmentWidth: 0.0),
    ]);
    return accountingSelectionMenuScrollbarHidden(
      context,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: AccountingMenuAnchor(
          menuWidth: width,
          maxHeight: math.min(320, options.length * 44 + 24),
          style: accountingSelectorMenuStyle(
            context,
            width,
            math.min(320, options.length * 44 + 24),
          ).copyWith(alignment: AlignmentDirectional.bottomEnd),
          menuChildren: [
            for (final option in options)
              SizedBox(
                width: width - 8,
                child: MenuItemButton(
                  key: option.key,
                  onPressed: option.enabled
                      ? () => onChanged(option.value)
                      : null,
                  style: accountingSelectorOptionStyle(
                    context,
                    selected: option.value == value,
                  ),
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
          builder: (context, controller, child) => Tooltip(
            message: tooltip,
            child: SizedBox.square(
              dimension: accountingSmallControlHeight,
              child: OutlinedButton(
                key: triggerKey,
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                style: accountingButtonHover(
                  OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size.square(
                      accountingSmallControlHeight,
                    ),
                    maximumSize: const Size.square(
                      accountingSmallControlHeight,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    overlayColor: Colors.transparent,
                    side: BorderSide(color: AccountingTheme.of(context).input),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        accountingSmallIconRadius,
                      ),
                    ),
                  ),
                  hoverColor: AccountingTheme.of(context).accent,
                ),
                child: Center(
                  child: iconAsset == null
                      ? const AccountingSelectorChevron(hoverTint: false)
                      : SvgPicture.asset(
                          'assets/icons/small/$iconAsset',
                          width: AccountingIcon.smallCanvasSizeForAsset(
                            iconAsset!,
                          ),
                          height: AccountingIcon.smallCanvasSizeForAsset(
                            iconAsset!,
                          ),
                          colorFilter: ColorFilter.mode(
                            AccountingTheme.of(context).foreground,
                            BlendMode.srcIn,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A selector prompt beginning Select plus two or more tokens displays the
/// next two only. Call only for prompts, never option labels or business values.
String accountingSelectorHintText(String hintText) {
  final match = RegExp(r'^Select\s+(\S+)\s+(\S+)(?:\s+\S+)*$')
      .firstMatch(hintText);
  return match == null ? hintText : '${match[1]} ${match[2]}';
}

const accountingSelectorTriggerRightInset = 14.0;

/// Shared content minimum for selectors and the layouts that allocate them.
double accountingSelectorMinimumWidth(
  BuildContext context,
  Iterable<String> labels, {
  bool compactToolbar = false,
  bool stackedLine = false,
  TextStyle? textStyle,
}) {
  double contentWidth = 0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style:
            textStyle ??
            (stackedLine
                ? AccountingTypography.controlValue(context)
                      .copyWith(letterSpacing: 0)
                : AccountingTypography.control(context)),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    contentWidth = math.max(contentWidth, painter.width);
    painter.dispose();
  }
  final inset = compactToolbar ? 12.0 : accountingContentInset;
  if (stackedLine) {
    // Match _buildTrigger: 14px before the existing 22px hover target puts
    // the centered 10px painted chevron 20px after the longest text. Ordinary
    // selector reservations must not add spare width to fluid line columns.
    return contentWidth +
        accountingContentInset +
        accountingSelectorTriggerRightInset +
        accountingSelectorLabelGap +
        accountingSelectorChevronHoverExtent;
  }
  return contentWidth + inset * 3 + 10 + 2;
}

class AccountingSelector<T> extends StatefulWidget {
  const AccountingSelector({
    required this.options,
    required this.value,
    required this.onChanged,
    required this.hintText,
    super.key,
    this.controlKey,
    this.triggerKey,
    this.menuKey,
    this.menuTitle,
    this.menuTitleKey,
    this.searchable = true,
    this.alwaysSearchable = false,
    this.searchKey,
    this.searchHintText = 'Search',
    this.emptyText = 'No options available',
    this.helperText,
    this.errorText,
    this.enabled = true,
    this.focusNode,
    this.semanticsLabel,
    this.onQueryChanged,
    this.menuMaxHeight = 360,
    this.menuWidth = 320,
    this.menuMinWidth = 0,
    this.assignedWidth,
    this.compactToolbar = false,
    this.displayLabel,
  });

  final List<AccountingSelectorOption<T>> options;
  final T? value;
  final ValueChanged<T?> onChanged;
  final String hintText;
  final Key? controlKey;
  final Key? triggerKey;
  final Key? menuKey;
  final String? menuTitle;
  final Key? menuTitleKey;
  final bool searchable;

  /// Record lookup can require search even before ten choices exist.
  final bool alwaysSearchable;
  final Key? searchKey;
  final String searchHintText;
  final String emptyText;
  final String? helperText;
  final String? errorText;
  final bool enabled;
  final FocusNode? focusNode;
  final String? semanticsLabel;
  final ValueChanged<String>? onQueryChanged;
  final double menuMaxHeight;
  final double menuWidth;
  final double menuMinWidth;
  final double? assignedWidth;
  final bool compactToolbar;

  /// Closed label for an explicit multiple-choice selector only. This is a
  /// committed selection label, never an unset prompt or a new menu option.
  final String? displayLabel;

  @override
  State<AccountingSelector<T>> createState() => _AccountingSelectorState<T>();
}

class _AccountingSelectorState<T> extends State<AccountingSelector<T>> {
  late final MenuController _menuController = MenuController();
  late final TextEditingController _searchController = TextEditingController();
  FocusNode? _internalFocusNode;
  bool _menuOpen = false;
  int _highlightedIndex = -1;
  int _hoveredIndex = -1;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  @override
  void dispose() {
    _searchController.dispose();
    _internalFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final menuHeight = math
        .min(widget.menuMaxHeight, math.max(160.0, viewportHeight - 32))
        .toDouble();
    // Reserve the longest choice plus shared menu padding before opening.
    // Match the painted trigger: two content insets, label-to-arrow gap,
    // arrow width and two border pixels. Explicit widths are minimums.
    // The chevron uses tight painted bounds, without font side bearings.
    final minimumLabelWidth = accountingSelectorMinimumWidth(context, [
      if (widget.displayLabel != null) widget.displayLabel!,
      if (_selectedOption == null) accountingSelectorHintText(widget.hintText),
      ...widget.options
          .where((o) => o.onPressed == null)
          .map((o) => o.selectedLabel ?? o.label),
    ], compactToolbar: widget.compactToolbar);
    // Assigned form columns fill their allotted width. Ordinary selectors
    // retain their content width when no column width is supplied.
    final desiredWidth = widget.assignedWidth ?? minimumLabelWidth;
    final controlWidth = math.min(
      desiredWidth,
      math.max(0.0, MediaQuery.sizeOf(context).width - 32),
    );
    // The scroller is independent of the closed field's assigned column.
    // Measure every option, including creation and retained historical choices,
    // before filtering so searching never changes the popup width.
    final choiceWidth = accountingMenuContentWidth(context, [
      for (final option in widget.options)
        (
          label: option.label,
          adornmentWidth:
              (option.checked == null ? 0.0 : 18 + accountingContentInset) +
              (option.group?.isNotEmpty == true ? 16.0 : 0.0) +
              (option.leading == null
                  ? 0.0
                  : option.leadingWidth +
                        math.max(
                          4.0,
                          12 + Theme.of(context).visualDensity.horizontal * 2,
                        )),
        ),
    ]);
    final popupWidth = math.min(
      math.max(0.0, MediaQuery.sizeOf(context).width - 16),
      math.max(choiceWidth, widget.menuMinWidth),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: controlWidth),
          child: accountingSelectionMenuScrollbarHidden(
            context,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context)
                  .copyWith(scrollbars: false),
              child: AccountingMenuAnchor(
                menuWidth: popupWidth,
                fitTriggerWidth: true,
                maxHeight: menuHeight,
                controller: _menuController,
                childFocusNode: _focusNode,
                style: _menuStyle(context, popupWidth, menuHeight),
                onOpen: _handleMenuOpen,
                onClose: _handleMenuClose,
                menuChildren: const [],
                menuChildrenBuilder: (width, height) => <Widget>[
                  KeyedSubtree(
                    key: widget.menuKey,
                    child: SizedBox(width: width, child: _buildMenu(context)),
                  ),
                ],
                builder: (context, controller, child) {
                  final selected = _selectedOption;
                  final searchTriggerActive = _searchEnabled && _menuOpen;
                  final trigger = Align(
                    widthFactor: 1,
                    heightFactor: 1,
                    alignment: AlignmentDirectional.centerStart,
                    child: SizedBox(
                      width: controlWidth,
                      child: _buildTrigger(context, controller, selected),
                    ),
                  );
                  return KeyedSubtree(
                    key: widget.controlKey,
                    child: Semantics(
                      container: true,
                      button: !searchTriggerActive,
                      textField: searchTriggerActive,
                      enabled: widget.enabled,
                      label: searchTriggerActive
                          ? widget.searchHintText
                          : widget.semanticsLabel ??
                                '${widget.displayLabel ?? selected?.label ?? accountingSelectorHintText(widget.hintText)}, selector',
                      child: trigger,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (widget.errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              widget.errorText!,
              softWrap: true,
              style: AccountingTypography.helper(context)
                  .copyWith(color: AccountingTheme.of(context).destructive),
            ),
          )
        else if (widget.helperText != null)
          accountingFieldHelper(context, widget.helperText!),
      ],
    );
  }

  AccountingSelectorOption<T>? get _selectedOption {
    for (final option in widget.options) {
      if (option.onPressed == null && option.value == widget.value) {
        return option;
      }
    }
    return null;
  }

  // Short selectors retain their normal dropdown; larger choice sets use
  // the same in-place searchable trigger throughout the app.
  bool get _searchEnabled =>
      widget.searchable &&
      (widget.alwaysSearchable ||
          widget.options.where((option) => option.onPressed == null).length >=
              10);

  void _handleMenuOpen() {
    if (!mounted) return;
    setState(() {
      _menuOpen = true;
      _highlightedIndex = -1;
      _hoveredIndex = -1;
    });
  }

  void _handleMenuClose() {
    if (!mounted) return;
    if (_menuOpen || _hoveredIndex != -1 || _highlightedIndex != -1) {
      setState(() {
        _menuOpen = false;
        _searchController.clear();
        _highlightedIndex = -1;
        _hoveredIndex = -1;
      });
      widget.onQueryChanged?.call('');
    }
  }

  Widget _buildTrigger(
    BuildContext context,
    MenuController controller,
    AccountingSelectorOption<T>? selected,
  ) {
    if (_searchEnabled && _menuOpen) {
      final searchDecoration = accountingSingleLineInputDecoration(
        context,
        hintText: widget.searchHintText,
      );
      return KeyedSubtree(
        key: widget.triggerKey,
        child: SizedBox(
          height: accountingControlHeight,
          child: Focus(
            skipTraversal: true,
            onKeyEvent: _handleSearchKeyEvent,
            child: SizedBox(
              height: accountingControlHeight,
              child: TextField(
                key: widget.searchKey,
                controller: _searchController,
                focusNode: _focusNode,
                autofocus: true,
                enabled: widget.enabled,
                onTap: () {
                  if (!controller.isOpen) _toggleMenu(controller);
                },
                onChanged: _handleQueryChanged,
                onSubmitted: (_) => _selectHighlighted(),
                textAlignVertical: TextAlignVertical.center,
                decoration: searchDecoration,
              ),
            ),
          ),
        ),
      );
    }
    return OutlinedButton(
      key: widget.triggerKey,
      focusNode: _focusNode,
      onPressed: widget.enabled ? () => _toggleMenu(controller) : null,
      style: AccountingButton.selectorTriggerStyle(context).copyWith(
        backgroundColor: WidgetStatePropertyAll(
          AccountingTheme.of(context).card,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        padding: WidgetStatePropertyAll(
          EdgeInsets.only(
            left: widget.compactToolbar ? 12 : accountingContentInset,
            right: widget.compactToolbar
                ? 6
                : accountingSelectorTriggerRightInset,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (selected?.leading != null) ...[
            selected!.leading!,
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              widget.displayLabel ??
                  selected?.selectedLabel ??
                  selected?.label ??
                  accountingSelectorHintText(widget.hintText),
              softWrap: false,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AccountingTypography.controlValue(context).copyWith(
                color:
                    widget.enabled &&
                        (selected != null || widget.displayLabel != null)
                    ? AccountingTheme.of(context).foreground
                    : AccountingTheme.of(context).mutedForeground,
                letterSpacing: 0,
              ),
            ),
          ),
          SizedBox(
            width: widget.compactToolbar ? 6 : accountingSelectorLabelGap,
          ),
          const AccountingSelectorChevron(),
        ],
      ),
    );
  }

  void _toggleMenu(MenuController controller) {
    if (controller.isOpen) {
      controller.close();
    } else {
      _searchController.clear();
      if (!_menuOpen) {
        setState(() {
          _menuOpen = true;
          _highlightedIndex = -1;
          _hoveredIndex = -1;
        });
      }
      controller.open();
    }
  }

  void _handleQueryChanged(String value) {
    setState(() {
      _highlightedIndex = _firstEnabledIndex(_filteredOptions());
      _hoveredIndex = -1;
    });
    widget.onQueryChanged?.call(value);
  }

  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _selectHighlighted();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _menuController.close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  int _firstEnabledIndex(List<AccountingSelectorOption<T>> options) {
    for (var index = 0; index < options.length; index++) {
      if (options[index].enabled && options[index].onPressed == null) {
        return index;
      }
    }
    return options.indexWhere((option) => option.enabled);
  }

  void _moveHighlight(int delta) {
    final options = _filteredOptions();
    if (options.isEmpty) return;
    var index = _highlightedIndex;
    if (index < 0 || index >= options.length) {
      index = delta < 0
          ? _lastEnabledIndex(options)
          : _firstEnabledIndex(options);
      if (index < 0) return;
      setState(() => _highlightedIndex = index);
      return;
    }
    for (var attempts = 0; attempts < options.length; attempts++) {
      index = (index + delta) % options.length;
      if (index < 0) index += options.length;
      if (options[index].enabled) {
        setState(() => _highlightedIndex = index);
        return;
      }
    }
  }

  int _lastEnabledIndex(List<AccountingSelectorOption<T>> options) {
    for (var index = options.length - 1; index >= 0; index--) {
      if (options[index].enabled) return index;
    }
    return -1;
  }

  void _selectHighlighted() {
    final options = _filteredOptions();
    if (options.isEmpty) return;
    var index = _highlightedIndex;
    if (index < 0 || index >= options.length || !options[index].enabled) {
      index = _firstEnabledIndex(options);
    }
    if (index < 0) return;
    _chooseOption(options[index]);
  }

  void _chooseOption(AccountingSelectorOption<T> option) {
    if (option.onPressed != null) {
      _menuController.close();
      option.onPressed!();
    } else {
      widget.onChanged(option.value);
      if (option.checked == null) _menuController.close();
    }
  }

  MenuStyle _menuStyle(BuildContext context, double width, double maxHeight) {
    return accountingSelectorMenuStyle(context, width, maxHeight);
  }

  List<AccountingSelectorOption<T>> _filteredOptions() {
    final query = _searchEnabled
        ? _searchController.text.trim().toLowerCase()
        : '';
    final matches = widget.options
        .where((option) {
          if (option.onPressed != null) return false;
          if (query.isEmpty) return true;
          return option.label.toLowerCase().contains(query) ||
              (option.group?.toLowerCase().contains(query) ?? false);
        })
        .toList(growable: false);
    // Keyboard navigation and hover refer to the same displayed group order.
    final grouped = <String?, List<AccountingSelectorOption<T>>>{};
    for (final option in matches) {
      grouped.putIfAbsent(option.group, () => []).add(option);
    }
    return [
      ...widget.options.where((option) => option.onPressed != null),
      for (final group in grouped.values) ...group,
    ];
  }

  Widget _buildMenu(BuildContext context) {
    final filtered = _filteredOptions();
    final children = <Widget>[];

    if (filtered.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(12),
          child: accountingHelperText(context, widget.emptyText),
        ),
      );
    } else {
      final grouped = <(bool, String?), List<AccountingSelectorOption<T>>>{};
      for (final option in filtered) {
        grouped
            .putIfAbsent((
              option.onPressed != null,
              option.onPressed == null ? option.group : null,
            ), () => <AccountingSelectorOption<T>>[])
            .add(option);
      }
      var filteredIndex = 0;
      for (final entry in grouped.entries) {
        final group = entry.key.$2;
        if (group != null && group.isNotEmpty) {
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
              child: Text(
                group,
                key: ValueKey<String>('accounting-selector-group-$group'),
                style: AccountingTypography.helper(context).copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AccountingTheme.of(context).mutedForeground
                      .withValues(alpha: 0.75),
                ),
              ),
            ),
          );
        }
        for (final option in entry.value) {
          final optionIndex = filteredIndex;
          final selected =
              option.onPressed == null &&
              (option.checked ?? (option.value == widget.value));
          final highlighted = _menuOpen && optionIndex == _highlightedIndex;
          final hovered = _menuOpen && optionIndex == _hoveredIndex;
          filteredIndex++;
          children.add(
            MouseRegion(
              onEnter: (_) {
                if (mounted) {
                  setState(() {
                    _hoveredIndex = optionIndex;
                    if (_searchEnabled && option.enabled) {
                      _highlightedIndex = optionIndex;
                    }
                  });
                }
              },
              onExit: (_) {
                if (mounted && _hoveredIndex == optionIndex) {
                  setState(() => _hoveredIndex = -1);
                }
              },
              child: MenuItemButton(
                key: option.key,
                requestFocusOnHover: !_searchEnabled,
                onFocusChange: _searchEnabled
                    ? (focused) {
                        if (focused && mounted && option.enabled) {
                          setState(() => _highlightedIndex = optionIndex);
                        }
                      }
                    : null,
                onPressed: option.enabled ? () => _chooseOption(option) : null,
                closeOnActivate: option.checked == null,
                semanticsLabel: option.label,
                leadingIcon: option.leading,
                style: accountingSelectorOptionStyle(
                  context,
                  selected: selected,
                  hovered: _searchEnabled
                      ? highlighted
                      : hovered || highlighted,
                  managedHighlight: _searchEnabled,
                  grouped: group != null && group.isNotEmpty,
                ),
                child: Semantics(
                  selected: selected,
                  checked: option.checked,
                  child: option.checked == null
                      ? Text(
                          option.label,
                          softWrap: false,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : Row(
                          children: [
                            IgnorePointer(
                              child: ExcludeSemantics(
                                child: AccountingLeadingCheckbox(
                                  undividedRow: true,
                                  value: option.checked!,
                                  onChanged: option.enabled
                                      ? (_) => _chooseOption(option)
                                      : null,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                option.label,
                                softWrap: false,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          );
        }
      }
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.menuMaxHeight),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          key: const ValueKey<String>('accounting-selector-menu-scroll'),
          primary: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// Settings editors expand in place with one shared compact disclosure arrow.
class AccountingSettingsSection extends StatefulWidget {
  const AccountingSettingsSection({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.inCard = false,
  });
  final String title;
  final Widget child;
  final IconData? icon;
  final bool inCard;
  @override
  State<AccountingSettingsSection> createState() =>
      _AccountingSettingsSectionState();
}

class _AccountingSettingsSectionState extends State<AccountingSettingsSection> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => ListTileTheme.merge(
    horizontalTitleGap: accountingContentInset,
    minLeadingWidth: 0,
    shape: widget.inCard ? const RoundedRectangleBorder() : null,
    child: ExpansionTile(
      maintainState: true,
      shape: widget.inCard ? const Border() : null,
      collapsedShape: widget.inCard ? const Border() : null,
      leading: widget.icon == null
          ? null
          : AccountingSettingsIcon(widget.icon!),
      minTileHeight: 56,
      dense: false,
      onExpansionChanged: (value) => setState(() => _expanded = value),
      title: Text(
        widget.title,
        style: AccountingTypography.fieldLabel(context),
      ),
      tilePadding: EdgeInsets.symmetric(horizontal: widget.inCard ? 20 : 12),
      childrenPadding: EdgeInsets.fromLTRB(
        widget.inCard ? 20 : 12,
        12,
        widget.inCard ? 20 : 12,
        20,
      ),
      trailing: AnimatedRotation(
        turns: _expanded ? 0.25 : 0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 160),
        child: const AccountingSettingsIcon(Icons.chevron_right),
      ),
      children: [widget.child],
    ),
  );
}

/// Active tab joins its panel with outward-curving lower shoulders.
class ConnectedTabDecoration extends Decoration {
  const ConnectedTabDecoration({required this.color});
  final Color color;
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _ConnectedTabPainter(color);
}

class _ConnectedTabPainter extends BoxPainter {
  _ConnectedTabPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final rect = offset & configuration.size!;
    const r = 10.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(r)),
      Paint()..color = color,
    );
  }
}

/// Shared icon box for metric summaries, report counts, and reminders.
class AccountingMetricIconBox extends StatelessWidget {
  const AccountingMetricIconBox(
    this.icon, {
    super.key,
    this.iconSize = 20,
    this.fillColor,
    this.foregroundColor,
    this.artwork,
    this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final double iconSize;
  final Color? fillColor;
  final Color? foregroundColor;
  final Widget? artwork;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final artwork =
        this.artwork ??
        Center(
          child: AccountingIcon(
            icon,
            size: iconSize,
            color: foregroundColor ?? tokens.primaryForeground,
          ),
        );
    return Container(
      width: accountingMetricIconExtent,
      height: accountingMetricIconExtent,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: fillColor ?? tokens.primary,
        borderRadius: BorderRadius.circular(accountingControlRadius),
      ),
      child: onPressed == null
          ? artwork
          : Tooltip(
              message: tooltip ?? 'Open review',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onPressed,
                  overlayColor: accountingButtonHover(const ButtonStyle())
                      .overlayColor,
                  child: Semantics(button: true, child: artwork),
                ),
              ),
            ),
    );
  }
}

/// Keeps two information lines at a fixed distance and centers them against
/// their metric icon, even when the value uses a smaller responsive font.
class AccountingMetricTextGroup extends StatelessWidget {
  const AccountingMetricTextGroup({super.key, required this.label, this.value});

  final Widget label;
  final Widget? value;

  @override
  Widget build(BuildContext context) {
    final enlargedText = MediaQuery.textScalerOf(context).scale(1) > 1.2;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: enlargedText ? 0 : accountingMetricIconExtent,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: enlargedText
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          if (value != null) ...[
            const SizedBox(height: accountingMetricLineGap),
            value!,
          ],
        ],
      ),
    );
  }
}

/// Shared geometry for dashboard summaries and reminder tiles.
class AccountingDashboardCard extends StatelessWidget {
  const AccountingDashboardCard({
    super.key,
    required this.title,
    required this.icon,
    required this.value,
    this.detail,
    this.expandedContent,
    this.onTap,
    this.iconFillColor,
    this.iconForegroundColor,
    this.iconArtwork,
    this.expanded = false,
    this.inline = false,
    this.hideStackedValue = false,
    this.compactValue,
    this.preferredValueWidth,
    this.preferredCompactValueWidth,
  });
  final bool expanded;
  final bool inline;
  final bool hideStackedValue;
  final Widget? compactValue;
  final double? preferredValueWidth;
  final double? preferredCompactValueWidth;
  final String title;
  final IconData icon;
  final Color? iconFillColor;
  final Color? iconForegroundColor;
  final Widget? iconArtwork;
  final Widget value;
  final Widget? detail;
  final Widget? expandedContent;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final enlargedText = MediaQuery.textScalerOf(context).scale(1) > 1.2;
    final reminderTitle = Text(
      title,
      maxLines: enlargedText ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: tokens.mutedForeground, height: 1),
    );
    final reminderIcon = AccountingMetricIconBox(
      icon,
      fillColor: iconFillColor,
      foregroundColor: iconForegroundColor,
      artwork: iconArtwork,
    );
    const chevronSize = Size(10, 6);
    const disclosureSize = 22.0;
    final disclosureButton = onTap == null
        ? null
        : Transform.translate(
            // Align the painted chevron, not its transparent hover target.
            offset: Offset(
              (disclosureSize - chevronSize.width) / 2,
              -(disclosureSize - chevronSize.height) / 2,
            ),
            child: Semantics(
              button: true,
              label: expanded ? 'Hide details' : 'Show details',
              child: GestureDetector(
                key: ValueKey('reminder-disclosure-$title'),
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: disclosureSize,
                  height: disclosureSize,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: RotatedBox(
                      quarterTurns: expanded ? 2 : 0,
                      child: const AccountingSelectorChevron(),
                    ),
                  ),
                ),
              ),
            ),
          );
    final textBlock = AccountingMetricTextGroup(
      label: reminderTitle,
      value: detail == null
          ? null
          : DefaultTextStyle.merge(
              maxLines: enlargedText ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              child: detail!,
            ),
    );
    return AccountingCard.surface(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: accountingContentPadding,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final titleWidth = AccountingResponsive.measuredTextWidth(
                  context,
                  title,
                  reminderTitle.style,
                );
                final valueWidth =
                    preferredValueWidth ??
                    (value is Text
                        ? AccountingResponsive.measuredTextWidth(
                            context,
                            (value as Text).data ?? '',
                            (value as Text).style,
                          )
                        : 70.0);
                final fixedWidth =
                    accountingMetricIconExtent +
                    12 +
                    (titleWidth < 80 ? 80 : titleWidth) +
                    AccountingResponsive.groupGap;
                final fullValueWidth =
                    preferredValueWidth == null && valueWidth < 70
                    ? 70.0
                    : valueWidth;
                final useCompactValue =
                    compactValue != null &&
                    preferredCompactValueWidth != null &&
                    constraints.maxWidth < fixedWidth + fullValueWidth &&
                    constraints.maxWidth >=
                        fixedWidth + preferredCompactValueWidth!;
                final shownValue = useCompactValue ? compactValue! : value;
                final shownValueWidth = useCompactValue
                    ? preferredCompactValueWidth!
                    : fullValueWidth;
                final stacked =
                    enlargedText ||
                    constraints.maxWidth < fixedWidth + shownValueWidth;
                return stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              reminderIcon,
                              const SizedBox(width: 12),
                              Expanded(child: textBlock),
                              if (disclosureButton != null) ...[
                                const SizedBox(
                                  width: AccountingResponsive.groupGap,
                                ),
                                disclosureButton,
                              ],
                            ],
                          ),
                          if (!hideStackedValue) ...[
                            const SizedBox(
                              height: AccountingResponsive.groupGap,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: shownValue,
                            ),
                          ],
                        ],
                      )
                    : Row(
                        children: [
                          reminderIcon,
                          const SizedBox(width: 12),
                          Expanded(child: textBlock),
                          const SizedBox(width: AccountingResponsive.groupGap),
                          SizedBox(
                            height: accountingMetricIconExtent,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [?disclosureButton, shownValue],
                            ),
                          ),
                        ],
                      );
              },
            ),
          ),
          ?expandedContent,
        ],
      ),
    );
  }
}

/// Shared label/value geometry used by summary tables and read-only popouts.
class AccountingSummaryValueRow extends StatelessWidget {
  const AccountingSummaryValueRow({
    super.key,
    required this.label,
    required this.value,
    this.heading = false,
    this.firstDataRow = false,
  });
  final String label, value;
  final bool heading, firstDataRow;
  @override
  Widget build(BuildContext context) {
    final headerStyle = AccountingTypography.tableHeader(context);
    return Padding(
      padding: EdgeInsets.only(
        top: heading || firstDataRow
            ? accountingContentInset
            : accountingUndividedRowVerticalInset,
        bottom: heading
            ? accountingContentInset
            : accountingUndividedRowVerticalInset,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: heading
                  ? headerStyle
                  : Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: accountingContentInset),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: heading
                  ? headerStyle
                  : Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cell owner shared with Home's Recent Expenses table.
Widget accountingCompactTableCell(
  String text, {
  TextStyle? style,
  TextAlign textAlign = TextAlign.left,
  double rightInset = AccountingResponsive.groupGap,
  double verticalInset = accountingUndividedRowVerticalInset,
  bool firstDataRow = false,
}) => Padding(
  padding: EdgeInsets.only(
    top: firstDataRow ? accountingContentInset : verticalInset,
    bottom: verticalInset,
    right: rightInset,
  ),
  child: Text(text, style: style, softWrap: true, textAlign: textAlign),
);

/// Sideways Details shares the record-card surface and divided row rhythm.
class AccountingInformationRows extends StatelessWidget {
  const AccountingInformationRows({super.key, required this.rows});
  final List<(String, String)> rows;
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final style = AccountingTypography.value(context);
    final labelStyle = AccountingTypography.sidewaysDetailsLabel(context);
    final table = Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: IntrinsicColumnWidth(),
        2: FlexColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(color: AccountingTheme.of(context).border),
      ),
      children: [
        for (final (index, row) in rows.indexed)
          TableRow(
            children: [
              Padding(
                padding: AccountingSidewaysDetailsTokens.rowPadding(
                  index,
                  rows.length,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AccountingSidewaysDetailsTokens.maximumLabelWidth,
                  ),
                  child: Text(row.$1, style: labelStyle),
                ),
              ),
              Padding(
                padding:
                    AccountingSidewaysDetailsTokens.rowPadding(
                      index,
                      rows.length,
                    ).copyWith(
                      left: AccountingSidewaysDetailsTokens.columnGap,
                      right: AccountingSidewaysDetailsTokens.columnGap,
                    ),
                child: Text(
                  AccountingSidewaysDetailsTokens.separator,
                  style: style,
                ),
              ),
              Padding(
                padding: AccountingSidewaysDetailsTokens.rowPadding(
                  index,
                  rows.length,
                ),
                child: Text(row.$2, style: style, textAlign: TextAlign.left),
              ),
            ],
          ),
      ],
    );
    return AccountingCard.surface(
      context,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AccountingSidewaysDetailsTokens.horizontalInset,
        ),
        child: table,
      ),
    );
  }
}

/// A compact report table with the same header and content axes as Home's
/// Recent Expenses card.
class AccountingSummaryTableCard extends StatelessWidget {
  const AccountingSummaryTableCard({
    super.key,
    required this.title,
    required this.description,
    required this.labelHeader,
    required this.valueHeader,
    required this.rows,
    this.note,
  });

  final String title;
  final String description;
  final String labelHeader;
  final String valueHeader;
  final List<(String, String)> rows;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    Widget row(
      String label,
      String value, {
      bool heading = false,
      bool firstDataRow = false,
    }) => AccountingSummaryValueRow(
      label: label,
      value: value,
      heading: heading,
      firstDataRow: firstDataRow,
    );
    return AccountingCard.surface(
      context,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: accountingContentPadding,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                accountingSectionTitle(context, title),
                const SizedBox(height: 6),
                accountingHelperText(context, description),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: accountingContentInset,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: tokens.border)),
                  ),
                  child: row(labelHeader, valueHeader, heading: true),
                ),
                for (var index = 0; index < rows.length; index++)
                  row(rows[index].$1, rows[index].$2, firstDataRow: index == 0),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 20),
                    child: accountingHelperText(context, note!),
                  )
                else
                  const SizedBox(
                    height:
                        accountingContentInset -
                        accountingUndividedRowVerticalInset,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AccountingTotalRow extends StatelessWidget {
  const AccountingTotalRow({
    super.key,
    required this.label,
    required this.value,
  });
  final String label, value;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AccountingTheme.of(context).muted,
      // This is a short inner row, so it follows the standard control radius;
      // the surrounding card owns the large section radius.
      borderRadius: BorderRadius.circular(accountingControlRadius),
    ),
    child: DefaultTextStyle.merge(
      style: const TextStyle(fontWeight: FontWeight.w600),
      child: LayoutBuilder(
        builder: (context, constraints) {
          double textWidth(String text) {
            final painter = TextPainter(
              text: TextSpan(
                text: text,
                style: DefaultTextStyle.of(context).style,
              ),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final width = painter.width;
            painter.dispose();
            return width;
          }

          if (textWidth(label) + 12 + textWidth(value) > constraints.maxWidth) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(label),
                const SizedBox(height: 8),
                Text(value, textAlign: TextAlign.right),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: Text(label)),
              const SizedBox(width: 12),
              Text(value),
            ],
          );
        },
      ),
    ),
  );
}

/// Record actions form one consistent icon group beside the amount.
class AccountingRecordActions extends StatelessWidget {
  const AccountingRecordActions({
    super.key,
    this.actions = const [],
    required this.trailing,
  });
  final List<Widget> actions;
  final List<Widget> trailing;
  Widget group(List<Widget> items) => Wrap(
    alignment: WrapAlignment.end,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: accountingRecordIconGap,
    runSpacing: accountingRecordIconGap,
    children: items,
  );
  @override
  Widget build(BuildContext context) =>
      AccountingButtonSizeScope(child: group([...actions, ...trailing]));
}

/// Wraps page controls at their content widths. An optional final control
/// remains right-aligned on whichever row it fits, with the same gap rule.
class AccountingControlFlow extends StatelessWidget {
  const AccountingControlFlow({
    super.key,
    required this.children,
    this.widths,
    this.trailing,
    this.trailingWidth,
    this.spacing = AccountingResponsive.groupGap,
    this.runSpacing,
    this.crossAxisAlignment = WrapCrossAlignment.start,
  }) : assert(widths == null || widths.length == children.length),
       assert(trailing == null || trailingWidth != null);

  final List<Widget> children;
  final List<double>? widths;
  final Widget? trailing;
  final double? trailingWidth;
  final double spacing;
  final double? runSpacing;
  final WrapCrossAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    if (trailing == null) {
      return Wrap(
        spacing: spacing,
        runSpacing: runSpacing ?? AccountingPageControlScope.runGapOf(context),
        crossAxisAlignment: crossAxisAlignment,
        children: children,
      );
    }
    assert(widths != null);
    return LayoutBuilder(
      builder: (context, constraints) {
        final items = [
          for (var index = 0; index < children.length; index++)
            (children[index], widths![index]),
          (trailing!, trailingWidth!),
        ];
        final rows = <List<(Widget, double)>>[];
        var row = <(Widget, double)>[];
        var rowWidth = 0.0;
        for (final item in items) {
          final needed = row.isEmpty ? item.$2 : spacing + item.$2;
          if (row.isNotEmpty && rowWidth + needed > constraints.maxWidth) {
            rows.add(row);
            row = [];
            rowWidth = 0;
          }
          row.add(item);
          rowWidth += row.length == 1 ? item.$2 : spacing + item.$2;
        }
        if (row.isNotEmpty) rows.add(row);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < rows.length; index++) ...[
              if (index > 0)
                SizedBox(
                  height:
                      runSpacing ??
                      AccountingPageControlScope.runGapOf(context),
                ),
              if (index == rows.length - 1)
                Row(
                  crossAxisAlignment:
                      crossAxisAlignment == WrapCrossAlignment.end
                      ? CrossAxisAlignment.end
                      : crossAxisAlignment == WrapCrossAlignment.center
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: spacing,
                        crossAxisAlignment: crossAxisAlignment,
                        runSpacing:
                            runSpacing ??
                            AccountingPageControlScope.runGapOf(context),
                        children: [
                          for (final item in rows[index].take(
                            rows[index].length - 1,
                          ))
                            item.$1,
                        ],
                      ),
                    ),
                    if (rows[index].length > 1) SizedBox(width: spacing),
                    trailing!,
                  ],
                )
              else
                Wrap(
                  spacing: spacing,
                  crossAxisAlignment: crossAxisAlignment,
                  runSpacing:
                      runSpacing ??
                      AccountingPageControlScope.runGapOf(context),
                  children: [for (final item in rows[index]) item.$1],
                ),
            ],
          ],
        );
      },
    );
  }
}

/// Shared compact record geometry; extra details and workflow actions are optional.
class AccountingRecordRow extends StatelessWidget {
  const AccountingRecordRow({
    super.key,
    required this.title,
    this.titleKey,
    this.titleStyle,
    this.minimumDetailsWidth,
    this.columnGap = accountingContentInset,
    this.topRightInfo = false,
    this.leading,
    this.leadingOverlaysTitle = false,
    this.adaptiveStatusLastLine = false,
    this.trailingWhenStatusLastLine,
    this.status,
    this.compactStatus,
    this.statusWidth,
    this.titleStatusGap = accountingRecordTitleLabelGap,
    this.padding = accountingContentPadding,
    required this.details,
    required this.trailing,
    this.trailingBelow,
    this.actions = const [],
  }) : assert(compactStatus == null || statusWidth != null);
  final bool topRightInfo;
  final bool adaptiveStatusLastLine;
  final Widget? trailingWhenStatusLastLine;
  final String title;
  final TextStyle? titleStyle;
  final double? minimumDetailsWidth;
  final double columnGap;
  final Key? titleKey;
  final Widget? leading;
  final bool leadingOverlaysTitle;
  final Widget? status;
  final Widget? compactStatus;

  /// Natural width from the status owner, including its existing inner padding.
  final double? statusWidth;
  final double titleStatusGap;
  final EdgeInsetsGeometry padding;
  final Widget details;
  final Widget trailing;

  /// Right-hand controls measured from a pinned price, rather than from the
  /// height of the independent left-hand details column.
  final Widget? trailingBelow;
  final List<Widget> actions;
  Widget? get _priceAnchoredActions {
    if (trailingBelow != null) return trailingBelow;
    if (!topRightInfo ||
        actions.length != 1 ||
        actions.single is! AccountingRecordActions) {
      return null;
    }
    return actions.single;
  }

  Widget _pricedRightSide(Widget price, Widget action) {
    final group = action is AccountingRecordActions ? action : null;
    final workflow = group?.actions ?? const <Widget>[];
    final neutral = group?.trailing ?? <Widget>[action];
    final iconGroup = group?.group([...workflow, ...neutral]) ?? action;
    // Amount and controls share the current right column at every width,
    // including dialogs without AccountingPageControlScope ancestors.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        price,
        const SizedBox(height: accountingRecordPriceActionGap),
        iconGroup,
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final titleStyle =
            this.titleStyle ??
            AccountingTypography.value(context).copyWith(
              fontSize: accountingControlFontSize,
              fontWeight: FontWeight.w500,
            );
        final titleMeasure = TextPainter(
          text: TextSpan(text: title, style: titleStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final readableDetailsWidth = math.min(
          240.0,
          math.max(
            160.0,
            titleMeasure.width +
                (leadingOverlaysTitle && leading != null
                    ? 18 + accountingContentInset
                    : leading == null
                    ? 0
                    : 52),
          ),
        );
        final statusOnLastLine =
            adaptiveStatusLastLine &&
            status != null &&
            constraints.maxWidth < titleMeasure.width + 340;
        final titleWidget = Text(
          title,
          key: titleKey,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
        );
        final leadingWidgets = <Widget>[
          if (leading != null) ...[
            if (!leadingOverlaysTitle) ...[leading!, const SizedBox(width: 8)],
          ],
        ];
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, titleConstraints) {
                final statusGap = math.min(
                  titleStatusGap,
                  titleConstraints.maxWidth / 4,
                );
                // The title yields first. Shorten a status only when the full
                // badge itself cannot fit the actual remaining content lane.
                final visibleStatus =
                    compactStatus != null &&
                        statusWidth != null &&
                        titleConstraints.maxWidth + precisionErrorTolerance <
                            statusGap + statusWidth!
                    ? compactStatus
                    : status;
                return Row(
                  children: [
                    ...leadingWidgets,
                    Flexible(child: titleWidget),
                    if (visibleStatus != null && !statusOnLastLine) ...[
                      SizedBox(width: statusGap),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: math.max(
                            0,
                            titleConstraints.maxWidth - statusGap,
                          ),
                        ),
                        child: visibleStatus,
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: accountingRecordInfoLineGap),
            DefaultTextStyle.merge(
              style: AccountingTypography.helper(context),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              child: details,
            ),
            if (statusOnLastLine) ...[
              const SizedBox(height: accountingRecordInfoLineGap),
              Align(
                alignment: Alignment.centerLeft,
                child: compactStatus ?? status!,
              ),
            ],
          ],
        );
        final description = leadingOverlaysTitle && leading != null
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18 + accountingContentInset,
                    child: Transform.translate(
                      // The checkbox mark paints 3px above its nominal box
                      // centre; align the visible mark with the text group.
                      offset: const Offset(0, 3),
                      child: leading!,
                    ),
                  ),
                  Expanded(child: text),
                ],
              )
            : text;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountingRecordBodyLayout(
              details: description,
              minimumDetailsWidth: minimumDetailsWidth ?? readableDetailsWidth,
              actions: AccountingButtonSizeScope(
                child: _priceAnchoredActions == null
                    ? statusOnLastLine && trailingWhenStatusLastLine != null
                          ? trailingWhenStatusLastLine!
                          : trailing
                    : _pricedRightSide(trailing, _priceAnchoredActions!),
              ),
              pinned: topRightInfo,
              columnGap: columnGap,
            ),
            if (actions.isNotEmpty && _priceAnchoredActions == null) ...[
              const SizedBox(height: 12),
              AccountingButtonSizeScope(
                child: Wrap(spacing: 8, runSpacing: 8, children: actions),
              ),
            ],
          ],
        );
      },
    ),
  );
}

/// One policy for operational row lists, independent of row height.
abstract final class AccountingRecordControlsPolicy {
  static const defaultPageSize = 5;
  static const pageSizes = [5, 10, 15, 20, 50];
  static bool visible(int unfilteredCount) => unfilteredCount >= 6;
}

/// View preferences survive leaving/reopening a page in the current app.
/// These are UI choices; they never modify business/accounting records.
abstract final class AccountingRecordPageSizes {
  static final Map<String, int> _values = {};
  static int read(String key, {int fallback = 5}) => _values[key] ?? fallback;
  static void remember(String key, int value) {
    if (value > 0) _values[key] = value;
  }

  @visibleForTesting
  static void reset() => _values.clear();
}

/// Hide the whole filter band and its spacing while retaining editor state.
class AccountingRecordControls extends StatelessWidget {
  const AccountingRecordControls({
    super.key,
    required this.recordCount,
    required this.child,
  });
  final int recordCount;
  final Widget child;
  @override
  Widget build(BuildContext context) => Visibility(
    visible: AccountingRecordControlsPolicy.visible(recordCount),
    maintainState: true,
    child: child,
  );
}

/// Shared record footer, with separate identities for nested search contexts.
class AccountingRecordPagination extends StatelessWidget {
  const AccountingRecordPagination({
    super.key,
    required this.total,
    required this.offset,
    required this.pageSize,
    required this.onPageSizeChanged,
    required this.onPrevious,
    required this.onNext,
    this.keyPrefix = 'record',
    this.pageSizes = const [5, 10, 15, 20, 50],
    this.unfilteredTotal,
  });
  final int total, offset, pageSize;
  final int? unfilteredTotal;
  final List<int> pageSizes;
  final ValueChanged<int> onPageSizeChanged;
  final VoidCallback? onPrevious, onNext;
  final String keyPrefix;
  @override
  Widget build(BuildContext context) => AccountingRecordControls(
    recordCount: unfilteredTotal ?? total,
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Rows',
              key: ValueKey('$keyPrefix-page-size-label'),
              style: AccountingTypography.fieldLabel(context),
            ),
            const SizedBox(width: accountingContentInset),
            AccountingSelector<int>(
              compactToolbar: true,
              value: pageSize,
              hintText: 'Rows',
              controlKey: ValueKey('$keyPrefix-page-size'),
              options: [
                for (final size in pageSizes)
                  AccountingSelectorOption(value: size, label: '$size'),
              ],
              onChanged: (value) {
                if (value != null) {
                  AccountingRecordPageSizes.remember(keyPrefix, value);
                  onPageSizeChanged(value);
                }
              },
            ),
          ],
        ),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Text(
              '${total == 0 ? 0 : offset + 1}–${math.min(offset + pageSize, total)} of $total',
            ),
            AccountingButton.outline(
              context,
              key: ValueKey('$keyPrefix-page-previous'),
              onPressed: onPrevious,
              child: const Text('Previous'),
            ),
            AccountingButton.outline(
              context,
              key: ValueKey('$keyPrefix-page-next'),
              onPressed: onNext,
              child: const Text('Next'),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Connected operational records share their outer surface and separators.
class AccountingRecordList extends StatefulWidget {
  const AccountingRecordList({
    super.key,
    required this.children,
    this.header,
    this.emptyState,
    this.defaultPageSize = AccountingRecordControlsPolicy.defaultPageSize,
    this.externalPagination,
    this.totalCount,
    this.paginationKey = 'record',
  });
  final List<Widget> children;
  final Widget? header;
  final Widget? emptyState;
  final int defaultPageSize;
  final Widget? externalPagination;

  /// Total before search/filtering and before pagination.
  final int? totalCount;
  final String paginationKey;
  @override
  State<AccountingRecordList> createState() => _AccountingRecordListState();
}

class _AccountingRecordListState extends State<AccountingRecordList> {
  late int _pageSize = AccountingRecordPageSizes.read(
    widget.paginationKey,
    fallback: widget.defaultPageSize,
  );
  int _page = 0;
  @override
  void didUpdateWidget(covariant AccountingRecordList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paginationKey != widget.paginationKey) {
      _pageSize = AccountingRecordPageSizes.read(
        widget.paginationKey,
        fallback: widget.defaultPageSize,
      );
      _page = 0;
    }
    if (oldWidget.children.map((w) => w.key).join('|') !=
        widget.children.map((w) => w.key).join('|')) {
      _page = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.children.length;
    final showControls = AccountingRecordControlsPolicy.visible(
      widget.totalCount ?? count,
    );
    final pages = math.max(1, (count / _pageSize).ceil());
    _page = _page.clamp(0, pages - 1);
    final start = widget.externalPagination == null ? _page * _pageSize : 0;
    final end = widget.externalPagination == null
        ? math.min(count, start + _pageSize)
        : count;
    final footer =
        widget.externalPagination ??
        Padding(
          padding: accountingContentPadding,
          child: AccountingRecordPagination(
            keyPrefix: widget.paginationKey,
            total: count,
            unfilteredTotal: widget.totalCount,
            offset: start,
            pageSize: _pageSize,
            onPageSizeChanged: (value) => setState(() {
              AccountingRecordPageSizes.remember(widget.paginationKey, value);
              _pageSize = value;
              _page = 0;
            }),
            onPrevious: _page == 0 ? null : () => setState(() => _page--),
            onNext: _page + 1 >= pages ? null : () => setState(() => _page++),
          ),
        );
    return AccountingCard.surface(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.header != null) ...[
            widget.header!,
            if (count > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: accountingContentInset,
                endIndent: accountingContentInset,
              ),
          ],
          if (count == 0 && widget.emptyState != null) widget.emptyState!,
          for (var index = start; index < end; index++) ...[
            if (index > start)
              const Divider(
                height: 1,
                thickness: 1,
                indent: accountingContentInset,
                endIndent: accountingContentInset,
              ),
            widget.children[index],
          ],
          if (showControls) ...[
            const Divider(
              height: 1,
              thickness: 1,
              indent: accountingContentInset,
              endIndent: accountingContentInset,
            ),
            footer,
          ],
        ],
      ),
    );
  }
}

class _RecordBodyData extends ContainerBoxParentData<RenderBox> {}

/// Existing measured details/actions geometry, also used by media footers.
/// This layout owns no surface, typography, button styles or content insets.
class AccountingRecordBodyLayout extends MultiChildRenderObjectWidget {
  AccountingRecordBodyLayout({
    super.key,
    required Widget details,
    required Widget actions,
    required this.minimumDetailsWidth,
    this.pinned = false,
    this.columnGap = accountingContentInset,
  }) : super(children: [details, actions]);
  final bool pinned;
  final double minimumDetailsWidth;
  final double columnGap;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRecordBody(pinned, minimumDetailsWidth, columnGap);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderBox renderObject,
  ) {
    final body = renderObject as _RenderRecordBody;
    body.pinned = pinned;
    body.minimumDetailsWidth = minimumDetailsWidth;
    body.columnGap = columnGap;
    body.markNeedsLayout();
  }
}

class _RenderRecordBody extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _RecordBodyData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _RecordBodyData> {
  _RenderRecordBody(this.pinned, this.minimumDetailsWidth, this.columnGap);
  bool pinned;
  double minimumDetailsWidth;
  double columnGap;
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _RecordBodyData) {
      child.parentData = _RecordBodyData();
    }
  }

  Size _layout(BoxConstraints constraints, {required bool dry}) {
    final details = firstChild!;
    final actions = lastChild!;
    final width = constraints.maxWidth;
    Size measure(RenderBox child, BoxConstraints limits) {
      if (dry) return child.getDryLayout(limits);
      child.layout(limits, parentUsesSize: true);
      return child.size;
    }

    final actionSize = measure(
      actions,
      BoxConstraints(maxWidth: pinned ? width * 0.55 : width),
    );
    // Text was measured by the widget owner. Intrinsic queries would enter its
    // nested LayoutBuilder and fail in real modal and demo layouts.
    final minimumDetails = math.min(width, minimumDetailsWidth);
    // Content-measured columns can differ by a floating-point fraction after
    // equal-gap distribution. That must not push a fitting row below its header.
    final inline =
        pinned ||
        width - actionSize.width - columnGap >=
            minimumDetails - precisionErrorTolerance;
    final detailSize = measure(
      details,
      BoxConstraints.tightFor(
        width: inline ? width - actionSize.width - columnGap : width,
      ),
    );
    final height = inline
        ? math.max(detailSize.height, actionSize.height)
        : detailSize.height + 12 + actionSize.height;
    if (!dry) {
      // The title/detail gap is fixed inside `details`. Move that group as a
      // unit when the opposite side makes the row taller; otherwise the offset
      // is zero and the ordinary outer inset remains intact.
      (details.parentData as _RecordBodyData).offset = Offset(
        0,
        inline ? (height - detailSize.height) / 2 : 0,
      );
      (actions.parentData as _RecordBodyData).offset = Offset(
        inline ? width - actionSize.width : (width - actionSize.width) / 2,
        inline ? (height - actionSize.height) / 2 : detailSize.height + 12,
      );
    }
    return constraints.constrain(Size(width, height));
  }

  @override
  void performLayout() => size = _layout(constraints, dry: false);
  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layout(constraints, dry: true);
  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class AccountingRecordFilter extends StatelessWidget {
  const AccountingRecordFilter({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.controlKey,
  });
  final String label;
  final Iterable<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final Key? controlKey;
  @override
  Widget build(BuildContext context) {
    final choices = options.where((s) => s.trim().isNotEmpty).toSet().toList()
      ..sort();
    return SizedBox(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          accountingFieldLabel(context, label),
          const SizedBox(height: accountingFieldLabelGap),
          AccountingSelector<String>(
            value: value ?? '',
            controlKey: controlKey,
            hintText: 'All',
            semanticsLabel: 'Filter by $label',
            options: [
              const AccountingSelectorOption(value: '', label: 'All'),
              for (final option in choices)
                AccountingSelectorOption(value: option, label: option),
            ],
            onChanged: (value) => onChanged(value == '' ? null : value),
          ),
        ],
      ),
    );
  }
}

Future<bool> confirmAttachmentDeletion(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AccountingDialog.alert(
        dialogContext,
        title: 'Delete attachment?',
        content: const Text('Are you sure you want to delete this attachment?'),
        actions: [
          AccountingButton.outline(
            dialogContext,
            key: null,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          AccountingButton.outline(
            dialogContext,
            key: null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ==
    true;

/// Stroke bounds meet the 10x6 box: no invisible font-glyph padding.
class _TightSelectorChevron extends CustomPainter {
  const _TightSelectorChevron(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    const halfStroke = 1.0;
    final path = Path()
      ..moveTo(halfStroke, halfStroke)
      ..lineTo(size.width / 2, size.height - halfStroke)
      ..lineTo(size.width - halfStroke, halfStroke);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = halfStroke * 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TightSelectorChevron oldDelegate) =>
      color != oldDelegate.color;
}

/// Standalone page text uses the same inset as record/card contents.
class AccountingPageText extends StatelessWidget {
  const AccountingPageText(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: accountingContentInset),
    child: Text(text),
  );
}
