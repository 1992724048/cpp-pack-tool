import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/cmake_builder.dart';
import 'package:cpp_nuget_pack/packaging/nuget_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';

abstract interface class PackageBuilder {
  String get id;

  String get displayName;

  Future<PackagePlan> buildPlan(PackModel pack);
}

abstract final class PackageBuilderRegistry {
  static const List<PackageBuilder> all = <PackageBuilder>[
    NuGetPackageBuilder(),
    CMakePackageBuilder(),
  ];
}

/// 该包启用的构建器（规范序 = 注册表序）；未记录 / 全部 id 非法时回退全部。
///
/// 空 `enabledFormats` 表示旧包缺字段（或未记录）——fail-open 到全部格式，
/// 与旧行为一致；保证返回值恒非空（`all` 非空时）。
List<PackageBuilder> enabledBuildersFor(
  PackModel pack, {
  List<PackageBuilder> all = PackageBuilderRegistry.all,
}) {
  if (all.isEmpty) {
    return const <PackageBuilder>[];
  }
  final Set<String> enabledIds = <String>{...pack.enabledFormats};
  final List<PackageBuilder> selected = <PackageBuilder>[
    for (final PackageBuilder builder in all)
      if (enabledIds.contains(builder.id)) builder,
  ];
  return selected.isEmpty ? List<PackageBuilder>.of(all) : selected;
}

/// 会话首选在启用集内则用之，否则返回首个启用项（启用集恒非空）。
PackageBuilder effectivePackagingBuilder(
  PackModel pack,
  PackageBuilder? preferred, {
  List<PackageBuilder> all = PackageBuilderRegistry.all,
}) {
  final List<PackageBuilder> enabled = enabledBuildersFor(pack, all: all);
  if (enabled.isEmpty) {
    throw ArgumentError('至少需要一个打包格式');
  }
  if (preferred != null) {
    for (final PackageBuilder builder in enabled) {
      if (builder.id == preferred.id) {
        return builder;
      }
    }
  }
  return enabled.first;
}
