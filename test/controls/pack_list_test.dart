import 'package:cpp_nuget_pack/controls/pack_list.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/util/repo_icon.dart';
import 'package:cpp_nuget_pack/util/svgs.dart';
import 'package:cpp_nuget_pack/widgets/library_card.dart';
import 'package:cpp_nuget_pack/widgets/tag.dart';
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

  testWidgets('版本标签在左、仓库徽标在右', (tester) async {
    await _pumpItems(
      tester,
      _items(<PackModel>[_pack()], repoBadgeFor: (_) => RepoBadge.git),
    );

    final Finder versionTag = _versionTag('1.0.0');
    expect(versionTag, findsOneWidget);

    final double badgeX = tester
        .getTopLeft(find.byKey(const Key('repoBadge_demo')))
        .dx;
    final double versionX = tester.getTopLeft(versionTag).dx;

    expect(versionX, lessThan(badgeX));
  });

  testWidgets('长标题单行省略且版本标签按 96 截断', (tester) async {
    final String longTitle = 'demo-${'x' * 80}';
    await _pumpItems(
      tester,
      _items(<PackModel>[
        _pack(name: longTitle, sourceVersion: 'version-3.49.1'),
      ]),
    );

    final Iterable<Text> titleTexts = tester.widgetList<Text>(
      find.text(longTitle),
    );
    expect(
      titleTexts.any(
        (Text text) =>
            text.maxLines == 1 && text.overflow == TextOverflow.ellipsis,
      ),
      isTrue,
      reason: '标题应单行省略，避免与版本标签一起溢出',
    );

    final Finder versionTag = _versionTag('version-3.49.1');
    expect(versionTag, findsOneWidget);
    final Tag tag = tester.widget<Tag>(versionTag);
    expect(tag.maxWidth, 96);
    expect(tag.tooltip, 'version-3.49.1');
  });

  testWidgets('有构建版本时版本标签优先显示 sourceVersion', (tester) async {
    await _pumpItems(
      tester,
      _items(<PackModel>[_pack(sourceVersion: 'v1.2.3')]),
    );

    expect(_versionTag('v1.2.3'), findsOneWidget);
    expect(_versionTag('1.0.0'), findsNothing);
  });

  testWidgets('无构建版本时版本标签回退显示手填版本', (tester) async {
    await _pumpItems(tester, _items(<PackModel>[_pack()]));

    expect(_versionTag('1.0.0'), findsOneWidget);
  });

  testWidgets('远程头像就绪时显示 Image 并带包名 key', (tester) async {
    await _pumpItems(
      tester,
      _items(
        <PackModel>[_pack()],
        repoIconFor: (_) =>
            (platform: RepoPlatform.github, avatarPath: r'C:\cache\avatar.png'),
      ),
    );

    expect(find.byKey(const Key('repoAvatar_demo')), findsOneWidget);
    final Image avatar = tester.widget<Image>(
      find.byKey(const Key('repoAvatar_demo')),
    );
    final FileImage provider = avatar.image as FileImage;
    expect(provider.file.path, r'C:\cache\avatar.png');
    expect(avatar.width, 20);
    expect(avatar.height, 20);
    expect(avatar.fit, BoxFit.contain);
  });

  testWidgets('头像不可用时显示平台回退图标（GitHub 官方标志）', (tester) async {
    await _pumpItems(
      tester,
      _items(
        <PackModel>[_pack()],
        repoIconFor: (_) => (platform: RepoPlatform.github, avatarPath: null),
      ),
    );

    final SvgPicture fallback = tester.widget<SvgPicture>(
      find.byKey(const Key('repoFallbackIcon_demo')),
    );
    expect(
      (fallback.bytesLoader as SvgAssetLoader).assetName,
      Svgs.repoGithubPath,
    );
    expect(fallback.colorFilter, isNotNull);
    expect(fallback.semanticsLabel, '开源仓库图标');
  });

  testWidgets('GitLab 回退使用自绘通用图标', (tester) async {
    await _pumpItems(
      tester,
      _items(
        <PackModel>[_pack()],
        repoIconFor: (_) => (platform: RepoPlatform.gitlab, avatarPath: null),
      ),
    );

    final SvgPicture fallback = tester.widget<SvgPicture>(
      find.byKey(const Key('repoFallbackIcon_demo')),
    );
    expect(
      (fallback.bytesLoader as SvgAssetLoader).assetName,
      Svgs.repoRemotePath,
    );
  });

  test('平台不可辨识且无本地图标时回退纸箱', () {
    final LibraryItem item =
        PackList.buildCards(
              <PackModel>[_pack()],
              onSave: _acceptSave,
              pickDirectory: _pickDirectory,
              repoIconFor: (_) => (platform: null, avatarPath: null),
            ).single
            as LibraryItem;

    expect(item.icon, same(Svgs.cardboardBox));
  });

  test('平台不可辨识但有本地图标时使用本地文件', () {
    final LibraryItem item =
        PackList.buildCards(
              <PackModel>[
                _pack(sourcePath: r'C:\libs\demo', iconPath: 'assets/logo.svg'),
              ],
              onSave: _acceptSave,
              pickDirectory: _pickDirectory,
              repoIconFor: (_) => (platform: null, avatarPath: null),
            ).single
            as LibraryItem;

    final SvgPicture icon = item.icon! as SvgPicture;
    expect(
      (icon.bytesLoader as SvgFileLoader).file.path,
      r'C:\libs\demo/assets/logo.svg',
    );
  });

  testWidgets('头像加载失败时经 errorBuilder 降级到平台回退图标', (tester) async {
    await _pumpItems(
      tester,
      _items(
        <PackModel>[_pack()],
        repoIconFor: (_) =>
            (platform: RepoPlatform.github, avatarPath: r'C:\cache\avatar.png'),
      ),
    );

    final Finder avatarFinder = find.byKey(const Key('repoAvatar_demo'));
    final Image avatar = tester.widget<Image>(avatarFinder);
    expect(avatar.errorBuilder, isNotNull);

    final Widget fallback = avatar.errorBuilder!(
      tester.element(avatarFinder),
      Exception('解码失败'),
      null,
    );
    expect(fallback, isA<SvgPicture>());
    expect((fallback as SvgPicture).key, const Key('repoFallbackIcon_demo'));

    final Widget localFallback = fallback.errorBuilder!(
      tester.element(avatarFinder),
      Exception('资产缺失'),
      StackTrace.empty,
    );
    expect(localFallback, same(Svgs.cardboardBox));
  });
}

Finder _versionTag(String text) => find.byWidgetPredicate(
  (Widget widget) => widget is Tag && widget.text == text,
);

PackModel _pack({
  String name = 'demo',
  String? iconPath,
  String? sourcePath,
  String? sourceVersion,
}) => PackModel(
  name: name,
  version: '1.0.0',
  author: 'tester',
  iconPath: iconPath,
  sourcePath: sourcePath,
  sourceVersion: sourceVersion,
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
  RepoIconSource Function(PackModel pack)? repoIconFor,
}) {
  return PackList.buildCards(
    packs,
    onSave: _acceptSave,
    pickDirectory: _pickDirectory,
    repoBadgeFor: repoBadgeFor,
    repoIconFor: repoIconFor,
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
