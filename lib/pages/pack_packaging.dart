import 'package:cpp_nuget_pack/controls/pack_preview_dialog.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/package_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:cpp_nuget_pack/util/format.dart';
import 'package:cpp_nuget_pack/util/licenses.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:fluent_ui/fluent_ui.dart';

const String _cmakeBuilderId = 'cmake';

class PackPackaging extends StatefulWidget {
  const PackPackaging({
    super.key,
    required this.pack,
    this.builders = PackageBuilderRegistry.all,
    this.selectedBuilder,
    this.onBuilderChanged,
  });

  final PackModel pack;
  final List<PackageBuilder> builders;

  /// 父级持有的选中格式；为空时回退到本地选择或首个格式。
  final PackageBuilder? selectedBuilder;
  final ValueChanged<PackageBuilder>? onBuilderChanged;

  @override
  State<PackPackaging> createState() => _PackPackagingState();
}

class _PackPackagingState extends State<PackPackaging> {
  PackageBuilder? _localBuilder;
  bool _previewing = false;

  PackageBuilder? get _builder {
    final PackageBuilder? selected = widget.selectedBuilder;
    if (selected != null) {
      final PackageBuilder? matched = _findBuilder(selected.id);
      if (matched != null) {
        return matched;
      }
    }
    final PackageBuilder? local = _localBuilder;
    if (local != null) {
      final PackageBuilder? matched = _findBuilder(local.id);
      if (matched != null) {
        return matched;
      }
    }
    return widget.builders.isEmpty ? null : widget.builders.first;
  }

  PackageBuilder? _findBuilder(String id) {
    for (final PackageBuilder builder in widget.builders) {
      if (builder.id == id) {
        return builder;
      }
    }
    return null;
  }

  void _selectBuilder(String? id) {
    final PackageBuilder? builder = id == null ? null : _findBuilder(id);
    if (builder == null) {
      return;
    }
    setState(() => _localBuilder = builder);
    widget.onBuilderChanged?.call(builder);
  }

  String _descriptionFor(PackageBuilder? builder) {
    if (builder?.id == _cmakeBuilderId) {
      return '按所选格式生成包内容：头文件与模块放入 include/<源目录名>/，'
          '库文件（lib/dll/pdb）放入 lib/，其余文件放入 files/；'
          '同时在 lib/cmake/<包名>/ 下生成 Config、Targets 与 ConfigVersion '
          '配置三件套。解压后把 CMAKE_PREFIX_PATH 指向包根，即可 '
          'find_package(<包名> CONFIG REQUIRED) 并链接 <包名>::<包名>。';
    }
    return '按所选格式生成包内容：头文件与模块按源目录命名空间放入 '
        'build/native/include/，库文件（lib/dll/pdb）放入 '
        'build/native/lib/，其余文件放入 build/native/files/；'
        '同时生成 .nuspec 与 .targets 构建集成文件。';
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
                _descriptionFor(_builder),
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
