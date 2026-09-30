import 'package:cpp_nuget_pack/pack/ui/dialogs/pack_preview_dialog.dart';
import 'package:cpp_nuget_pack/pack/model/pack_model.dart';
import 'package:cpp_nuget_pack/nuget/nuget_builder.dart';
import 'package:cpp_nuget_pack/nuget/package_plan.dart';
import 'package:cpp_nuget_pack/shared/format.dart';
import 'package:cpp_nuget_pack/shared/floating_toast.dart';
import 'package:fluent_ui/fluent_ui.dart';

const String _description =
    '按 NuGet 格式生成包内容：头文件与模块按源目录命名空间放入 '
    'build/native/include/，其余文件按类型放入 build/native/files/ 下的 '
    'source / library / assembly / resource / script / msbuild / fortran / llvm / '
    'python / data / executable / other 子目录（根级许可证直接放在 files/ 下）；'
    '同时生成 .nuspec 与 .targets 构建集成文件。'
    '提示：.lib 与 .a 的 Release/Debug 隔离按路径中的 release / debug 目录名'
    '推断（大小写不敏感，多段命中取最后一个），目录改名会导致隔离失效。';

// 消费方契约违反后 NuGet 与 MSBuild 一律不报错、只静默失效，不写在这里用户就永远看不到。
// 单独成段而非并入 _description：那是版式说明，这条是失效边界，混作一段会互相淹没。
const String _consumerContract =
    '消费本包需遵守以下约定，违反后均无任何报错：'
    '.targets 固定落在 build/native/，其中 native 段名必须字面一致 —— '
    'NuGet 为 .vcxproj 硬编码的目标框架标识恰是 native@0.0，'
    '改成 build/native/x64/ 这类四段路径后整个 .targets 会被静默忽略；'
    '文件名必须恰好是「包 ID.targets」与「包 ID.props」，改名同样静默失效；'
    '.targets 只有 .vcxproj（含 C++/CLI）项目会导入；'
    '而 build/<包 ID>.props 是两段路径，任何目标框架的项目都会导入；'
    '产物不得落在点开头或名为 build / out 的目录里（任意层级），否则扫描时被静默跳过。';

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
              Text(_consumerContract, style: TextStyle(color: theme.resources.textFillColorSecondary)),
              const SizedBox(height: 8),
              Text('点击「预览打包内容」可查看包内完整文件列表与文件内容。', style: TextStyle(color: theme.resources.textFillColorSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
