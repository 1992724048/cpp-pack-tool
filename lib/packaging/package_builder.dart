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
