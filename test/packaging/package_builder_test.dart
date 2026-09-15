import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/package_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBuilder implements PackageBuilder {
  _FakeBuilder(this.id);

  @override
  final String id;

  @override
  String get displayName => id;

  @override
  Future<PackagePlan> buildPlan(PackModel pack) async =>
      PackagePlan(entries: const <PackageEntry>[]);
}

void main() {
  final List<PackageBuilder> builders = <PackageBuilder>[
    _FakeBuilder('nuget'),
    _FakeBuilder('cmake'),
  ];

  PackModel packWith(List<String> enabledFormats) {
    return PackModel(name: 'demo', version: '1.0.0', author: 'tester')
      ..enabledFormats = enabledFormats;
  }

  group('enabledBuildersFor', () {
    test('未记录（空列表）时回退全部并按注册表序', () {
      expect(
        enabledBuildersFor(
          packWith(<String>[]),
          all: builders,
        ).map((PackageBuilder builder) => builder.id),
        <String>['nuget', 'cmake'],
      );
    });

    test('只保留已知 id 并按注册表序', () {
      expect(
        enabledBuildersFor(
          packWith(<String>['cmake', 'nuget']),
          all: builders,
        ).map((PackageBuilder builder) => builder.id),
        <String>['nuget', 'cmake'],
      );
      expect(
        enabledBuildersFor(
          packWith(<String>['cmake']),
          all: builders,
        ).single.id,
        'cmake',
      );
    });

    test('全部 id 非法时回退全部（fail-open）', () {
      expect(
        enabledBuildersFor(
          packWith(<String>['unknown', 'other']),
          all: builders,
        ).map((PackageBuilder builder) => builder.id),
        <String>['nuget', 'cmake'],
      );
    });

    test('混合合法与非法 id 时只保留合法项', () {
      expect(
        enabledBuildersFor(
          packWith(<String>['unknown', 'cmake']),
          all: builders,
        ).single.id,
        'cmake',
      );
    });

    test('构建器列表为空时返回空', () {
      expect(
        enabledBuildersFor(packWith(<String>[]), all: const <PackageBuilder>[]),
        isEmpty,
      );
    });
  });

  group('effectivePackagingBuilder', () {
    test('首选在启用集内时返回首选', () {
      expect(
        effectivePackagingBuilder(
          packWith(<String>['nuget', 'cmake']),
          builders[1],
          all: builders,
        ).id,
        'cmake',
      );
    });

    test('首选未启用时回落到首个启用项', () {
      expect(
        effectivePackagingBuilder(
          packWith(<String>['cmake']),
          builders[0],
          all: builders,
        ).id,
        'cmake',
      );
    });

    test('首选为空时返回首个启用项', () {
      expect(
        effectivePackagingBuilder(packWith(<String>[]), null, all: builders).id,
        'nuget',
      );
    });

    test('启用集与构建器列表均为空时抛出 ArgumentError', () {
      expect(
        () => effectivePackagingBuilder(
          packWith(<String>[]),
          null,
          all: const <PackageBuilder>[],
        ),
        throwsArgumentError,
      );
    });
  });
}
