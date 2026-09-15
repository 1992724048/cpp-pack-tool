import 'package:cpp_nuget_pack/models/build_model.dart';
import 'package:cpp_nuget_pack/models/script_project_model.dart';
import 'package:cpp_nuget_pack/util/build_config.dart';
import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:cpp_nuget_pack/util/licenses.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// 新建脚本项目的表单结果（视觉规范 §8.1）：名称 + 触发时机 + 构建标签。
typedef NewScriptProjectRequest = ({
  String name,
  ScriptTrigger trigger,
  BuildModel buildModel,
});

final RegExp _numberedNamePattern = RegExp(r'^脚本 (\d+)$');
final RegExp _numberedIdPattern = RegExp(r'^script_(\d+)$');

const String _emptyNameError = '名称不能为空';
const String _duplicateNameError = '名称已存在';

/// 下一个默认项目名「脚本 N」：扫描现有名称 `^脚本 (\d+)$` 取最大 N +1（§8.1）。
String nextScriptProjectName(List<ScriptProjectModel> existing) =>
    '脚本 ${_maxNumber(existing, _numberedNamePattern, (p) => p.name) + 1}';

/// 下一个脚本 id `script_<N>`：解析既有 `script_(\d+)` 取最大 N +1
/// （设计 spec §2.1「script_N 递增」）；不匹配的 id 忽略。
String nextScriptProjectId(List<ScriptProjectModel> existing) =>
    'script_${_maxNumber(existing, _numberedIdPattern, (p) => p.id) + 1}';

/// 扫描 [existing] 中匹配 [pattern] 的序号最大值；不匹配或超出整数范围时忽略。
int _maxNumber(
  List<ScriptProjectModel> existing,
  RegExp pattern,
  String Function(ScriptProjectModel project) valueOf,
) {
  int maxNumber = 0;
  for (final ScriptProjectModel project in existing) {
    final RegExpMatch? match = pattern.firstMatch(valueOf(project));
    if (match == null) {
      continue;
    }
    final int? number = int.tryParse(match.group(1)!);
    if (number != null && number > maxNumber) {
      maxNumber = number;
    }
  }
  return maxNumber;
}

/// 项目名校验（§8.1/§8.2）：空 → `名称不能为空`；大小写不敏感重名 → `名称已存在`。
///
/// [excludeId] 供重命名时排除自身；返回 null 表示合法。
String? scriptProjectNameError({
  required List<ScriptProjectModel> existing,
  required String name,
  String? excludeId,
}) {
  final String value = name.trim();
  if (value.isEmpty) {
    return _emptyNameError;
  }
  final String lower = value.toLowerCase();
  for (final ScriptProjectModel project in existing) {
    if (project.id != excludeId && project.name.toLowerCase() == lower) {
      return _duplicateNameError;
    }
  }
  return null;
}

/// 新建脚本项目对话框（§8.1）：名称必填且大小写不敏感唯一，
/// 触发时机与构建标签默认编译前/ALL；确认返回表单结果，取消返回 null。
Future<NewScriptProjectRequest?> showCreateScriptProjectDialog(
  BuildContext context, {
  required List<ScriptProjectModel> existing,
}) {
  return showDialog<NewScriptProjectRequest>(
    context: context,
    builder: (BuildContext dialogContext) =>
        _CreateScriptProjectDialog(existing: existing),
  );
}

/// 重命名脚本项目对话框（§8.2）：预填当前名称，校验同新建，
/// 与原值相同或非法时「确定」禁用；确认返回新名称（trim 后），取消返回 null。
Future<String?> showRenameScriptProjectDialog(
  BuildContext context, {
  required ScriptProjectModel project,
  required List<ScriptProjectModel> existing,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) =>
        _RenameScriptProjectDialog(project: project, existing: existing),
  );
}

/// 删除脚本项目确认对话框（§8.3）：确认返回 true，取消返回 false。
Future<bool> showDeleteScriptProjectDialog(
  BuildContext context, {
  required ScriptProjectModel project,
}) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => ContentDialog(
      key: const Key('deleteScriptProjectDialog'),
      title: const Text('删除脚本项目'),
      constraints: const BoxConstraints(maxWidth: 440),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('确定要删除脚本项目「${project.name}」吗？'),
          const SizedBox(height: 8),
          const Text('将移除其节点图，此操作不可恢复。'),
        ],
      ),
      actions: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            FilledButton(
              key: const Key('deleteScriptProjectConfirmButton'),
              style: ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(
                  AppColors.critical(FluentTheme.of(dialogContext).brightness),
                ),
                foregroundColor: const WidgetStatePropertyAll(Colors.white),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除'),
            ),
            Button(
              key: const Key('deleteScriptProjectCancelButton'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
          ],
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _CreateScriptProjectDialog extends StatefulWidget {
  const _CreateScriptProjectDialog({required this.existing});

  final List<ScriptProjectModel> existing;

  @override
  State<_CreateScriptProjectDialog> createState() =>
      _CreateScriptProjectDialogState();
}

class _CreateScriptProjectDialogState
    extends State<_CreateScriptProjectDialog> {
  late final TextEditingController _name = TextEditingController(
    text: nextScriptProjectName(widget.existing),
  );
  ScriptTrigger _trigger = ScriptTrigger.pre;
  BuildModel _buildModel = BuildModel.all;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? get _nameError =>
      scriptProjectNameError(existing: widget.existing, name: _name.text);

  void _submit() {
    Navigator.pop(context, (
      name: _name.text.trim(),
      trigger: _trigger,
      buildModel: _buildModel,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ContentDialog(
      key: const Key('createScriptProjectDialog'),
      title: const Text('新建脚本项目'),
      constraints: const BoxConstraints(maxWidth: 440),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildNameField(),
          const SizedBox(height: 12),
          _buildField(
            '触发时机',
            _denseComboBox(
              context,
              ComboBox<ScriptTrigger>(
                key: const Key('createScriptProjectTriggerField'),
                value: _trigger,
                isExpanded: true,
                items: <ComboBoxItem<ScriptTrigger>>[
                  ComboBoxItem<ScriptTrigger>(
                    value: ScriptTrigger.pre,
                    child: const Text('编译前'),
                  ),
                  ComboBoxItem<ScriptTrigger>(
                    value: ScriptTrigger.post,
                    child: const Text('编译后'),
                  ),
                ],
                onChanged: (ScriptTrigger? next) {
                  if (next != null) {
                    setState(() => _trigger = next);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildField(
            '构建标签',
            _denseComboBox(
              context,
              ComboBox<BuildModel>(
                key: const Key('createScriptProjectBuildModelField'),
                value: _buildModel,
                isExpanded: true,
                items: <ComboBoxItem<BuildModel>>[
                  for (final BuildModel buildModel in BuildModel.values)
                    ComboBoxItem<BuildModel>(
                      value: buildModel,
                      child: Text(buildModelLabel(buildModel)),
                    ),
                ],
                onChanged: (BuildModel? next) {
                  if (next != null) {
                    setState(() => _buildModel = next);
                  }
                },
              ),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        Button(
          key: const Key('createScriptProjectCancelButton'),
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('createScriptProjectConfirmButton'),
          onPressed: _nameError == null ? _submit : null,
          child: const Text('创建'),
        ),
      ],
    );
  }

  Widget _buildNameField() {
    final String? error = _nameError;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _fieldLabel(FluentTheme.of(context), '名称'),
        const SizedBox(height: 4),
        TextBox(
          key: const Key('createScriptProjectNameField'),
          controller: _name,
          autofocus: true,
          onChanged: (String value) => setState(() {}),
        ),
        if (error != null) ...<Widget>[
          const SizedBox(height: 4),
          _buildFieldError(
            FluentTheme.of(context),
            const Key('createScriptProjectNameError'),
            error,
          ),
        ],
      ],
    );
  }

  Widget _buildField(String label, Widget control) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _fieldLabel(FluentTheme.of(context), label),
        const SizedBox(height: 4),
        control,
      ],
    );
  }
}

class _RenameScriptProjectDialog extends StatefulWidget {
  const _RenameScriptProjectDialog({
    required this.project,
    required this.existing,
  });

  final ScriptProjectModel project;
  final List<ScriptProjectModel> existing;

  @override
  State<_RenameScriptProjectDialog> createState() =>
      _RenameScriptProjectDialogState();
}

class _RenameScriptProjectDialogState
    extends State<_RenameScriptProjectDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.project.name,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? get _nameError => scriptProjectNameError(
    existing: widget.existing,
    name: _name.text,
    excludeId: widget.project.id,
  );

  bool get _unchanged => _name.text.trim() == widget.project.name;

  void _submit() {
    Navigator.pop(context, _name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final String? error = _nameError;
    return ContentDialog(
      key: const Key('renameScriptProjectDialog'),
      title: const Text('重命名脚本项目'),
      constraints: const BoxConstraints(maxWidth: 440),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _fieldLabel(FluentTheme.of(context), '名称'),
          const SizedBox(height: 4),
          TextBox(
            key: const Key('renameScriptProjectNameField'),
            controller: _name,
            autofocus: true,
            onChanged: (String value) => setState(() {}),
          ),
          if (error != null) ...<Widget>[
            const SizedBox(height: 4),
            _buildFieldError(
              FluentTheme.of(context),
              const Key('renameScriptProjectNameError'),
              error,
            ),
          ],
        ],
      ),
      actions: <Widget>[
        Button(
          key: const Key('renameScriptProjectCancelButton'),
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('renameScriptProjectConfirmButton'),
          onPressed: error == null && !_unchanged ? _submit : null,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

Widget _fieldLabel(FluentThemeData theme, String label) => Text(
  label,
  style: TextStyle(
    fontSize: 12,
    color: theme.resources.textFillColorSecondary,
  ),
);

Widget _buildFieldError(FluentThemeData theme, Key key, String message) {
  final Color color = AppColors.critical(theme.brightness);
  return Row(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Icon(FluentIcons.error_badge, size: 12, color: color),
      const SizedBox(width: 4),
      Expanded(
        child: Text(message, style: TextStyle(fontSize: 12, color: color)),
      ),
    ],
  );
}

Widget _denseComboBox(BuildContext context, Widget child) {
  return FluentTheme(
    data: FluentTheme.of(context).copyWith(visualDensity: comboBoxDensity),
    child: child,
  );
}
