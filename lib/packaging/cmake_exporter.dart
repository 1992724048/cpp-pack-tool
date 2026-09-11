import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/cmake_builder.dart';
import 'package:cpp_nuget_pack/packaging/nuget_builder.dart';
import 'package:cpp_nuget_pack/packaging/nupkg_exporter.dart'
    show PackageExportResult;
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:cpp_nuget_pack/util/format.dart';

/// 将 [pack] 的 CMake 配置包导出为 .zip，输出到 [outputDirectory]。
///
/// 文件名为 `<包名>-<去 +build 版本>-cmake.zip`，包内条目来自
/// [CMakePackageBuilder.buildPlan]。源文件缺失或读取失败时抛出异常。
Future<PackageExportResult> exportCmakePackage(
  PackModel pack,
  String outputDirectory,
) async {
  final String? sourcePath = pack.sourcePath;
  if (sourcePath == null) {
    throw ArgumentError('该包缺少源目录信息，无法打包');
  }

  final PackagePlan plan = await const CMakePackageBuilder().buildPlan(pack);
  final Archive archive = Archive();
  for (final PackageEntry entry in plan.entries) {
    _addEntry(archive, entry, sourcePath);
  }

  final Uint8List bytes = ZipEncoder().encodeBytes(
    archive,
    level: DeflateLevel.defaultCompression,
  );
  Directory(outputDirectory).createSync(recursive: true);

  final String fileName =
      '${pack.name}-${NuGetPackageBuilder.normalizedVersion(pack.version)}-cmake.zip';
  final String outputPath = joinPath(outputDirectory, fileName);
  final File tempFile = File('$outputPath.tmp');
  tempFile.writeAsBytesSync(bytes);
  final File outputFile = File(outputPath);
  if (outputFile.existsSync()) {
    outputFile.deleteSync();
  }
  tempFile.renameSync(outputPath);

  return (
    outputPath: outputPath,
    fileCount: plan.fileCount,
    packageSize: bytes.length,
  );
}

void _addEntry(Archive archive, PackageEntry entry, String sourcePath) {
  switch (entry.source) {
    case PackageGeneratedSource(:final String content):
      archive.addFile(ArchiveFile.string(entry.packagePath, content));
    case PackageFileSource(:final String path):
      final Uint8List bytes = File(joinPath(sourcePath, path))
          .readAsBytesSync();
      archive.addFile(ArchiveFile.bytes(entry.packagePath, bytes));
  }
}
