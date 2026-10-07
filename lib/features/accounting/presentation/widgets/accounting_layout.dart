import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';

import 'dart:math' as math;

import '../../../../app/accounting_components.dart';
import '../../../../app/accounting_theme.dart';
import '../../../../app/responsive.dart';

const double accountingPageTitleOuterGap =
    AccountingResponsive.pageTitleOuterGap;

/// Shared outer bounds for desktop page chrome and its content body.
/// The title's inner content inset remains owned by AccountingPageHeader.
class AccountingPageAlignment extends StatelessWidget {
  const AccountingPageAlignment({
    required this.child,
    super.key,
    this.maxWidth = AccountingResponsive.pageMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final inset = AccountingResponsive.pageInsetFor(media.size.width);
    return Padding(
      padding: EdgeInsets.only(
        left: inset + media.viewPadding.left,
        right: inset + media.viewPadding.right,
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  }
}

class AccountingPageShell extends StatefulWidget {
  const AccountingPageShell({
    required this.child,
    super.key,
    this.maxWidth = AccountingResponsive.pageMaxWidth,
    this.includeTopSafeArea = true,
    this.topInset = AccountingResponsive.pageTitleOuterGap,
  });

  final Widget child;
  final double maxWidth;
  final bool includeTopSafeArea;
  final double topInset;

  @override
  State<AccountingPageShell> createState() => _AccountingPageShellState();
}

class _AccountingPageShellState extends State<AccountingPageShell> {
  final _scrollController = ScrollController();
  double _menuSpace = 0;
  double? _beforeMenuOffset;
  int _menuRequest = 0;
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _reserveMenuSpace(double clearance) async {
    if (!mounted || !_scrollController.hasClients || clearance <= 0) return;
    final request = ++_menuRequest;
    _beforeMenuOffset ??= _scrollController.offset;
    final target = _scrollController.offset + clearance;
    setState(() => _menuSpace = clearance);
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted || request != _menuRequest || !_scrollController.hasClients) {
      return;
    }
    _scrollController.jumpTo(
      math.min(target, _scrollController.position.maxScrollExtent),
    );
    await SchedulerBinding.instance.endOfFrame;
  }

  void _releaseMenuSpace() {
    if (!mounted) return;
    final request = ++_menuRequest;
    final offset = _beforeMenuOffset;
    _beforeMenuOffset = null;
    setState(() => _menuSpace = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          request != _menuRequest ||
          offset == null ||
          !_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(
        math.min(offset, _scrollController.position.maxScrollExtent),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AccountingTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaQuery = MediaQuery.of(context);
        final safeArea = mediaQuery.viewPadding;
        final bottomInset =
            AccountingResponsive.groupGap +
            _menuSpace +
            safeArea.bottom +
            mediaQuery.viewInsets.bottom;

        return Semantics(
          container: true,
          label: 'Main content',
          child: Material(
            color: tokens.background,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context)
                  .copyWith(scrollbars: false),
              child: AccountingMenuViewportScope(
                reserveBelow: _reserveMenuSpace,
                release: _releaseMenuSpace,
                child: PrimaryScrollController(
                  controller: _scrollController,
                  child: SingleChildScrollView(
                    key: const ValueKey('accounting-main-scroll'),
                    primary: true,
                    padding: EdgeInsets.only(
                      top:
                          widget.topInset +
                          (widget.includeTopSafeArea ? safeArea.top : 0),
                      bottom: bottomInset,
                    ),
                    child: AccountingPageAlignment(
                      maxWidth: widget.maxWidth,
                      child: AccountingPageControlScope(child: widget.child),
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

class AccountingPageHeader extends StatelessWidget {
  const AccountingPageHeader({
    required this.routeLabel,
    required this.title,
    required this.description,
    super.key,
    this.action,
    this.secondaryActions = const [],
    this.titleKey,
    this.eyebrow,
  });

  final String routeLabel;
  final String title;
  final String description;
  final Widget? action;
  final List<Widget> secondaryActions;
  final String? titleKey;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final titleBlock = Padding(
          padding: const EdgeInsets.only(left: accountingContentInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Semantics(
                header: true,
                child: accountingPageTitle(
                  context,
                  title,
                  key: ValueKey<String>(titleKey ?? 'page-title-$routeLabel'),
                ),
              ),
              const SizedBox(height: AccountingResponsive.titleSubtitleGap),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AccountingResponsive.pageHeaderDescriptionMaxWidth,
                ),
                child: Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AccountingTypography.helper(context),
                ),
              ),
            ],
          ),
        );

        final headerAction = action == null
            ? null
            : AccountingButtonGroup(
                compact: false,
                headerAction: true,
                child: action!,
              );
        final minimumTitleWidth = AccountingResponsive.measuredTextWidth(
          context,
          title,
          AccountingTypography.pageTitle(context),
        );
        final headerBody = headerAction == null
            ? titleBlock
            : accountingHeaderBody(
                title: titleBlock,
                actions: headerAction,
                minimumTitleWidth: minimumTitleWidth + accountingContentInset,
                stackedGap: 16,
                stretchStackedActions: false,
              );

        return SizedBox(
          key: const ValueKey('accounting-page-header'),
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeyedSubtree(
                key: const ValueKey('accounting-page-title-row'),
                child: headerBody,
              ),
              if (secondaryActions.isNotEmpty) ...[
                const SizedBox(height: accountingContentInset),
                AccountingControlFlow(
                  spacing: accountingContentInset,
                  children: secondaryActions,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Measures the existing header action group before choosing its established
/// inline/stacked arrangement. No viewport breakpoint or assumed action width.
Widget accountingHeaderBody({
  required Widget title,
  required Widget actions,
  required double minimumTitleWidth,
  double stackedGap = accountingContentInset,
  bool stretchStackedActions = false,
  bool centerInline = false,
}) => _MeasuredHeaderBody(
  title: title,
  actions: actions,
  minimumTitleWidth: minimumTitleWidth,
  stackedGap: stackedGap,
  stretchStackedActions: stretchStackedActions,
  centerInline: centerInline,
);

class _HeaderBodyData extends ContainerBoxParentData<RenderBox> {}

class _MeasuredHeaderBody extends MultiChildRenderObjectWidget {
  _MeasuredHeaderBody({
    required Widget title,
    required Widget actions,
    required this.minimumTitleWidth,
    required this.stackedGap,
    required this.stretchStackedActions,
    required this.centerInline,
  }) : super(children: [title, actions]);

  final double minimumTitleWidth;
  final double stackedGap;
  final bool stretchStackedActions;
  final bool centerInline;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHeaderBody(
    minimumTitleWidth,
    stackedGap,
    stretchStackedActions,
    centerInline,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeaderBody renderObject,
  ) {
    renderObject
      ..minimumTitleWidth = minimumTitleWidth
      ..stackedGap = stackedGap
      ..stretchStackedActions = stretchStackedActions
      ..centerInline = centerInline
      ..markNeedsLayout();
  }
}

class _RenderHeaderBody extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeaderBodyData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeaderBodyData> {
  _RenderHeaderBody(
    this.minimumTitleWidth,
    this.stackedGap,
    this.stretchStackedActions,
    this.centerInline,
  );
  double minimumTitleWidth;
  double stackedGap;
  bool stretchStackedActions;
  bool centerInline;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HeaderBodyData) {
      child.parentData = _HeaderBodyData();
    }
  }

  Size _layout(BoxConstraints limits, {required bool dry}) {
    final title = firstChild!;
    final actions = lastChild!;
    final width = limits.maxWidth;
    Size measure(RenderBox child, BoxConstraints constraints) {
      if (dry) return child.getDryLayout(constraints);
      child.layout(constraints, parentUsesSize: true);
      return child.size;
    }

    var actionSize = measure(actions, BoxConstraints(maxWidth: width));
    final inline =
        width - actionSize.width - accountingContentInset >=
        minimumTitleWidth - precisionErrorTolerance;
    final titleSize = measure(
      title,
      BoxConstraints.tightFor(
        width: inline
            ? width - actionSize.width - accountingContentInset
            : width,
      ),
    );
    if (!inline && stretchStackedActions) {
      actionSize = measure(actions, BoxConstraints.tightFor(width: width));
    }
    final height = inline
        ? math.max(titleSize.height, actionSize.height)
        : titleSize.height + stackedGap + actionSize.height;
    if (!dry) {
      (title.parentData as _HeaderBodyData).offset = Offset(
        0,
        inline && centerInline ? (height - titleSize.height) / 2 : 0,
      );
      (actions.parentData as _HeaderBodyData).offset = Offset(
        width - actionSize.width,
        inline
            ? (centerInline ? (height - actionSize.height) / 2 : 0)
            : titleSize.height + stackedGap,
      );
    }
    return limits.constrain(Size(width, height));
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
