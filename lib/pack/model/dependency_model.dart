class DependencyModel {
  const DependencyModel({
    required this.name,
    required this.version,
    this.system = false,
  });

  final String name;
  final String version;
  final bool system;

  Map<String, Object?> toMap() => <String, Object?>{
    'name': name,
    'version': version,
    if (system) 'system': true,
  };

  factory DependencyModel.fromMap(Map<String, Object?> map) {
    final Object? name = map['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('依赖缺少 name 字段');
    }
    final Object? version = map['version'];
    if (version is! String || version.isEmpty) {
      throw const FormatException('依赖缺少 version 字段');
    }
    return DependencyModel(
      name: name,
      version: version,
      system: map['system'] == true,
    );
  }
}
