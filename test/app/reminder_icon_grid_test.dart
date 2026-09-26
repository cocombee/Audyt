import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:audyt/app/accounting_theme.dart';
import 'package:audyt/features/accounting/application/accounting_workspace.dart';
import 'package:audyt/features/accounting/domain/workspace_reminder.dart';
import 'package:audyt/features/accounting/presentation/reminders_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'journal_workspace_integration_test.dart' show captureUi;

void main() {
  test(
    'picker collection contains exactly the 44 unmodified supplied icons',
    () {
      expect(reminderSelectableIcons, hasLength(44));
      for (final filename in reminderSelectableIcons.values) {
        expect(
          File('assets/icons/reminder_originals/$filename').readAsBytesSync(),
          File('tool/user_icon_originals/$filename').readAsBytesSync(),
          reason: filename,
        );
      }
    },
  );
  testWidgets('all 44 crops preserve artwork and fill the same 20px canvas', (
    tester,
  ) async {
    await tester.runAsync(() async {
      String artwork(String value) => value.replaceFirstMapped(
        RegExp(r'<svg\b[^>]*>'),
        (match) => match.group(0)!.replaceAll(RegExp(r'\sviewBox="[^"]*"'), ''),
      );
      for (final name in reminderSelectableIcons.values) {
        final original = File('assets/icons/reminder_originals/$name')
            .readAsStringSync();
        final cropped = File('assets/icons/reminder_cropped/$name')
            .readAsStringSync();
        final viewBox = RegExp(r'viewBox="([^"]+)"')
            .firstMatch(original)!
            .group(1)!
            .split(RegExp(r'[ ,]+'))
            .map(double.parse)
            .toList();
        var equivalentOriginal = original;
        for (var i = 0; i < 2; i++) {
          final dimension = i == 0 ? 'width' : 'height';
          final value = viewBox[i + 2]
              .toStringAsFixed(3)
              .replaceFirst(RegExp(r'\.?0+$'), '');
          equivalentOriginal = equivalentOriginal.replaceAll(
            '$dimension="100%"',
            '$dimension="$value"',
          );
        }
        expect(artwork(cropped), artwork(equivalentOriginal), reason: name);
        final info = await vg.loadPicture(SvgStringLoader(cropped), null);
        final scale = 20 / math.max(info.size.width, info.size.height);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)
          ..scale(32)
          ..translate(
            2 + (20 - info.size.width * scale) / 2,
            2 + (20 - info.size.height * scale) / 2,
          )
          ..scale(scale);
        canvas.drawPicture(info.picture);
        final picture = recorder.endRecording();
        final image = await picture.toImage(768, 768);
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var left = 768, top = 768, right = -1, bottom = -1;
        for (var y = 0; y < 768; y++) {
          for (var x = 0; x < 768; x++) {
            if (pixels.getUint8((y * 768 + x) * 4 + 3) == 0) continue;
            left = math.min(left, x);
            top = math.min(top, y);
            right = math.max(right, x);
            bottom = math.max(bottom, y);
          }
        }
        final longest = math.max(right - left + 1, bottom - top + 1) / 32;
        expect(longest, closeTo(20, .13), reason: name);
        expect(left, greaterThanOrEqualTo(63), reason: name);
        expect(top, greaterThanOrEqualTo(63), reason: name);
        expect(right, lessThanOrEqualTo(704), reason: name);
        expect(bottom, lessThanOrEqualTo(704), reason: name);
        image.dispose();
        picture.dispose();
        info.picture.dispose();
      }
    });
  });
  for (final size in [
    const Size(720, 700),
    const Size(1224, 700),
    const Size(720, 520),
  ]) {
    testWidgets(
      'six columns scroll to all supplied icons, select and restart at $size',
      (tester) async {
        final shadows = debugDisableShadows;
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = shadows);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await (FontLoader('Inter')
              ..addFont(rootBundle.load('assets/fonts/Inter-Variable.woff2')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final root = Directory.systemTemp.createTempSync('reminder-icon-grid-');
        addTearDown(() => root.deleteSync(recursive: true));
        final path = '${root.path}/ledger.sqlite';
        var w = await AccountingWorkspace.open(path);
        addTearDown(() => w.dispose());
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('workspace-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AccountingTheme.light(),
              home: Scaffold(body: RemindersPage(workspace: w)),
            ),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('new-reminder')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('reminder-name')),
          'Selected Icon',
        );
        final trigger = find.byKey(const ValueKey('reminder-icon-selector'));
        await tester.ensureVisible(trigger);
        await tester.pumpAndSettle();
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        final grid = find.byKey(const ValueKey('reminder-icon-grid'));
        expect(grid, findsOneWidget);
        expect(
          find.descendant(of: grid, matching: find.byType(MenuItemButton)),
          findsNWidgets(44),
        );
        final first = tester.getRect(
          find.byKey(const ValueKey('reminder-icon-Invoice')),
        );
        final second = tester.getRect(
          find.byKey(const ValueKey('reminder-icon-History')),
        );
        expect(first.size, const Size(32, 32));
        expect(second.left - first.right, 4);
        expect(second.top, first.top);
        final names = reminderSelectableIcons.keys.toList();
        final sixth = tester.getRect(
          find.byKey(ValueKey('reminder-icon-${names[5]}')),
        );
        final seventh = tester.getRect(
          find.byKey(ValueKey('reminder-icon-${names[6]}')),
        );
        expect(sixth.top, first.top);
        expect(seventh.left, first.left);
        expect(seventh.top - first.bottom, 4);
        final menuScroll = find
            .ancestor(of: grid, matching: find.byType(Scrollable))
            .first;
        final scroll = tester.state<ScrollableState>(menuScroll);
        expect(scroll.position.axis, Axis.vertical);
        expect(scroll.position.maxScrollExtent, greaterThan(0));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(first.center);
        await tester.pumpAndSettle();
        await captureUi(
          tester,
          'Supplied Reminder Icon Grid Top ${size.width.toInt()}x${size.height.toInt()}',
        );
        await mouse.removePointer();
        final last = find.byKey(const ValueKey('reminder-icon-Folder'));
        await tester.ensureVisible(last);
        await tester.pumpAndSettle();
        expect(scroll.position.pixels, greaterThan(0));
        expect(last.hitTestable(), findsOneWidget);
        final lastRect = tester.getRect(last);
        expect(lastRect.right, lessThanOrEqualTo(size.width));
        expect(lastRect.bottom, lessThanOrEqualTo(size.height));
        await captureUi(
          tester,
          'Supplied Reminder Icon Grid Bottom ${size.width.toInt()}x${size.height.toInt()}',
        );
        await tester.tap(last);
        await tester.pumpAndSettle();
        expect(grid, findsNothing);
        expect(
          w.reminders,
          isEmpty,
          reason: 'Choosing artwork alone must not save the form.',
        );
        await tester.ensureVisible(find.byKey(const ValueKey('reminder-save')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('reminder-save')));
        await tester.pumpAndSettle();
        expect(w.reminders.single.icon, 'Choice:Folder');
        await tester.pumpWidget(const SizedBox.shrink());
        w.dispose();
        w = await AccountingWorkspace.open(path);
        expect(w.reminders.single.icon, 'Choice:Folder');
        expect(w.reminders.single.displayIcon, 'Choice:Folder');
        expect(tester.takeException(), isNull);
        debugDisableShadows = shadows;
      },
    );
  }
  test(
    'legacy default icons vary by saved obligation without changing data',
    () {
      for (final entry in {
        'SSM Annual Return': 'Letter',
        'Income Tax Return': 'Taxes',
        'SST Return': 'Calculator',
      }.entries) {
        final original = WorkspaceReminder.fromJson({
          'id': 'd3c585e1-f2e8-4a47-9872-e23ad3a6865a',
          'title': 'Saved Reminder',
          'obligation': entry.key,
          'agency': 'Reviewed Agency',
          'dueDate': DateTime.now().toIso8601String(),
          'status': 'Not Started',
          'notes': '',
          'legalSource': '',
          'icon': 'Calendar',
        });
        expect(original.displayIcon, 'Choice:${entry.value}');
        expect(original.toJson()['icon'], 'Calendar');
        final selected = WorkspaceReminder.fromJson({
          ...original.toJson(),
          'icon': 'Choice:Calendar',
        });
        expect(selected.displayIcon, 'Choice:Calendar');
      }
    },
  );
}
