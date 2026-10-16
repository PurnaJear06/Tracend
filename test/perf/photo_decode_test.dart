import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/features/progress/widgets/photo_widgets.dart';

void main() {
  for (final pixelRatio in [2.0, 3.0]) {
    testWidgets('photos decode at their layout width at ${pixelRatio}x', (
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

      final image = tester.widget<Image>(find.byType(Image));
      final box = tester.getSize(find.byType(Image));
      expect(box, const Size(225, 300));
      final provider = image.image;
      expect(provider, isA<ResizeImage>());
      expect((provider as ResizeImage).width, (225 * pixelRatio).round());
      expect(provider.height, isNull);
    });
  }
}
