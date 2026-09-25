/// 编译器 Profile 的结构版本；读回时版本不符即回退本版本并产生警告。
const int compilerProfileVersion = 1;

/// 旧运行库选项在 `PackModel.buildOptions` 中的保留键（值域 `MD` / `MT`）。
///
/// Profile 引入前的运行库选择入口，仅供读侧懒迁移识别：包未记录
/// `compilerProfile` 时由 [compilerRuntimeChoiceFromLegacy] 派生有效 Profile。
const String legacyRuntimeOptionName = 'runtime';

/// Profile 的两个构建配置分区。
enum CompilerProfileConfig { release, debug }

/// 运行库家族；`follow` = 跟随配方 `# runtime:` 声明（缺省 `md`）。
enum CompilerRuntimeChoice { follow, md, mt }

/// 指令集；`follow` = 跟随工具链默认。
enum CompilerInstructionSetChoice { follow, baseline, avx2 }

/// 优化级别；`follow` = 跟随构建脚本默认。
enum CompilerOptimizationChoice { follow, standard, maximum }

/// 链接时优化；`follow` = 跟随构建脚本默认。
///
/// YAML 口径为 `follow` / 布尔值（`true` 开启、`false` 关闭），见
/// [CompilerConfigProfile.toMap] 与 [CompilerConfigProfile.fromMap]。
enum CompilerIpoChoice { follow, on, off }

/// Profile 校验结果；[warnings] 为面向用户的可见提示（经包加载警告通道上报）。
class CompilerProfileValidation {
  const CompilerProfileValidation({
    required this.supportedVersion,
    required this.warnings,
  });

  final bool supportedVersion;
  final List<String> warnings;
}

/// 单个构建配置分区的编译选项；四字段全 `follow` 即完全交给构建脚本决定。
class CompilerConfigProfile {
  const CompilerConfigProfile({
    this.runtime = CompilerRuntimeChoice.follow,
    this.instructionSet = CompilerInstructionSetChoice.follow,
    this.optimization = CompilerOptimizationChoice.follow,
    this.ipo = CompilerIpoChoice.follow,
  });

  /// 容错解析：未知字段、非法值与类型错误均产生警告并回退 `follow`。
  factory CompilerConfigProfile.fromMap(
    Map<Object?, Object?> map, {
    List<String>? warnings,
    required String path,
  }) {
    const Set<String> knownKeys = <String>{
      'runtime',
      'instructionSet',
      'optimization',
      'ipo',
    };
    for (final Object? key in map.keys) {
      if (key is String && !knownKeys.contains(key)) {
        warnings?.add('compilerProfile.$path 含未知字段「$key」，已忽略');
      }
    }
    return CompilerConfigProfile(
      runtime: _enumFrom(
        map['runtime'],
        CompilerRuntimeChoice.values,
        CompilerRuntimeChoice.follow,
        warnings,
        '$path.runtime',
      ),
      instructionSet: _enumFrom(
        map['instructionSet'],
        CompilerInstructionSetChoice.values,
        CompilerInstructionSetChoice.follow,
        warnings,
        '$path.instructionSet',
      ),
      optimization: _enumFrom(
        map['optimization'],
        CompilerOptimizationChoice.values,
        CompilerOptimizationChoice.follow,
        warnings,
        '$path.optimization',
      ),
      ipo: _ipoFrom(map['ipo'], warnings, '$path.ipo'),
    );
  }

  final CompilerRuntimeChoice runtime;
  final CompilerInstructionSetChoice instructionSet;
  final CompilerOptimizationChoice optimization;
  final CompilerIpoChoice ipo;

  Map<String, Object?> toMap() => <String, Object?>{
    'runtime': runtime.name,
    'instructionSet': instructionSet.name,
    'optimization': optimization.name,
    'ipo': switch (ipo) {
      CompilerIpoChoice.follow => 'follow',
      CompilerIpoChoice.on => true,
      CompilerIpoChoice.off => false,
    },
  };

  CompilerConfigProfile copyWith({
    CompilerRuntimeChoice? runtime,
    CompilerInstructionSetChoice? instructionSet,
    CompilerOptimizationChoice? optimization,
    CompilerIpoChoice? ipo,
  }) => CompilerConfigProfile(
    runtime: runtime ?? this.runtime,
    instructionSet: instructionSet ?? this.instructionSet,
    optimization: optimization ?? this.optimization,
    ipo: ipo ?? this.ipo,
  );
}

/// 编译器 Profile：按 Release / Debug 两个分区记录编译选项。
class CompilerProfile {
  const CompilerProfile({
    this.version = compilerProfileVersion,
    this.release = const CompilerConfigProfile(),
    this.debug = const CompilerConfigProfile(),
  });

  /// 容错解析：非映射、版本不符与坏字段均产生警告并按 v1 全 `follow` 处理。
  factory CompilerProfile.fromMap(Object? value, {List<String>? warnings}) {
    if (value is! Map) {
      warnings?.add('compilerProfile 字段类型错误，已按 v1 全 follow 处理');
      return const CompilerProfile();
    }
    final Object? rawVersion = value['version'];
    if (rawVersion == null) {
      warnings?.add('compilerProfile.version 缺失，已按 v1 全 follow 处理');
    } else if (rawVersion is! int || rawVersion != compilerProfileVersion) {
      warnings?.add('compilerProfile.version=$rawVersion 不受支持，已按 v1 全 follow 处理');
    }
    for (final Object? key in value.keys) {
      if (key != 'version' && key != 'release' && key != 'debug') {
        warnings?.add('compilerProfile 含未知字段「$key」，已忽略');
      }
    }
    final Object? rawRelease = value['release'];
    final Object? rawDebug = value['debug'];
    if (rawRelease != null && rawRelease is! Map) {
      warnings?.add('compilerProfile.release 类型错误，已按全 follow 处理');
    }
    if (rawDebug != null && rawDebug is! Map) {
      warnings?.add('compilerProfile.debug 类型错误，已按全 follow 处理');
    }
    // 版本受支持才采用分区解析结果；否则照常解析以保留未知/非法字段告警，再丢弃取值。
    final bool versionSupported =
        rawVersion is int && rawVersion == compilerProfileVersion;
    final CompilerConfigProfile release = rawRelease is Map
        ? CompilerConfigProfile.fromMap(rawRelease, warnings: warnings, path: 'release')
        : const CompilerConfigProfile();
    final CompilerConfigProfile debug = rawDebug is Map
        ? CompilerConfigProfile.fromMap(rawDebug, warnings: warnings, path: 'debug')
        : const CompilerConfigProfile();
    return CompilerProfile(
      release: versionSupported ? release : const CompilerConfigProfile(),
      debug: versionSupported ? debug : const CompilerConfigProfile(),
    );
  }

  final int version;
  final CompilerConfigProfile release;
  final CompilerConfigProfile debug;

  Map<String, Object?> toMap() => <String, Object?>{
    'version': version,
    'release': release.toMap(),
    'debug': debug.toMap(),
  };

  CompilerProfile copyWith({
    int? version,
    CompilerConfigProfile? release,
    CompilerConfigProfile? debug,
  }) => CompilerProfile(
    version: version ?? this.version,
    release: release ?? this.release,
    debug: debug ?? this.debug,
  );

  CompilerConfigProfile configFor(CompilerProfileConfig config) =>
      config == CompilerProfileConfig.release ? release : debug;

  CompilerProfileValidation validate() => CompilerProfileValidation(
    supportedVersion: version == compilerProfileVersion,
    warnings: version == compilerProfileVersion
        ? const <String>[]
        : <String>['compilerProfile.version=$version 不受支持'],
  );
}

T _enumFrom<T extends Enum>(
  Object? value,
  List<T> allowed,
  T fallback,
  List<String>? warnings,
  String path,
) {
  if (value == null) {
    return fallback;
  }
  final String normalized = value is String ? value.trim().toLowerCase() : '';
  for (final T item in allowed) {
    if (item.name == normalized) {
      return item;
    }
  }
  warnings?.add('compilerProfile.$path 非法值「$value」，已按 ${fallback.name} 处理');
  return fallback;
}

/// IPO 三态解析：接受 `follow` / `on` / `off` 与 YAML 布尔值。
CompilerIpoChoice _ipoFrom(
  Object? value,
  List<String>? warnings,
  String path,
) {
  final String normalized = value is String ? value.trim().toLowerCase() : '';
  if (value == null || normalized == 'follow') {
    return CompilerIpoChoice.follow;
  }
  if (value is bool) {
    return value ? CompilerIpoChoice.on : CompilerIpoChoice.off;
  }
  if (normalized == 'on' || normalized == '1' || normalized == 'true') {
    return CompilerIpoChoice.on;
  }
  if (normalized == 'off' || normalized == '0' || normalized == 'false') {
    return CompilerIpoChoice.off;
  }
  warnings?.add('compilerProfile.$path 非法值「$value」，已按 follow 处理');
  return CompilerIpoChoice.follow;
}

/// 旧 `buildOptions.runtime` 值 → 运行库选择；未记录或非法返回 null（非法值产生警告）。
CompilerRuntimeChoice? compilerRuntimeChoiceFromLegacy(
  String? value, {
  List<String>? warnings,
}) {
  final String normalized = (value ?? '').trim().toLowerCase();
  if (normalized == 'md' || normalized == 'mt') {
    return normalized == 'md'
        ? CompilerRuntimeChoice.md
        : CompilerRuntimeChoice.mt;
  }
  if (value != null && value.trim().isNotEmpty) {
    warnings?.add(
      '旧 buildOptions.$legacyRuntimeOptionName 值「$value」非法，已按 follow 处理',
    );
  }
  return null;
}
