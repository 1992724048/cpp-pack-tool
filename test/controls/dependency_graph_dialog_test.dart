import 'package:cpp_nuget_pack/controls/dependency_graph_dialog.dart';
import 'package:cpp_nuget_pack/models/dependency_model.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('打开对话框后渲染全部包节点、缺失节点与图例', (tester) async {
    await _pumpDialog(tester, packs: _packs(), selectedPackName: 'beta');

    expect(find.byKey(const Key('dependencyGraphDialog')), findsOneWidget);
    expect(find.text('依赖关系图'), findsOneWidget);
    expect(find.text('拖拽平移、滚轮缩放；红色为缺失依赖'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);

    for (final String name in <String>[
      'alpha',
      'beta',
      'gamma',
      'delta',
      'ghost',
    ]) {
      expect(find.byKey(Key('dependencyGraphNode_$name')), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byKey(const Key('dependencyGraphNode_ghost')),
        matching: find.text('缺失'),
      ),
      findsOneWidget,
    );
    expect(find.text('普通'), findsOneWidget);
    expect(find.text('当前包'), findsOneWidget);
    expect(find.text('缺失'), findsNWidgets(2));

    final double deltaY = _topLeft(tester, 'delta').dy;
    final double gammaY = _topLeft(tester, 'gamma').dy;
    final double ghostY = _topLeft(tester, 'ghost').dy;
    expect(deltaY, lessThan(gammaY));
    expect(gammaY, lessThan(ghostY));

    final double gammaX = _topLeft(tester, 'gamma').dx;
    final double betaX = _topLeft(tester, 'beta').dx;
    final double alphaX = _topLeft(tester, 'alpha').dx;
    expect(gammaX, lessThan(betaX));
    expect(betaX, lessThan(alphaX));
    expect(_topLeft(tester, 'ghost').dx, gammaX);
  });

  testWidgets('选中包、缺失节点与普通节点使用对应描边', (tester) async {
    await _pumpDialog(tester, packs: _packs(), selectedPackName: 'beta');

    expect(_borderColor(tester, 'beta'), UCColors.accent);
    expect(_borderWidth(tester, 'beta'), 2);
    expect(_borderColor(tester, 'ghost'), UCColors.flavor.red);
    expect(_borderWidth(tester, 'ghost'), 2);
    expect(_borderColor(tester, 'gamma'), UCColors.flavor.overlay0);
    expect(_borderWidth(tester, 'gamma'), 1);
  });

  testWidgets('拖拽画布平移不抛异常', (tester) async {
    await _pumpDialog(tester, packs: _packs(), selectedPackName: 'beta');

    await tester.drag(find.byType(InteractiveViewer), const Offset(60, 40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
  });

  testWidgets('无包时显示空态且不渲染画布', (tester) async {
    await _pumpDialog(tester, packs: const <PackModel>[]);

    expect(find.byKey(const Key('dependencyGraphDialog')), findsOneWidget);
    expect(find.text('暂无包'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('点击关闭按钮关闭对话框', (tester) async {
    await _pumpDialog(tester, packs: _packs());

    await tester.tap(find.byKey(const Key('dependencyGraphCloseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('dependencyGraphDialog')), findsNothing);
  });
}

List<PackModel> _packs() {
  return <PackModel>[
    _pack(
      'alpha',
      dependencies: const <DependencyModel>[
        DependencyModel(name: 'beta', version: '[1.0.0,)'),
        DependencyModel(name: 'ghost', version: '[1.0.0,)'),
      ],
    ),
    _pack(
      'beta',
      dependencies: const <DependencyModel>[
        DependencyModel(name: 'gamma', version: '[1.0.0,)'),
      ],
    ),
    _pack('gamma'),
    _pack('delta'),
  ];
}

PackModel _pack(
  String name, {
  List<DependencyModel> dependencies = const <DependencyModel>[],
}) {
  final PackModel pack = PackModel(
    name: name,
    version: '1.0.0',
    author: 'tester',
  );
  pack.dependencies.addAll(dependencies);
  return pack;
}

Offset _topLeft(WidgetTester tester, String name) {
  return tester.getTopLeft(find.byKey(Key('dependencyGraphNode_$name')));
}

Border _nodeBorder(WidgetTester tester, String name) {
  final Container container = tester.widget<Container>(
    find.byKey(Key('dependencyGraphNode_$name')),
  );
  final BoxDecoration decoration = container.decoration! as BoxDecoration;
  return decoration.border! as Border;
}

Color _borderColor(WidgetTester tester, String name) {
  return _nodeBorder(tester, name).top.color;
}

double _borderWidth(WidgetTester tester, String name) {
  return _nodeBorder(tester, name).top.width;
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required List<PackModel> packs,
  String? selectedPackName,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FluentApp(
      home: Builder(
        builder: (BuildContext context) => Center(
          child: Button(
            onPressed: () => showDependencyGraphDialog(
              context,
              packs: packs,
              selectedPackName: selectedPackName,
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
