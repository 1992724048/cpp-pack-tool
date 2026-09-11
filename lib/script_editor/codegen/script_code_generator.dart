import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/script_editor/script_diagnostic.dart';

class ScriptCompileResult {
  const ScriptCompileResult({required this.code, required this.diagnostics});

  /// 成功时为以 U+FEFF 开头的完整脚本文本；编译错误时为 null。
  final String? code;
  final List<ScriptDiagnostic> diagnostics;

  bool get hasErrors =>
      diagnostics.any((ScriptDiagnostic diagnostic) => diagnostic.isError);
}

abstract interface class ScriptCodeGenerator {
  String get fileExtension;

  ScriptCompileResult compile(
    ScriptProjectModel project, {
    required String packName,
  });
}
