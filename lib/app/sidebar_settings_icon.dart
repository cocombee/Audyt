import 'package:flutter/material.dart';

import 'accounting_icons.dart';
import 'accounting_theme.dart';

class SidebarSettingsIcon extends StatelessWidget {
  const SidebarSettingsIcon({super.key, this.color});
  final Color? color;
  @override
  Widget build(BuildContext context) =>
      AccountingIcon(Icons.settings_outlined, size: 17, color: color);
}

/// The existing sidebar Settings surface, also used by popout shortcuts.
class AccountingSettingsIconBox extends StatelessWidget {
  const AccountingSettingsIconBox({
    super.key,
    this.surfaceKey,
    required this.highlighted,
  });
  final bool highlighted;
  final Key? surfaceKey;
  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    return SizedBox.square(
      dimension: accountingControlHeight,
      child: Center(
        child: DecoratedBox(
          key: surfaceKey,
          decoration: BoxDecoration(
            color: highlighted
                ? accountingNeutralHighlight
                : Colors.transparent,
            borderRadius: BorderRadius.circular(accountingControlRadius),
          ),
          child: SizedBox.square(
            dimension: accountingSmallControlHeight,
            child: SidebarSettingsIcon(
              color: highlighted ? tokens.foreground : tokens.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}

class AccountingSettingsShortcut extends StatefulWidget {
  const AccountingSettingsShortcut({super.key, required this.onPressed});
  final VoidCallback? onPressed;
  @override
  State<AccountingSettingsShortcut> createState() =>
      _AccountingSettingsShortcutState();
}

class _AccountingSettingsShortcutState
    extends State<AccountingSettingsShortcut> {
  bool highlighted = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => highlighted = true),
    onExit: (_) => setState(() => highlighted = false),
    child: SizedBox.square(
      dimension: accountingControlHeight,
      child: IconButton(
        onPressed: widget.onPressed,
        tooltip: 'Settings',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(
          width: accountingControlHeight,
          height: accountingControlHeight,
        ),
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        icon: AccountingSettingsIconBox(highlighted: highlighted),
      ),
    ),
  );
}
