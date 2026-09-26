import 'dart:async';

import 'package:flutter/material.dart';

import 'accounting_theme.dart';

/// Shows the shared tooltip beside controls in a vertical icon bar.
class AccountingSideTooltip extends StatefulWidget {
  const AccountingSideTooltip({
    required this.message,
    required this.child,
    this.onLeft = false,
    super.key,
  });

  final String message;
  final Widget child;
  final bool onLeft;

  @override
  State<AccountingSideTooltip> createState() => _AccountingSideTooltipState();
}

class _AccountingSideTooltipState extends State<AccountingSideTooltip> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _overlay = OverlayPortalController();
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        _timer?.cancel();
        _timer = Timer(accountingTooltipWaitDuration, () {
          if (mounted) _overlay.show();
        });
      },
      onExit: (_) {
        _timer?.cancel();
        _overlay.hide();
      },
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _overlay,
          overlayChildBuilder: (context) {
            final theme = TooltipTheme.of(context);
            return Positioned(
              left: 0,
              top: 0,
              child: IgnorePointer(
                child: CompositedTransformFollower(
                  link: _link,
                  targetAnchor: widget.onLeft
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  followerAnchor: widget.onLeft
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  offset: Offset(widget.onLeft ? -12 : 12, 0),
                  showWhenUnlinked: false,
                  child: DecoratedBox(
                    key: ValueKey('side-tooltip-${widget.message}'),
                    decoration: theme.decoration ?? accountingTooltipDecoration,
                    child: Padding(
                      padding: theme.padding ?? accountingTooltipPadding,
                      child: Text(
                        widget.message,
                        style:
                            theme.textStyle ??
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}
