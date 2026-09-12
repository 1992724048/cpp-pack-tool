import 'package:cpp_nuget_pack/controls/script_editor/node_inspector.dart';
import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/graph_editor_controller.dart';
import 'package:cpp_nuget_pack/script_editor/msbuild_macros.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/widgets/tag.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('节点属性模式', () {
    testWidgets('头部显示显示名与类型键，无参数节点显示提示', (WidgetTester tester) async {
      final _Harness harness = await _pumpInspector(tester);
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'file.copy');
      await tester.pump();

      expect(find.text('复制'), findsOneWidget);
      expect(find.text('file.copy'), findsOneWidget);
      expect(find.text('该节点没有可编辑参数'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('text 参数渲染 TextBox，编辑即时写回模型', (WidgetTester tester) async {
      final _Harness harness = await _pumpInspector(tester);
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'value.text');
      await tester.pump();

      final Finder field = find.byKey(const Key('inspectorField_value'));
      expect(field, findsOneWidget);
      expect(tester.widget<TextBox>(field).controller!.text, '');

      await tester.enterText(field, 'abc');
      await tester.pump();

      expect(controller.project.nodes.single.params['value'], 'abc');
    });

    testWidgets('boolean 参数渲染 ToggleSwitch，点击写回模型', (WidgetTester tester) async {
      final _Harness harness = await _pumpInspector(tester);
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'value.boolean');
      await tester.pump();

      final Finder toggle = find.byKey(const Key('inspectorField_value'));
      expect(toggle, findsOneWidget);
      expect(tester.widget<ToggleSwitch>(toggle).checked, isFalse);

      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(controller.project.nodes.single.params['value'], isTrue);
    });

    testWidgets('number 参数渲染数值输入框，整数/小数/负数写回 num', (
      WidgetTester tester,
    ) async {
      final _Harness harness = await _pumpInspector(tester);
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'value.number');
      await tester.pump();

      final Finder field = find.byKey(const Key('inspectorField_value'));
      expect(field, findsOneWidget);
      expect(tester.widget<TextBox>(field).controller!.text, '0');

      await tester.enterText(field, '5');
      await tester.pump();
      expect(controller.project.nodes.single.params['value'], isA<int>());
      expect(controller.project.nodes.single.params['value'], 5);

      await tester.enterText(field, '5.5');
      await tester.pump();
      expect(controller.project.nodes.single.params['value'], isA<double>());
      expect(controller.project.nodes.single.params['value'], 5.5);

      await tester.enterText(field, '-3');
      await tester.pump();
      expect(controller.project.nodes.single.params['value'], isA<int>());
      expect(controller.project.nodes.single.params['value'], -3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('number 非数字或非有限值不写回，原值保留', (WidgetTester tester) async {
      final _Harness harness = await _pumpInspector(tester);
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'value.number');
      await tester.pump();

      final Finder field = find.byKey(const Key('inspectorField_value'));
      await tester.enterText(field, '5');
      await tester.pump();
      expect(controller.project.nodes.single.params['value'], 5);

      for (final String invalid in <String>[
        '',
        'abc',
        'NaN',
        'Infinity',
        '-Infinity',
      ]) {
        await tester.enterText(field, invalid);
        await tester.pump();
        expect(
          controller.project.nodes.single.params['value'],
          5,
          reason: '「$invalid」不应写入',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('number 初始文本显示已存储值，缺省用注册表默认 0', (WidgetTester tester) async {
      final ScriptProjectModel project = _project();
      final ScriptNodeModel node = ScriptNodeModel(
        id: 'n1',
        type: 'value.number',
      );
      node.params['value'] = 2.5;
      project.nodes = <ScriptNodeModel>[node];
      final _Harness harness = await _pumpInspector(tester, project: project);
      final GraphEditorController controller = harness.controller!;

      controller.selectNode('n1');
      await tester.pump();
      expect(
        tester
            .widget<TextBox>(find.byKey(const Key('inspectorField_value')))
            .controller!
            .text,
        '2.5',
      );

      controller.clearSelection();
      final String nodeId = controller.addNode('value.number', Offset.zero);
      controller.selectNode(nodeId);
      await tester.pump();
      expect(
        tester
            .widget<TextBox>(find.byKey(const Key('inspectorField_value')))
            .controller!
            .text,
        '0',
      );
    });

    testWidgets('macroKey 下拉列出全部 11 项 MSBuild 宏，选择后写回宏键', (WidgetTester tester) async {
      final _Harness harness = await _pumpInspector(tester);
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'context.macro');
      await tester.pump();

      final Finder field = find.byKey(const Key('inspectorField_macro'));
      final ComboBox<String> combo = tester.widget<ComboBox<String>>(field);
      expect(combo.value, 'OutDir');
      expect(
        combo.items!.map((ComboBoxItem<String> item) => item.value).toList(),
        msbuildMacroKeys,
      );

      await _selectCombo(tester, field, r'$(Configuration)');

      expect(controller.project.nodes.single.params['macro'], 'Configuration');
    });

    testWidgets('logLevel 下拉选项为 信息/警告/错误，选择后写回 info/warn/error', (
      WidgetTester tester,
    ) async {
      final _Harness harness = await _pumpInspector(tester);
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'log.message');
      await tester.pump();

      final Finder field = find.byKey(const Key('inspectorField_level'));
      final ComboBox<String> combo = tester.widget<ComboBox<String>>(field);
      expect(combo.value, 'info');
      expect(
        combo.items!.map((ComboBoxItem<String> item) => item.value).toList(),
        <String>['info', 'warn', 'error'],
      );

      await tester.tap(field);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('信息'), findsWidgets);
      expect(find.text('警告'), findsOneWidget);
      expect(find.text('错误'), findsOneWidget);
      await tester.tap(find.text('错误').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(controller.project.nodes.single.params['level'], 'error');
    });

    testWidgets('stringOperator 下拉选项为 等于/不等于/包含，选择后写回运算符', (
      WidgetTester tester,
    ) async {
      final _Harness harness = await _pumpInspector(tester);
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'logic.compareString');
      await tester.pump();

      final Finder field = find.byKey(const Key('inspectorField_operator'));
      final ComboBox<String> combo = tester.widget<ComboBox<String>>(field);
      expect(combo.value, 'eq');
      expect(
        combo.items!.map((ComboBoxItem<String> item) => item.value).toList(),
        <String>['eq', 'ne', 'contains'],
      );

      await _selectCombo(tester, field, '包含');

      expect(controller.project.nodes.single.params['operator'], 'contains');
    });

    testWidgets('mathOperator 下拉选项为 加/减/乘/除/取模，选择后写回运算符', (
      WidgetTester tester,
    ) async {
      final _Harness harness = await _pumpInspector(tester);
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'math.arithmetic');
      await tester.pump();

      final Finder field = find.byKey(const Key('inspectorField_operator'));
      final ComboBox<String> combo = tester.widget<ComboBox<String>>(field);
      expect(combo.value, 'add');
      expect(
        combo.items!.map((ComboBoxItem<String> item) => item.value).toList(),
        <String>['add', 'subtract', 'multiply', 'divide', 'modulo'],
      );

      await _selectCombo(tester, field, '取模');

      expect(controller.project.nodes.single.params['operator'], 'modulo');
    });

    testWidgets('bitwiseOperator 下拉选项为 与/或/异或/左移/右移，选择后写回运算符', (
      WidgetTester tester,
    ) async {
      final _Harness harness = await _pumpInspector(tester);
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'math.bitwise');
      await tester.pump();

      final Finder field = find.byKey(const Key('inspectorField_operator'));
      final ComboBox<String> combo = tester.widget<ComboBox<String>>(field);
      expect(combo.value, 'and');
      expect(
        combo.items!.map((ComboBoxItem<String> item) => item.value).toList(),
        <String>['and', 'or', 'xor', 'shiftLeft', 'shiftRight'],
      );

      await _selectCombo(tester, field, '左移');

      expect(controller.project.nodes.single.params['operator'], 'shiftLeft');
    });

    testWidgets('numberOperator 下拉选项为 < ≤ > ≥ = ≠，选择后写回运算符', (
      WidgetTester tester,
    ) async {
      final _Harness harness = await _pumpInspector(tester);
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'logic.compareNumber');
      await tester.pump();

      final Finder field = find.byKey(const Key('inspectorField_operator'));
      final ComboBox<String> combo = tester.widget<ComboBox<String>>(field);
      expect(combo.value, 'lt');
      expect(
        combo.items!.map((ComboBoxItem<String> item) => item.value).toList(),
        <String>['lt', 'le', 'gt', 'ge', 'eq', 'ne'],
      );

      await _selectCombo(tester, field, '≠');

      expect(controller.project.nodes.single.params['operator'], 'ne');
    });

    testWidgets('hashAlgorithm 下拉选项为 SHA256/SHA1/SHA512/MD5/CRC32，选择后写回算法', (
      WidgetTester tester,
    ) async {
      final _Harness harness = await _pumpInspector(tester);
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'crypto.fileHash');
      await tester.pump();

      final Finder field = find.byKey(const Key('inspectorField_algorithm'));
      final ComboBox<String> combo = tester.widget<ComboBox<String>>(field);
      expect(combo.value, 'sha256');
      expect(
        combo.items!.map((ComboBoxItem<String> item) => item.value).toList(),
        <String>['sha256', 'sha1', 'sha512', 'md5', 'crc32'],
      );

      await _selectCombo(tester, field, 'CRC32');

      expect(controller.project.nodes.single.params['algorithm'], 'crc32');
    });

    testWidgets('packageFilePath 建议列表来自注入的 packagePaths，选择后写回路径', (
      WidgetTester tester,
    ) async {
      final _Harness harness = await _pumpInspector(
        tester,
        packagePaths: const <String>['lib/x.lib', 'files/x.txt'],
      );
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'context.packageFile');
      await tester.pump();

      final Finder field = find.byKey(const Key('inspectorField_path'));
      expect(field, findsOneWidget);

      await tester.enterText(field, 'x.lib');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('lib/x.lib'), findsOneWidget);

      await tester.tap(find.text('lib/x.lib'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(controller.project.nodes.single.params['path'], 'lib/x.lib');
    });

    testWidgets('packageFilePath 手填自由文本合法（非空即可）', (WidgetTester tester) async {
      final _Harness harness = await _pumpInspector(
        tester,
        packagePaths: const <String>['lib/x.lib'],
      );
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'context.packageFile');
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('inspectorField_path')),
        'custom/path.txt',
      );
      await tester.pump();

      expect(controller.project.nodes.single.params['path'], 'custom/path.txt');
    });

    testWidgets('packageFilePath 无匹配时显示手填提示文案', (WidgetTester tester) async {
      final _Harness harness = await _pumpInspector(
        tester,
        packagePaths: const <String>['lib/x.lib'],
      );
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'context.packageFile');
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('inspectorField_path')),
        'zzz',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('无匹配路径，将按手填内容使用'), findsOneWidget);
    });

    testWidgets('未注入 packagePaths 时回退 NuGetBuilder 计划路径，浮层可显示并选择', (
      WidgetTester tester,
    ) async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'x.lib', path: 'lib/x.lib', size: 4),
        ];
      final _Harness harness = await _pumpInspector(tester, pack: pack);
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'context.packageFile');
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('inspectorField_path')),
        'x.lib',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final Finder suggestion = find.text('lib/x.lib');
      expect(suggestion, findsOneWidget);

      await tester.tap(suggestion);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(
        controller.project.nodes.single.params['path'],
        'lib/x.lib',
      );
    });

    testWidgets('未注入 packagePaths 时根级 nuspec 条目不进入建议列表', (
      WidgetTester tester,
    ) async {
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'x.lib', path: 'lib/x.lib', size: 4),
        ];
      final _Harness harness = await _pumpInspector(tester, pack: pack);
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'context.packageFile');
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('inspectorField_path')),
        'nuspec',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('demo.nuspec'), findsNothing);
      expect(find.text('无匹配路径，将按手填内容使用'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('超长路径建议项单行省略显示且不触发布局溢出', (WidgetTester tester) async {
      const String longPath =
          'files/some/deeply/nested/directory/with/many/'
          'segments/and_a_very_long_header_file_name.hpp';
      final _Harness harness = await _pumpInspector(
        tester,
        packagePaths: const <String>[longPath],
      );
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'context.packageFile');
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('inspectorField_path')),
        'segments',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final Finder suggestion = find.text(longPath);
      expect(suggestion, findsOneWidget);
      final Text tileText = tester.widget<Text>(suggestion);
      expect(tileText.maxLines, 1);
      expect(tileText.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    testWidgets('scriptFilePath 项来自包源目录脚本映射 files/ 前缀，大小写不敏感排序，非脚本与生成脚本不出现', (
      WidgetTester tester,
    ) async {
      final ScriptProjectModel project = _project();
      project.nodes = <ScriptNodeModel>[
        ScriptNodeModel(id: 'n1', type: 'context.scriptFile'),
      ];
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'x.lib', path: 'lib/x.lib', size: 4),
          FileModel(name: 'data.txt', path: 'docs/data.txt', size: 4),
          FileModel(name: 'run.bat', path: 'scripts/run.bat', size: 4),
          FileModel(name: 'run.bat', path: 'scripts/run.bat', size: 4),
          // 文件名酷似生成脚本，但它是源于 pack.files 的源文件，应出现。
          FileModel(name: 'script_9.ps1', path: 'scripts/script_9.ps1', size: 4),
          FileModel(name: 'INSTALL.BAT', path: 'INSTALL.BAT', size: 4),
          FileModel(name: 'setup.exe', path: 'tools/setup.exe', size: 4),
          // apple.bat 与 Zeta.ps1 用于判别排序口径：大小写敏感比较会先排
          // INSTALL.BAT/Zeta.ps1 再排小写项，与大小写不敏感序不同。
          FileModel(name: 'apple.bat', path: 'apple.bat', size: 4),
          FileModel(name: 'Zeta.ps1', path: 'Zeta.ps1', size: 4),
        ];
      final _Harness harness = await _pumpInspector(
        tester,
        pack: pack,
        project: project,
        packagePaths: const <String>[
          'files/scripts/script_1.ps1',
          'files/from-plan.bat',
        ],
      );
      final GraphEditorController controller = harness.controller!;
      controller.selectNode('n1');
      await tester.pump();

      final ComboBox<String> combo = tester.widget<ComboBox<String>>(
        find.byKey(const Key('inspectorField_file')),
      );
      // 大小写不敏感排序 + 同路径去重；非脚本与包内生成脚本不出现。
      final List<String?> items = combo.items!
          .map((ComboBoxItem<String> item) => item.value)
          .toList();
      expect(items, <String>[
        'files/apple.bat',
        'files/INSTALL.BAT',
        'files/scripts/run.bat',
        'files/scripts/script_9.ps1',
        'files/tools/setup.exe',
        'files/Zeta.ps1',
      ]);
      expect(items, isNot(contains('lib/x.lib')));
      expect(items, isNot(contains('files/docs/data.txt')));
      expect(items, isNot(contains('files/scripts/script_1.ps1')));
      expect(items, isNot(contains('files/from-plan.bat')));
      expect(combo.value, isNull);
      expect(find.text('选择脚本'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('scriptFilePath 下拉点选后写回包内相对路径', (WidgetTester tester) async {
      final ScriptProjectModel project = _project();
      final ScriptNodeModel node = ScriptNodeModel(
        id: 'n1',
        type: 'process.runScript',
      );
      node.params['script'] = 'files/build.ps1';
      project.nodes = <ScriptNodeModel>[node];
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'build.ps1', path: 'build.ps1', size: 4),
          FileModel(name: 'deploy.bat', path: 'tools/deploy.bat', size: 4),
        ];
      final _Harness harness = await _pumpInspector(
        tester,
        pack: pack,
        project: project,
      );
      final GraphEditorController controller = harness.controller!;
      controller.selectNode('n1');
      await tester.pump();

      final Finder field = find.byKey(const Key('inspectorField_script'));
      // 当前值在项列表内时正常选中：不插入额外首项、不重复（精确项序）。
      expect(tester.widget<ComboBox<String>>(field).value, 'files/build.ps1');
      expect(
        tester
            .widget<ComboBox<String>>(field)
            .items!
            .map((ComboBoxItem<String> item) => item.value)
            .toList(),
        <String>['files/build.ps1', 'files/tools/deploy.bat'],
      );
      expect(find.text('files/build.ps1'), findsOneWidget);

      await _selectCombo(tester, field, 'files/tools/deploy.bat');

      expect(
        controller.project.nodes.single.params['script'],
        'files/tools/deploy.bat',
      );
      expect(
        tester.widget<ComboBox<String>>(field).value,
        'files/tools/deploy.bat',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('scriptFilePath 当前值缺列时置于首项回显，并可改选其他项', (
      WidgetTester tester,
    ) async {
      final ScriptProjectModel project = _project();
      final ScriptNodeModel node = ScriptNodeModel(
        id: 'n1',
        type: 'context.scriptFile',
      );
      node.params['file'] = 'files/legacy/old.ps1';
      project.nodes = <ScriptNodeModel>[node];
      final PackModel pack = _pack()
        ..files = <FileModel>[
          FileModel(name: 'new.bat', path: 'new.bat', size: 4),
        ];
      final _Harness harness = await _pumpInspector(
        tester,
        pack: pack,
        project: project,
      );
      final GraphEditorController controller = harness.controller!;
      controller.selectNode('n1');
      await tester.pump();

      final Finder field = find.byKey(const Key('inspectorField_file'));
      final ComboBox<String> combo = tester.widget<ComboBox<String>>(field);
      expect(combo.value, 'files/legacy/old.ps1');
      expect(
        combo.items!.map((ComboBoxItem<String> item) => item.value).toList(),
        <String>['files/legacy/old.ps1', 'files/new.bat'],
      );
      // 缺列回显时项非空 → 触发按钮按库 isEnabled 口径启用（onPressed 非空）。
      expect(
        tester
            .widget<Button>(
              find.descendant(of: field, matching: find.byType(Button)),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('files/legacy/old.ps1'), findsOneWidget);

      await _selectCombo(tester, field, 'files/new.bat');

      expect(controller.project.nodes.single.params['file'], 'files/new.bat');
      expect(tester.takeException(), isNull);
    });

    testWidgets('scriptFilePath 无源脚本时显示「选择脚本」占位且接线保持（空 items 库渲染为禁用）', (
      WidgetTester tester,
    ) async {
      final ScriptProjectModel project = _project();
      project.nodes = <ScriptNodeModel>[
        ScriptNodeModel(id: 'n1', type: 'context.scriptFile'),
      ];
      final _Harness harness = await _pumpInspector(tester, project: project);
      final GraphEditorController controller = harness.controller!;
      controller.selectNode('n1');
      await tester.pump();

      final Finder field = find.byKey(const Key('inspectorField_file'));
      final ComboBox<String> combo = tester.widget<ComboBox<String>>(field);
      expect(combo.items, isEmpty);
      expect(combo.value, isNull);
      expect(combo.onChanged, isNotNull);
      expect(find.text('选择脚本'), findsOneWidget);
      // fluent_ui 4.16.1：空 items 时 isEnabled 为 false，触发按钮必然渲染禁用
      // （onPressed 为 null）。此处锁定库行为，不作为「可用」保证。
      expect(
        tester
            .widget<Button>(
              find.descendant(of: field, matching: find.byType(Button)),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('textLines 渲染多行 TextBox，写回按行清洗后的 List<String>', (
      WidgetTester tester,
    ) async {
      final ScriptProjectModel project = _project();
      final ScriptNodeModel node = ScriptNodeModel(
        id: 'n1',
        type: 'system.findTool',
      );
      node.params['name'] = 'clang';
      node.params['candidates'] = <String>[r'C:\Tools', r'C:\bin'];
      project.nodes = <ScriptNodeModel>[node];
      final _Harness harness = await _pumpInspector(
        tester,
        project: project,
      );
      final GraphEditorController controller = harness.controller!;
      controller.selectNode('n1');
      await tester.pump();

      final Finder field = find.byKey(const Key('inspectorField_candidates'));
      final TextBox textBox = tester.widget<TextBox>(field);
      expect(textBox.maxLines, isNull);
      expect(textBox.controller!.text, '${r'C:\Tools'}\n${r'C:\bin'}');

      // 多行写回：按行 split → trim → 去空
      await tester.enterText(
        field,
        '  ${r'C:\Tools'}  \n\n ${r'C:\bin'} \n \n',
      );
      await tester.pump();
      expect(controller.project.nodes.single.params['candidates'], <String>[
        r'C:\Tools',
        r'C:\bin',
      ]);

      await tester.enterText(field, '   \n  ');
      await tester.pump();
      expect(controller.project.nodes.single.params['candidates'], isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('环境变量名非法时显示红字，合法后消失', (WidgetTester tester) async {
      final _Harness harness = await _pumpInspector(tester);
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'context.environment');
      await tester.pump();

      const String message = '变量名须以字母或下划线开头，且仅含字母、数字、下划线';
      expect(find.text(message), findsOneWidget);

      final Finder field = find.byKey(const Key('inspectorField_name'));
      await tester.enterText(field, '1abc');
      await tester.pump();
      expect(find.text(message), findsOneWidget);
      expect(controller.project.nodes.single.params['name'], '1abc');

      await tester.enterText(field, 'abc_1');
      await tester.pump();
      expect(find.text(message), findsNothing);
    });

    testWidgets('变量节点名非法时显示红字，合法后消失（四类共用 name 参数）', (
      WidgetTester tester,
    ) async {
      final _Harness harness = await _pumpInspector(tester);
      final GraphEditorController controller = harness.controller!;
      const String message = '变量名须以字母或下划线开头，且仅含字母、数字、下划线';

      for (final String typeKey in <String>[
        'variable.setNumber',
        'variable.getNumber',
        'variable.setString',
        'variable.getString',
      ]) {
        _addAndSelect(controller, typeKey);
        await tester.pump();
        expect(find.text(message), findsOneWidget, reason: typeKey);

        final Finder field = find.byKey(const Key('inspectorField_name'));
        await tester.enterText(field, '1abc');
        await tester.pump();
        expect(find.text(message), findsOneWidget, reason: typeKey);
        expect(
          controller.project.nodes.last.params['name'],
          '1abc',
          reason: typeKey,
        );

        await tester.enterText(field, 'abc_1');
        await tester.pump();
        expect(find.text(message), findsNothing, reason: typeKey);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('非变量节点不显示变量名红字', (WidgetTester tester) async {
      final _Harness harness = await _pumpInspector(tester);
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'value.text');
      await tester.pump();

      expect(find.text('变量名须以字母或下划线开头，且仅含字母、数字、下划线'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('输入过程中控件不重建，焦点保持', (WidgetTester tester) async {
      final _Harness harness = await _pumpInspector(tester);
      final GraphEditorController controller = harness.controller!;
      _addAndSelect(controller, 'value.text');
      await tester.pump();

      final Finder field = find.byKey(const Key('inspectorField_value'));
      await tester.showKeyboard(field);
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'a',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ab',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();

      final EditableText editable = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      expect(controller.project.nodes.single.params['value'], 'ab');
    });

    testWidgets('切换选中节点后字段刷新为新节点参数值', (WidgetTester tester) async {
      final _Harness harness = await _pumpInspector(tester);
      final GraphEditorController controller = harness.controller!;
      controller.addNode('value.text', Offset.zero);
      controller.addNode('value.text', Offset.zero);
      controller.project.nodes[0].params['value'] = 'A';
      controller.project.nodes[1].params['value'] = 'B';

      controller.selectNode('n1');
      await tester.pump();
      expect(
        tester
            .widget<TextBox>(find.byKey(const Key('inspectorField_value')))
            .controller!
            .text,
        'A',
      );

      controller.selectNode('n2');
      await tester.pump();
      expect(
        tester
            .widget<TextBox>(find.byKey(const Key('inspectorField_value')))
            .controller!
            .text,
        'B',
      );
    });

    testWidgets('选中节点显示节点属性，清空选中回到项目属性', (WidgetTester tester) async {
      final _Harness harness = await _pumpInspector(tester);
      final GraphEditorController controller = harness.controller!;
      expect(find.text('脚本项目'), findsOneWidget);

      _addAndSelect(controller, 'value.text');
      await tester.pump();
      expect(find.text('脚本项目'), findsNothing);
      expect(find.text('文本'), findsOneWidget);

      controller.clearSelection();
      await tester.pump();
      expect(find.text('脚本项目'), findsOneWidget);
    });
  });

  group('项目属性模式', () {
    testWidgets('无选中时显示名称/触发/构建模型/脚本 ID/执行顺序', (WidgetTester tester) async {
      final PackModel pack = _packWithProjects();
      final _Harness harness = await _pumpInspector(
        tester,
        pack: pack,
        project: pack.scripts.first,
      );
      expect(harness.controller!.selectedNodeId, isNull);

      expect(find.text('脚本项目'), findsOneWidget);
      expect(find.text('脚本 1'), findsWidgets);
      expect(
        tester
            .widget<TextBox>(find.byKey(const Key('inspectorProjectName')))
            .controller!
            .text,
        '脚本 1',
      );
      expect(find.text('编译前'), findsWidgets);
      expect(find.text('ALL'), findsWidgets);
      expect(find.text('脚本 ID'), findsOneWidget);
      expect(find.text('script_1'), findsOneWidget);
      expect(find.text('导出时决定包内文件名与 Target 名'), findsOneWidget);
      expect(find.text('执行顺序'), findsOneWidget);
      expect(find.text('同组内按列表顺序执行'), findsOneWidget);
      for (final String id in <String>['script_1', 'script_2', 'script_3']) {
        expect(find.byKey(Key('scriptProjectRow_$id')), findsOneWidget);
      }
    });

    testWidgets('执行顺序列表按项目顺序渲染', (WidgetTester tester) async {
      final PackModel pack = _packWithProjects();
      await _pumpInspector(tester, pack: pack, project: pack.scripts.first);

      final double first = _rowTop(tester, 'script_1');
      final double second = _rowTop(tester, 'script_2');
      final double third = _rowTop(tester, 'script_3');
      expect(first, lessThan(second));
      expect(second, lessThan(third));
    });

    testWidgets('当前项目行带选中背景与 accent 左缘竖条', (WidgetTester tester) async {
      final PackModel pack = _packWithProjects();
      await _pumpInspector(tester, pack: pack, project: pack.scripts.first);

      final BoxDecoration current = _rowDecoration(tester, 'script_1');
      expect(current.color, UCColors.accent.withValues(alpha: 0.35));
      expect((current.border! as Border).left.color, UCColors.accent);
      expect((current.border! as Border).left.width, 2);

      final BoxDecoration other = _rowDecoration(tester, 'script_2');
      expect(other.color, isNull);
    });

    testWidgets('非当前行悬停时背景变为 surface0，移出恢复', (WidgetTester tester) async {
      final PackModel pack = _packWithProjects();
      await _pumpInspector(tester, pack: pack, project: pack.scripts.first);

      expect(_rowDecoration(tester, 'script_2').color, isNull);

      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const Key('scriptProjectRow_script_2'))),
      );
      await tester.pump();

      expect(_rowDecoration(tester, 'script_2').color, UCColors.flavor.surface0);

      await mouse.moveTo(const Offset(1200, 700));
      await tester.pump();

      expect(_rowDecoration(tester, 'script_2').color, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('首末行上移/下移按钮禁用，中间行均可用', (WidgetTester tester) async {
      final PackModel pack = _packWithProjects();
      await _pumpInspector(tester, pack: pack, project: pack.scripts.first);

      expect(_moveUp(tester, 'script_1').onPressed, isNull);
      expect(_moveDown(tester, 'script_1').onPressed, isNotNull);
      expect(_moveUp(tester, 'script_2').onPressed, isNotNull);
      expect(_moveDown(tester, 'script_2').onPressed, isNotNull);
      expect(_moveUp(tester, 'script_3').onPressed, isNotNull);
      expect(_moveDown(tester, 'script_3').onPressed, isNull);
      expect(find.byTooltip('上移'), findsNWidgets(3));
      expect(find.byTooltip('下移'), findsNWidgets(3));
    });

    testWidgets('点击行回调选中项目，点击上移/下移回调排序', (WidgetTester tester) async {
      final PackModel pack = _packWithProjects();
      final List<String> selected = <String>[];
      final List<String> movedUp = <String>[];
      final List<String> movedDown = <String>[];
      await _pumpInspector(
        tester,
        pack: pack,
        project: pack.scripts.first,
        onSelectProject: (ScriptProjectModel project) => selected.add(project.id),
        onMoveProjectUp: (ScriptProjectModel project) => movedUp.add(project.id),
        onMoveProjectDown: (ScriptProjectModel project) =>
            movedDown.add(project.id),
      );

      await tester.tap(find.byKey(const Key('scriptProjectRow_script_2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(selected, <String>['script_2']);

      await tester.tap(find.byKey(const Key('scriptProjectMoveDown_script_1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(movedDown, <String>['script_1']);

      await tester.tap(find.byKey(const Key('scriptProjectMoveUp_script_3')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(movedUp, <String>['script_3']);
    });

    testWidgets('构建标签预览按构建模型着色', (WidgetTester tester) async {
      final PackModel pack = _packWithProjects();
      await _pumpInspector(tester, pack: pack, project: pack.scripts.first);

      final Tag tag = tester.widget<Tag>(
        find.byKey(const Key('inspectorProjectBuildTag')),
      );
      expect(tag.text, 'ALL');
      expect(tag.color, UCColors.flavor.blue);
    });

    testWidgets('项目名称回车提交：空名与重名显示红字且不回调', (WidgetTester tester) async {
      final PackModel pack = _packWithProjects();
      final List<String> renamed = <String>[];
      await _pumpInspector(
        tester,
        pack: pack,
        project: pack.scripts.first,
        onRenameProject: (ScriptProjectModel project, String name) =>
            renamed.add('${project.id}:$name'),
      );
      final Finder field = find.byKey(const Key('inspectorProjectName'));

      await tester.enterText(field, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('名称不能为空'), findsOneWidget);
      expect(renamed, isEmpty);

      await tester.enterText(field, '脚本 2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('名称已存在'), findsOneWidget);
      expect(renamed, isEmpty);

      await tester.enterText(field, '新脚本');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('名称已存在'), findsNothing);
      expect(find.text('名称不能为空'), findsNothing);
      expect(renamed, <String>['script_1:新脚本']);
    });

    testWidgets('切换到等名文本的另一项目后红字残留清除', (WidgetTester tester) async {
      final PackModel pack = _packWithProjects();
      final List<String> renamed = <String>[];
      final _Harness harness = await _pumpInspector(
        tester,
        pack: pack,
        project: pack.scripts.first,
        onRenameProject: (ScriptProjectModel project, String name) =>
            renamed.add('${project.id}:$name'),
      );
      final Finder field = find.byKey(const Key('inspectorProjectName'));

      // 复现：在项目 1 名称框输入项目 2 的名字并提交 → 报「名称已存在」。
      await tester.enterText(field, '脚本 2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('名称已存在'), findsOneWidget);
      expect(renamed, isEmpty);

      // 页面切换路径：先失焦提交，再加载项目 2（其名称恰为「脚本 2」）。
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      harness.controller!.loadProject(pack.scripts[1]);
      await tester.pump();

      expect(find.text('名称已存在'), findsNothing);
      expect(
        tester
            .widget<TextBox>(find.byKey(const Key('inspectorProjectName')))
            .controller!
            .text,
        '脚本 2',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('触发时机下拉选择回调 post', (WidgetTester tester) async {
      final PackModel pack = _packWithProjects();
      final List<ScriptTrigger> triggers = <ScriptTrigger>[];
      await _pumpInspector(
        tester,
        pack: pack,
        project: pack.scripts.first,
        onTriggerChanged: (ScriptProjectModel project, ScriptTrigger trigger) =>
            triggers.add(trigger),
      );

      await _selectCombo(
        tester,
        find.byKey(const Key('inspectorProjectTrigger')),
        '编译后',
      );

      expect(triggers, <ScriptTrigger>[ScriptTrigger.post]);
    });

    testWidgets('构建模型下拉选择回调 Debug', (WidgetTester tester) async {
      final PackModel pack = _packWithProjects();
      final List<BuildModel> models = <BuildModel>[];
      await _pumpInspector(
        tester,
        pack: pack,
        project: pack.scripts.first,
        onBuildModelChanged: (ScriptProjectModel project, BuildModel model) =>
            models.add(model),
      );

      await _selectCombo(
        tester,
        find.byKey(const Key('inspectorProjectBuildModel')),
        'Debug',
      );

      expect(models, <BuildModel>[BuildModel.debug]);
    });
  });

  group('空态', () {
    testWidgets('无项目时显示空态提示', (WidgetTester tester) async {
      await _pumpInspector(tester, noProject: true);

      expect(find.text('请先新建脚本项目'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _Harness {
  _Harness(this.controller, this.pack);

  final GraphEditorController? controller;
  final PackModel pack;
}

PackModel _pack() =>
    PackModel(name: 'demo', version: '1.0.0', author: 'tester');

ScriptProjectModel _project({
  String id = 'script_1',
  String name = '脚本 1',
  ScriptTrigger trigger = ScriptTrigger.pre,
}) => ScriptProjectModel(id: id, name: name, trigger: trigger);

PackModel _packWithProjects() {
  final PackModel pack = _pack();
  pack.scripts = <ScriptProjectModel>[
    _project(id: 'script_1', name: '脚本 1'),
    _project(id: 'script_2', name: '脚本 2', trigger: ScriptTrigger.post),
    _project(id: 'script_3', name: '脚本 3'),
  ];
  return pack;
}

void _addAndSelect(GraphEditorController controller, String typeKey) {
  final String nodeId = controller.addNode(typeKey, Offset.zero);
  controller.selectNode(nodeId);
}

Future<_Harness> _pumpInspector(
  WidgetTester tester, {
  PackModel? pack,
  ScriptProjectModel? project,
  List<String>? packagePaths,
  bool noProject = false,
  ValueChanged<ScriptProjectModel>? onSelectProject,
  void Function(ScriptProjectModel project, String name)? onRenameProject,
  void Function(ScriptProjectModel project, ScriptTrigger trigger)?
  onTriggerChanged,
  void Function(ScriptProjectModel project, BuildModel buildModel)?
  onBuildModelChanged,
  void Function(ScriptProjectModel project)? onMoveProjectUp,
  void Function(ScriptProjectModel project)? onMoveProjectDown,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final PackModel resolvedPack = pack ?? _pack();
  final GraphEditorController? controller = noProject
      ? null
      : GraphEditorController(project ?? _project());
  if (controller != null) {
    addTearDown(controller.dispose);
  }

  await tester.pumpWidget(
    FluentApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 280,
          height: 800,
          child: NodeInspector(
            controller: controller,
            pack: resolvedPack,
            packagePaths: packagePaths,
            onSelectProject: onSelectProject,
            onRenameProject: onRenameProject,
            onTriggerChanged: onTriggerChanged,
            onBuildModelChanged: onBuildModelChanged,
            onMoveProjectUp: onMoveProjectUp,
            onMoveProjectDown: onMoveProjectDown,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return _Harness(controller, resolvedPack);
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

IconButton _moveUp(WidgetTester tester, String id) =>
    tester.widget<IconButton>(find.byKey(Key('scriptProjectMoveUp_$id')));

IconButton _moveDown(WidgetTester tester, String id) =>
    tester.widget<IconButton>(find.byKey(Key('scriptProjectMoveDown_$id')));

double _rowTop(WidgetTester tester, String id) =>
    tester.getTopLeft(find.byKey(Key('scriptProjectRow_$id'))).dy;

BoxDecoration _rowDecoration(WidgetTester tester, String id) => tester
    .widget<Container>(find.byKey(Key('scriptProjectRow_$id')))
    .decoration! as BoxDecoration;
