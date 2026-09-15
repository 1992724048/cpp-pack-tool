import 'package:cpp_nuget_pack/models/history_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HistoryModel 序列化', () {
    test('toMap/fromMap 往返保留全部字段', () {
      final HistoryModel entry = HistoryModel(
        time: DateTime(2026, 9, 11, 14, 30, 5),
        type: HistoryType.versionChanged,
        message: '版本变更：1.0.0 → 2.0.0',
      );

      final HistoryModel loaded = HistoryModel.fromMap(entry.toMap());

      expect(loaded.time, entry.time);
      expect(loaded.type, HistoryType.versionChanged);
      expect(loaded.message, '版本变更：1.0.0 → 2.0.0');
    });

    test('toMap 写入 ISO8601 时间与类型名', () {
      final HistoryModel entry = HistoryModel(
        time: DateTime(2026, 9, 11, 14, 30, 5),
        type: HistoryType.exported,
        message: '打包导出',
      );

      final Map<String, Object?> map = entry.toMap();

      expect(map['time'], entry.time.toIso8601String());
      expect(map['type'], 'exported');
      expect(map['message'], '打包导出');
    });

    test('fromMap 解析 ISO8601 时间', () {
      final HistoryModel entry = HistoryModel.fromMap(<String, Object?>{
        'time': '2026-09-11T14:30:05',
        'type': 'created',
        'message': '创建包',
      });

      expect(entry.time, DateTime(2026, 9, 11, 14, 30, 5));
    });

    test('fromMap 缺少 time 时抛出 FormatException', () {
      expect(
        () => HistoryModel.fromMap(<String, Object?>{
          'type': 'created',
          'message': '创建包',
        }),
        throwsFormatException,
      );
    });

    test('fromMap time 非法时抛出 FormatException', () {
      expect(
        () => HistoryModel.fromMap(<String, Object?>{
          'time': '昨天',
          'type': 'created',
          'message': '创建包',
        }),
        throwsFormatException,
      );
    });

    test('fromMap 缺少 type 时抛出 FormatException', () {
      expect(
        () => HistoryModel.fromMap(<String, Object?>{
          'time': '2026-09-11T14:30:05',
          'message': '创建包',
        }),
        throwsFormatException,
      );
    });

    test('fromMap 未知 type 时抛出 FormatException', () {
      expect(
        () => HistoryModel.fromMap(<String, Object?>{
          'time': '2026-09-11T14:30:05',
          'type': 'renamed',
          'message': '创建包',
        }),
        throwsFormatException,
      );
    });

    test('fromMap 缺少 message 时抛出 FormatException', () {
      expect(
        () => HistoryModel.fromMap(<String, Object?>{
          'time': '2026-09-11T14:30:05',
          'type': 'created',
        }),
        throwsFormatException,
      );
    });

    test('fromMap message 类型错误时抛出 FormatException', () {
      expect(
        () => HistoryModel.fromMap(<String, Object?>{
          'time': '2026-09-11T14:30:05',
          'type': 'created',
          'message': 42,
        }),
        throwsFormatException,
      );
    });

    test('类型标签覆盖全部类型', () {
      expect(historyTypeLabels, hasLength(HistoryType.values.length));
      expect(historyTypeLabels[HistoryType.created], '创建');
      expect(historyTypeLabels[HistoryType.versionChanged], '版本');
      expect(historyTypeLabels[HistoryType.filesChanged], '映射');
      expect(historyTypeLabels[HistoryType.exported], '打包');
      expect(historyTypeLabels[HistoryType.built], '构建');
    });

    test('built 类型可往返序列化', () {
      final HistoryModel entry = HistoryModel(
        time: DateTime(2026, 9, 16, 10, 30),
        type: HistoryType.built,
        message: '构建成功：耗时 3 分 12 秒',
      );

      final HistoryModel loaded = HistoryModel.fromMap(entry.toMap());

      expect(loaded.type, HistoryType.built);
      expect(loaded.message, '构建成功：耗时 3 分 12 秒');
    });
  });

  group('appendHistoryEntry', () {
    test('追加到末尾且原列表不变', () {
      final HistoryModel first = _entry(0);
      final List<HistoryModel> origin = <HistoryModel>[first];
      final HistoryModel second = _entry(1);

      final List<HistoryModel> updated = appendHistoryEntry(origin, second);

      expect(updated, <HistoryModel>[first, second]);
      expect(origin, <HistoryModel>[first]);
    });

    test('恰好达到上限时不淘汰', () {
      List<HistoryModel> history = <HistoryModel>[];
      for (int index = 0; index < maxHistoryEntries; index++) {
        history = appendHistoryEntry(history, _entry(index));
      }

      expect(history, hasLength(maxHistoryEntries));
      expect(history.first.message, '记录 0');
      expect(history.last.message, '记录 ${maxHistoryEntries - 1}');
    });

    test('超过上限时淘汰最旧记录', () {
      List<HistoryModel> history = <HistoryModel>[];
      for (int index = 0; index < maxHistoryEntries + 5; index++) {
        history = appendHistoryEntry(history, _entry(index));
      }

      expect(history, hasLength(maxHistoryEntries));
      expect(history.first.message, '记录 5');
      expect(history.last.message, '记录 ${maxHistoryEntries + 4}');
    });
  });
}

HistoryModel _entry(int index) {
  return HistoryModel(
    time: DateTime(2026, 1, 1).add(Duration(minutes: index)),
    type: HistoryType.created,
    message: '记录 $index',
  );
}
