import 'package:cpp_nuget_pack/controls/pack_preview_dialog.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/package_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/util/licenses.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:fluent_ui/fluent_ui.dart';

class PackPackaging extends StatefulWidget {
  const PackPackaging({
    super.key,
    required this.pack,
    this.builders = PackageBuilderRegistry.all,
  });

  final PackModel pack;
  final List<PackageBuilder> builders;

  @override
  State<PackPackaging> createState() => _PackPackagingState();
}

class _PackPackagingState extends State<PackPackaging> {
  PackageBuilder? _builder;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    _builder = widget.builders.isEmpty ? null : widget.builders.first;
  }

  @override
  void didUpdateWidget(covariant PackPackaging oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.builders.contains(_builder)) {
      _builder = widget.builders.isEmpty ? null : widget.builders.first;
    }
  }

  void _selectBuilder(String? id) {
    for (final PackageBuilder builder in widget.builders) {
      if (builder.id == id) {
        setState(() => _builder = builder);
        return;
      }
    }
  }

  Future<void> _preview() async {
    final PackageBuilder? builder = _builder;
    if (builder == null || _previewing) {
      return;
    }
    if (widget.pack.sourcePath == null) {
      showFloatingToast(
        context,
        '该包缺少源目录信息，无法预览打包内容',
        type: FloatingToastType.error,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    _previewing = true;
    final PackagePlan plan;
    try {
      plan = await builder.buildPlan(widget.pack);
    } catch (error) {
      _previewing = false;
      if (!mounted) {
        return;
      }
      showFloatingToast(
        context,
        '预览失败：${formatError(error)}',
        type: FloatingToastType.error,
        duration: const Duration(seconds: 5),
      );
      return;
    }
    _previewing = false;
    if (!mounted) {
      return;
    }
    await showPackPreviewDialog(context, pack: widget.pack, plan: plan);
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '打包格式',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: theme.typography.body?.color,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 320,
                child: FluentTheme(
                  data: theme.copyWith(visualDensity: comboBoxDensity),
                  child: ComboBox<String>(
                    key: const Key('packagingBuilderField'),
                    value: _builder?.id,
                    placeholder: const Text('请选择打包格式'),
                    isExpanded: true,
                    onChanged: _selectBuilder,
                    items: <ComboBoxItem<String>>[
                      for (final PackageBuilder builder in widget.builders)
                        ComboBoxItem<String>(
                          value: builder.id,
                          child: Text(builder.displayName),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('packPreviewButton'),
                onPressed: _builder == null ? null : _preview,
                child: const Text('预览打包内容'),
              ),
              const SizedBox(height: 16),
              Text(
                '按所选格式生成包内容：头文件与模块放入 build/native/include/，'
                '库文件（lib/dll/pdb）放入 build/native/lib/，其余文件不打包；'
                '同时生成 .nuspec 与 .targets 构建集成文件。',
                style: TextStyle(color: theme.resources.textFillColorSecondary),
              ),
              const SizedBox(height: 8),
              Text(
                '点击「预览打包内容」可查看包内完整文件列表与文件内容。',
                style: TextStyle(color: theme.resources.textFillColorSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
