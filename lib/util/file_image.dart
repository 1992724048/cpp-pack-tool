import 'dart:io';

import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';

const List<String> _imageExtensions = [
  'png',
  'jpg',
  'jpeg',
  'svg',
  'ico',
  'webp',
];

FileModel? findIconFile(List<FileModel>? files) {
  if (files == null) {
    return null;
  }
  for (final FileModel file in files) {
    if (_imageExtensions.contains(file.extension)) {
      return file;
    }
  }
  return null;
}

Widget buildFileImage(
  String absolutePath, {
  required double size,
  required Widget fallback,
}) {
  if (absolutePath.toLowerCase().endsWith('.svg')) {
    return SvgPicture.file(
      File(absolutePath),
      width: size,
      height: size,
      errorBuilder: (
        BuildContext context,
        Object error,
        StackTrace stackTrace,
      ) => fallback,
    );
  }
  return Image.file(
    File(absolutePath),
    width: size,
    height: size,
    fit: BoxFit.contain,
    errorBuilder: (
      BuildContext context,
      Object error,
      StackTrace? stackTrace,
    ) => fallback,
  );
}
