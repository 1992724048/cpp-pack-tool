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
}

PackModel _pack({String? iconPath, String? sourcePath}) => PackModel(
  name: 'demo',
  version: '1.0.0',
  author: 'tester',
  iconPath: iconPath,
  sourcePath: sourcePath,
);

LibraryItem _firstItem(PackModel pack) =>
    PackList.buildCards(<PackModel>[pack]).single as LibraryItem;
