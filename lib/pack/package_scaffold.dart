import 'dart:io';

/// 脚手架创建的产物目录。首段 `lib`/`bin` 会被 `package_plan.dart` 的
/// `_withoutLeadingLibOrBin` 剥除；`Debug`/`Release` 段被 `nuget_builder.dart` 的
/// `libraryBuildModelOf` 识别为配置段（大小写不敏感、多段取最后一个）。
const List<String> scaffoldDirectories = <String>[
  'lib/x64/Debug',
  'lib/x64/Release',
  'bin/x64/Debug',
  'bin/x64/Release',
];

const String _recipeTemplate = '''"""配方脚本：把产物组装成包内容。

构建时本脚本以包源目录为工作目录执行，可用环境变量：
  CNP_PACKAGE_ROOT  包源目录，产物写这里
  CNP_SRC_DIR       源码区（.cache/src，跨构建保留）
  CNP_TMP_DIR       中间产物区（.cache/tmp，每次构建前清空）
  CNP_TOOLS_DIR     共享工具目录
  CNP_COMPILER      选中的编译器可执行文件路径

约定：正常结束（退出码 0）即成功；抛异常或 exit(非 0) 会中断打包。
注意：产物不要落在点开头、build、out 命名的目录里，否则不会进包。

示例：
import os, shutil
root = os.environ['CNP_PACKAGE_ROOT']
os.makedirs(os.path.join(root, 'include'), exist_ok=True)
shutil.copyfile(os.environ['CNP_SRC_DIR'] + '/demo.h', os.path.join(root, 'include', 'demo.h'))
"""
''';

// 批处理模板用原始字符串：`$(MSBuildThisFileDirectory)` 的 `$(` 在普通字符串里
// 会被 Dart 当作插值起始，直接编译失败。
const String _preBatchTemplate = r'''@echo off
rem 消费者工程的编译前钩子。%1 = 目标文件路径。
rem 由包内 build/native/<包ID>.targets 的 CnpPreBuild_* 目标调用。
rem 可用 $(MSBuildThisFileDirectory) 定位包内载荷。
''';

const String _postBatchTemplate = r'''@echo off
rem 消费者工程的编译后钩子。%1 = 目标文件路径。
rem 由包内 build/native/<包ID>.targets 的 CnpPostBuild_* 目标调用。
rem 可用 $(MSBuildThisFileDirectory) 定位包内载荷。
''';

/// 脚手架落盘汇总。已存在的文件与目录不计入 created*，避免用户把「补齐缺失项」
/// 误读成「重建了整棵树」。
class ScaffoldOutcome {
  const ScaffoldOutcome({
    required this.createdDirectories,
    required this.createdFiles,
    required this.skippedFiles,
  });

  /// 相对包源根、以 `/` 分隔；包源根本身由本次创建时记为 `.`。
  final List<String> createdDirectories;
  final List<String> createdFiles;
  final List<String> skippedFiles;
}

class PackageScaffoldException implements Exception {
  const PackageScaffoldException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 在 [rootPath]（不存在则连父目录一并创建）铺出脚手架结构。已存在的文件绝不覆盖，
/// 只记入 [ScaffoldOutcome.skippedFiles] —— 用户可安全重复运行补齐缺失项。
/// 中途写盘失败不回滚已写内容：未覆盖任何既有文件，重跑即可收敛。
Future<ScaffoldOutcome> createPackageStructure(String rootPath) async {
  final List<String> createdDirectories = <String>[];
  final List<String> createdFiles = <String>[];
  final List<String> skippedFiles = <String>[];

  try {
    final Directory root = Directory(rootPath);
    if (!root.existsSync()) {
      await root.create(recursive: true);
      createdDirectories.add('.');
    }

    for (final String relative in scaffoldDirectories) {
      final Directory directory = Directory('$rootPath/$relative');
      if (directory.existsSync()) {
        continue;
      }

      await directory.create(recursive: true);
      createdDirectories.add(relative);
    }

    await _writeIfAbsent(rootPath, 'build.py', _recipeTemplate, createdFiles, skippedFiles);
    await _writeIfAbsent(rootPath, 'pre.bat', _preBatchTemplate, createdFiles, skippedFiles);
    await _writeIfAbsent(rootPath, 'post.bat', _postBatchTemplate, createdFiles, skippedFiles);
  } on FileSystemException catch (error) {
    throw PackageScaffoldException('无法创建包结构：${error.message}');
  }

  return ScaffoldOutcome(
    createdDirectories: createdDirectories,
    createdFiles: createdFiles,
    skippedFiles: skippedFiles,
  );
}

/// 已存在则跳过并记名。存在性判定用 [File.existsSync]：路径被同名目录占位时它返回
/// false，冲突会穿透到写入并作为 [PackageScaffoldException] 上报，而不是伪装成「已存在」。
Future<void> _writeIfAbsent(
  String rootPath,
  String name,
  String content,
  List<String> createdFiles,
  List<String> skippedFiles,
) async {
  final File file = File('$rootPath/$name');
  if (file.existsSync()) {
    skippedFiles.add(name);
    return;
  }

  await file.writeAsString(content, flush: true);
  createdFiles.add(name);
}
