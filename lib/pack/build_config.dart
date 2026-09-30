import 'dart:ui' show Color;

import 'package:cpp_nuget_pack/pack/model/build_model.dart';
import 'package:cpp_nuget_pack/shared/colors.dart';

const String allBuildLabel = 'ALL';
// 这两个常量同时充当写进 .targets 的 MSBuild 条件字面量，故取值须与 MSBuild 认识
// 的配置名逐字一致；运行时二进制的 release 组另有「非 Debug」兜底条件，不直接用本常量。
const String releaseBuildLabel = 'Release';
const String debugBuildLabel = 'Debug';

String buildModelLabel(BuildModel buildModel) {
  return switch (buildModel) {
    BuildModel.all => allBuildLabel,
    BuildModel.release => releaseBuildLabel,
    BuildModel.debug => debugBuildLabel,
  };
}

Color buildModelColor(BuildModel buildModel) => switch (buildModel) {
  BuildModel.all => MarkerColors.blue,
  BuildModel.release => MarkerColors.green,
  BuildModel.debug => MarkerColors.orange,
};
