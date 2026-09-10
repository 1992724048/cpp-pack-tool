import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
