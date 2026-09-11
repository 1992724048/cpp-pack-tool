import 'package:cpp_nuget_pack/app_info.dart';
import 'package:cpp_nuget_pack/util/file_opener.dart';
import 'package:cpp_nuget_pack/util/svgs.dart';
import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:cpp_nuget_pack/widgets/tag.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';

class About extends StatefulWidget {
  const About({super.key, this.openUrl = openExternalUrl});

  final Future<bool> Function(String url) openUrl;

  @override
  State<About> createState() => _AboutState();
}

class _AboutState extends State<About> {
  Future<void> _openRepository() async {
    final bool opened = await widget.openUrl(appRepositoryUrl);
    if (!opened && mounted) {
      showFloatingToast(
        context,
        '无法打开链接',
        type: FloatingToastType.error,
        duration: const Duration(seconds: 5),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final Color secondaryColor = theme.resources.textFillColorSecondary;
    return SizedBox.expand(
      key: const Key('aboutPage'),
      child: Container(
        decoration: BoxDecoration(color: theme.cardColor),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  'assets/icons/cardboard_box.svg',
                  width: 64,
                  height: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  appName,
                  style: theme.typography.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Tag(text: 'v$appVersion', fontSize: 11),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(
                    appDescription,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: secondaryColor),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('aboutRepoButton'),
                  onPressed: _openRepository,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Svgs.openBox,
                      const SizedBox(width: 8),
                      const Text('项目主页'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '第三方组件许可见仓库 THIRD_PARTY_NOTICES.md',
                  style: TextStyle(color: secondaryColor, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
