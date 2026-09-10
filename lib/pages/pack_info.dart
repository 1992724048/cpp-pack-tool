import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:fluent_ui/fluent_ui.dart';

class PackInfo extends StatefulWidget {
  const PackInfo({super.key, required this.pack});

  final PackModel pack;

  @override
  State<PackInfo> createState() => _PackInfoState();
}

class _PackInfoState extends State<PackInfo> {
  late final TextEditingController _idController;
  late final TextEditingController _versionController;
  late final TextEditingController _authorController;
  late final TextEditingController _licenseController;
  late final TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _idController = TextEditingController(text: widget.pack.name);
    _versionController = TextEditingController(text: widget.pack.version);
    _authorController = TextEditingController(text: widget.pack.author);
    _licenseController = TextEditingController(text: widget.pack.license ?? '');
    _descriptionController = TextEditingController(
      text: widget.pack.description ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant PackInfo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pack == widget.pack) {
      return;
    }
    _idController.text = widget.pack.name;
    _versionController.text = widget.pack.version;
    _authorController.text = widget.pack.author;
    _licenseController.text = widget.pack.license ?? '';
    _descriptionController.text = widget.pack.description ?? '';
  }

  @override
  void dispose() {
    _idController.dispose();
    _versionController.dispose();
    _authorController.dispose();
    _licenseController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _field('包 ID', _idController)),
              const SizedBox(width: 16),
              Expanded(child: _field('版本', _versionController)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _field('作者', _authorController)),
              const SizedBox(width: 16),
              Expanded(
                child: _field('许可证', _licenseController, placeholder: '无'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('描述'),
                const SizedBox(height: 4),
                Expanded(
                  child: TextBox(
                    controller: _descriptionController,
                    readOnly: true,
                    maxLines: null,
                    expands: true,
                    placeholder: '无',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? placeholder,
  }) {
    return InfoLabel(
      label: label,
      child: TextBox(
        controller: controller,
        readOnly: true,
        placeholder: placeholder,
      ),
    );
  }
}
