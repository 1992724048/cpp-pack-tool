import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/package_icon.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('package_icon_test');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  testWidgets('无图标时渲染默认图标为同尺寸 PNG', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final Uint8List png = await resolvePackageIconPng(
        _pack(sourcePath: root.path),
      );

      expect(_pngSize(png), (width: 48, height: 48));
    });
  });

  testWidgets('SVG 图标转换成功且不放大', (WidgetTester tester) async {
    await tester.runAsync(() async {
      _writeText(
        joinPath(root.path, 'icon.svg'),
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
        'width="24" height="24"><rect width="24" height="24" '
        'fill="red"/></svg>',
      );

      final Uint8List png = await resolvePackageIconPng(
        _pack(sourcePath: root.path, iconPath: 'icon.svg'),
      );

      expect(_pngSize(png), (width: 24, height: 24));
    });
  });

  testWidgets('大尺寸 SVG 等比缩小到最大边长', (WidgetTester tester) async {
    await tester.runAsync(() async {
      _writeText(
        joinPath(root.path, 'icon.svg'),
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 300" '
        'width="300" height="300"><rect width="300" height="300" '
        'fill="blue"/></svg>',
      );

      final Uint8List png = await resolvePackageIconPng(
        _pack(sourcePath: root.path, iconPath: 'icon.svg'),
      );

      expect(_pngSize(png), (width: 128, height: 128));
    });
  });

  testWidgets('位图等比缩小到最大边长', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final Uint8List bitmap = await _renderPng(200, 100);
      _writeBytes(joinPath(root.path, 'icon.png'), bitmap);

      final Uint8List png = await resolvePackageIconPng(
        _pack(sourcePath: root.path, iconPath: 'icon.png'),
      );

      expect(_pngSize(png), (width: 128, height: 64));
    });
  });

  testWidgets('小尺寸位图保持原尺寸', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final Uint8List bitmap = await _renderPng(64, 32);
      _writeBytes(joinPath(root.path, 'icon.png'), bitmap);

      final Uint8List png = await resolvePackageIconPng(
        _pack(sourcePath: root.path, iconPath: 'icon.png'),
      );

      expect(_pngSize(png), (width: 64, height: 32));
    });
  });

  testWidgets('图标文件缺失时回退默认图标', (WidgetTester tester) async {
    await tester.runAsync(() async {
      final Uint8List png = await resolvePackageIconPng(
        _pack(sourcePath: root.path, iconPath: 'missing.png'),
      );

      expect(_pngSize(png), (width: 48, height: 48));
    });
  });

  testWidgets('损坏的位图内容回退默认图标', (WidgetTester tester) async {
    await tester.runAsync(() async {
      _writeBytes(joinPath(root.path, 'icon.png'), <int>[1, 2, 3, 4, 5]);

      final Uint8List png = await resolvePackageIconPng(
        _pack(sourcePath: root.path, iconPath: 'icon.png'),
      );

      expect(_pngSize(png), (width: 48, height: 48));
    });
  });

  testWidgets('损坏的 SVG 内容回退默认图标', (WidgetTester tester) async {
    await tester.runAsync(() async {
      _writeText(joinPath(root.path, 'icon.svg'), 'not an svg at all');

      final Uint8List png = await resolvePackageIconPng(
        _pack(sourcePath: root.path, iconPath: 'icon.svg'),
      );

      expect(_pngSize(png), (width: 48, height: 48));
    });
  });
}

PackModel _pack({String? sourcePath, String? iconPath}) {
  return PackModel(
    name: 'demo',
    version: '1.0.0',
    author: 'tester',
    iconPath: iconPath,
    sourcePath: sourcePath,
  );
}

/// 解析 PNG 的 IHDR 尺寸，同时校验 PNG 签名。
({int width, int height}) _pngSize(Uint8List bytes) {
  expect(bytes.sublist(0, 8), <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ]);
  final ByteData data = ByteData.sublistView(bytes);
  return (width: data.getUint32(16), height: data.getUint32(20));
}

Future<Uint8List> _renderPng(int width, int height) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366FF),
  );
  final ui.Picture picture = recorder.endRecording();
  try {
    final ui.Image image = await picture.toImage(width, height);
    try {
      final ByteData? data = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

void _writeText(String path, String content) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
}

void _writeBytes(String path, List<int> bytes) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}
