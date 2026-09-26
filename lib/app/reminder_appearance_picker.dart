import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../features/accounting/domain/workspace_reminder.dart';
import 'accounting_components.dart';
import 'accounting_theme.dart';

/// Supplied artwork with only transparent margins cropped; no contours,
/// substitutions, or per-icon size offsets. Originals remain preserved.
class OriginalReminderIcon extends StatelessWidget {
  const OriginalReminderIcon(
    this.name, {
    super.key,
    required this.color,
    this.size = 20,
  });
  final String name;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Center(
    child: SvgPicture.asset(
      'assets/icons/reminder_cropped/${reminderOriginalIcons[name]!}',
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    ),
  );
}

class ReminderAppearancePicker extends StatefulWidget {
  const ReminderAppearancePicker({
    super.key,
    required this.icon,
    required this.onChanged,
  });
  final String icon;
  final ValueChanged<String> onChanged;
  @override
  State<ReminderAppearancePicker> createState() =>
      _ReminderAppearancePickerState();
}

class _ReminderAppearancePickerState extends State<ReminderAppearancePicker> {
  final _menu = MenuController();
  final _firstIconFocus = FocusNode();
  @override
  void dispose() {
    _firstIconFocus.dispose();
    super.dispose();
  }

  static const _gap = 4.0; // Sidebar highlights have 2px on each side.
  static const _size = accountingSmallControlHeight;
  static const _columns = 6;
  double gridWidth(int columns) => columns * _size + (columns - 1) * _gap;

  Widget grid(int columns, ValueChanged<String> select) => SizedBox(
    key: const ValueKey('reminder-icon-grid'),
    width: gridWidth(columns),
    child: Wrap(
      spacing: _gap,
      runSpacing: _gap,
      children: [
        for (final name in reminderSelectableIcons.keys)
          Tooltip(
            message: name,
            waitDuration: accountingTooltipWaitDuration,
            child: Semantics(
              label: name,
              selected: widget.icon == 'Choice:$name',
              child: MenuItemButton(
                focusNode: name == reminderSelectableIcons.keys.first
                    ? _firstIconFocus
                    : null,
                key: ValueKey('reminder-icon-$name'),
                onPressed: () => select('Choice:$name'),
                style:
                    accountingSelectorOptionStyle(
                      context,
                      selected: widget.icon == 'Choice:$name',
                    ).copyWith(
                      minimumSize: const WidgetStatePropertyAll(
                        Size.square(_size),
                      ),
                      maximumSize: const WidgetStatePropertyAll(
                        Size.square(_size),
                      ),
                      fixedSize: const WidgetStatePropertyAll(
                        Size.square(_size),
                      ),
                      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            accountingSmallIconRadius,
                          ),
                        ),
                      ),
                    ),
                child: OriginalReminderIcon(
                  'Choice:$name',
                  color: AccountingTheme.of(context).foreground,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  void open() {
    if (_menu.isOpen) {
      _menu.close();
    } else {
      _menu.open();
      // The grid is nested inside one menu child. Give its first actual
      // choice focus so Escape dismisses the selector, not the parent form.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _menu.isOpen) _firstIconFocus.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('Card Icon', style: AccountingTypography.fieldLabel(context)),
      const SizedBox(height: accountingFieldLabelGap),
      AccountingMenuAnchor(
        controller: _menu,
        menuWidth: gridWidth(_columns) + 8,
        maxHeight: 220,
        menuChildren: [grid(_columns, widget.onChanged)],
        builder: (context, controller, child) => SizedBox(
          height: accountingControlHeight,
          width: double.infinity,
          child: OutlinedButton(
            key: const ValueKey('reminder-icon-selector'),
            onPressed: open,
            style: AccountingButton.selectorTriggerStyle(context).copyWith(
              backgroundColor: WidgetStatePropertyAll(
                AccountingTheme.of(context).card,
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.only(left: accountingContentInset, right: 14),
              ),
            ),
            child: Row(
              children: [
                OriginalReminderIcon(
                  widget.icon,
                  color: AccountingTheme.of(context).foreground,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.icon.replaceFirst('Choice:', ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AccountingTypography.controlValue(
                      context,
                    ).copyWith(color: AccountingTheme.of(context).foreground),
                  ),
                ),
                const SizedBox(width: 14),
                const AccountingSelectorChevron(),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
