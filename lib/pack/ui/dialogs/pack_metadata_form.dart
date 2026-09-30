import 'package:cpp_nuget_pack/pack/ui/dialogs/license_field.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// 新增包时收集的元数据值。字段定义与必填口径只有 [PackMetadataForm] 一处，
/// 「添加文件夹」与「创建包结构」两个入口共用同一份表单，避免两处漂移。
class PackMetadata {
  const PackMetadata({
    required this.name,
    required this.version,
    required this.author,
    this.description,
    this.license,
  });

  final String name;
  final String version;
  final String author;
  final String? description;
  final String? license;
}

/// 表单状态快照。[isComplete] 是必填口径的判定处，调用方据此决定主按钮是否可用，
/// 不再自行重复推导。
class PackMetadataDraft {
  const PackMetadataDraft({required this.metadata, required this.isComplete});

  final PackMetadata metadata;
  final bool isComplete;
}

/// 包元数据表单：包 ID / 版本 / 作者 / 许可证 / 描述。
class PackMetadataForm extends StatefulWidget {
  const PackMetadataForm({super.key, required this.onChanged});

  final ValueChanged<PackMetadataDraft> onChanged;

  @override
  State<PackMetadataForm> createState() => _PackMetadataFormState();
}

class _PackMetadataFormState extends State<PackMetadataForm> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _versionController = TextEditingController();
  final TextEditingController _authorController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  String? _license;
  bool _licenseValid = true;

  @override
  void initState() {
    super.initState();
    // 不在 initState 里回调 onChanged：「创建包结构」的首帧由父级 build 触发，
    // 回调会连带父级 setState 而在 build 期间报错。父级以空快照起步即可。
    _nameController.addListener(_emit);
    _versionController.addListener(_emit);
    _authorController.addListener(_emit);
    _descriptionController.addListener(_emit);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _versionController.dispose();
    _authorController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool get _isComplete =>
      _nameController.text.trim().isNotEmpty &&
      _versionController.text.trim().isNotEmpty &&
      _authorController.text.trim().isNotEmpty &&
      _licenseValid;

  void _emit() {
    final String description = _descriptionController.text.trim();
    widget.onChanged(
      PackMetadataDraft(
        metadata: PackMetadata(
          name: _nameController.text.trim(),
          version: _versionController.text.trim(),
          author: _authorController.text.trim(),
          description: description.isEmpty ? null : description,
          license: _license,
        ),
        isComplete: _isComplete,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildField(label: '包 ID', child: TextBox(key: const Key('packIdField'), controller: _nameController)),
        const SizedBox(height: 12),
        _buildField(
          label: '版本',
          child: TextBox(key: const Key('packVersionField'), controller: _versionController, placeholder: '1.0.0'),
        ),
        const SizedBox(height: 12),
        _buildField(
          label: '作者',
          child: TextBox(key: const Key('packAuthorField'), controller: _authorController),
        ),
        const SizedBox(height: 12),
        _buildField(
          label: '许可证',
          child: LicenseField(
            value: _license,
            comboBoxKey: const Key('packLicenseField'),
            customFieldKey: const Key('packLicenseCustomField'),
            errorKey: const Key('packLicenseCustomError'),
            onChanged: (String? license, bool isValid) {
              setState(() {
                _license = license;
                _licenseValid = isValid;
              });
              _emit();
            },
          ),
        ),
        const SizedBox(height: 12),
        _buildField(
          label: '描述',
          child: TextBox(
            key: const Key('packDescriptionField'),
            controller: _descriptionController,
            minLines: 3,
            maxLines: 3,
          ),
        ),
      ],
    );
  }

  Widget _buildField({required String label, required Widget child}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(label), const SizedBox(height: 4), child],
    );
  }
}
