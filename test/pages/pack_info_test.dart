import 'dart:async';

import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:cpp_nuget_pack/models/lib_dir_model.dart';
import 'package:cpp_nuget_pack/models/library_model.dart';
import 'package:cpp_nuget_pack/models/macro_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/pages/pack_info.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('默认只读展示包的字段且仅显示编辑按钮', (tester) async {
    final PackModel pack = _pack();

    await _pumpPage(tester, PackInfo(pack: pack, onSave: _acceptSave));

    expect(find.text('demo'), findsOneWidget);
    expect(find.text('1.2.3'), findsOneWidget);
    expect(find.text('张三'), findsOneWidget);
    expect(find.text('MIT'), findsOneWidget);
    expect(find.text('示例描述'), findsOneWidget);

    final Iterable<TextBox> boxes = tester.widgetList<TextBox>(
      find.byType(TextBox),
    );
    expect(boxes, isNotEmpty);
    expect(boxes.every((TextBox box) => box.readOnly), isTrue);
    expect(find.byKey(const Key('packInfoEditButton')), findsOneWidget);
    expect(find.byKey(const Key('packInfoSaveButton')), findsNothing);
    expect(find.byKey(const Key('packInfoCancelButton')), findsNothing);
  });

  testWidgets('许可证与描述为空时显示占位', (tester) async {
    final PackModel pack = _pack(description: null, license: null);

    await _pumpPage(tester, PackInfo(pack: pack, onSave: _acceptSave));

    expect(find.text('无'), findsNWidgets(2));
  });

  testWidgets('点击编辑后仅包 ID 保持只读并显示保存取消', (tester) async {
    final PackModel pack = _pack();

    await _pumpPage(tester, PackInfo(pack: pack, onSave: _acceptSave));
    await _tapEdit(tester);

    expect(_textBox(tester, 'packInfoIdField').readOnly, isTrue);
    expect(_textBox(tester, 'packInfoVersionField').readOnly, isFalse);
    expect(_textBox(tester, 'packInfoAuthorField').readOnly, isFalse);
    expect(_textBox(tester, 'packInfoDescriptionField').readOnly, isFalse);
    expect(find.byType(ComboBox<String?>), findsOneWidget);
    expect(find.byKey(const Key('packInfoSaveButton')), findsOneWidget);
    expect(find.byKey(const Key('packInfoCancelButton')), findsOneWidget);
    expect(find.byKey(const Key('packInfoEditButton')), findsNothing);
  });

  testWidgets('编辑态许可证下拉框与相邻输入框等高同宽', (tester) async {
    final PackModel pack = _pack();

    await _pumpPage(tester, PackInfo(pack: pack, onSave: _acceptSave));
    await _tapEdit(tester);

    final Size license = tester.getSize(
      find.byKey(const Key('packInfoLicenseField')),
    );
    final Size version = tester.getSize(
      find.byKey(const Key('packInfoVersionField')),
    );
    final Size author = tester.getSize(
      find.byKey(const Key('packInfoAuthorField')),
    );

    expect(find.byType(ComboBox<String?>), findsOneWidget);
    expect(license.height, version.height);
    expect(license.height, author.height);
    expect(license.width, version.width);
    expect(license.width, author.width);
    expect(tester.takeException(), isNull);
  });

  testWidgets('取消编辑还原字段并回到只读态', (tester) async {
    final PackModel pack = _pack();

    await _pumpPage(tester, PackInfo(pack: pack, onSave: _acceptSave));
    await _tapEdit(tester);
    await tester.enterText(
      find.byKey(const Key('packInfoVersionField')),
      '9.9.9',
    );
    await tester.enterText(find.byKey(const Key('packInfoAuthorField')), '李四');
    await tester.pump();

    await tester.tap(find.byKey(const Key('packInfoCancelButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_textBox(tester, 'packInfoVersionField').controller!.text, '1.2.3');
    expect(_textBox(tester, 'packInfoAuthorField').controller!.text, '张三');
    expect(_textBox(tester, 'packInfoVersionField').readOnly, isTrue);
    expect(find.byKey(const Key('packInfoEditButton')), findsOneWidget);
    expect(find.byKey(const Key('packInfoSaveButton')), findsNothing);
  });

  testWidgets('保存按钮仅在必填有效且有改动时可用', (tester) async {
    final PackModel pack = _pack();

    await _pumpPage(tester, PackInfo(pack: pack, onSave: _acceptSave));
    await _tapEdit(tester);

    expect(_saveButton(tester).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('packInfoVersionField')),
      '2.0.0',
    );
    await tester.pump();
    expect(_saveButton(tester).onPressed, isNotNull);

    await tester.enterText(find.byKey(const Key('packInfoAuthorField')), '   ');
    await tester.pump();
    expect(_saveButton(tester).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('packInfoAuthorField')), '张三');
    await tester.pump();
    expect(_saveButton(tester).onPressed, isNotNull);

    await tester.enterText(
      find.byKey(const Key('packInfoVersionField')),
      '1.2.3',
    );
    await tester.pump();
    expect(_saveButton(tester).onPressed, isNull);
  });

  testWidgets('保存成功后回调收到更新后的包并显示已保存', (tester) async {
    final PackModel pack = _pack()
      ..files = <FileModel>[
        FileModel(name: 'foo.h', path: 'include/foo.h', size: 128),
      ];
    PackModel? saved;

    await _pumpPage(
      tester,
      PackInfo(
        pack: pack,
        onSave: (PackModel updated) async {
          saved = updated;
          return true;
        },
      ),
    );
    await _tapEdit(tester);
    await tester.enterText(
      find.byKey(const Key('packInfoVersionField')),
      '2.0.0',
    );
    await tester.enterText(find.byKey(const Key('packInfoAuthorField')), '李四');
    await tester.enterText(
      find.byKey(const Key('packInfoDescriptionField')),
      '新描述',
    );
    await _selectLicense(tester, 'Apache-2.0');
    await tester.pump();

    await tester.tap(find.byKey(const Key('packInfoSaveButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved, isNotNull);
    expect(saved!.name, 'demo');
    expect(saved!.version, '2.0.0');
    expect(saved!.author, '李四');
    expect(saved!.description, '新描述');
    expect(saved!.license, 'Apache-2.0');
    expect(saved!.iconPath, isNull);
    expect(saved!.sourcePath, isNull);
    expect(saved!.files, hasLength(1));
    expect(saved!.files.single.path, 'include/foo.h');
    expect(find.text('已保存'), findsOneWidget);
    expect(find.byKey(const Key('packInfoSaveButton')), findsNothing);
    expect(find.byKey(const Key('packInfoEditButton')), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text('已保存'), findsNothing);
  });

  testWidgets('保存包信息时保留依赖列表', (tester) async {
    final PackModel pack = _pack()
      ..dependencies = <DependencyModel>[
        const DependencyModel(name: 'libfoo', version: '[1.0,2.0)'),
      ]
      ..macros = <MacroModel>[const MacroModel(value: 'MY_MACRO=1')]
      ..libDirectories = <LibDirModel>[
        const LibDirModel(path: 'third_party/lib'),
      ]
      ..libraries = <LibraryModel>[const LibraryModel(name: 'mylib.lib')]
      ..buildOptions = <String, String>{'tbb': 'on'};
    PackModel? saved;

    await _pumpPage(
      tester,
      PackInfo(
        pack: pack,
        onSave: (PackModel updated) async {
          saved = updated;
          return true;
        },
      ),
    );
    await _tapEdit(tester);
    await tester.enterText(
      find.byKey(const Key('packInfoVersionField')),
      '2.0.0',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('packInfoSaveButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved, isNotNull);
    expect(saved!.version, '2.0.0');
    expect(saved!.dependencies, hasLength(1));
    expect(saved!.dependencies.single.name, 'libfoo');
    expect(saved!.dependencies.single.version, '[1.0,2.0)');
    expect(saved!.macros.single.value, 'MY_MACRO=1');
    expect(saved!.libDirectories.single.path, 'third_party/lib');
    expect(saved!.libraries.single.name, 'mylib.lib');
    expect(saved!.buildOptions, <String, String>{'tbb': 'on'});
  });

  testWidgets('保存包信息时保留脚本列表', (tester) async {
    final PackModel pack = _pack()
      ..scripts = <ScriptProjectModel>[
        ScriptProjectModel(
          id: 'script_1',
          name: '脚本 1',
          trigger: ScriptTrigger.pre,
        ),
      ];
    PackModel? saved;

    await _pumpPage(
      tester,
      PackInfo(
        pack: pack,
        onSave: (PackModel updated) async {
          saved = updated;
          return true;
        },
      ),
    );
    await _tapEdit(tester);
    await tester.enterText(
      find.byKey(const Key('packInfoVersionField')),
      '2.0.0',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('packInfoSaveButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved, isNotNull);
    expect(saved!.version, '2.0.0');
    expect(saved!.scripts, hasLength(1));
    expect(saved!.scripts.single.id, 'script_1');
  });

  testWidgets('清空描述并选择无许可证时保存为空值', (tester) async {
    final PackModel pack = _pack();
    PackModel? saved;

    await _pumpPage(
      tester,
      PackInfo(
        pack: pack,
        onSave: (PackModel updated) async {
          saved = updated;
          return true;
        },
      ),
    );
    await _tapEdit(tester);
    await _selectLicense(tester, '无');
    await tester.enterText(
      find.byKey(const Key('packInfoDescriptionField')),
      '',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('packInfoSaveButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(saved, isNotNull);
    expect(saved!.license, isNull);
    expect(saved!.description, isNull);
  });

  testWidgets('保存失败时停留在编辑态', (tester) async {
    final PackModel pack = _pack();

    await _pumpPage(tester, PackInfo(pack: pack, onSave: (_) async => false));
    await _tapEdit(tester);
    await tester.enterText(
      find.byKey(const Key('packInfoVersionField')),
      '2.0.0',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('packInfoSaveButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('packInfoSaveButton')), findsOneWidget);
    expect(find.byKey(const Key('packInfoCancelButton')), findsOneWidget);
    expect(_saveButton(tester).onPressed, isNotNull);
    expect(find.text('已保存'), findsNothing);
    expect(_textBox(tester, 'packInfoVersionField').controller!.text, '2.0.0');
  });

  testWidgets('切换包时丢弃未保存修改并回到只读态', (tester) async {
    final PackModel first = _pack();
    final PackModel second = _pack(
      name: 'other',
      version: '3.0.0',
      author: '王五',
      description: '另一个包',
    );

    await _pumpPage(tester, PackInfo(pack: first, onSave: _acceptSave));
    await _tapEdit(tester);
    await tester.enterText(
      find.byKey(const Key('packInfoVersionField')),
      '9.9.9',
    );
    await tester.pump();

    await _pumpPage(tester, PackInfo(pack: second, onSave: _acceptSave));

    expect(find.text('other'), findsOneWidget);
    expect(find.text('3.0.0'), findsOneWidget);
    expect(find.text('9.9.9'), findsNothing);
    expect(_textBox(tester, 'packInfoVersionField').readOnly, isTrue);
    expect(find.byKey(const Key('packInfoEditButton')), findsOneWidget);
    expect(find.byKey(const Key('packInfoSaveButton')), findsNothing);
  });

  testWidgets('保存挂起期间切换包时丢弃回写且不污染新包界面', (tester) async {
    final PackModel first = _pack();
    final PackModel second = _pack(
      name: 'other',
      version: '3.0.0',
      author: '王五',
      description: '另一个包',
    );
    final Completer<bool> pending = Completer<bool>();

    await _pumpPage(
      tester,
      PackInfo(pack: first, onSave: (_) => pending.future),
    );
    await _tapEdit(tester);
    await tester.enterText(
      find.byKey(const Key('packInfoVersionField')),
      '9.9.9',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('packInfoSaveButton')));
    await tester.pump();
    expect(find.text('9.9.9'), findsOneWidget);

    await _pumpPage(
      tester,
      PackInfo(pack: second, onSave: (_) => pending.future),
    );

    pending.complete(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_textBox(tester, 'packInfoVersionField').controller!.text, '3.0.0');
    expect(find.text('9.9.9'), findsNothing);
    expect(find.text('已保存'), findsNothing);
    expect(find.byKey(const Key('packInfoEditButton')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<bool> _acceptSave(PackModel pack) async => true;

PackModel _pack({
  String name = 'demo',
  String version = '1.2.3',
  String author = '张三',
  String? description = '示例描述',
  String? license = 'MIT',
}) => PackModel(
  name: name,
  version: version,
  author: author,
  description: description,
  license: license,
);

TextBox _textBox(WidgetTester tester, String key) =>
    tester.widget<TextBox>(find.byKey(Key(key)));

FilledButton _saveButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('packInfoSaveButton')));

Future<void> _tapEdit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('packInfoEditButton')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _selectLicense(WidgetTester tester, String option) async {
  final Finder field = find.byKey(const Key('packInfoLicenseField'));
  await tester.ensureVisible(field);
  await tester.pump();
  await tester.tap(field);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(option).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(FluentApp(home: page));
  await tester.pump();
}
