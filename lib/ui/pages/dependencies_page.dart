/// 依赖管理 Tab：包依赖（id + version）列表、添加/删除。
///
/// 「添加依赖」对话框上方列出现有包（来自输出目录注册表 [loadRegistry]），
/// 点选一条可回填 id/version，也可手动输入。同 id 已存在时更新其版本。
/// 依赖在生成 nuspec 时输出为 `<dependencies>` 段（见 `nuspec_generator`）。
library;

import 'package:flutter/material.dart';

import '../../models/pack_project.dart';
import '../../services/package_registry.dart';
import '../tokens.dart';
import '../widgets/form_fields.dart';

/// 依赖管理页。
class DependenciesPage extends StatefulWidget {
  const DependenciesPage({
    super.key,
    required this.project,
    required this.onChanged,
    required this.outputDir,
  });

  /// 当前项目；为 null 时显示占位。
  final PackProject? project;

  final ValueChanged<PackProject> onChanged;

  /// 输出目录（用于加载注册表已有包作为快捷候选；为空则不展示候选）。
  final String outputDir;

  @override
  State<DependenciesPage> createState() => _DependenciesPageState();
}

class _DependenciesPageState extends State<DependenciesPage> {
  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    if (project == null) {
      return const _DependenciesPlaceholder();
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (project.dependencies.isEmpty)
            _emptyState()
          else
            _dependencyList(project),
          const SizedBox(height: AppSpacing.s2),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSemantic,
                minimumSize: Size(67, 35),
              ),
              onPressed: () => _addDependency(project),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加依赖'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link_off, size: 36, color: AppColors.textDisabled),
          SizedBox(height: AppSpacing.s2),
          Text(
            '尚无依赖',
            style: TextStyle(
              color: AppColors.textSemantic,
              fontSize: AppFontSizes.body,
            ),
          ),
          SizedBox(height: AppSpacing.s1),
          Text(
            '点击「添加依赖」或从输出目录中的包选择',
            style: TextStyle(
              color: AppColors.textDisabled,
              fontSize: AppFontSizes.small,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dependencyList(PackProject project) {
    return Column(
      children: [
        _header(),
        for (var i = 0; i < project.dependencies.length; i++)
          _dependencyRow(project, i),
      ],
    );
  }

  Widget _header() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      color: AppColors.bgSurface,
      child: const Row(
        children: [
          Expanded(
            child: Text(
              '依赖包 ID',
              style: TextStyle(
                color: AppColors.textSemantic,
                fontSize: AppFontSizes.small,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '版本',
              style: TextStyle(
                color: AppColors.textSemantic,
                fontSize: AppFontSizes.small,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: 88),
        ],
      ),
    );
  }

  Widget _dependencyRow(PackProject project, int index) {
    final dep = project.dependencies[index];
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              dep.id,
              style: monoTextStyle(),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              dep.version.isEmpty ? '不限' : dep.version,
              style: monoTextStyle(),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 88,
            child: IconButton(
              onPressed: () => _removeDependency(project, index),
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline, size: 16),
              iconSize: 16,
              color: AppColors.error,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addDependency(PackProject project) async {
    final dep = await showDialog<PackDependency>(
      context: context,
      builder: (_) => _AddDependencyDialog(
        outputDir: widget.outputDir,
        excludedPackageId: project.packageId,
      ),
    );
    if (dep == null || dep.id.trim().isEmpty || !mounted) return;
    widget.onChanged(_upsertDependency(project, dep));
  }

  void _removeDependency(PackProject project, int index) {
    final next = List<PackDependency>.of(project.dependencies)..removeAt(index);
    widget.onChanged(project.copyWith(dependencies: next));
  }

  /// 按 id 追加或更新依赖（同 id 已存在时更新版本）。
  PackProject _upsertDependency(PackProject project, PackDependency dep) {
    final list = <PackDependency>[];
    var replaced = false;
    for (final existing in project.dependencies) {
      if (existing.id == dep.id) {
        list.add(dep);
        replaced = true;
      } else {
        list.add(existing);
      }
    }
    if (!replaced) list.add(dep);
    return project.copyWith(dependencies: list);
  }
}

/// 「添加依赖」对话框。
///
/// 上方为输出目录注册表中已有的包（点选回填 id/version），下方为手动 id/version
/// 输入。确认返回 [PackDependency]；取消或 id 为空返回 null。
class _AddDependencyDialog extends StatefulWidget {
  const _AddDependencyDialog({required this.outputDir, this.excludedPackageId});

  final String outputDir;

  /// 当前项目的 packageId；注册表候选列表中会排除它（大小写不敏感），
  /// 手动输入自身 id 时也会被拦截并提示（不能添加自身作为依赖）。
  final String? excludedPackageId;

  @override
  State<_AddDependencyDialog> createState() => _AddDependencyDialogState();
}

class _AddDependencyDialogState extends State<_AddDependencyDialog> {
  late final TextEditingController _id;
  late final TextEditingController _version;
  final List<RegisteredPackage> _packages = <RegisteredPackage>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    _id = TextEditingController();
    _version = TextEditingController();
    // loadRegistry 对空目录/缺失/损坏均容错（返回空 + 可选错误），不会抛出。
    // 排除当前项目自身（大小写不敏感），避免把自身添加为依赖。
    final excluded = widget.excludedPackageId?.trim().toLowerCase() ?? '';
    _packages.addAll(
      loadRegistry(widget.outputDir).packages
          .where((pkg) => pkg.project.packageId.toLowerCase() != excluded),
    );
  }

  @override
  void dispose() {
    _id.dispose();
    _version.dispose();
    super.dispose();
  }

  void _pickPackage(RegisteredPackage pkg) {
    setState(() {
      _id.text = pkg.project.packageId;
      _version.text = "[${pkg.project.version})";
      _error = null;
    });
  }

  void _confirm() {
    final id = _id.text.trim();
    if (id.isEmpty) {
      setState(() => _error = '依赖包 ID 不能为空');
      return;
    }
    final excluded = widget.excludedPackageId?.trim().toLowerCase() ?? '';
    if (id.toLowerCase() == excluded) {
      setState(() => _error = '不能添加自身作为依赖');
      return;
    }
    Navigator.of(context)
        .pop(PackDependency(id: id, version: _version.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加依赖'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_packages.isNotEmpty) ...[
                const Text(
                  '从输出目录中的包选择',
                  style: TextStyle(
                    color: AppColors.textSemantic,
                    fontSize: AppFontSizes.small,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _packageList(),
                const SizedBox(height: AppSpacing.s2),
                const Text(
                  '或手动输入',
                  style: TextStyle(
                    color: AppColors.textSemantic,
                    fontSize: AppFontSizes.small,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ] else ...[
                const Text(
                  '输出目录暂无已打包的包，请手动输入依赖',
                  style: TextStyle(
                    color: AppColors.textSemantic,
                    fontSize: AppFontSizes.small,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
              ],
              _manualFields(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSemantic,
            minimumSize: Size(67, 35),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _confirm, child: const Text('添加')),
      ],
    );
  }

  Widget _packageList() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _packages.length,
        itemBuilder: (context, index) {
          final pkg = _packages[index];
          return InkWell(
            onTap: () => _pickPackage(pkg),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s2,
                vertical: AppSpacing.s1,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      pkg.project.packageId,
                      style: monoTextStyle(),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: Text(
                      pkg.project.version,
                      style: monoTextStyle(color: AppColors.textSemantic),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _manualFields() {
    return Column(
      children: [
        const SizedBox(height: AppSpacing.s1),
        TextField(
          controller: _id,
          style: monoTextStyle(),
          decoration: InputDecoration(
            labelText: '依赖包 ID *',
            hintText: '如 V8.Native',
            errorText: _error,
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        TextField(
          controller: _version,
          style: monoTextStyle(),
          decoration: const InputDecoration(
            labelText: '版本',
            hintText: '如 15.2.124.1 或 [1.0,2.0)',
          ),
        ),
      ],
    );
  }
}

class _DependenciesPlaceholder extends StatelessWidget {
  const _DependenciesPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '从左侧选择一个库项目开始编辑',
        style: TextStyle(
          color: AppColors.textSemantic,
          fontSize: AppFontSizes.body,
        ),
      ),
    );
  }
}
