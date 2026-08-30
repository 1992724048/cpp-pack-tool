/// 包信息 Tab：id/version/description/authors/owners/tags/license/
/// repository/outputDirectory 表单。
///
/// 字段以 controller 承载，onChanged 同步回 [PackProject]；表单校验以内联
/// errorText 呈现（不弹窗打断）。对照 `docs/ui-spec.md` §3.4。
library;

import 'package:flutter/material.dart';

import '../../models/pack_project.dart';
import '../tokens.dart';
import '../widgets/form_fields.dart';

/// 包信息页。
class PackInfoPage extends StatefulWidget {
  const PackInfoPage({
    super.key,
    required this.project,
    required this.onChanged,
  });

  /// 当前项目；为 null 时显示占位（未选中库项目）。
  final PackProject? project;

  /// 字段变更回调（传入更新后的项目）。
  final ValueChanged<PackProject> onChanged;

  @override
  State<PackInfoPage> createState() => _PackInfoPageState();
}

class _PackInfoPageState extends State<PackInfoPage> {
  late TextEditingController _packageId;
  late TextEditingController _version;
  late TextEditingController _description;
  late TextEditingController _authors;
  late TextEditingController _owners;
  late TextEditingController _tags;
  late TextEditingController _license;
  late TextEditingController _repository;
  late TextEditingController _outputDirectory;

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    _packageId = TextEditingController(text: p?.packageId ?? '');
    _version = TextEditingController(text: p?.version ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _authors = TextEditingController(text: p?.authors ?? '');
    _owners = TextEditingController(text: p?.owners ?? '');
    _tags = TextEditingController(text: p?.tags ?? '');
    _license = TextEditingController(text: p?.license ?? '');
    _repository = TextEditingController(text: p?.repository ?? '');
    _outputDirectory = TextEditingController(text: p?.outputDirectory ?? '');
  }

  @override
  void didUpdateWidget(PackInfoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(
      widget.project?.packageId,
      _packageId,
      oldWidget.project?.packageId,
    );
    _syncController(
      widget.project?.version,
      _version,
      oldWidget.project?.version,
    );
    _syncController(
      widget.project?.description,
      _description,
      oldWidget.project?.description,
    );
    _syncController(
      widget.project?.authors,
      _authors,
      oldWidget.project?.authors,
    );
    _syncController(widget.project?.owners, _owners, oldWidget.project?.owners);
    _syncController(widget.project?.tags, _tags, oldWidget.project?.tags);
    _syncController(
      widget.project?.license,
      _license,
      oldWidget.project?.license,
    );
    _syncController(
      widget.project?.repository,
      _repository,
      oldWidget.project?.repository,
    );
    _syncController(
      widget.project?.outputDirectory,
      _outputDirectory,
      oldWidget.project?.outputDirectory,
    );
  }

  @override
  void dispose() {
    _packageId.dispose();
    _version.dispose();
    _description.dispose();
    _authors.dispose();
    _owners.dispose();
    _tags.dispose();
    _license.dispose();
    _repository.dispose();
    _outputDirectory.dispose();
    super.dispose();
  }

  void _syncController(
    String? value,
    TextEditingController controller,
    String? oldValue,
  ) {
    final next = value ?? '';
    if (next != controller.text && next != oldValue) {
      controller.text = next;
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    if (project == null) {
      return const _Placeholder();
    }

    final packageIdError = _packageIdError(project.packageId);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '包信息'),
          const SizedBox(height: AppSpacing.s2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LabeledFormField(
                  label: '包 ID *',
                  child: TextFormField(
                    controller: _packageId,
                    onChanged: (value) =>
                        _update(project.copyWith(packageId: value)),
                    decoration: InputDecoration(
                      hintText: '如 V8.Native',
                      errorText: packageIdError,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: LabeledFormField(
                  label: '版本 *',
                  child: TextFormField(
                    controller: _version,
                    onChanged: (value) =>
                        _update(project.copyWith(version: value)),
                    decoration: const InputDecoration(hintText: '如 1.2.0'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          LabeledFormField(
            label: '描述',
            child: TextFormField(
              controller: _description,
              maxLines: 3,
              onChanged: (value) =>
                  _update(project.copyWith(description: value)),
              decoration: const InputDecoration(hintText: '包用途简述'),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LabeledFormField(
                  label: '作者',
                  child: TextFormField(
                    controller: _authors,
                    onChanged: (value) =>
                        _update(project.copyWith(authors: value)),
                    decoration: const InputDecoration(hintText: '如 V8 Team'),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: LabeledFormField(
                  label: '拥有者',
                  child: TextFormField(
                    controller: _owners,
                    onChanged: (value) =>
                        _update(project.copyWith(owners: value)),
                    decoration: const InputDecoration(hintText: '如 V8 Project'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LabeledFormField(
                  label: '标签',
                  child: TextFormField(
                    controller: _tags,
                    onChanged: (value) =>
                        _update(project.copyWith(tags: value)),
                    decoration: const InputDecoration(
                      hintText: '逗号分隔，如 cpp,v8,native',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: LabeledFormField(
                  label: '许可证',
                  child: TextFormField(
                    controller: _license,
                    onChanged: (value) =>
                        _update(project.copyWith(license: value)),
                    decoration: const InputDecoration(
                      hintText: '可空，如 BSD-3-Clause',
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LabeledFormField(
                  label: '仓库地址',
                  child: TextFormField(
                    controller: _repository,
                    onChanged: (value) =>
                        _update(project.copyWith(repository: value)),
                    decoration: const InputDecoration(hintText: '可空，仓库 URL'),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: LabeledFormField(
                  label: '输出目录',
                  child: TextFormField(
                    controller: _outputDirectory,
                    onChanged: (value) =>
                        _update(project.copyWith(outputDirectory: value)),
                    style: monoTextStyle(),
                    decoration: const InputDecoration(hintText: '打包产物输出目录'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _packageIdError(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (!PackProject.isValidPackageId(trimmed)) {
      return '包 ID 需以字母/数字开头，仅含字母、数字、下划线、连字符、点号';
    }
    return null;
  }

  void _update(PackProject updated) => widget.onChanged(updated);
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

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
