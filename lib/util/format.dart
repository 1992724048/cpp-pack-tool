const int _bytesPerUnit = 1024;
const List<String> _sizeUnits = ['B', 'KB', 'MB', 'GB'];
final RegExp _pathSeparator = RegExp(r'[/\\]');
final RegExp _trailingPathSeparators = RegExp(r'[/\\]+$');

String baseName(String path) => path.split(_pathSeparator).last;

String joinPath(String base, String relative) =>
    '${base.replaceFirst(_trailingPathSeparators, '')}/$relative';

String formatError(Object error) {
  if (error is ArgumentError) {
    final String? message = error.message?.toString();
    if (message != null && message.isNotEmpty) {
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
