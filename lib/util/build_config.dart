import 'package:cpp_nuget_pack/models/build_model.dart';

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

/// 从文件相对路径推断构建配置标签。
///
/// 按 [/\\] 切分路径段，段名（忽略大小写）等于 `release`/`debug` 时命中；
/// 两者同时出现时取路径中更靠后（更接近文件）的匹配段；均无则返回 null。
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
