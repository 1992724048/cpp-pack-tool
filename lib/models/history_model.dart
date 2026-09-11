enum HistoryType { created, versionChanged, filesChanged, exported }

const int maxHistoryEntries = 100;

const Map<HistoryType, String> historyTypeLabels = <HistoryType, String>{
  HistoryType.created: '创建',
  HistoryType.versionChanged: '版本',
  HistoryType.filesChanged: '映射',
  HistoryType.exported: '打包',
};

class HistoryModel {
  const HistoryModel({
    required this.time,
    required this.type,
    required this.message,
  });

  final DateTime time;
  final HistoryType type;
  final String message;

  Map<String, Object?> toMap() => <String, Object?>{
    'time': time.toIso8601String(),
    'type': type.name,
    'message': message,
  };

  factory HistoryModel.fromMap(Map<String, Object?> map) {
    final Object? timeValue = map['time'];
    if (timeValue is! String) {
      throw const FormatException('历史记录缺少 time 字段');
    }
    final DateTime? time = DateTime.tryParse(timeValue);
    if (time == null) {
      throw const FormatException('历史记录 time 字段格式错误');
    }
    final Object? typeValue = map['type'];
    if (typeValue is! String) {
      throw const FormatException('历史记录缺少 type 字段');
    }
    final HistoryType? type = HistoryType.values.asNameMap()[typeValue];
    if (type == null) {
      throw FormatException('历史记录 type 字段非法：$typeValue');
    }
    final Object? message = map['message'];
    if (message is! String) {
      throw const FormatException('历史记录缺少 message 字段');
    }
    return HistoryModel(time: time, type: type, message: message);
  }
}

List<HistoryModel> appendHistoryEntry(
  List<HistoryModel> history,
  HistoryModel entry,
) {
  final List<HistoryModel> updated = <HistoryModel>[...history, entry];
  if (updated.length <= maxHistoryEntries) {
    return updated;
  }
  return updated.sublist(updated.length - maxHistoryEntries);
}
