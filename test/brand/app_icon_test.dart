import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracend/shared/brand/tracend_mark.dart';

/// `tool/render_app_icon.sh` sets this to write the rendered masters into the
/// iOS asset catalog; a normal test run only checks them.
const _writeAssets = bool.fromEnvironment('TRACEND_RENDER_BRAND_ASSETS');

const _appIcons = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
const _launchImages = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';

/// The launch screen's mark is 132 points, the size the intro draws it at.
const _launchMarkPoints = 132;

/// The tinted icon is grayscale: iOS tints it by brightness.
const _tintedLetter = Color(0xFFFFFFFF);
const _tintedArc = Color(0xFFC8C8C8);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the app icon renders as an opaque 1024 square with no alpha', () async {
    final pixels = await _rasterize(
      const TracendMarkPainter(background: TracendBrandColors.graphite),
      1024,
    );
    expect(_isOpaque(pixels), isTrue);
    expect(_pixel(pixels, 1024, 0, 0), TracendBrandColors.graphite);
    // The dot's centre, the T's bar and the arc's body carry the brand colours.
    expect(_pixel(pixels, 1024, 623, 472), TracendBrandColors.lime);
    expect(_pixel(pixels, 1024, 560, 290), TracendBrandColors.chalk);
    expect(_pixel(pixels, 1024, 420, 700), TracendBrandColors.lime);

    final png = _encodePng(pixels, 1024, alpha: false);
    final header = _PngHeader.parse(png);
    expect(header.width, 1024);
    expect(header.height, 1024);
    expect(header.hasAlpha, isFalse);

    if (_writeAssets) {
      File('$_appIcons/Icon-App-1024x1024@1x.png').writeAsBytesSync(png);
      await _writeVariants();
    }
  });

  test('every icon Contents.json lists is present at its size', () {
    final listed = _checkCatalog(_appIcons, pointsFor: _iconPoints);
    for (final image in listed) {
      final appearance = _appearance(image);
      final header = _PngHeader.parse(
        File('$_appIcons/${image['filename']}').readAsBytesSync(),
      );
      // The App Store and the home screen icon take no transparency; the
      // dark icon is transparent so iOS can lay its own dark backdrop.
      expect(
        header.hasAlpha,
        appearance == 'dark',
        reason: '${image['filename']} alpha',
      );
    }
    expect(listed.map(_appearance).toSet(), {
      null,
      'dark',
      'tinted',
    }, reason: 'the iOS 18 dark and tinted icons');
  });

  test('the launch image is the 132-point mark at each scale', () {
    final listed = _checkCatalog(
      _launchImages,
      pointsFor: (_) => _launchMarkPoints.toDouble(),
    );
    expect(listed.map((image) => image['scale']).toSet(), {'1x', '2x', '3x'});
  });
}

/// Writes the dark and tinted icon masters and the 3x launch image; the
/// script scales the rest from them.
Future<void> _writeVariants() async {
  final dark = await _rasterize(const TracendMarkPainter(), 1024);
  File(
    '$_appIcons/Icon-App-Dark-1024x1024@1x.png',
  ).writeAsBytesSync(_encodePng(dark, 1024, alpha: true));

  final tinted = await _rasterize(
    const TracendMarkPainter(
      background: Color(0xFF000000),
      letterColor: _tintedLetter,
      arcColor: _tintedArc,
      dotColor: _tintedArc,
    ),
    1024,
  );
  File(
    '$_appIcons/Icon-App-Tinted-1024x1024@1x.png',
  ).writeAsBytesSync(_encodePng(tinted, 1024, alpha: false));

  const launchPixels = _launchMarkPoints * 3;
  final launch = await _rasterize(const TracendMarkPainter(), launchPixels);
  File(
    '$_launchImages/LaunchImage@3x.png',
  ).writeAsBytesSync(_encodePng(launch, launchPixels, alpha: true));
}

/// Checks each image an asset catalog's Contents.json lists exists at its
/// pixel size and that the folder holds no unlisted PNG; returns the list.
List<Map<String, Object?>> _checkCatalog(
  String folder, {
  required double Function(Map<String, Object?> image) pointsFor,
}) {
  final contents =
      jsonDecode(File('$folder/Contents.json').readAsStringSync())
          as Map<String, Object?>;
  final images = (contents['images']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final listed = <String>{};
  for (final image in images) {
    final name = image['filename']! as String;
    listed.add(name);
    final scale = int.parse((image['scale']! as String).replaceAll('x', ''));
    final pixels = (pointsFor(image) * scale).round();
    final header = _PngHeader.parse(File('$folder/$name').readAsBytesSync());
    expect(header.width, pixels, reason: '$name width');
    expect(header.height, pixels, reason: '$name height');
  }
  final present = Directory(folder)
      .listSync()
      .map((entry) => entry.uri.pathSegments.last)
      .where((name) => name.endsWith('.png'))
      .toSet();
  expect(present, listed, reason: 'PNGs in $folder');
  return images;
}

double _iconPoints(Map<String, Object?> image) =>
    double.parse((image['size']! as String).split('x').first);

String? _appearance(Map<String, Object?> image) {
  final appearances = image['appearances'] as List<Object?>?;
  if (appearances == null) return null;
  return (appearances.single! as Map<String, Object?>)['value']! as String;
}

Future<Uint8List> _rasterize(TracendMarkPainter painter, int pixels) async {
  final recorder = ui.PictureRecorder();
  painter.paint(ui.Canvas(recorder), Size.square(pixels.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(pixels, pixels);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

bool _isOpaque(Uint8List rgba) {
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] != 0xFF) return false;
  }
  return true;
}

Color _pixel(Uint8List rgba, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return Color.fromARGB(rgba[i + 3], rgba[i], rgba[i + 1], rgba[i + 2]);
}

/// An 8-bit PNG of [rgba]: truecolour with alpha, or plain truecolour (no
/// alpha channel at all, as App Store icons need) when [alpha] is false.
Uint8List _encodePng(Uint8List rgba, int size, {required bool alpha}) {
  final channels = alpha ? 4 : 3;
  final rows = BytesBuilder(copy: false);
  for (var y = 0; y < size; y++) {
    final row = Uint8List(1 + size * channels);
    for (var x = 0; x < size; x++) {
      final from = (y * size + x) * 4;
      final to = 1 + x * channels;
      row.setRange(to, to + channels, rgba, from);
    }
    rows.add(row);
  }
  final header = ByteData(13)
    ..setUint32(0, size)
    ..setUint32(4, size)
    ..setUint8(8, 8)
    ..setUint8(9, alpha ? 6 : 2);
  return (BytesBuilder(copy: false)
        ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        ..add(_chunk('IHDR', header.buffer.asUint8List()))
        ..add(_chunk('IDAT', ZLibCodec(level: 9).encode(rows.takeBytes())))
        ..add(_chunk('IEND', Uint8List(0))))
      .takeBytes();
}

Uint8List _chunk(String type, List<int> data) {
  final typed = [...ascii.encode(type), ...data];
  final chunk = ByteData(12 + data.length)..setUint32(0, data.length);
  final bytes = chunk.buffer.asUint8List()..setRange(4, 8 + data.length, typed);
  chunk.setUint32(8 + data.length, _crc32(typed));
  return bytes;
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return crc ^ 0xFFFFFFFF;
}

class _PngHeader {
  const _PngHeader(this.width, this.height, this.colorType);

  factory _PngHeader.parse(Uint8List png) {
    final data = ByteData.sublistView(png);
    expect(ascii.decode(png.sublist(12, 16)), 'IHDR');
    return _PngHeader(
      data.getUint32(16),
      data.getUint32(20),
      data.getUint8(25),
    );
  }

  final int width;
  final int height;

  /// 2 is truecolour, 6 truecolour with alpha, 4 grayscale with alpha.
  final int colorType;

  bool get hasAlpha => colorType == 4 || colorType == 6;
}
