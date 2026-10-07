import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'accounting_theme.dart';

/// User-supplied vectors: fit the longest visible side, never stretch.
class AccountingIcon extends StatelessWidget {
  const AccountingIcon(this.icon, {super.key, this.size = 20, this.color})
    : smallAction = false;
  const AccountingIcon.smallAction(this.icon, {super.key, this.color})
    : size = accountingRecordVisibleIconExtent,
      smallAction = true;
  final IconData icon;
  final Color? color;
  final double size;
  final bool smallAction;
  // Legacy assets need these measured viewBox fractions to reach the small
  // painted longest side. The cropped user-supplied small icons already fill
  // their own viewBoxes and therefore use the full target canvas.
  static const paintedLongestSideFraction = <String, double>{
    '007-calendar.svg': 0.9050,
    '009-wallet.svg': 0.9475,
    '021-upload.svg': 0.7675,
    '022-sidebar.svg': 0.8100,
    '023-add.svg': 0.7250,
    '024-search.svg': 0.9150,
    '025-chevron-right.svg': 0.6600,
    '026-chevron-left.svg': 0.6600,
    '027-chevron-down.svg': 0.6600,
    '028-close.svg': 0.6350,
    '029-folder-open.svg': 0.8150,
    '030-help.svg': 0.8150,
    '039-link-off.svg': 0.9604,
    '047-approve.svg': 0.8150,
    '048-return.svg': 0.6775,
    '049-void.svg': 0.8150,
    '050-payment.svg': 0.8150,
    '055-refresh-outline.svg': 0.8150,
    '057-zoom-in-outline.svg': 0.8575,
    '058-zoom-out-outline.svg': 0.8575,
    '060-coin-outline.svg': (20 + 1.635520) / 24,
    '062-swap.svg': 0.7850,
    '068-coins.svg': 19.5 / 24,
    '070-balance-thin.svg': 760 / 960,
    'top-bar-avatar.svg': 0.9950,
  };

  static const _specialSmallAssets = <String>{
    '013-bell.svg',
    '022-sidebar.svg',
    '024-search.svg',
    '025-chevron-right.svg',
    '026-chevron-left.svg',
    '027-chevron-down.svg',
    '028-close.svg',
    '088-approval-check.svg',
    '030-help.svg',
    '032-warning-sign.svg',
    '033-info.svg',
    '035-error.svg',
    'top-bar-avatar.svg',
  };

  // Optical exceptions stay relative to the shared size. Remove an entry only
  // when that icon's artwork is replaced, not when the baseline changes.
  static const _smallOpticalOffsets = <String, double>{
    '036-eye.svg': 1,
    '037-pencil.svg': -1,
    '044-invoice.svg': 1,
    '065-money-bag.svg': 1,
    '069-category-outline.svg': -1,
    '071-cash-register.svg': 1,
    '075-account-grouping.svg': 1,
  };

  static double smallPaintedExtentForAsset(String asset) =>
      _specialSmallAssets.contains(asset)
      ? 13.5
      : accountingRecordVisibleIconExtent + (_smallOpticalOffsets[asset] ?? 0);

  static double smallCanvasSizeForAsset(String asset) =>
      smallPaintedExtentForAsset(asset) /
      (paintedLongestSideFraction[asset] ?? 1);

  static double rowCanvasSize(IconData icon) =>
      smallCanvasSizeForAsset(smallAssetFor(icon) ?? '');

  // Tight crop centers the existing return silhouette without moving paths
  // or changing its physical stroke. Other utility variants stay untouched.
  static String? smallAssetFor(IconData icon) => icon == Icons.undo
      ? '087-return-centered.svg'
      : _newActionAssets[icon] ?? assets[icon];
  static final _newActionAssets = <IconData, String>{
    Icons.inventory_2_outlined: '090-posted.svg',
    Icons.edit_note_outlined: '091-drafts.svg',
    Icons.filter_alt_off_outlined: '092-clear.svg',
    Icons.rate_review_outlined: '093-review.svg',
    Icons.savings_outlined: '094-savings.svg',
    Icons.sync: '095-sync.svg',
    Icons.check: '088-approval-check.svg',
    Icons.check_rounded: '088-approval-check.svg',
  };
  static final assets = <IconData, String>{
    Icons.dashboard_outlined: '001-home.svg',
    Icons.business_outlined: '002-office.svg',
    Icons.shopping_bag_outlined: '003-shopping-bag.svg',
    Icons.percent_outlined: '004-tax.svg',
    Icons.account_tree_outlined: '005-calculator.svg',
    Icons.account_balance_outlined: '006-bank.svg',
    Icons.calendar_today_outlined: '007-calendar.svg',
    Icons.payments_outlined: '008-money.svg',
    Icons.receipt_long_outlined: '009-wallet.svg',
    Icons.calendar_month_outlined: '010-calendar-1.svg',
    Icons.fact_check_outlined: '011-letter.svg',
    Icons.bar_chart_outlined: '012-pie-chart.svg',
    Icons.notifications_none: '013-bell.svg',
    Icons.insert_chart_outlined: '014-presentation.svg',
    Icons.badge_outlined: '015-police.svg',
    Icons.description_outlined: '016-document.svg',
    Icons.image_outlined: '031-image.svg',
    Icons.file_upload_outlined: '021-upload.svg',
    Icons.view_sidebar_outlined: '022-sidebar.svg',
    Icons.add_rounded: '023-add.svg',
    Icons.add: '023-add.svg',
    Icons.search_rounded: '024-search.svg',
    Icons.chevron_right: '025-chevron-right.svg',
    Icons.chevron_right_rounded: '025-chevron-right.svg',
    Icons.chevron_left_rounded: '026-chevron-left.svg',
    Icons.keyboard_arrow_down: '027-chevron-down.svg',
    Icons.close: '028-close.svg',
    Icons.close_rounded: '028-close.svg',
    Icons.folder_open_outlined: '029-folder-open.svg',
    Icons.balance_outlined: '070-balance-thin.svg',
    Icons.help_outline: '030-help.svg',
    Icons.settings_outlined: '034-controls.svg',
    Icons.tune: '034-controls.svg',
    Icons.warning_rounded: '032-warning-sign.svg',
    Icons.info_rounded: '033-info.svg',
    Icons.error_rounded: '035-error.svg',
    Icons.pending_actions_outlined: '018-draft.svg',
    Icons.receipt_outlined: '019-bill.svg',
    Icons.verified_outlined: 'checked.svg',
    Icons.delete_outline: '020-trash.svg',
    Icons.delete_outline_rounded: '020-trash.svg',
    Icons.visibility_outlined: '036-eye.svg',
    Icons.preview_outlined: '072-preview.svg',
    Icons.edit_outlined: '037-pencil.svg',
    Icons.link_outlined: '038-link.svg',
    Icons.link_off_outlined: '039-link-off.svg',
    Icons.download_outlined: '040-download.svg',
    Icons.checklist_outlined: '041-checklist.svg',
    Icons.history_outlined: '042-history.svg',
    Icons.call_received_outlined: '043-receive.svg',
    Icons.attach_money: '052-receive-money.svg',
    Icons.note_add_outlined: '044-invoice.svg',
    Icons.receipt_long: '045-expense.svg',
    Icons.assignment_turned_in_outlined: '046-voucher.svg',
    Icons.check_circle_outline: '047-approve.svg',
    Icons.undo: '048-return.svg',
    Icons.block: '049-void.svg',
    Icons.payment_outlined: '050-payment.svg',
    Icons.restore: '051-restore.svg',
    Icons.restart_alt: '051-restore.svg',
    Icons.pie_chart_outline: '053-pie-outline.svg',
    Icons.category_outlined: '069-category-outline.svg',
    Icons.stacked_bar_chart_outlined: '054-bar-outline.svg',
    Icons.refresh_outlined: '055-refresh-outline.svg',
    Icons.person_outline: '056-user-outline.svg',
    Icons.zoom_in: '057-zoom-in-outline.svg',
    Icons.zoom_out: '058-zoom-out-outline.svg',
    Icons.list_alt_outlined: '059-list-outline.svg',
    Icons.paid_outlined: '060-coin-outline.svg',
    Icons.more_horiz: '061-more-horizontal.svg',
    Icons.swap_horiz: '062-swap.svg',
    Icons.logout: '089-sign-out.svg',
  };
  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? AccountingTheme.of(context).mutedForeground;
    // Reset reuses the approved small restore artwork, including in photo tools.
    final useSmallAsset = smallAction || icon == Icons.restart_alt;
    final asset = useSmallAsset ? smallAssetFor(icon) : assets[icon];
    // The thin balance symbol paints 760/960 of its canvas. At 17px its
    // visible width matches the neighboring folder mark in labelled buttons.
    final displaySize = smallAction
        ? rowCanvasSize(icon)
        : icon == Icons.balance_outlined && size == 16
        ? 17.0
        : size;
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox(
        width: displaySize,
        height: displaySize,
        child: asset == null
            ? Icon(icon, size: displaySize, color: iconColor)
            : SvgPicture.asset(
                'assets/icons/${useSmallAsset ? 'small/' : ''}$asset',
                fit: BoxFit.contain,
                colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
              ),
      ),
    );
  }
}

/// Only Close X and Remove dash belong to the filled SST-red family.
class AccountingCloseIcon extends StatelessWidget {
  const AccountingCloseIcon({super.key});
  @override
  Widget build(BuildContext context) => const AccountingDismissIcon();
}

class AccountingRemoveIcon extends StatelessWidget {
  const AccountingRemoveIcon({super.key});
  @override
  Widget build(BuildContext context) =>
      const AccountingDismissIcon(remove: true);
}

class AccountingAddIcon extends StatelessWidget {
  const AccountingAddIcon({super.key});
  @override
  Widget build(BuildContext context) => const AccountingDismissIcon(add: true);
}

class AccountingDismissIcon extends StatelessWidget {
  const AccountingDismissIcon({
    super.key,
    this.remove = false,
    this.add = false,
  });
  final bool remove;
  final bool add;
  // Close is the accepted size and optical-weight reference for compact
  // actions. Add/Remove keep its painted 7.65px span in the 28px frame.
  static const controlExtent = 28.0;
  static const canvasSize = 9.835714285714;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: canvasSize,
    child: SvgPicture.asset(
      'assets/icons/${add
          ? 'add-inline'
          : remove
          ? 'remove-inline'
          : 'close-popout'}.svg',
      colorFilter: ColorFilter.mode(
        IconTheme.of(context).color ?? Colors.white,
        BlendMode.srcIn,
      ),
    ),
  );
}

/// Notification content is its own optical family, independent of menus.
class AccountingNotificationIcon extends StatelessWidget {
  const AccountingNotificationIcon(this.icon, {super.key, this.color});
  final IconData icon;
  final Color? color;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 20,
    child: SvgPicture.asset(
      'assets/icons/notification-${AccountingIcon.assets[icon]}',
      colorFilter: ColorFilter.mode(
        color ?? AccountingTheme.of(context).foreground,
        BlendMode.srcIn,
      ),
    ),
  );
}

/// Labelled buttons reuse the measured small-action family and exceptions.
class AccountingButtonIcon extends StatelessWidget {
  const AccountingButtonIcon(
    this.icon, {
    super.key,
    this.size = 16,
    this.color,
  });
  final IconData icon;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => Transform.scale(
    scale: size / 16,
    child: AccountingIcon.smallAction(icon, color: color),
  );
}

/// Profile menu contours match the accepted sidebar Home line weight.
/// Other uses retain their own artwork and optical size.
class AccountingProfileMenuIcon extends StatelessWidget {
  const AccountingProfileMenuIcon(this.icon, {super.key, this.color});
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => Center(
    widthFactor: 1,
    heightFactor: 1,
    child: SizedBox.square(
      dimension: 20,
      child: SvgPicture.asset(
        icon == Icons.email_outlined
            ? 'assets/icons/profile-015-letter.svg'
            : 'assets/icons/profile-${AccountingIcon.assets[icon]}',
        colorFilter: ColorFilter.mode(
          color ?? AccountingTheme.of(context).mutedForeground,
          BlendMode.srcIn,
        ),
      ),
    ),
  );
}

/// Reuse a small SVG directly without altering its paths, stroke or saved size.
class AccountingSettingsIcon extends StatelessWidget {
  const AccountingSettingsIcon(this.icon, {super.key});
  final IconData icon;

  // These already appear in small record, chart or navigation controls.
  // Reuse their artwork and optical sizes instead of normalizing them again.
  static const reusedSmallIcons = <IconData>[
    Icons.payment_outlined,
    Icons.calendar_today_outlined,
    Icons.fact_check_outlined,
    Icons.note_add_outlined,
    Icons.download_outlined,
    Icons.person_outline,
    Icons.history_outlined,
    Icons.receipt_long,
    Icons.assignment_turned_in_outlined,
    Icons.checklist_outlined,
    Icons.chevron_right,
  ];

  @override
  Widget build(BuildContext context) => icon == Icons.person_outline
      ? const AccountingSmallAssetIcon(
          '056-user-outline.svg',
          paintedSizeAdjustment: 2,
        )
      : reusedSmallIcons.contains(icon)
      ? AccountingIcon.smallAction(icon)
      : SizedBox(
          width: accountingRecordVisibleIconExtent,
          height: accountingRecordVisibleIconExtent,
          child: SvgPicture.asset(
            'assets/icons/small/settings-${AccountingIcon.assets[icon]}',
            colorFilter: ColorFilter.mode(
              AccountingTheme.of(context).mutedForeground,
              BlendMode.srcIn,
            ),
          ),
        );
}

class AccountingSmallAssetIcon extends StatelessWidget {
  const AccountingSmallAssetIcon(
    this.asset, {
    super.key,
    this.color,
    this.paintedSizeAdjustment = 0,
  });
  final String asset;
  final Color? color;
  final double paintedSizeAdjustment;

  @override
  Widget build(BuildContext context) {
    final size =
        AccountingIcon.smallCanvasSizeForAsset(asset) +
        paintedSizeAdjustment /
            (AccountingIcon.paintedLongestSideFraction[asset] ?? 1);
    // A tight square constrains both axes. SVG width/height arguments alone
    // can use height as the aspect-ratio anchor and enlarge a wide icon.
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox(
        width: size,
        height: size,
        child: SvgPicture.asset(
          'assets/icons/small/$asset',
          fit: BoxFit.contain,
          colorFilter: ColorFilter.mode(
            color ?? AccountingTheme.of(context).mutedForeground,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}
