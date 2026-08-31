import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:cpp_nuget_pack/services/scanner.dart';
import 'package:cpp_nuget_pack/services/path_utils.dart';

void main() {
  test('replicate config tags issue', () {
    final tempRoot = Directory.systemTemp.createTempSync('replicate_bug_');
    final sourceDir = Directory(joinPath([tempRoot.path, 'libsrc']))..createSync(recursive: true);

    File makeFile(String rel) {
      final file = File(joinPath([sourceDir.path, ...rel.split('/')]))..createSync(recursive: true);
      file.writeAsStringSync('x');
      return file;
    }

    // Create two libs in Debug and Release
    makeFile('lib/x64/Debug/mylib.lib');
    makeFile('lib/x64/Release/mylib.lib');
    makeFile('bin/x64/Debug/mylib.dll');
    makeFile('bin/x64/Release/mylib.dll');

    final result = scanSourceDir(sourceDir.path);

    debugPrint('Suggested mappings:');
    for (final m in result.suggestedMappings) {
      debugPrint('${m.srcGlob} -> ${m.target}  platforms=${m.platforms} configs=${m.configurations} fileKind=${m.fileKind}');
    }

    // Cleanup
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {}
  });
}
