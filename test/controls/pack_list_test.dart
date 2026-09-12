import 'package:cpp_nuget_pack/controls/pack_list.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/svgs.dart';
import 'package:cpp_nuget_pack/widgets/library_card.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('无图标信息时使用默认纸箱图标', () {
    final LibraryItem item = _firstItem(_pack());

    expect(item.icon, same(Svgs.cardboardBox));
  });

  test('缺少源目录时使用默认纸箱图标', () {
    final LibraryItem item = _firstItem(_pack(iconPath: 'assets/logo.svg'));

    expect(item.icon, same(Svgs.cardboardBox));
  });

  test('SVG 图标按源目录拼接绝对路径并带兜底', () {
    final LibraryItem item = _firstItem(
      _pack(sourcePath: r'C:\libs\foo', iconPath: 'assets/logo.svg'),
    );

    final SvgPicture svg = item.icon! as SvgPicture;
    final SvgFileLoader loader = svg.bytesLoader as SvgFileLoader;
    expect(loader.file.path, r'C:\libs\foo/assets/logo.svg');
    expect(svg.width, 20);
    expect(svg.height, 20);
    expect(svg.errorBuilder, isNotNull);
  });

  test('大写 SVG 扩展名同样按矢量图渲染', () {
    final LibraryItem item = _firstItem(
      _pack(sourcePath: r'C:\libs\foo', iconPath: 'assets/LOGO.SVG'),
    );

    expect(item.icon, isA<SvgPicture>());
    expect((item.icon! as SvgPicture).bytesLoader, isA<SvgFileLoader>());
  });

  test('位图图标生成 FileImage 并带兜底', () {
    final LibraryItem item = _firstItem(
      _pack(sourcePath: r'C:\libs\foo', iconPath: 'images/banner.png'),
    );

    final Image image = item.icon! as Image;
    final FileImage provider = image.image as FileImage;
    expect(provider.file.path, r'C:\libs\foo/images/banner.png');
    expect(image.width, 20);
    expect(image.height, 20);
    expect(image.fit, BoxFit.contain);
    expect(image.errorBuilder, isNotNull);
  });

  testWidgets('未提供徽标状态时不渲染仓库徽标', (tester) async {
    await _pumpItems(tester, _items(<PackModel>[_pack()]));

    expect(find.byKey(const Key('repoBadge_demo')), findsNothing);
    expect(find.byKey(const Key('repoUpdateBadge_demo')), findsNothing);
  });

  testWidgets('git 状态渲染 git 徽标', (tester) async {
    await _pumpItems(
      tester,
      _items(<PackModel>[_pack()], repoBadgeFor: (_) => RepoBadge.git),
    );

    expect(find.byKey(const Key('repoBadge_demo')), findsOneWidget);
    expect(find.byKey(const Key('repoUpdateBadge_demo')), findsNothing);
  });

  testWidgets('update 状态渲染更新徽标且不显示 git 徽标', (tester) async {
    await _pumpItems(
      tester,
      _items(<PackModel>[_pack()], repoBadgeFor: (_) => RepoBadge.update),
    );

    expect(find.byKey(const Key('repoUpdateBadge_demo')), findsOneWidget);
    expect(find.byKey(const Key('repoBadge_demo')), findsNothing);
  });
}

PackModel _pack({String? iconPath, String? sourcePath}) => PackModel(
  name: 'demo',
  version: '1.0.0',
  author: 'tester',
  iconPath: iconPath,
  sourcePath: sourcePath,
);

LibraryItem _firstItem(PackModel pack) =>
    PackList.buildCards(
          <PackModel>[pack],
          onSave: _acceptSave,
          pickDirectory: _pickDirectory,
        ).single
        as LibraryItem;

List<NavigationPaneItem> _items(
  List<PackModel> packs, {
  RepoBadge? Function(PackModel pack)? repoBadgeFor,
}) {
  return PackList.buildCards(
    packs,
    onSave: _acceptSave,
    pickDirectory: _pickDirectory,
    repoBadgeFor: repoBadgeFor,
  );
}

Future<void> _pumpItems(
  WidgetTester tester,
  List<NavigationPaneItem> items,
) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    FluentApp(
      home: NavigationView(
        pane: NavigationPane(
          selected: 0,
          displayMode: PaneDisplayMode.expanded,
          items: items,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<bool> _acceptSave(PackModel pack) async => true;

Future<String?> _pickDirectory() async => null;
