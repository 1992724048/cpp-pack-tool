import 'package:fluent_ui/fluent_ui.dart';

class PackInfo extends StatefulWidget {
  const PackInfo({super.key});

  @override
  State<PackInfo> createState() => _PackInfoState();
}

class _PackInfoState extends State<PackInfo> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InfoLabel(label: '包 ID*', child: const TextBox()),
              ),
              SizedBox(width: 16),
              Expanded(
                child: InfoLabel(label: '版本*', child: const TextBox(placeholder: '1.0.0')),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: InfoLabel(label: '作者*', child: const TextBox()),
              ),
              SizedBox(width: 16),
              Expanded(
                child: InfoLabel(
                  label: '许可证',
                  child: const TextBox(placeholder: 'MIT'),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('描述'),
                SizedBox(height: 4),
                Expanded(child: TextBox(maxLines: null, expands: true, placeholder: '输入包描述…')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
