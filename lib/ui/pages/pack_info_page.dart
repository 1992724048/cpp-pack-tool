/// 包信息 Tab：id/version/description/authors/owners/tags/license/repository 表单。
///
/// 字段以 controller 承载，onChanged 同步回 [PackProject]；表单校验以内联
/// errorText 呈现（不弹窗打断）。输出目录为全局设置（见打包页），此处不再出现。
/// 对照 `docs/ui-spec.md` §3.4。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/pack_project.dart';
import '../../services/path_utils.dart';
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

  /// 已尝试自动读取描述/许可证默认值的源目录集合（避免重复读取与循环触发）。
  final Set<String> _descriptionReadAttempted = <String>{};
  final Set<String> _licenseReadAttempted = <String>{};

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFillDefaults());
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFillDefaults());
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

  /// 加载/新建包时的默认值回填：首个源目录下的 README/LICENSE 作为空的
  /// description/license 默认值；读取失败静默跳过（不报错、不崩溃）。
  void _maybeFillDefaults() {
    final project = widget.project;
    if (project == null) return;
    final sourceDirs = project.sourceDirs;
    if (sourceDirs.isEmpty) return;
    final firstPath = sourceDirs.first.path;

    String? description;
    if (project.description.trim().isEmpty &&
        !_descriptionReadAttempted.contains(firstPath)) {
      _descriptionReadAttempted.add(firstPath);
      description = _readDefaultDescription(firstPath);
    }
    String? license;
    if (project.license.trim().isEmpty &&
        !_licenseReadAttempted.contains(firstPath)) {
      _licenseReadAttempted.add(firstPath);
      license = _readDefaultLicense(firstPath);
    }

    final filledDescription = (description != null && description.isNotEmpty)
        ? description
        : null;
    final filledLicense = (license != null && license.isNotEmpty)
        ? license
        : null;
    if (filledDescription != null || filledLicense != null) {
      // 一次 copyWith 同时应用两个默认值，避免多次 onChanged 覆盖彼此。
      widget.onChanged(
        project.copyWith(
          description: filledDescription,
          license: filledLicense,
        ),
      );
    }
  }

  /// 从源目录下读取 README（优先 .md，大小写不敏感）前若干字符；无则返回 null。
  String? _readDefaultDescription(String sourceDirPath) {
    final file = _findFirstCandidate(sourceDirPath, const [
      'README.md',
      'README.txt',
    ]);
    if (file == null) return null;
    return _firstChars(_readFileSilently(file), 300);
  }

  /// 从源目录下读取 LICENSE（大小写不敏感）首行（或前 80 字符）；无则返回 null。
  String? _readDefaultLicense(String sourceDirPath) {
    final file = _findFirstCandidate(sourceDirPath, const [
      'LICENSE',
      'LICENSE.txt',
      'LICENSE.md',
    ]);
    if (file == null) return null;
    return _firstLine(_readFileSilently(file), 80);
  }

  /// 在 [sourceDirPath] 顶层按优先级找第一个匹配的（大小写不敏感）文件名。
  String? _findFirstCandidate(String sourceDirPath, List<String> names) {
    final dir = Directory(sourceDirPath);
    if (!dir.existsSync()) return null;
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync();
    } on FileSystemException {
      return null;
    }
    final wanted = names.map((n) => n.toLowerCase()).toSet();
    final candidates = <String>[];
    for (final entry in entries) {
      if (FileSystemEntity.typeSync(entry.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      if (wanted.contains(basenameOf(entry.path).toLowerCase())) {
        candidates.add(entry.path);
      }
    }
    if (candidates.isEmpty) return null;
    // 按传入优先级（如 .md 优先）匹配，未命中时退回首个候选。
    for (final name in names) {
      for (final path in candidates) {
        if (basenameOf(path).toLowerCase() == name.toLowerCase()) {
          return path;
        }
      }
    }
    return candidates.first;
  }

  /// 读取文件全部内容；失败返回空串（读取失败按需求静默跳过、不报错）。
  String _readFileSilently(String path) {
    try {
      return File(path).readAsStringSync();
    } on Object {
      return '';
    }
  }

  /// 取内容前 [maxLen] 个字符（去首尾空白）。
  String _firstChars(String content, int maxLen) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.length <= maxLen ? trimmed : trimmed.substring(0, maxLen);
  }

  /// 取内容首行（去首尾空白），超长时截取前 [maxLen] 个字符。
  String _firstLine(String content, int maxLen) {
    final newline = content.indexOf('\n');
    final line = (newline < 0 ? content : content.substring(0, newline)).trim();
    if (line.isEmpty) return '';
    return line.length <= maxLen ? line : line.substring(0, maxLen);
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
          LabeledFormField(
            label: '仓库地址',
            child: TextFormField(
              controller: _repository,
              onChanged: (value) =>
                  _update(project.copyWith(repository: value)),
              decoration: const InputDecoration(hintText: '可空，仓库 URL'),
            ),
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
