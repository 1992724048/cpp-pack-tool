import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 包图标最大边长（像素）；超出时等比缩小，不放大。
const int maxPackageIconDimension = 128;

/// 无可用图标或图标转换失败时使用的默认包图标资源。
const String defaultPackageIconAsset = 'assets/icons/cardboard_box.svg';

/// 把 [pack] 的图标解析为 PNG 字节，用于 .nupkg 内的 `images/icon.png`。
///
/// 图标源为相对 [PackModel.sourcePath] 的 [PackModel.iconPath]，SVG 与位图
/// 都输出等比缩放至最长边不超过 [maxPackageIconDimension] 的 PNG；未设置、
/// 文件缺失或转换失败时回退到 [defaultPackageIconAsset]；默认图标也渲染失败
/// 时抛出带中文消息的异常。
Future<Uint8List> resolvePackageIconPng(PackModel pack) async {
  final Uint8List? converted = await _tryConvertIcon(pack);
  return converted ?? await _renderDefaultIcon();
}

Future<Uint8List?> _tryConvertIcon(PackModel pack) async {
  final String? iconPath = pack.iconPath;
  final String? sourcePath = pack.sourcePath;
  if (iconPath == null || iconPath.isEmpty || sourcePath == null) {
    return null;
  }
  final String path = joinPath(sourcePath, iconPath);
  if (!File(path).existsSync()) {
    return null;
  }
  try {
    return await _convertIconFile(path);
  } catch (_) {
    return null;
  }
}

Future<Uint8List> _convertIconFile(String path) async {
  final Uint8List bytes = await File(path).readAsBytes();
  if (baseName(path).toLowerCase().endsWith('.svg')) {
    return _renderSvgBytes(bytes);
  }
  return _convertBitmapBytes(bytes);
}

Future<Uint8List> _renderDefaultIcon() async {
  try {
    final ByteData data = await rootBundle.load(defaultPackageIconAsset);
    return await _renderSvgBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } catch (error) {
    throw StateError('默认包图标渲染失败：$error');
  }
}

Future<Uint8List> _renderSvgBytes(Uint8List bytes) async {
  final PictureInfo info = await vg.loadPicture(SvgBytesLoader(bytes), null);
  try {
    final ui.Size size = info.size;
    if (size.width <= 0 || size.height <= 0) {
      throw const FormatException('SVG 图标尺寸无效');
    }
    return await _encodePicture(info.picture, size);
  } finally {
    info.picture.dispose();
  }
}

Future<Uint8List> _encodePicture(ui.Picture picture, ui.Size sourceSize) async {
  final ({int width, int height}) target = _targetSize(
    sourceSize.width,
    sourceSize.height,
  );
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.scale(
    target.width / sourceSize.width,
    target.height / sourceSize.height,
  );
  canvas.drawPicture(picture);
  final ui.Picture scaled = recorder.endRecording();
  try {
    final ui.Image image = await scaled.toImage(target.width, target.height);
    try {
      return await _encodePng(image);
    } finally {
      image.dispose();
    }
  } finally {
    scaled.dispose();
  }
}

Future<Uint8List> _convertBitmapBytes(Uint8List bytes) async {
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  try {
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ui.Image image = frame.image;
    try {
      final ({int width, int height}) target = _targetSize(
        image.width.toDouble(),
        image.height.toDouble(),
      );
      if (target.width == image.width && target.height == image.height) {
        return await _encodePng(image);
      }
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(recorder);
      canvas.scale(target.width / image.width, target.height / image.height);
      canvas.drawImage(image, ui.Offset.zero, ui.Paint());
      final ui.Picture scaled = recorder.endRecording();
      try {
        final ui.Image scaledImage = await scaled.toImage(
          target.width,
          target.height,
        );
        try {
          return await _encodePng(scaledImage);
        } finally {
          scaledImage.dispose();
        }
      } finally {
        scaled.dispose();
      }
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

Future<Uint8List> _encodePng(ui.Image image) async {
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) {
    throw StateError('图标 PNG 编码失败');
  }
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

({int width, int height}) _targetSize(double width, double height) {
  final double longest = math.max(width, height);
  if (longest <= maxPackageIconDimension) {
    return (width: _pixelCount(width), height: _pixelCount(height));
  }
  final double scale = maxPackageIconDimension / longest;
  return (
    width: _pixelCount(width * scale),
    height: _pixelCount(height * scale),
  );
}

int _pixelCount(double value) => math.max(1, value.round());
