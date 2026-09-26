import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Engine image decoding runs in real time. Settling simulated animations or
/// inspecting MemoryImage bytes alone does not prove a preview has painted.
Future<void> pumpDecodedAttachment(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  ImageStream? stream;
  ImageStreamListener? listener;
  var decoded = false;
  Object? failure;
  try {
    while (!decoded && failure == null && DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      final images = find.byType(Image);
      if (stream == null && images.evaluate().length == 1) {
        stream = tester
            .widget<Image>(images)
            .image
            .resolve(createLocalImageConfiguration(tester.element(images)));
        listener = ImageStreamListener(
          (info, _) {
            decoded = true;
            info.dispose();
          },
          onError: (error, _) {
            failure = error;
          },
        );
        stream.addListener(listener);
      }
    }
    expect(failure, isNull, reason: 'The actual preview image must decode.');
    expect(
      decoded,
      true,
      reason: 'The actual preview image must be ready before capture.',
    );
  } finally {
    if (stream != null && listener != null) stream.removeListener(listener);
  }
  await tester.pumpAndSettle();
}
