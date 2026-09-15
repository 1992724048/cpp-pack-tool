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

/// 时长文本：`45 秒` / `3 分 12 秒` / `3 分` / `1 小时 2 分`；
/// 不足 1 秒按下限 `1 秒` 显示（避免「0 秒」）。
String formatDuration(Duration duration) {
  final int totalSeconds = duration.inSeconds < 1 ? 1 : duration.inSeconds;
  final int hours = totalSeconds ~/ 3600;
  final int minutes = (totalSeconds % 3600) ~/ 60;
  final int seconds = totalSeconds % 60;
  if (hours > 0) {
    return minutes > 0 ? '$hours 小时 $minutes 分' : '$hours 小时';
  }
  if (minutes > 0) {
    return seconds > 0 ? '$minutes 分 $seconds 秒' : '$minutes 分';
  }
  return '$seconds 秒';
}
