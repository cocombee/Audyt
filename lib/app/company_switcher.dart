import 'package:flutter/material.dart';

import 'accounting_components.dart';
import 'accounting_theme.dart';
import 'frontend_review.dart';
import 'demo_company.dart';
import 'restored_company.dart';
import '../features/accounting/application/restored_workspaces.dart';

/// Isolated company selection preview. Never changes the live workspace owner.
class CompanySwitcher extends StatefulWidget {
  const CompanySwitcher({super.key});
  @override
  State<CompanySwitcher> createState() => _CompanySwitcherState();
}

class _CompanySwitcherState extends State<CompanySwitcher> {
  String _company = 'Example Company A';
  int _section = 0;
  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: AccountingSelector<String>(
                  options: const [
                    AccountingSelectorOption(
                      value: 'Example Company A',
                      label: 'Example Company A',
                    ),
                    AccountingSelectorOption(
                      value: 'Example Company B',
                      label: 'Example Company B',
                    ),
                  ],
                  value: _company,
                  hintText: 'Select Company',
                  onChanged: (value) {
                    if (value != null) setState(() => _company = value);
                  },
                ),
              ),
              AccountingButton.ghost(
                context,
                key: null,
                onPressed: () => Navigator.pop(context),
                child: const Text('Return To Current Company'),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Company preview · Example companies contain no live records. Switching clears this preview; your current books remain open separately.',
          ),
        ),
        AccountingTabs(
          keyPrefix: "company-preview-tabs",
          labels: const ['Sales', 'Purchases', 'Banking'],
          selectedIndex: _section,
          onChanged: (i) => setState(() => _section = i),
        ),
        Expanded(
          child: FrontendAreaPage(
            key: ValueKey('$_company-$_section'),
            area: const [
              'sales-customers',
              'expenses-vendors',
              'banking',
            ][_section],
            title: _company,
          ),
        ),
      ],
    ),
  );
}

/// The sidebar uses the same one-click, selected-option popup as form fields.
class CompanySelector extends StatefulWidget {
  const CompanySelector({super.key, this.compact = false, this.companyName});
  final bool compact;
  final String? companyName;
  @override
  State<CompanySelector> createState() => _CompanySelectorState();
}

class _CompanySelectorState extends State<CompanySelector> {
  RestoredWorkspaceCatalog? _catalog;
  bool _failed = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final catalog = await const RestoredWorkspaces().list();
      if (mounted && generation == _generation) {
        setState(() {
          _catalog = catalog;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    final demo = DemoCompany.active(context);
    final restored = RestoredCompany.of(context);
    final savedName = widget.companyName?.trim() ?? '';
    const legalTypeFallback = 'Legal Type Not Set';
    final title = demo
        ? 'Demo Company'
        : savedName.isNotEmpty
        ? savedName
        : 'Current Company';
    final currentOptionLabel = !demo && restored == null && savedName.isNotEmpty
        ? savedName
        : 'Current Company';
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = widget.compact ? 340.0 : constraints.maxWidth;
        return accountingSelectionMenuScrollbarHidden(
          context,
          child: AccountingMenuAnchor(
            menuWidth: width,
            maxHeight: 360,
            onOpen: _load,
            style: accountingSelectorMenuStyle(context, width, 360),
            menuChildren: [
              for (final option in [
                (false, currentOptionLabel),
                (true, 'Demo Company'),
              ])
                SizedBox(
                  width: width - 8,
                  child: MenuItemButton(
                    key: ValueKey(
                      option.$1
                          ? 'company-option-demo'
                          : 'company-option-current',
                    ),
                    onPressed: () {
                      if (option.$1 == demo && restored == null) return;
                      if (option.$1) {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const DemoCompanyPage(),
                          ),
                        );
                      } else {
                        Navigator.of(context)
                            .popUntil((route) => route.isFirst);
                      }
                    },
                    style: accountingSelectorOptionStyle(
                      context,
                      selected: option.$1 == demo && restored == null,
                    ),
                    child: Semantics(
                      selected: option.$1 == demo && restored == null,
                      child: Text(option.$2),
                    ),
                  ),
                ),
              for (final entry
                  in _catalog?.entries ?? <RestoredWorkspaceEntry>[])
                SizedBox(
                  width: width - 8,
                  child: MenuItemButton(
                    key: ValueKey('company-option-restored-${entry.id}'),
                    onPressed: !entry.available
                        ? null
                        : () {
                            if (restored?.id == entry.id) return;
                            Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) =>
                                    RestoredCompanyPage(path: entry.path),
                              ),
                            );
                          },
                    style: accountingSelectorOptionStyle(
                      context,
                      selected: restored?.id == entry.id,
                    ),
                    child: Semantics(
                      selected: restored?.id == entry.id,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.available
                                ? '$legalTypeFallback (Restored) · ${entry.createdAt.toLocal().day.toString().padLeft(2, '0')}-${entry.createdAt.toLocal().month.toString().padLeft(2, '0')}-${entry.createdAt.toLocal().year}'
                                : '$legalTypeFallback (Restored) · Unavailable',
                            style: AccountingTypography.helper(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_failed || (_catalog?.issues ?? 0) > 0)
                SizedBox(
                  width: width - 8,
                  child: MenuItemButton(
                    key: const ValueKey('retry-restored-list'),
                    onPressed: _load,
                    style: accountingSelectorOptionStyle(
                      context,
                      selected: false,
                    ),
                    child: const Text('Restored Copies Unavailable · Retry'),
                  ),
                ),
            ],
            builder: (context, controller, child) => widget.compact
                ? Tooltip(
                    message: 'Company: $title',
                    child: Semantics(
                      button: true,
                      label: 'Company selector, $title selected',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          accountingControlRadius,
                        ),
                        onTap: () => controller.isOpen
                            ? controller.close()
                            : controller.open(),
                        child: Container(
                          key: const ValueKey(
                            'accounting-compact-brand-icon-box',
                          ),
                          width: accountingControlHeight,
                          height: accountingControlHeight,
                          decoration: BoxDecoration(
                            color: tokens.sidebarPrimary,
                            borderRadius: BorderRadius.circular(
                              accountingControlRadius,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : Material(
                    color: tokens.card,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        accountingControlRadius,
                      ),
                      side: BorderSide(color: tokens.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Semantics(
                      button: true,
                      label: 'Company selector, $title selected',
                      child: InkWell(
                        hoverColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        splashFactory: NoSplash.splashFactory,
                        onTap: () => controller.isOpen
                            ? controller.close()
                            : controller.open(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Container(
                                key: const ValueKey('company-selector-logo'),
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: accountingTabBandColor(context),
                                  borderRadius: BorderRadius.circular(
                                    accountingControlRadius,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      demo ? 'Sdn. Bhd.' : legalTypeFallback,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AccountingTypography.helper(
                                        context,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 20),
                              const AccountingSelectorChevron(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}
