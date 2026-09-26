import 'package:flutter/material.dart';

import 'accounting_components.dart';
import 'accounting_icons.dart';
import 'accounting_side_tooltip.dart';
import 'accounting_theme.dart';

/// The established receipt editor control, shared with profile photo editing.
class AccountingPhotoButton extends StatelessWidget {
  const AccountingPhotoButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  static const extent = 37.4;

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => AccountingSideTooltip(
    message: tooltip,
    onLeft: [
      'Zoom In',
      'Zoom Out',
      'Zoom to Fit',
      'Undo',
      'Redo',
      'Reset',
      'Apply Crop',
      'Cancel Crop',
    ].contains(tooltip),
    child: Semantics(
      label: tooltip,
      button: true,
      enabled: onPressed != null,
      child: SizedBox(
        width: extent,
        height: extent,
        child: OutlinedButton(
          onPressed: onPressed,
          style: AccountingButton.outlineStyle(context).copyWith(
            backgroundColor: WidgetStatePropertyAll(
              AccountingTheme.of(context).card,
            ),
            minimumSize: const WidgetStatePropertyAll(Size(extent, extent)),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.5)),
            ),
          ),
          child: AccountingIcon(icon, size: 15.3),
        ),
      ),
    ),
  );
}
