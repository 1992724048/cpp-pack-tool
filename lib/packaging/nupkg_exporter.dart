import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/nuget_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:cpp_nuget_pack/util/format.dart';

/// 打包结果：输出文件路径、包内条目总数与 .nupkg 字节数。
typedef PackageExportResult = ({
  String outputPath,
  int fileCount,
  int packageSize,
});

const String _contentTypesPath = '[Content_Types].xml';
const String _relationshipsPath = '_rels/.rels';
const String _corePropertiesPath =
    'package/services/metadata/core-properties/nuget.psmdcp';
const String _manifestRelationshipType =
    'http://schemas.microsoft.com/packaging/2010/07/manifest';
const String _corePropertiesRelationshipType =
    'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties';
const String _relationshipsContentType =
    'application/vnd.openxmlformats-package.relationships+xml';
const String _corePropertiesContentType =
    'application/vnd.openxmlformats-package.core-properties+xml';
const String _octetContentType = 'application/octet';
const String _corePropertiesNamespace =
    'http://schemas.openxmlformats.org/package/2006/metadata/core-properties';
const String _relationshipsNamespace =
    'http://schemas.openxmlformats.org/package/2006/relationships';
const int _opcFileCount = 3;

/// 将 [pack] 的打包计划导出为 NuGet 包（.nupkg），输出到 [outputDirectory]。
///
/// 包内条目顺序对齐官方包：`_rels/.rels` → nuspec → 负载 →
/// `[Content_Types].xml` → core-properties。源文件缺失或读取失败时抛出异常。
Future<PackageExportResult> exportNuGetPackage(
  PackModel pack,
  String outputDirectory,
) async {
  final String? sourcePath = pack.sourcePath;
  if (sourcePath == null) {
    throw ArgumentError('该包缺少源目录信息，无法打包');
  }

  final PackagePlan plan = await const NuGetPackageBuilder().buildPlan(pack);
  final String nuspecPath = '${pack.name}.nuspec';
  final PackageEntry nuspecEntry = plan.entries.firstWhere(
    (PackageEntry entry) => entry.packagePath == nuspecPath,
    orElse: () => throw StateError('打包计划缺少 $nuspecPath'),
  );

  final Archive archive = Archive();
  archive.addFile(
    ArchiveFile.string(_relationshipsPath, _relationshipsContent(pack)),
  );
  _addEntry(archive, nuspecEntry, sourcePath);
  for (final PackageEntry entry in plan.entries) {
    if (entry.packagePath != nuspecPath) {
      _addEntry(archive, entry, sourcePath);
    }
  }
  archive.addFile(
    ArchiveFile.string(_contentTypesPath, _contentTypesContent(plan)),
  );
  archive.addFile(
    ArchiveFile.string(_corePropertiesPath, _corePropertiesContent(pack)),
  );

  final Uint8List bytes = ZipEncoder().encodeBytes(
    archive,
    level: DeflateLevel.defaultCompression,
  );
  Directory(outputDirectory).createSync(recursive: true);

  final String fileName =
      '${pack.name}.${NuGetPackageBuilder.normalizedVersion(pack.version)}.nupkg';
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
    fileCount: plan.fileCount + _opcFileCount,
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

String _relationshipsContent(PackModel pack) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln('<Relationships xmlns="$_relationshipsNamespace">')
    ..writeln(
      '  <Relationship Type="$_manifestRelationshipType" '
      'Target="/${_escapeXml(pack.name)}.nuspec" Id="R1" />',
    )
    ..writeln(
      '  <Relationship Type="$_corePropertiesRelationshipType" '
      'Target="/$_corePropertiesPath" Id="R2" />',
    );
  buffer.writeln('</Relationships>');
  return buffer.toString();
}

String _contentTypesContent(PackagePlan plan) {
  final Set<String> extensions = <String>{};
  final List<String> overrides = <String>[];
  for (final PackageEntry entry in plan.entries) {
    final String? extension = _extensionOf(entry.packagePath);
    if (extension == null) {
      overrides.add(entry.packagePath);
    } else {
      extensions.add(extension);
    }
  }
  final List<String> sortedExtensions = extensions.toList()..sort();
  overrides.sort(comparePackagePaths);

  final StringBuffer buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln(
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
    )
    ..writeln(
      '  <Default Extension="rels" ContentType="$_relationshipsContentType" />',
    )
    ..writeln(
      '  <Default Extension="psmdcp" ContentType="$_corePropertiesContentType" />',
    );
  for (final String extension in sortedExtensions) {
    buffer.writeln(
      '  <Default Extension="${_escapeXml(extension)}" '
      'ContentType="$_octetContentType" />',
    );
  }
  for (final String path in overrides) {
    buffer.writeln(
      '  <Override PartName="/${_escapeXml(path)}" '
      'ContentType="$_octetContentType" />',
    );
  }
  buffer.writeln('</Types>');
  return buffer.toString();
}

String _corePropertiesContent(PackModel pack) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln(
      '<coreProperties xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
      'xmlns="$_corePropertiesNamespace">',
    )
    ..writeln('  <dc:creator>${_escapeXml(pack.author)}</dc:creator>')
    ..writeln(
      '  <dc:description>${_escapeXml(pack.description ?? '')}</dc:description>',
    )
    ..writeln('  <dc:identifier>${_escapeXml(pack.name)}</dc:identifier>')
    ..writeln(
      '  <version>${_escapeXml(NuGetPackageBuilder.normalizedVersion(pack.version))}</version>',
    )
    ..writeln('  <keywords>native cpp</keywords>')
    ..writeln('  <lastModifiedBy>cpp_nuget_pack</lastModifiedBy>');
  buffer.writeln('</coreProperties>');
  return buffer.toString();
}

String? _extensionOf(String packagePath) {
  final String name = baseName(packagePath);
  final int separator = name.lastIndexOf('.');
  if (separator <= 0 || separator == name.length - 1) {
    return null;
  }
  return name.substring(separator + 1).toLowerCase();
}

String _escapeXml(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
