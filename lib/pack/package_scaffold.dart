import 'dart:io';

import 'package:cpp_nuget_pack/shared/format.dart';

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

/// 模板文件内容，键为文件名、值为落盘内容，顺序即落盘顺序。UI 的落盘预览共用此表，
/// 避免「界面预告的文件」与「实际落盘的文件」两处漂移。
const Map<String, String> scaffoldTemplates = <String, String>{
  'build.py': _recipeTemplate,
  'pre.bat': _preBatchTemplate,
  'post.bat': _postBatchTemplate,
};

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
      final Directory directory = Directory(joinPath(rootPath, relative));
      if (directory.existsSync()) {
        continue;
      }

      await directory.create(recursive: true);
      createdDirectories.add(relative);
    }

    for (final MapEntry<String, String> template in scaffoldTemplates.entries) {
      await _writeIfAbsent(rootPath, template.key, template.value, createdFiles, skippedFiles);
    }
  } on FileSystemException catch (error) {
    // 插值整个异常而非 [FileSystemException.message]：后者恒为英文通用文案
    // （「Cannot open file」），丢掉失败路径与本地化 OS 原因，而本条消息要
    // 经 toast 直接面向用户。口径同 build_environment.dart / build_runner.dart。
    throw PackageScaffoldException('无法创建包结构：$error');
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
  final File file = File(joinPath(rootPath, name));
  if (file.existsSync()) {
    skippedFiles.add(name);
    return;
  }

  await file.writeAsString(content, flush: true);
  createdFiles.add(name);
}

/// 落盘前预演。只回答「哪些会被创建、哪些既有文件会被跳过」，不写盘 ——
/// 真正的结果以 [createPackageStructure] 的返回为准。
class ScaffoldPreview {
  const ScaffoldPreview({required this.existingEntryCount, required this.existingFiles});

  /// 目标目录已存在的条目数（文件与子目录合计）。大于 0 即触发落盘前确认。
  final int existingEntryCount;

  /// 模板文件中已存在的，将被跳过而非覆盖。顺序同 [scaffoldTemplates]。
  final List<String> existingFiles;

  bool get requiresConfirmation => existingEntryCount > 0;
}

ScaffoldPreview previewPackageStructure(String rootPath) {
  final Directory root = Directory(rootPath);
  int existingEntryCount = 0;
  // existsSync 对权限不足等错误返回 false 而不抛出，因此这里只需处理「目录确实存在
  // 但列不出来」：按无需确认降级，后续写盘失败会经 PackageScaffoldException 提示。
  if (root.existsSync()) {
    try {
      existingEntryCount = root.listSync().length;
    } on FileSystemException {
      existingEntryCount = 0;
    }
  }

  return ScaffoldPreview(
    existingEntryCount: existingEntryCount,
    existingFiles: <String>[
      for (final String name in scaffoldTemplates.keys)
        if (File(joinPath(rootPath, name)).existsSync()) name,
    ],
  );
}
