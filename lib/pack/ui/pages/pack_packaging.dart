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
// 只列用户能行动的两条；工具自身的包内布局约定（native@0.0、文件名等）属改本工具的人，
// 整段见 README「包消费契约」，在配包页写出来只会让读者去遵守一件自己控制不了的事。
const String _consumerContract =
    '使用本包时的两条硬性约束，违反后不会有任何报错：\n'
    '\n'
    '1. 产物不要放进点开头的目录，也不要把目录命名为 build 或 out（任意层级都算）'
    '—— 扫描器会跳过它们，产物不会进包。\n'
    '\n'
    '2. 本包生成的 .targets 只会被 .vcxproj（含 C++/CLI）工程导入。'
    '工程类型不对时，包里的编译选项、库目录、pre/post 钩子全部不生效，且不报错。\n'
    '\n'
    '另：放在 msbuild/ 目录的 .props 与 .targets 会被自动导入。';

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
