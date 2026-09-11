import 'package:cpp_nuget_pack/controls/compile_entry_dialog.dart';
import 'package:cpp_nuget_pack/models/build_model.dart';
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
