import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:cpp_nuget_pack/packaging/packaging_issues.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('包内路径重复问题', () {
    test('大小写不敏感命中的重复路径映射为「包内路径」问题', () {
      final PackagePlan plan = PackagePlan(
        entries: <PackageEntry>[
          PackageEntry(
            packagePath: 'build/native/files/a.h',
            source: const PackageFileSource(
              path: 'a.h',
              isBinary: false,
              size: 1,
            ),
          ),
          PackageEntry(
            packagePath: 'build/native/include/demo/foo.h',
            source: const PackageFileSource(
              path: 'foo.h',
              isBinary: false,
              size: 1,
            ),
          ),
          PackageEntry(
            packagePath: 'BUILD/NATIVE/FILES/A.H',
            source: const PackageFileSource(
              path: 'A.H',
              isBinary: false,
              size: 1,
            ),
          ),
        ],
      );

      final List<PackagingIssue> issues = collectDuplicatePathIssues(plan);

      expect(issues, hasLength(1));
      expect(issues.single.label, '包内路径');
      // 计划按大小写不敏感排序，BUILD... 在 build... 之前，报首次出现的原样路径
      expect(issues.single.message, '包内路径重复：BUILD/NATIVE/FILES/A.H');
    });

    test('无重复路径时返回空列表', () {
      final PackagePlan plan = PackagePlan(
        entries: <PackageEntry>[
          PackageEntry(
            packagePath: 'build/native/include/demo/foo.h',
            source: const PackageFileSource(
              path: 'foo.h',
              isBinary: false,
              size: 1,
            ),
          ),
          PackageEntry(
            packagePath: 'demo.nuspec',
            source: const PackageGeneratedSource(content: 'nuspec'),
          ),
        ],
      );

      expect(collectDuplicatePathIssues(plan), isEmpty);
    });
  });

  group('exe 警告', () {
    test('.exe 条目（大小写不敏感）逐条生成警告，label 为包内路径', () {
      final PackagePlan plan = PackagePlan(
        entries: <PackageEntry>[
          PackageEntry(
            packagePath: 'build/native/files/bin/tool.exe',
            source: const PackageFileSource(
              path: 'bin/tool.exe',
              isBinary: true,
              size: 10,
            ),
          ),
          PackageEntry(
            packagePath: 'FILES/Setup.EXE',
            source: const PackageFileSource(
              path: 'Setup.EXE',
              isBinary: true,
              size: 20,
            ),
          ),
          PackageEntry(
            packagePath: 'build/native/lib/demo.dll',
            source: const PackageFileSource(
              path: 'demo.dll',
              isBinary: true,
              size: 30,
            ),
          ),
        ],
      );

      final List<PackagingIssue> warnings = collectExecutableWarnings(plan);

      expect(warnings, hasLength(2));
      // PackagePlan 按路径大小写不敏感排序，build/... 在 FILES/... 之前
      expect(warnings[0].label, 'build/native/files/bin/tool.exe');
      expect(warnings[0].message, '可执行二进制随包分发');
      expect(warnings[1].label, 'FILES/Setup.EXE');
      expect(warnings[1].message, '可执行二进制随包分发');
    });

    test('无 .exe 条目时返回空列表', () {
      final PackagePlan plan = PackagePlan(
        entries: <PackageEntry>[
          PackageEntry(
            packagePath: 'build/native/include/demo/foo.h',
            source: const PackageFileSource(
              path: 'foo.h',
              isBinary: false,
              size: 1,
            ),
          ),
          PackageEntry(
            packagePath: 'build/native/files/bin/tool.bat',
            source: const PackageFileSource(
              path: 'bin/tool.bat',
              isBinary: false,
              size: 1,
            ),
          ),
        ],
      );

      expect(collectExecutableWarnings(plan), isEmpty);
    });
  });
}
