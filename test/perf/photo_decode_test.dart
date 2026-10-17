import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/progress/widgets/cover_resize_image.dart';
import 'package:tracend/features/progress/widgets/photo_widgets.dart';

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// The size of the image the provider hands the widget tree after decoding
/// [bytes] for a cover box of [boxWidth] x [boxHeight] pixels.
Future<Size> _decoded(
  WidgetTester tester,
  Uint8List bytes, {
  required int boxWidth,
  required int boxHeight,
}) async {
  final image = await tester.runAsync(() {
    final decoded = Completer<ui.Image>();
    CoverResizeImage(MemoryImage(bytes), width: boxWidth, height: boxHeight)
        .resolve(ImageConfiguration.empty)
        .addListener(
          ImageStreamListener((info, _) => decoded.complete(info.image)),
        );
    return decoded.future;
  });
  return Size(image!.width.toDouble(), image.height.toDouble());
}

void main() {
  group('coverDecodeSize', () {
    test('a landscape photo is sized by its height, not its width', () {
      // 1800x1200 into a 675x900 box (3x): the height sets the scale.
      final size = coverDecodeSize(
        imageWidth: 1800,
        imageHeight: 1200,
        boxWidth: 675,
        boxHeight: 900,
      );
      expect((size.width, size.height), (1350, 900));
    });

    test('a square photo is sized by its height', () {
      final size = coverDecodeSize(
        imageWidth: 1800,
        imageHeight: 1800,
        boxWidth: 675,
        boxHeight: 900,
      );
      expect((size.width, size.height), (900, 900));
    });

    test('a portrait photo of the box shape is sized by its width', () {
      final size = coverDecodeSize(
        imageWidth: 1800,
        imageHeight: 2400,
        boxWidth: 675,
        boxHeight: 900,
      );
      expect((size.width, size.height), (675, 900));
    });

    test('a taller photo is sized by its width, covering the height', () {
      final size = coverDecodeSize(
        imageWidth: 1080,
        imageHeight: 1920,
        boxWidth: 675,
        boxHeight: 900,
      );
      expect(size.width, 675);
      expect(size.height, greaterThanOrEqualTo(900));
    });

    test('a photo smaller than the box is never enlarged', () {
      final size = coverDecodeSize(
        imageWidth: 300,
        imageHeight: 200,
        boxWidth: 675,
        boxHeight: 900,
      );
      expect((size.width, size.height), (300, 200));
    });
  });

  group('CoverResizeImage decodes', () {
    testWidgets('a landscape photo covers the box without upscaling', (
      tester,
    ) async {
      final bytes = (await tester.runAsync(() => _png(600, 400)))!;
      final size = await _decoded(tester, bytes, boxWidth: 225, boxHeight: 300);
      expect(size, const Size(450, 300));
    });

    testWidgets('a square photo covers the box without upscaling', (
      tester,
    ) async {
      final bytes = (await tester.runAsync(() => _png(600, 600)))!;
      final size = await _decoded(tester, bytes, boxWidth: 225, boxHeight: 300);
      expect(size, const Size(300, 300));
    });

    testWidgets('a portrait photo decodes at the box size', (tester) async {
      final bytes = (await tester.runAsync(() => _png(600, 800)))!;
      final size = await _decoded(tester, bytes, boxWidth: 225, boxHeight: 300);
      expect(size, const Size(225, 300));
    });
  });

  for (final pixelRatio in [2.0, 3.0]) {
    testWidgets('the viewer asks for its box in pixels at ${pixelRatio}x', (
      tester,
    ) async {
      tester.view.physicalSize = Size(390, 844) * pixelRatio;
      tester.view.devicePixelRatio = pixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PrivatePhotoViewer(urls: ['https://example.test/front.jpg']),
          ),
        ),
      );

      expect(tester.getSize(find.byType(Image)), const Size(225, 300));
      final provider = tester.widget<Image>(find.byType(Image)).image;
      expect(provider, isA<CoverResizeImage>());
      expect((provider as CoverResizeImage).width, (225 * pixelRatio).round());
      expect(provider.height, (300 * pixelRatio).round());
    });
  }
}
