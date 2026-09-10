import 'dart:ui' show Brightness;

import 'package:cpp_nuget_pack/util/catppuccin_icons.dart';
import 'package:flutter_test/flutter_test.dart';

String _latte(String icon) => 'assets/icons/catppuccin/latte/$icon.svg';

String _mocha(String icon) => 'assets/icons/catppuccin/mocha/$icon.svg';

String _file(String name, {Brightness brightness = Brightness.light}) =>
    iconAssetFor(brightness: brightness, name: name);

String _dir(
  String name, {
  bool expanded = false,
  Brightness brightness = Brightness.light,
}) => iconAssetFor(
  brightness: brightness,
  name: name,
  isDirectory: true,
  isExpanded: expanded,
);

void main() {
  group('扩展名映射', () {
    test('C/C++ 源文件与头文件', () {
      expect(_file('main.c'), _latte('c'));
      expect(_file('main.cpp'), _latte('cpp'));
      expect(_file('main.cc'), _latte('cpp'));
      expect(_file('main.cxx'), _latte('cpp'));
      expect(_file('main.c++'), _latte('cpp'));
      expect(_file('foo.h'), _latte('c-header'));
      expect(_file('foo.hpp'), _latte('cpp-header'));
      expect(_file('foo.inl'), _latte('cpp-header'));
      expect(_file('foo.ipp'), _latte('cpp-header'));
    });

    test('C++20 模块映射到 cpp 图标', () {
      expect(_file('module.ixx'), _latte('cpp'));
      expect(_file('module.cppm'), _latte('cpp'));
      expect(_file('module.mpp'), _latte('cpp'));
    });

    test('文档与配置文件', () {
      expect(_file('notes.md'), _latte('markdown'));
      expect(_file('conf.yaml'), _latte('yaml'));
      expect(_file('conf.yml'), _latte('yaml'));
      expect(_file('data.json'), _latte('json'));
      expect(_file('data.xml'), _latte('xml'));
      expect(_file('notes.txt'), _latte('text'));
      expect(_file('config.toml'), _latte('toml'));
    });

    test('库、图片与压缩包', () {
      expect(_file('foo.lib'), _latte('lib'));
      expect(_file('foo.dll'), _latte('lib'));
      expect(_file('logo.png'), _latte('image'));
      expect(_file('logo.jpeg'), _latte('image'));
      expect(_file('icon.ico'), _latte('image'));
      expect(_file('logo.svg'), _latte('svg'));
      expect(_file('archive.zip'), _latte('zip'));
      expect(_file('archive.tar.gz'), _latte('zip'));
      expect(_file('doc.pdf'), _latte('pdf'));
    });

    test('VS 工程、NuGet、脚本与 Dart 文件', () {
      expect(_file('app.sln'), _latte('visual-studio'));
      expect(_file('app.vcxproj'), _latte('visual-studio'));
      expect(_file('app.csproj'), _latte('visual-studio'));
      expect(_file('package.nupkg'), _latte('nuget'));
      expect(_file('build.ps1'), _latte('powershell'));
      expect(_file('run.bat'), _latte('batch'));
      expect(_file('run.cmd'), _latte('batch'));
      expect(_file('main.dart'), _latte('dart'));
    });

    test('未知扩展名回退 _file', () {
      expect(_file('data.xyz'), _latte('_file'));
      expect(_file('main.rc'), _latte('_file'));
      expect(_file('noextension'), _latte('_file'));
    });
  });

  group('文件名匹配', () {
    test('CMakeLists.txt 与 Makefile', () {
      expect(_file('CMakeLists.txt'), _latte('cmake'));
      expect(_file('cmakelists.txt'), _latte('cmake'));
      expect(_file('Makefile'), _latte('makefile'));
    });

    test('.gitignore/.gitattributes/.gitmodules', () {
      expect(_file('.gitignore'), _latte('git'));
      expect(_file('.gitattributes'), _latte('git'));
      expect(_file('.gitmodules'), _latte('git'));
    });

    test('README/LICENSE/NOTICE/COPYING/CHANGELOG 前缀匹配', () {
      expect(_file('README.md'), _latte('readme'));
      expect(_file('readme.txt'), _latte('readme'));
      expect(_file('LICENSE'), _latte('license'));
      expect(_file('license.txt'), _latte('license'));
      expect(_file('NOTICE'), _latte('license'));
      expect(_file('COPYING'), _latte('license'));
      expect(_file('CHANGELOG.md'), _latte('changelog'));
    });

    test('nuget.config 映射到 nuget', () {
      expect(_file('nuget.config'), _latte('nuget'));
    });

    test('文件名匹配优先于扩展名匹配', () {
      expect(_file('README.h'), _latte('readme'));
    });

    test('大小写不敏感', () {
      expect(_file('MaKeFiLe'), _latte('makefile'));
      expect(_file('.GITIGNORE'), _latte('git'));
      expect(_file('ReadMe.md'), _latte('readme'));
    });
  });

  group('目录映射', () {
    test('具名目录', () {
      expect(_dir('include'), _latte('folder_include'));
      expect(_dir('includes'), _latte('folder_include'));
      expect(_dir('src'), _latte('folder_src'));
      expect(_dir('sources'), _latte('folder_src'));
      expect(_dir('lib'), _latte('folder_lib'));
      expect(_dir('tests'), _latte('folder_tests'));
      expect(_dir('spec'), _latte('folder_tests'));
      expect(_dir('docs'), _latte('folder_docs'));
      expect(_dir('assets'), _latte('folder_assets'));
      expect(_dir('images'), _latte('folder_images'));
      expect(_dir('scripts'), _latte('folder_scripts'));
      expect(_dir('config'), _latte('folder_config'));
      expect(_dir('bin'), _latte('folder_dist'));
      expect(_dir('windows'), _latte('folder_windows'));
      expect(_dir('shared'), _latte('folder_shared'));
      expect(_dir('utils'), _latte('folder_utils'));
      expect(_dir('themes'), _latte('folder_themes'));
    });

    test('目录名大小写不敏感', () {
      expect(_dir('Include'), _latte('folder_include'));
      expect(_dir('SRC'), _latte('folder_src'));
    });

    test('未知目录回退 _folder', () {
      expect(_dir('whatever'), _latte('_folder'));
    });

    test('展开态使用 _open 变体', () {
      expect(_dir('include', expanded: true), _latte('folder_include_open'));
      expect(_dir('whatever', expanded: true), _latte('_folder_open'));
    });
  });

  group('flavor 选择', () {
    test('深色主题 mocha，浅色主题 latte', () {
      expect(_file('main.cpp', brightness: Brightness.dark), _mocha('cpp'));
      expect(_file('main.cpp', brightness: Brightness.light), _latte('cpp'));
      expect(
        iconAssetFor(
          brightness: Brightness.dark,
          name: 'include',
          isDirectory: true,
          isExpanded: true,
        ),
        _mocha('folder_include_open'),
      );
    });
  });
}
