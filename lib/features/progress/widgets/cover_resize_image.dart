import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// The size to decode an image so that [BoxFit.cover] fills a box of
/// [boxWidth] x [boxHeight] pixels without upscaling.
///
/// Cover scales the image until both sides reach the box, so the scale is
/// the larger of the two ratios. That keeps the cropped side at or above the
/// box and the other side at or above it too. An image already smaller than
/// that keeps its own size: the decoder never decodes above the source.
({int width, int height}) coverDecodeSize({
  required int imageWidth,
  required int imageHeight,
  required int boxWidth,
  required int boxHeight,
}) {
  final scale = math.max(boxWidth / imageWidth, boxHeight / imageHeight);
  if (scale >= 1) return (width: imageWidth, height: imageHeight);
  return (
    width: math.max(boxWidth, (imageWidth * scale).ceil()),
    height: math.max(boxHeight, (imageHeight * scale).ceil()),
  );
}

/// Decodes [imageProvider] for a [BoxFit.cover] box of [width] x [height]
/// pixels.
///
/// `cacheWidth` alone under-sizes a landscape or square photo (the height
/// falls short of the box and cover upscales it), and `cacheHeight` alone
/// does the same to a very tall one. The source size is only known once the
/// decoder has read the header, so this asks for the target size there,
/// through the same `getTargetSize` hook as [ResizeImage], and derives both
/// sides from the real aspect ratio.
@immutable
class CoverResizeImage extends ImageProvider<CoverResizeKey> {
  const CoverResizeImage(
    this.imageProvider, {
    required this.width,
    required this.height,
  });

  final ImageProvider<Object> imageProvider;
  final int width;
  final int height;

  @override
  Future<CoverResizeKey> obtainKey(ImageConfiguration configuration) async =>
      CoverResizeKey(
        await imageProvider.obtainKey(configuration),
        width,
        height,
      );

  @override
  ImageStreamCompleter loadImage(
    CoverResizeKey key,
    ImageDecoderCallback decode,
  ) {
    Future<ui.Codec> decodeCover(
      ui.ImmutableBuffer buffer, {
      ui.TargetImageSizeCallback? getTargetSize,
    }) => decode(
      buffer,
      getTargetSize: (intrinsicWidth, intrinsicHeight) {
        final size = coverDecodeSize(
          imageWidth: intrinsicWidth,
          imageHeight: intrinsicHeight,
          boxWidth: width,
          boxHeight: height,
        );
        return ui.TargetImageSize(width: size.width, height: size.height);
      },
    );
    return imageProvider.loadImage(key.source, decodeCover);
  }
}

/// Cache key for [CoverResizeImage]: the source key plus the box size.
@immutable
class CoverResizeKey {
  const CoverResizeKey(this.source, this.width, this.height);

  final Object source;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is CoverResizeKey &&
      other.source == source &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(source, width, height);
}
