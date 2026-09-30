import 'package:cpp_nuget_pack/pack/model/file_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileModel 文件类型识别', () {
    test('头文件 .h/.hpp 映射为 header', () {
      expect(FileModel(name: 'widget.h', path: '').type, FileType.header);
      expect(FileModel(name: 'widget.hpp', path: '').type, FileType.header);
    });

    test('头文件后缀变体 .hh/.hxx/.h++/.inl/.ipp/.tcc 映射为 header', () {
      for (final extension in ['hh', 'hxx', 'h++', 'inl', 'ipp', 'tcc']) {
        expect(
          FileModel(name: 'widget.$extension', path: '').type,
          FileType.header,
        );
      }
    });

    test('源文件 .c/.cpp 映射为 source', () {
      expect(FileModel(name: 'main.c', path: '').type, FileType.source);
      expect(FileModel(name: 'main.cpp', path: '').type, FileType.source);
    });

    test('源文件后缀变体 .cc/.cxx/.c++ 映射为 source', () {
      for (final extension in ['cc', 'cxx', 'c++']) {
        expect(
          FileModel(name: 'unit.$extension', path: '').type,
          FileType.source,
        );
      }
    });

    test('C++20 模块接口单元扩展名映射为 module', () {
      for (final extension in [
        'ixx',
        'cppm',
        'ccm',
        'cxxm',
        'c++m',
        'mxx',
        'mpp',
      ]) {
        expect(
          FileModel(name: 'math.$extension', path: '').type,
          FileType.module,
        );
      }
    });

    test('模块扩展名大小写不敏感', () {
      expect(FileModel(name: 'FOO.CPPM', path: '').type, FileType.module);
    });

    test('含 "+" 与多点的文件名解析出最后一段扩展名', () {
      expect(FileModel(name: 'foo.c++m', path: '').type, FileType.module);
      expect(FileModel(name: 'foo.c++m', path: '').extension, 'c++m');
      expect(FileModel(name: 'bar.cxxm', path: '').type, FileType.module);
      expect(FileModel(name: 'pkg.detail.ixx', path: '').type, FileType.module);
    });

    test('资源文件 .rc 映射为 resource', () {
      expect(FileModel(name: 'app.rc', path: '').type, FileType.resource);
    });

    test('库文件 .lib/.dll 映射为 lib 与 dll', () {
      expect(FileModel(name: 'mylib.lib', path: '').type, FileType.lib);
      expect(FileModel(name: 'mylib.dll', path: '').type, FileType.dll);
    });

    test('.a 作为通用归档映射为 lib 类型', () {
      expect(FileModel(name: 'libz.a', path: '').type, FileType.lib);
      expect(FileModel(name: 'libz.dll.a', path: '').type, FileType.lib);
      expect(FileModel(name: 'LIBZ.A', path: '').type, FileType.lib);
    });

    test('PDB 调试符号映射为 pdb', () {
      expect(FileModel(name: 'app.pdb', path: '').type, FileType.pdb);
    });

    test('汇编扩展名映射为 asm', () {
      for (final extension in ['asm', 's', 'nasm']) {
        expect(FileModel(name: 'boot.$extension', path: '').type, FileType.asm);
      }
    });

    test('Fortran 扩展名映射为 fortran', () {
      for (final extension in ['f', 'for', 'f77', 'f90', 'f95', 'f03', 'f08']) {
        expect(
          FileModel(name: 'solver.$extension', path: '').type,
          FileType.fortran,
        );
      }
    });

    test('脚本扩展名映射为 script', () {
      for (final extension in ['bat', 'cmd', 'ps1', 'vbs']) {
        expect(
          FileModel(name: 'run.$extension', path: '').type,
          FileType.script,
        );
      }
    });

    test('LLVM 扩展名映射为 llvm', () {
      expect(FileModel(name: 'module.ll', path: '').type, FileType.llvm);
      expect(FileModel(name: 'module.bc', path: '').type, FileType.llvm);
    });

    test('Python 扩展名映射为 python', () {
      for (final extension in ['py', 'pyw', 'pyi']) {
        expect(
          FileModel(name: 'tool.$extension', path: '').type,
          FileType.python,
        );
      }
    });

    test('数据库扩展名映射为 database', () {
      expect(FileModel(name: 'data.db', path: '').type, FileType.database);
    });

    test('可执行文件 .exe 映射为 executable', () {
      expect(FileModel(name: 'tool.exe', path: '').type, FileType.executable);
      expect(FileModel(name: 'FOO.EXE', path: '').type, FileType.executable);
    });

    test('新类型扩展名大小写不敏感', () {
      expect(FileModel(name: 'FOO.PY', path: '').type, FileType.python);
      expect(FileModel(name: 'APP.PDB', path: '').type, FileType.pdb);
      expect(FileModel(name: 'SOLVER.F90', path: '').type, FileType.fortran);
      expect(FileModel(name: 'MODULE.LL', path: '').type, FileType.llvm);
      expect(FileModel(name: 'DATA.DB', path: '').type, FileType.database);
    });

    test('未知扩展名或无扩展名映射为 other', () {
      expect(FileModel(name: 'readme.md', path: '').type, FileType.other);
      expect(FileModel(name: 'LICENSE', path: '').type, FileType.other);
      expect(FileModel(name: 'trailing.', path: '').type, FileType.other);
    });

    test('扩展名大小写不敏感', () {
      expect(FileModel(name: 'FOO.H', path: '').type, FileType.header);
      expect(FileModel(name: 'BAR.CPP', path: '').type, FileType.source);
      expect(FileModel(name: 'Baz.DLL', path: '').extension, 'dll');
    });
  });

  group('isBinaryFileType', () {
    // 逐一锁定规格 §6.4 表中的 31 个二进制扩展名：从其中任意一个删掉条目，
    // 本用例必红。FileType 走 FileModel 由文件名推导而非写死，断言的是
    // 「扩展名映射 + 二进制判定」的组合结果 —— 这才是打包时实际走的路径。
    test('规格 §6.4 表中的 31 个二进制扩展名全部判为二进制', () {
      const List<String> binaryExtensions = <String>[
        'ico', 'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'tiff', 'cur',
        'zip', '7z', 'rar', 'tar', 'gz', 'bz2', 'xz',
        'ttf', 'otf', 'woff', 'woff2',
        'onnx', 'pt', 'pth', 'safetensors', 'npy',
        'bin', 'dat', 'ilk', 'dbg', 'idb', 'obj',
      ];
      for (final String extension in binaryExtensions) {
        final FileModel model = FileModel(name: 'fixture.$extension', path: 'assets/fixture.$extension');

        expect(isBinaryFileType(model.type, model.extension), isTrue, reason: '.$extension');
      }
    });

    // 规格 §6.4「效果」句点名的三者各留一条具名锚点，回归时能直接指回该句。
    test('规格 §6.4「效果」点名的 .png / .zip / .ico 判为二进制', () {
      final FileModel png = FileModel(name: 'logo.png', path: '');
      final FileModel zip = FileModel(name: 'bundle.zip', path: '');
      final FileModel ico = FileModel(name: 'app.ico', path: '');

      expect(isBinaryFileType(png.type, png.extension), isTrue, reason: 'logo.png');
      expect(isBinaryFileType(zip.type, zip.extension), isTrue, reason: 'bundle.zip');
      expect(isBinaryFileType(ico.type, ico.extension), isTrue, reason: 'app.ico');
    });
  });
}
