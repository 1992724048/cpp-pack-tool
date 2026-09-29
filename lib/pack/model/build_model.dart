enum BuildModel {
  all,
  release,
  debug;

  static BuildModel fromName(Object? name) {
    if (name == null) {
      return BuildModel.all;
    }
    if (name is! String) {
      throw const FormatException('buildModel 字段类型错误，应为字符串');
    }
    for (final BuildModel buildModel in BuildModel.values) {
      if (buildModel.name == name) {
        return buildModel;
      }
    }
    throw FormatException('buildModel 字段值非法：$name');
  }
}
