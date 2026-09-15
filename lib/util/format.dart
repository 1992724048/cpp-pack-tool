const int _bytesPerUnit = 1024;
const List<String> _sizeUnits = ['B', 'KB', 'MB', 'GB'];
final RegExp _pathSeparator = RegExp(r'[/\\]');
final RegExp _trailingPathSeparators = RegExp(r'[/\\]+$');

String baseName(String path) => path.split(_pathSeparator).last;

String joinPath(String base, String relative) =>
    '${base.replaceFirst(_trailingPathSeparators, '')}/$relative';

/// 路径的父目录（`/` 与 `\` 分隔符均可）；无分隔符或仅以分隔符开头时返回原路径。
String parentDirectory(String path) {
  final int separator = path.lastIndexOf(_pathSeparator);
  return separator <= 0 ? path : path.substring(0, separator);
}

String formatError(Object error) {
  if (error is ArgumentError) {
    final String? message = error.message?.toString();
    if (message != null && message.isNotEmpty) {
      return message;
    }
  }
  if (error is FormatException) {
    final Object message = error.message;
    if (message is String && message.isNotEmpty) {
      return message;
    }
  }
  return error.toString();
}

String formatBytes(int bytes) {
  if (bytes < _bytesPerUnit) {
    return '$bytes B';
  }
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= _bytesPerUnit && unitIndex < _sizeUnits.length - 1) {
    value /= _bytesPerUnit;
    unitIndex++;
  }
  return '${value.toStringAsFixed(1)} ${_sizeUnits[unitIndex]}';
}

String formatTimestamp(DateTime time) {
  String pad(int value, [int width = 2]) =>
      value.toString().padLeft(width, '0');
  return '${pad(time.year, 4)}-${pad(time.month)}-${pad(time.day)} '
      '${pad(time.hour)}:${pad(time.minute)}:${pad(time.second)}';
}
