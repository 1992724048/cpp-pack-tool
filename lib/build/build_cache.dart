import 'dart:io';

import 'package:cpp_nuget_pack/config/pack_store.dart';
import 'package:cpp_nuget_pack/util/format.dart';

/// 包构建缓存目录（`<cacheRoot>/build/<清洗包ID>`），与构建流水线同口径。
///
/// [cacheRoot] 以绝对路径解析，保证同一工作目录下缓存稳定命中
/// （与 `build_runner.dart` 的源码缓存路径完全一致）。
Directory packBuildCacheDirectory(
  String packName, {
  String cacheRoot = 'cache',
}) {
  return Directory(
    joinPath(
      Directory(cacheRoot).absolute.path,
      'build/${PackStore.sanitizeFileName(packName)}',
    ),
  );
}

/// 包是否已有构建缓存目录（不存在视为无缓存）。
Future<bool> hasPackBuildCache(String packName, {String cacheRoot = 'cache'}) {
  return packBuildCacheDirectory(packName, cacheRoot: cacheRoot).exists();
}

/// 删除包构建缓存目录；不存在视为成功，删除失败抛出（由调用方转换提示）。
Future<void> deletePackBuildCache(
  String packName, {
  String cacheRoot = 'cache',
}) async {
  final Directory directory = packBuildCacheDirectory(
    packName,
    cacheRoot: cacheRoot,
  );
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}
