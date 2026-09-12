import 'dart:ui' show Color;

import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/util/colors.dart';

final RegExp _pathSeparator = RegExp(r'[/\\]');

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

/// 构建标签着色（视觉规范 §2.2）：ALL 蓝 / Release 绿 / Debug 橙。
Color buildModelColor(BuildModel buildModel) => switch (buildModel) {
  BuildModel.all => UCColors.flavor.blue,
  BuildModel.release => UCColors.flavor.green,
  BuildModel.debug => UCColors.flavor.peach,
};

/// 触发时机标签（视觉规范 §2.2）。
String scriptTriggerLabel(ScriptTrigger trigger) =>
    trigger == ScriptTrigger.pre ? '编译前' : '编译后';

/// 触发时机着色（视觉规范 §2.2）：编译前 sky / 编译后 lavender。
Color scriptTriggerColor(ScriptTrigger trigger) => trigger == ScriptTrigger.pre
    ? UCColors.flavor.sky
    : UCColors.flavor.lavender;

/// 从文件相对路径推断构建配置标签。
///
/// 按 [/\\] 切分路径段，段名（忽略大小写）等于 `release`/`debug` 时命中；
/// 两者同时出现时取路径中更靠后（更接近文件）的匹配段；均无则返回 null。
/// 与构建产物分层布局（`release/lib`、`release/bin`、`debug/lib`、
/// `debug/bin`）口径一致，打包侧据此生成按配置条件的库引用。
String? inferBuildLabel(String path) {
  String? label;
  for (final String segment in path.split(_pathSeparator)) {
    final String lower = segment.toLowerCase();
    if (lower == 'release') {
      label = releaseBuildLabel;
    } else if (lower == 'debug') {
      label = debugBuildLabel;
    }
  }
  return label;
}
