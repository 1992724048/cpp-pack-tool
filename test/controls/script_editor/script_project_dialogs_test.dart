import 'package:cpp_nuget_pack/controls/script_editor/script_project_dialogs.dart';
import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('新建脚本项目对话框', () {
    testWidgets('默认名称为下一个「脚本 N」，触发时机编译前、构建标签 ALL', (WidgetTester tester) async {
      await _openCreateDialog(
        tester,
        existing: <ScriptProjectModel>[_project(id: 'script_1', name: '脚本 1')],
      );

      expect(
        find.byKey(const Key('createScriptProjectDialog')),
        findsOneWidget,
      );
      expect(find.text('新建脚本项目'), findsWidgets);
      expect(find.text('名称'), findsOneWidget);
      expect(find.text('触发时机'), findsOneWidget);
      expect(find.text('构建标签'), findsOneWidget);
      expect(_createName(tester), '脚本 2');
      expect(
        tester
            .widget<ComboBox<ScriptTrigger>>(
              find.byKey(const Key('createScriptProjectTriggerField')),
            )
            .value,
        ScriptTrigger.pre,
      );
      expect(
        tester
            .widget<ComboBox<BuildModel>>(
              find.byKey(const Key('createScriptProjectBuildModelField')),
            )
            .value,
        BuildModel.all,
      );
      expect(_createConfirm(tester).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('名称清空后显示「名称不能为空」且创建禁用', (WidgetTester tester) async {
      await _openCreateDialog(tester, existing: const <ScriptProjectModel>[]);

      await tester.enterText(
        find.byKey(const Key('createScriptProjectNameField')),
        '   ',
      );
      await tester.pump();

      expect(
        find.byKey(const Key('createScriptProjectNameError')),
        findsOneWidget,
      );
      expect(find.text('名称不能为空'), findsOneWidget);
      expect(_createConfirm(tester).onPressed, isNull);
    });

    testWidgets('大小写不敏感重名显示「名称已存在」且创建禁用', (WidgetTester tester) async {
      await _openCreateDialog(
        tester,
        existing: <ScriptProjectModel>[_project(id: 'script_1', name: 'Build')],
      );

      await tester.enterText(
        find.byKey(const Key('createScriptProjectNameField')),
        'bUiLd',
      );
      await tester.pump();

      expect(find.text('名称已存在'), findsOneWidget);
      expect(_createConfirm(tester).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('createScriptProjectNameField')),
        '生成版本头',
      );
      await tester.pump();

      expect(find.text('名称已存在'), findsNothing);
      expect(_createConfirm(tester).onPressed, isNotNull);
    });

    testWidgets('选择编译后与 Debug 后创建返回名称与所选值', (WidgetTester tester) async {
      NewScriptProjectRequest? result;
      await _openCreateDialog(
        tester,
        existing: <ScriptProjectModel>[_project(id: 'script_1', name: '脚本 1')],
        onResult: (NewScriptProjectRequest? value) => result = value,
      );

      await _selectCombo(
        tester,
        find.byKey(const Key('createScriptProjectTriggerField')),
        '编译后',
      );
      await _selectCombo(
        tester,
        find.byKey(const Key('createScriptProjectBuildModelField')),
        'Debug',
      );
      await tester.tap(
        find.byKey(const Key('createScriptProjectConfirmButton')),
      );
      await _pumpDialogTransition(tester);

      expect(result, isNotNull);
      expect(result!.name, '脚本 2');
      expect(result!.trigger, ScriptTrigger.post);
      expect(result!.buildModel, BuildModel.debug);
      expect(find.byKey(const Key('createScriptProjectDialog')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('取消返回 null', (WidgetTester tester) async {
      NewScriptProjectRequest? result;
      await _openCreateDialog(
        tester,
        existing: const <ScriptProjectModel>[],
        onResult: (NewScriptProjectRequest? value) => result = value,
      );

      await tester.tap(
        find.byKey(const Key('createScriptProjectCancelButton')),
      );
      await _pumpDialogTransition(tester);

      expect(result, isNull);
      expect(find.byKey(const Key('createScriptProjectDialog')), findsNothing);
    });
  });

  group('重命名脚本项目对话框', () {
    testWidgets('预填当前名称，未修改时确定禁用', (WidgetTester tester) async {
      await _openRenameDialog(
        tester,
        project: _project(id: 'script_1', name: '脚本 1'),
        existing: <ScriptProjectModel>[
          _project(id: 'script_1', name: '脚本 1'),
          _project(id: 'script_2', name: '脚本 2'),
        ],
      );

      expect(
        find.byKey(const Key('renameScriptProjectDialog')),
        findsOneWidget,
      );
      expect(find.text('重命名脚本项目'), findsOneWidget);
      expect(_renameName(tester), '脚本 1');
      expect(_renameConfirm(tester).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('与其他项目重名显示「名称已存在」，改名后确定返回新名称', (WidgetTester tester) async {
      String? result;
      await _openRenameDialog(
        tester,
        project: _project(id: 'script_1', name: '脚本 1'),
        existing: <ScriptProjectModel>[
          _project(id: 'script_1', name: '脚本 1'),
          _project(id: 'script_2', name: '脚本 2'),
        ],
        onResult: (String? value) => result = value,
      );

      await tester.enterText(
        find.byKey(const Key('renameScriptProjectNameField')),
        '脚本 2',
      );
      await tester.pump();
      expect(find.text('名称已存在'), findsOneWidget);
      expect(_renameConfirm(tester).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('renameScriptProjectNameField')),
        '  ',
      );
      await tester.pump();
      expect(find.text('名称不能为空'), findsOneWidget);
      expect(_renameConfirm(tester).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('renameScriptProjectNameField')),
        '  生成版本头  ',
      );
      await tester.pump();
      expect(_renameConfirm(tester).onPressed, isNotNull);

      await tester.tap(
        find.byKey(const Key('renameScriptProjectConfirmButton')),
      );
      await _pumpDialogTransition(tester);

      expect(result, '生成版本头');
      expect(find.byKey(const Key('renameScriptProjectDialog')), findsNothing);
    });

    testWidgets('取消返回 null', (WidgetTester tester) async {
      String? result;
      await _openRenameDialog(
        tester,
        project: _project(id: 'script_1', name: '脚本 1'),
        existing: <ScriptProjectModel>[_project(id: 'script_1', name: '脚本 1')],
        onResult: (String? value) => result = value,
      );

      await tester.tap(
        find.byKey(const Key('renameScriptProjectCancelButton')),
      );
      await _pumpDialogTransition(tester);

      expect(result, isNull);
    });
  });

  group('删除脚本项目对话框', () {
    testWidgets('显示项目名与不可恢复提示，确认返回 true', (WidgetTester tester) async {
      bool? result;
      await _openDeleteDialog(
        tester,
        project: _project(id: 'script_1', name: '脚本 1'),
        onResult: (bool value) => result = value,
      );

      expect(
        find.byKey(const Key('deleteScriptProjectDialog')),
        findsOneWidget,
      );
      expect(find.text('删除脚本项目'), findsOneWidget);
      expect(find.text('确定要删除脚本项目「脚本 1」吗？'), findsOneWidget);
      expect(find.text('将移除其节点图，此操作不可恢复。'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('deleteScriptProjectConfirmButton')),
      );
      await _pumpDialogTransition(tester);

      expect(result, isTrue);
      expect(find.byKey(const Key('deleteScriptProjectDialog')), findsNothing);
    });

    testWidgets('取消返回 false', (WidgetTester tester) async {
      bool? result;
      await _openDeleteDialog(
        tester,
        project: _project(id: 'script_1', name: '脚本 1'),
        onResult: (bool value) => result = value,
      );

      await tester.tap(
        find.byKey(const Key('deleteScriptProjectCancelButton')),
      );
      await _pumpDialogTransition(tester);

      expect(result, isFalse);
    });
  });

  group('序号分配与名称校验', () {
    test('nextScriptProjectId 解析 script_(\\d+) 取最大 +1 并忽略不匹配', () {
      final List<ScriptProjectModel> existing = <ScriptProjectModel>[
        _project(id: 'script_1', name: 'A'),
        _project(id: 'script_3', name: 'B'),
        _project(id: 'custom', name: 'C'),
        _project(id: 'script_x', name: 'D'),
      ];

      expect(nextScriptProjectId(existing), 'script_4');
      expect(nextScriptProjectId(const <ScriptProjectModel>[]), 'script_1');
    });

    test('nextScriptProjectName 解析「脚本 N」取最大 +1 并忽略不匹配', () {
      final List<ScriptProjectModel> existing = <ScriptProjectModel>[
        _project(id: 'script_1', name: '脚本 1'),
        _project(id: 'script_2', name: '脚本 3'),
        _project(id: 'script_3', name: '生成版本头'),
        _project(id: 'script_4', name: '脚本 x'),
      ];

      expect(nextScriptProjectName(existing), '脚本 4');
      expect(nextScriptProjectName(const <ScriptProjectModel>[]), '脚本 1');
    });

    test('scriptProjectNameError 大小写不敏感且可排除自身', () {
      final List<ScriptProjectModel> existing = <ScriptProjectModel>[
        _project(id: 'script_1', name: 'Build'),
        _project(id: 'script_2', name: '脚本 2'),
      ];

      expect(scriptProjectNameError(existing: existing, name: '  '), '名称不能为空');
      expect(
        scriptProjectNameError(existing: existing, name: 'bUiLd'),
        '名称已存在',
      );
      expect(
        scriptProjectNameError(
          existing: existing,
          name: 'build',
          excludeId: 'script_1',
        ),
        isNull,
      );
      expect(scriptProjectNameError(existing: existing, name: '新脚本'), isNull);
    });
  });
}

ScriptProjectModel _project({required String id, required String name}) =>
    ScriptProjectModel(id: id, name: name, trigger: ScriptTrigger.pre);

Future<void> _openCreateDialog(
  WidgetTester tester, {
  required List<ScriptProjectModel> existing,
  ValueChanged<NewScriptProjectRequest?>? onResult,
}) async {
  await _pumpHost(
    tester,
    buttonKey: const Key('openCreateDialogButton'),
    label: '打开创建对话框',
    open: (BuildContext context) async {
      final NewScriptProjectRequest? result =
          await showCreateScriptProjectDialog(context, existing: existing);
      onResult?.call(result);
    },
  );
}

Future<void> _openRenameDialog(
  WidgetTester tester, {
  required ScriptProjectModel project,
  required List<ScriptProjectModel> existing,
  ValueChanged<String?>? onResult,
}) async {
  await _pumpHost(
    tester,
    buttonKey: const Key('openRenameDialogButton'),
    label: '打开重命名对话框',
    open: (BuildContext context) async {
      final String? result = await showRenameScriptProjectDialog(
        context,
        project: project,
        existing: existing,
      );
      onResult?.call(result);
    },
  );
}

Future<void> _openDeleteDialog(
  WidgetTester tester, {
  required ScriptProjectModel project,
  ValueChanged<bool>? onResult,
}) async {
  await _pumpHost(
    tester,
    buttonKey: const Key('openDeleteDialogButton'),
    label: '打开删除对话框',
    open: (BuildContext context) async {
      final bool result = await showDeleteScriptProjectDialog(
        context,
        project: project,
      );
      onResult?.call(result);
    },
  );
}

Future<void> _pumpHost(
  WidgetTester tester, {
  required Key buttonKey,
  required String label,
  required Future<void> Function(BuildContext context) open,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FluentApp(
      home: Builder(
        builder: (BuildContext context) => Center(
          child: Button(
            key: buttonKey,
            onPressed: () => open(context),
            child: Text(label),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(buttonKey));
  await _pumpDialogTransition(tester);
}

Future<void> _pumpDialogTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _selectCombo(
  WidgetTester tester,
  Finder field,
  String label,
) async {
  await tester.tap(field);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(label).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

String _createName(WidgetTester tester) => tester
    .widget<TextBox>(find.byKey(const Key('createScriptProjectNameField')))
    .controller!
    .text;

String _renameName(WidgetTester tester) => tester
    .widget<TextBox>(find.byKey(const Key('renameScriptProjectNameField')))
    .controller!
    .text;

FilledButton _createConfirm(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const Key('createScriptProjectConfirmButton')),
);

FilledButton _renameConfirm(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const Key('renameScriptProjectConfirmButton')),
);
