import 'dart:ui' show Color;

import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/util/colors.dart';

const String allBuildLabel = 'ALL';
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

String scriptTriggerLabel(ScriptTrigger trigger) => trigger == ScriptTrigger.pre ? '编译前' : '编译后';

Color scriptTriggerColor(ScriptTrigger trigger) =>
    trigger == ScriptTrigger.pre ? MarkerColors.cyan : MarkerColors.purple;
