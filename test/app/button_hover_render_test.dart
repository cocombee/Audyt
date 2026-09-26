import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audyt/app/accounting_components.dart';
import 'package:audyt/app/accounting_theme.dart';

void main() {
  testWidgets('white semantic and trash buttons darken their rendered fill on hover', (tester) async {
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(theme: AccountingTheme.light(), home: Scaffold(body: RepaintBoundary(key: boundaryKey, child: Builder(builder: (context) => Container(color: Colors.white, padding: const EdgeInsets.all(32), child: Wrap(spacing: 20, children: [
      AccountingButton.outline(context, key: const ValueKey('white'), onPressed: () {}, child: const Text('View')),
      AccountingButton.primary(context, key: const ValueKey('green'), onPressed: () {}, child: const Text('Approve')),
      AccountingButton.destructive(context, key: const ValueKey('red'), onPressed: () {}, child: const Text('Decline')),
      AccountingButton.iconOnly(context, key: const ValueKey('trash'), onPressed: () {}, icon: Icons.delete_outline, tooltip: 'Trash'),
      AccountingButton.outline(context, key: const ValueKey('disabled'), onPressed: null, child: const Text('Locked')),
    ])))))));
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: const Offset(1, 1));
    Future<List<int>> sample(String key) async {
      final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final rect = tester.getRect(find.byKey(ValueKey(key)));
      final local = boundary.globalToLocal(Offset(rect.left + 8, rect.center.dy));
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final index = (local.dy.floor() * image.width + local.dx.floor()) * 4;
      final rgb = [bytes.getUint8(index), bytes.getUint8(index + 1), bytes.getUint8(index + 2)];
      image.dispose();
      return rgb;
    }
    for (final key in ['white', 'green', 'red', 'trash', 'disabled']) {
      await pointer.moveTo(const Offset(1, 1));
      await tester.pumpAndSettle();
      final idle = (await tester.runAsync(() => sample(key)))!;
      await pointer.moveTo(tester.getCenter(find.byKey(ValueKey(key))));
      await tester.pumpAndSettle();
      final hovered = (await tester.runAsync(() => sample(key)))!;
      if (key == 'disabled') {
        expect(hovered, idle);
      } else {
        expect(hovered.reduce((a,b) => a+b), lessThan(idle.reduce((a,b) => a+b)), reason: '$key must darken its fill');
      }
    }
    await pointer.removePointer();
  });
}
