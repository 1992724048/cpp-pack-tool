import 'package:cpp_nuget_pack/controls/pack_preview_dialog.dart';
import 'package:cpp_nuget_pack/models/pack_model.dart';
import 'package:cpp_nuget_pack/packaging/nuget_builder.dart';
import 'package:cpp_nuget_pack/packaging/package_plan.dart';
import 'package:cpp_nuget_pack/shared/format.dart';
import 'package:cpp_nuget_pack/shared/floating_toast.dart';
import 'package:fluent_ui/fluent_ui.dart';

const String _description =
    '按 NuGet 格式生成包内容：头文件与模块按源目录命名空间放入 '
    'build/native/include/，库文件（lib/dll/pdb）放入 '
    'build/native/lib/，其余文件放入 build/native/files/；'
    '同时生成 .nuspec 与 .targets 构建集成文件。';

class PackPackaging extends StatefulWidget {
  const PackPackaging({super.key, required this.pack});

  final PackModel pack;

  @override
  State<PackPackaging> createState() => _PackPackagingState();
}

class _PackPackagingState extends State<PackPackaging> {
  static const NuGetPackageBuilder _builder = NuGetPackageBuilder();

  bool _previewing = false;

  Future<void> _preview() async {
    if (_previewing) {
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
      plan = await _builder.buildPlan(widget.pack);
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
              FilledButton(key: const Key('packPreviewButton'), onPressed: _preview, child: const Text('预览打包内容')),
              const SizedBox(height: 16),
              Text(_description, style: TextStyle(color: theme.resources.textFillColorSecondary)),
              const SizedBox(height: 8),
              Text('点击「预览打包内容」可查看包内完整文件列表与文件内容。', style: TextStyle(color: theme.resources.textFillColorSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
