const int _maxVersionPart = 2147483647;
const int _versionPartCount = 4;

final RegExp _digitsPattern = RegExp(r'^[0-9]+$');
final RegExp _identifierPattern = RegExp(r'^[0-9A-Za-z-]+$');
final RegExp _metadataPattern = RegExp(r'^[0-9A-Za-z-.]+$');

const String _requiredMessage = '请输入版本范围';
const String _floatingMessage = '不支持浮版本（*），请填写具体版本或区间';
const String _formatMessage = '版本范围格式无效';
const String _singleValueMessage = '单值范围必须写成 [版本] 形式';
const String _versionMessage = '版本号格式无效';
const String _orderMessage = '下限高于上限';
const String _zeroWidthMessage = '区间宽度为零，请使用 [版本] 表示';

/// 校验 NuGet 风格的版本范围写法；合法返回 null，非法返回中文错误描述。
String? versionRangeError(String input) {
  final String text = input.trim();
  if (text.isEmpty) {
    return _requiredMessage;
  }
  if (text.contains('*')) {
    return _floatingMessage;
  }
  if (text.startsWith('[') || text.startsWith('(')) {
    return _intervalError(text);
  }
  if (text.contains(',') ||
      text.contains('[') ||
      text.contains(']') ||
      text.contains('(') ||
      text.contains(')')) {
    return _formatMessage;
  }
  return _parseVersion(text) == null ? _versionMessage : null;
}

bool isValidVersionRange(String input) => versionRangeError(input) == null;

String? _intervalError(String text) {
  final bool lowerInclusive = text.startsWith('[');
  final String last = text[text.length - 1];
  if (last != ']' && last != ')') {
    return _formatMessage;
  }
  final bool upperInclusive = last == ']';
  final String inner = text.substring(1, text.length - 1);
  if (inner.contains('[') ||
      inner.contains(']') ||
      inner.contains('(') ||
      inner.contains(')')) {
    return _formatMessage;
  }
  final List<String> parts = inner.split(',');
  if (parts.length == 1) {
    return _singleValueError(parts.single, lowerInclusive, upperInclusive);
  }
  if (parts.length != 2) {
    return _formatMessage;
  }
  return _boundsError(
    parts[0].trim(),
    parts[1].trim(),
    lowerInclusive,
    upperInclusive,
  );
}

String? _singleValueError(
  String raw,
  bool lowerInclusive,
  bool upperInclusive,
) {
  if (!lowerInclusive || !upperInclusive) {
    return _singleValueMessage;
  }
  final String value = raw.trim();
  if (value.isEmpty) {
    return _formatMessage;
  }
  return _parseVersion(value) == null ? _versionMessage : null;
}

String? _boundsError(
  String lowerText,
  String upperText,
  bool lowerInclusive,
  bool upperInclusive,
) {
  if (lowerText.isEmpty && upperText.isEmpty) {
    return _formatMessage;
  }
  final _ParsedVersion? lower = lowerText.isEmpty
      ? null
      : _parseVersion(lowerText);
  final _ParsedVersion? upper = upperText.isEmpty
      ? null
      : _parseVersion(upperText);
  if (lowerText.isNotEmpty && lower == null) {
    return _versionMessage;
  }
  if (upperText.isNotEmpty && upper == null) {
    return _versionMessage;
  }
  if (lower == null || upper == null) {
    return null;
  }
  final int order = _compareVersions(lower, upper);
  if (order > 0) {
    return _orderMessage;
  }
  if (order == 0 && !(lowerInclusive && upperInclusive)) {
    return _zeroWidthMessage;
  }
  return null;
}

class _ParsedVersion {
  const _ParsedVersion({required this.parts, required this.preRelease});

  final List<int> parts;
  final List<String> preRelease;
}

_ParsedVersion? _parseVersion(String text) {
  final int metadataIndex = text.indexOf('+');
  final String coreAndPreRelease;
  if (metadataIndex >= 0) {
    if (text.indexOf('+', metadataIndex + 1) >= 0) {
      return null;
    }
    final String metadata = text.substring(metadataIndex + 1);
    if (metadata.isEmpty || !_metadataPattern.hasMatch(metadata)) {
      return null;
    }
    coreAndPreRelease = text.substring(0, metadataIndex);
  } else {
    coreAndPreRelease = text;
  }

  final String core;
  final List<String> preRelease;
  final int dashIndex = coreAndPreRelease.indexOf('-');
  if (dashIndex >= 0) {
    core = coreAndPreRelease.substring(0, dashIndex);
    preRelease = coreAndPreRelease.substring(dashIndex + 1).split('.');
    for (final String identifier in preRelease) {
      if (!_isValidIdentifier(identifier)) {
        return null;
      }
    }
  } else {
    core = coreAndPreRelease;
    preRelease = const <String>[];
  }

  final List<String> segments = core.split('.');
  if (segments.isEmpty || segments.length > _versionPartCount) {
    return null;
  }
  final List<int> parts = <int>[];
  for (final String segment in segments) {
    if (!_digitsPattern.hasMatch(segment)) {
      return null;
    }
    final int? value = int.tryParse(segment);
    if (value == null || value > _maxVersionPart) {
      return null;
    }
    parts.add(value);
  }
  return _ParsedVersion(parts: parts, preRelease: preRelease);
}

bool _isValidIdentifier(String identifier) {
  if (identifier.isEmpty || !_identifierPattern.hasMatch(identifier)) {
    return false;
  }
  final bool numericWithLeadingZero =
      identifier.length > 1 &&
      identifier.startsWith('0') &&
      _digitsPattern.hasMatch(identifier);
  return !numericWithLeadingZero;
}

int _compareVersions(_ParsedVersion first, _ParsedVersion second) {
  for (var index = 0; index < _versionPartCount; index++) {
    final int firstPart = index < first.parts.length ? first.parts[index] : 0;
    final int secondPart = index < second.parts.length
        ? second.parts[index]
        : 0;
    if (firstPart != secondPart) {
      return firstPart < secondPart ? -1 : 1;
    }
  }
  final bool firstPreRelease = first.preRelease.isNotEmpty;
  final bool secondPreRelease = second.preRelease.isNotEmpty;
  if (firstPreRelease != secondPreRelease) {
    return firstPreRelease ? -1 : 1;
  }
  final int count = first.preRelease.length < second.preRelease.length
      ? first.preRelease.length
      : second.preRelease.length;
  for (var index = 0; index < count; index++) {
    final int result = _compareIdentifiers(
      first.preRelease[index],
      second.preRelease[index],
    );
    if (result != 0) {
      return result;
    }
  }
  return first.preRelease.length.compareTo(second.preRelease.length);
}

int _compareIdentifiers(String first, String second) {
  final bool firstNumeric = _digitsPattern.hasMatch(first);
  final bool secondNumeric = _digitsPattern.hasMatch(second);
  if (firstNumeric && secondNumeric) {
    if (first.length != second.length) {
      return first.length < second.length ? -1 : 1;
    }
    return _compareStrings(first, second);
  }
  if (firstNumeric != secondNumeric) {
    return firstNumeric ? -1 : 1;
  }
  return _compareStrings(first.toLowerCase(), second.toLowerCase());
}

int _compareStrings(String first, String second) {
  final int result = first.compareTo(second);
  if (result < 0) {
    return -1;
  }
  if (result > 0) {
    return 1;
  }
  return 0;
}
