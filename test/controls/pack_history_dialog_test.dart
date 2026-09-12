import 'dart:async';

import 'package:cpp_nuget_pack/controls/pack_history_dialog.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/history_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('无历史记录时显示空态', (tester) async {
    await _pumpDialog(tester, pack: _pack());

    expect(find.byKey(const Key('packHistoryDialog')), findsOneWidget);
    expect(find.text('历史记录'), findsOneWidget);
    expect(find.text('暂无历史记录'), findsOneWidget);
    expect(find.byKey(const Key('historyDeleteButton_0')), findsNothing);
  });

  testWidgets('逆序展示条目并显示类型标签、消息与时间', (tester) async {
    await _pumpDialog(
      tester,
      pack: _pack(
        history: <HistoryModel>[
          HistoryModel(
            time: DateTime(2026, 9, 11, 14, 30, 5),
            type: HistoryType.created,
            message: '创建包：1 个文件',
          ),
          HistoryModel(
            time: DateTime(2026, 9, 12, 9, 0, 0),
            type: HistoryType.versionChanged,
            message: '版本变更：1.0.0 → 2.0.0',
          ),
          HistoryModel(
            time: DateTime(2026, 9, 13, 10, 0, 0),
            type: HistoryType.exported,
            message: r'打包导出：D:\out\demo.nupkg',
          ),
        ],
      ),
    );

    expect(find.text('创建'), findsOneWidget);
    expect(find.text('版本'), findsOneWidget);
    expect(find.text('打包'), findsOneWidget);
    expect(find.text('创建包：1 个文件'), findsOneWidget);
    expect(find.text('2026-09-11 14:30:05'), findsOneWidget);
    expect(find.byKey(const Key('historyDeleteButton_0')), findsOneWidget);
    expect(find.byKey(const Key('historyDeleteButton_2')), findsOneWidget);

    expect(
      tester.getTopLeft(find.text(r'打包导出：D:\out\demo.nupkg')).dy,
      lessThan(tester.getTopLeft(find.text('版本变更：1.0.0 → 2.0.0')).dy),
    );
    expect(
      tester.getTopLeft(find.text('版本变更：1.0.0 → 2.0.0')).dy,
      lessThan(tester.getTopLeft(find.text('创建包：1 个文件')).dy),
    );
  });

  testWidgets('删除条目时回传减少后的历史并提示已删除', (tester) async {
    PackModel? saved;
    await _pumpDialog(
      tester,
      pack: _pack(
        history: <HistoryModel>[
          HistoryModel(
            time: DateTime(2026, 9, 11, 14, 30, 5),
            type: HistoryType.created,
            message: '旧记录',
          ),
          HistoryModel(
            time: DateTime(2026, 9, 12, 9, 0, 0),
            type: HistoryType.exported,
            message: '新记录',
          ),
        ],
      )..buildOptions = <String, String>{'tbb': 'on'},
      onSave: (PackModel pack) async {
        saved = pack;
        return true;
      },
    );

    await tester.tap(find.byKey(const Key('historyDeleteButton_0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved, isNotNull);
    expect(saved!.name, 'demo');
    expect(saved!.files, hasLength(1));
    expect(saved!.history, hasLength(1));
    expect(saved!.history.single.message, '旧记录');
    expect(saved!.buildOptions, <String, String>{'tbb': 'on'});
    expect(find.text('新记录'), findsNothing);
    expect(find.text('已删除'), findsOneWidget);
  });

  testWidgets('删除历史条目后保存的包保留脚本', (tester) async {
    final PackModel pack =
        _pack(
            history: <HistoryModel>[
              HistoryModel(
                time: DateTime(2026, 9, 11, 14, 30, 5),
                type: HistoryType.created,
                message: '旧记录',
              ),
              HistoryModel(
                time: DateTime(2026, 9, 12, 9, 0, 0),
                type: HistoryType.exported,
                message: '新记录',
              ),
            ],
          )
          ..scripts = <ScriptProjectModel>[
            ScriptProjectModel(
              id: 'script_1',
              name: '脚本 1',
              trigger: ScriptTrigger.pre,
            ),
          ];
    PackModel? saved;

    await _pumpDialog(
      tester,
      pack: pack,
      onSave: (PackModel pack) async {
        saved = pack;
        return true;
      },
    );

    await tester.tap(find.byKey(const Key('historyDeleteButton_0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved, isNotNull);
    expect(saved!.history, hasLength(1));
    expect(saved!.scripts, hasLength(1));
    expect(saved!.scripts.single.id, 'script_1');
  });

  testWidgets('保存失败时保留条目且不显示已删除', (tester) async {
    int saveCount = 0;
    await _pumpDialog(
      tester,
      pack: _pack(
        history: <HistoryModel>[
          HistoryModel(
            time: DateTime(2026, 9, 11, 14, 30, 5),
            type: HistoryType.created,
            message: '旧记录',
          ),
          HistoryModel(
            time: DateTime(2026, 9, 12, 9, 0, 0),
            type: HistoryType.exported,
            message: '新记录',
          ),
        ],
      ),
      onSave: (PackModel pack) async {
        saveCount++;
        return false;
      },
    );

    await tester.tap(find.byKey(const Key('historyDeleteButton_0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saveCount, 1);
    expect(find.text('新记录'), findsOneWidget);
    expect(find.text('旧记录'), findsOneWidget);
    expect(find.text('已删除'), findsNothing);
  });

  testWidgets('保存挂起时删除按钮禁用且不重入', (tester) async {
    final Completer<bool> completer = Completer<bool>();
    int saveCount = 0;
    await _pumpDialog(
      tester,
      pack: _pack(
        history: <HistoryModel>[
          HistoryModel(
            time: DateTime(2026, 9, 11, 14, 30, 5),
            type: HistoryType.created,
            message: '旧记录',
          ),
        ],
      ),
      onSave: (PackModel pack) {
        saveCount++;
        return completer.future;
      },
    );

    await tester.tap(find.byKey(const Key('historyDeleteButton_0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('historyDeleteButton_0')));
    await tester.pump();

    expect(saveCount, 1);

    completer.complete(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('暂无历史记录'), findsOneWidget);
    expect(find.text('已删除'), findsOneWidget);
  });

  testWidgets('点击关闭按钮关闭对话框', (tester) async {
    await _pumpDialog(tester, pack: _pack());

    await tester.tap(find.byKey(const Key('packHistoryCloseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('packHistoryDialog')), findsNothing);
  });
}

PackModel _pack({List<HistoryModel> history = const <HistoryModel>[]}) {
  final PackModel pack = PackModel(
    name: 'demo',
    version: '1.0.0',
    author: 'tester',
    sourcePath: r'C:\libs\demo',
  );
  pack.files.add(FileModel(name: 'foo.h', path: 'include/foo.h', size: 128));
  pack.history = List<HistoryModel>.of(history);
  return pack;
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required PackModel pack,
  Future<bool> Function(PackModel pack)? onSave,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FluentApp(
      home: Builder(
        builder: (BuildContext context) => Center(
          child: Button(
            onPressed: () => showPackHistoryDialog(
              context,
              pack: pack,
              onSave: onSave ?? (PackModel pack) async => true,
            ),
            child: const Text('打开对话框'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开对话框'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}
