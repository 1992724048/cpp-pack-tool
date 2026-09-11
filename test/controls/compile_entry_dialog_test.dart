import 'package:cpp_nuget_pack/controls/compile_entry_dialog.dart';
import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/file_model.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('默认显示标题、字段、ALL 构建配置且空文本禁用确定', (tester) async {
    await _pumpDialog(
      tester,
      title: '添加宏定义',
      label: '宏定义',
      hintText: 'MY_MACRO=1',
    );

    expect(find.byKey(const Key('compileEntryDialog')), findsOneWidget);
    expect(find.text('添加宏定义'), findsOneWidget);
    expect(find.text('宏定义'), findsOneWidget);
    expect(find.text('构建配置'), findsOneWidget);
    expect(find.text('ALL'), findsOneWidget);
    expect(find.byKey(const Key('compileEntryBrowseButton')), findsNothing);
    expect(_confirmButton(tester).onPressed, isNull);
    expect(_buildModelValue(tester), BuildModel.all);
  });

  testWidgets('输入框占位文案随参数显示', (tester) async {
    await _pumpDialog(
      tester,
      title: '添加附加库',
      label: '库名称',
      hintText: 'mylib.lib',
    );

    expect(_textBox(tester).placeholder, 'mylib.lib');
  });

  testWidgets('输入文本后确定返回 trim 后的记录', (tester) async {
    CompileEntryResult? result;
    await _pumpDialog(
      tester,
      title: '添加宏定义',
      label: '宏定义',
      hintText: 'MY_MACRO=1',
      onResult: (CompileEntryResult? value) => result = value,
    );

    await tester.enterText(
      find.byKey(const Key('compileEntryTextField')),
      '  MY_MACRO=1  ',
    );
    await tester.pump();
    expect(_confirmButton(tester).onPressed, isNotNull);

    await _tapConfirm(tester);

    expect(result, isNotNull);
    expect(result!.text, 'MY_MACRO=1');
    expect(result!.buildModel, BuildModel.all);
    expect(find.byType(ContentDialog), findsNothing);
  });

  testWidgets('仅空白文本时确定保持禁用', (tester) async {
    await _pumpDialog(tester, title: '添加宏定义', label: '宏定义');

    await tester.enterText(
      find.byKey(const Key('compileEntryTextField')),
      '   ',
    );
    await tester.pump();

    expect(_confirmButton(tester).onPressed, isNull);
  });

  testWidgets('选择构建配置后确定返回所选值', (tester) async {
    CompileEntryResult? result;
    await _pumpDialog(
      tester,
      title: '添加宏定义',
      label: '宏定义',
      onResult: (CompileEntryResult? value) => result = value,
    );

    await tester.enterText(
      find.byKey(const Key('compileEntryTextField')),
      'NDEBUG',
    );
    await tester.pump();
    await _selectBuildModel(tester, 'Debug');
    await _tapConfirm(tester);

    expect(result, isNotNull);
    expect(result!.text, 'NDEBUG');
    expect(result!.buildModel, BuildModel.debug);
  });

  testWidgets('浏览按钮调用目录选择并填入返回值', (tester) async {
    int pickCount = 0;
    await _pumpDialog(
      tester,
      title: '添加附加库目录',
      label: '目录路径',
      showBrowse: true,
      pickDirectory: () async {
        pickCount++;
        return r'D:\libs\third_party';
      },
    );

    expect(find.byKey(const Key('compileEntryBrowseButton')), findsOneWidget);
    expect(find.text('浏览…'), findsOneWidget);

    await tester.tap(find.byKey(const Key('compileEntryBrowseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(pickCount, 1);
    expect(_textBox(tester).controller!.text, r'D:\libs\third_party');
    expect(_confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('取消目录选择时保持原文本', (tester) async {
    await _pumpDialog(
      tester,
      title: '添加附加库目录',
      label: '目录路径',
      showBrowse: true,
      initialText: 'lib',
      pickDirectory: () async => null,
    );

    await tester.tap(find.byKey(const Key('compileEntryBrowseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_textBox(tester).controller!.text, 'lib');
    expect(_confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('编辑模式预填文本与构建配置', (tester) async {
    await _pumpDialog(
      tester,
      title: '编辑编译前命令',
      label: '命令',
      initialText: 'echo hi',
      initialBuildModel: BuildModel.release,
    );

    expect(find.text('编辑编译前命令'), findsOneWidget);
    expect(find.text('命令'), findsOneWidget);
    expect(_textBox(tester).controller!.text, 'echo hi');
    expect(_buildModelValue(tester), BuildModel.release);
    expect(_confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('点击取消返回 null', (tester) async {
    bool completed = false;
    CompileEntryResult? result;
    await _pumpDialog(
      tester,
      title: '添加宏定义',
      label: '宏定义',
      onResult: (CompileEntryResult? value) {
        completed = true;
        result = value;
      },
    );

    await tester.tap(find.byKey(const Key('compileEntryCancelButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(completed, isTrue);
    expect(result, isNull);
    expect(find.byType(ContentDialog), findsNothing);
  });

  testWidgets('传入脚本列表时显示脚本下拉并列出相对路径', (tester) async {
    await _pumpDialog(
      tester,
      title: '添加编译前命令',
      label: '命令',
      selectableScripts: _scripts(),
    );

    expect(find.text('从包中选择'), findsOneWidget);
    expect(
      _scriptCombo(tester).items!
          .map((ComboBoxItem<FileModel> item) => item.value!.path)
          .toList(),
      <String>['scripts/build.bat', 'tools/gen.py'],
    );
  });

  testWidgets('未传脚本列表时不显示脚本下拉', (tester) async {
    await _pumpDialog(tester, title: '添加宏定义', label: '宏定义');

    expect(find.byKey(const Key('compileEntryScriptField')), findsNothing);
    expect(find.text('从包中选择'), findsNothing);
  });

  testWidgets('选择 bat 脚本插入带引号的包内引用路径', (tester) async {
    await _pumpDialog(
      tester,
      title: '添加编译前命令',
      label: '命令',
      selectableScripts: _singleScript('build.bat', 'scripts/build.bat'),
    );

    await _selectScript(tester, 'scripts/build.bat');

    expect(
      _textBox(tester).controller!.text,
      r'"$(MSBuildThisFileDirectory)files\scripts\build.bat"',
    );
    expect(_confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('选择 py 脚本插入 python 前缀引用', (tester) async {
    await _pumpDialog(
      tester,
      title: '添加编译前命令',
      label: '命令',
      selectableScripts: _singleScript('gen.py', 'tools/gen.py'),
    );

    await _selectScript(tester, 'tools/gen.py');

    expect(
      _textBox(tester).controller!.text,
      r'python "$(MSBuildThisFileDirectory)files\tools\gen.py"',
    );
  });

  testWidgets('选择 ps1 脚本插入 powershell 前缀引用', (tester) async {
    await _pumpDialog(
      tester,
      title: '添加编译前命令',
      label: '命令',
      selectableScripts: _singleScript('setup.ps1', 'tools/setup.ps1'),
    );

    await _selectScript(tester, 'tools/setup.ps1');

    expect(
      _textBox(tester).controller!.text,
      r'powershell -NoProfile -ExecutionPolicy Bypass -File '
      r'"$(MSBuildThisFileDirectory)files\tools\setup.ps1"',
    );
  });

  testWidgets('选择 exe 脚本插入直接引用路径', (tester) async {
    await _pumpDialog(
      tester,
      title: '添加编译前命令',
      label: '命令',
      selectableScripts: _singleScript('app.exe', 'bin/app.exe'),
    );

    await _selectScript(tester, 'bin/app.exe');

    expect(
      _textBox(tester).controller!.text,
      r'"$(MSBuildThisFileDirectory)files\bin\app.exe"',
    );
  });

  testWidgets('脚本引用在光标处插入并定位到插入末尾', (tester) async {
    await _pumpDialog(
      tester,
      title: '编辑编译前命令',
      label: '命令',
      initialText: 'echo ',
      selectableScripts: _singleScript('build.bat', 'scripts/build.bat'),
    );

    final TextEditingController controller = _textBox(tester).controller!;
    controller.selection = const TextSelection.collapsed(offset: 5);
    await tester.pump();

    await _selectScript(tester, 'scripts/build.bat');

    expect(
      controller.text,
      r'echo "$(MSBuildThisFileDirectory)files\scripts\build.bat"',
    );
    expect(controller.selection.baseOffset, controller.text.length);
  });

  testWidgets('脚本引用替换选中文本', (tester) async {
    await _pumpDialog(
      tester,
      title: '编辑编译前命令',
      label: '命令',
      initialText: 'old',
      selectableScripts: _singleScript('build.bat', 'scripts/build.bat'),
    );

    final TextEditingController controller = _textBox(tester).controller!;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    await tester.pump();

    await _selectScript(tester, 'scripts/build.bat');

    expect(
      controller.text,
      r'"$(MSBuildThisFileDirectory)files\scripts\build.bat"',
    );
    expect(controller.selection.baseOffset, controller.text.length);
  });

  testWidgets('选择无效时脚本引用追加到已有文本末尾', (tester) async {
    await _pumpDialog(
      tester,
      title: '编辑编译前命令',
      label: '命令',
      initialText: 'echo ',
      selectableScripts: _singleScript('build.bat', 'scripts/build.bat'),
    );

    expect(_textBox(tester).controller!.selection.isValid, isFalse);

    await _selectScript(tester, 'scripts/build.bat');

    expect(
      _textBox(tester).controller!.text,
      r'echo "$(MSBuildThisFileDirectory)files\scripts\build.bat"',
    );
  });

  testWidgets('传入 showMacroHelper 时显示宏下拉并插入所选宏', (tester) async {
    await _pumpDialog(
      tester,
      title: '添加编译前命令',
      label: '命令',
      showMacroHelper: true,
    );

    expect(find.text('插入宏'), findsOneWidget);

    await _selectMacro(tester, r'$(OutDir)');

    expect(_textBox(tester).controller!.text, r'$(OutDir)');
    expect(_confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('宏下拉包含全部 16 个常用宏', (tester) async {
    await _pumpDialog(
      tester,
      title: '添加编译前命令',
      label: '命令',
      showMacroHelper: true,
    );

    expect(
      _macroCombo(tester).items!
          .map((ComboBoxItem<String> item) => item.value)
          .toList(),
      _expectedMacros,
    );
  });

  testWidgets('未传 showMacroHelper 时不显示宏下拉', (tester) async {
    await _pumpDialog(tester, title: '添加宏定义', label: '宏定义');

    expect(find.byKey(const Key('compileEntryMacroField')), findsNothing);
    expect(find.text('插入宏'), findsNothing);
  });

  testWidgets('脚本与宏下拉可同时显示且无布局异常', (tester) async {
    await _pumpDialog(
      tester,
      title: '添加编译前命令',
      label: '命令',
      selectableScripts: _scripts(),
      showMacroHelper: true,
    );

    expect(find.byKey(const Key('compileEntryScriptField')), findsOneWidget);
    expect(find.byKey(const Key('compileEntryMacroField')), findsOneWidget);
    expect(find.text('从包中选择'), findsOneWidget);
    expect(find.text('插入宏'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required String title,
  required String label,
  String? hintText,
  bool showBrowse = false,
  Future<String?> Function()? pickDirectory,
  String initialText = '',
  BuildModel initialBuildModel = BuildModel.all,
  List<FileModel> selectableScripts = const <FileModel>[],
  bool showMacroHelper = false,
  ValueChanged<CompileEntryResult?>? onResult,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FluentApp(
      home: Builder(
        builder: (BuildContext context) => Center(
          child: Button(
            onPressed: () async {
              final CompileEntryResult? result =
                  await showDialog<CompileEntryResult>(
                    context: context,
                    builder: (_) => CompileEntryDialog(
                      title: title,
                      label: label,
                      hintText: hintText,
                      showBrowse: showBrowse,
                      pickDirectory: pickDirectory,
                      initialText: initialText,
                      initialBuildModel: initialBuildModel,
                      selectableScripts: selectableScripts,
                      showMacroHelper: showMacroHelper,
                    ),
                  );
              onResult?.call(result);
            },
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

Future<void> _selectBuildModel(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const Key('compileEntryBuildModelField')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(label).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _selectScript(WidgetTester tester, String path) async {
  await tester.tap(find.byKey(const Key('compileEntryScriptField')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(path).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _selectMacro(WidgetTester tester, String macro) async {
  await tester.tap(find.byKey(const Key('compileEntryMacroField')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(macro).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _tapConfirm(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('compileEntryConfirmButton')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

TextBox _textBox(WidgetTester tester) =>
    tester.widget<TextBox>(find.byKey(const Key('compileEntryTextField')));

FilledButton _confirmButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.byKey(const Key('compileEntryConfirmButton')),
);

BuildModel _buildModelValue(WidgetTester tester) => tester
    .widget<ComboBox<BuildModel>>(
      find.byKey(const Key('compileEntryBuildModelField')),
    )
    .value!;

List<FileModel> _scripts() => <FileModel>[
  FileModel(name: 'build.bat', path: 'scripts/build.bat'),
  FileModel(name: 'gen.py', path: 'tools/gen.py'),
];

List<FileModel> _singleScript(String name, String path) => <FileModel>[
  FileModel(name: name, path: path),
];

ComboBox<FileModel> _scriptCombo(WidgetTester tester) =>
    tester.widget<ComboBox<FileModel>>(
      find.byKey(const Key('compileEntryScriptField')),
    );

ComboBox<String> _macroCombo(WidgetTester tester) => tester
    .widget<ComboBox<String>>(find.byKey(const Key('compileEntryMacroField')));

const List<String> _expectedMacros = <String>[
  r'$(Configuration)',
  r'$(Platform)',
  r'$(OutDir)',
  r'$(IntDir)',
  r'$(ProjectDir)',
  r'$(SolutionDir)',
  r'$(TargetPath)',
  r'$(TargetName)',
  r'$(TargetExt)',
  r'$(MSBuildThisFileDirectory)',
  r'$(VCTargetsPath)',
  r'%(Filename)',
  r'%(Extension)',
  r'%(FullPath)',
  r'%(RelativeDir)',
  r'%(RootDir)',
];
