class ScriptDiagnostic {
  const ScriptDiagnostic({
    required this.message,
    this.nodeId,
    required this.isError,
  });

  final String message;
  final String? nodeId;
  final bool isError;

  @override
  String toString() {
    final String level = isError ? '错误' : '警告';
    final String target = nodeId == null ? '' : '（节点 $nodeId）';
    return '$level$target：$message';
  }
}
