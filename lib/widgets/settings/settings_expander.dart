import 'package:cpp_nuget_pack/widgets/settings/settings_card.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// PowerToys SettingsExpander token：头部 16,16,4,16；chevron 按钮 32×32；
/// 展开 333ms 减速 / 收起 167ms。
abstract final class SettingsExpanderTokens {
  static const EdgeInsets headerPadding = EdgeInsets.fromLTRB(16, 16, 4, 16);
  static const double chevronButtonSize = 32;
  static const double chevronIconSize = 16;
  static const Duration expandDuration = Duration(milliseconds: 333);
  static const Duration collapseDuration = Duration(milliseconds: 167);
  static const Curve expandCurve = Cubic(0, 0, 0, 1);
  static const Curve collapseCurve = Cubic(1, 1, 0, 1);

  /// 展开体容器 Key（供测试定位动画参数；同一页面多实例时按 first 取用）。
  static const Key bodyKey = Key('settingsExpanderBody');
}

/// 可折叠设置卡：头部为无边框 [SettingsCard] + 右侧 32×32 chevron 按钮；
/// 展开后按 [items] 渲染子项（[SettingsExpanderItem]，顶部 1px 分隔线）。
///
/// 默认收起（[initiallyExpanded] = false）；头部与 chevron 均可聚焦/点击切换
/// （Enter/Space 生效），展开/收起动画期间允许连续点击（动画可中断）。
class SettingsExpander extends StatefulWidget {
  const SettingsExpander({
    super.key,
    this.header,
    this.description,
    this.headerIcon,
    this.content,
    this.items = const <Widget>[],
    this.initiallyExpanded = false,
    this.enabled = true,
    this.toggleKey,
  });

  final Widget? header;
  final Widget? description;
  final Widget? headerIcon;
  final Widget? content;
  final List<Widget> items;
  final bool initiallyExpanded;
  final bool enabled;

  /// chevron 按钮 Key（多实例时由调用方保证唯一）；供测试定位。
  final Key? toggleKey;

  @override
  State<SettingsExpander> createState() => _SettingsExpanderState();
}

class _SettingsExpanderState extends State<SettingsExpander> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() {
    if (!widget.enabled) {
      return;
    }
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: SettingsCard(
                header: widget.header,
                description: widget.description,
                headerIcon: widget.headerIcon,
                content: widget.content,
                padding: SettingsExpanderTokens.headerPadding,
                borderless: true,
                enabled: widget.enabled,
                onPressed: _toggle,
                // 展开器自带 32×32 折叠按钮，头部卡不再重复显示尾部箭头。
                showChevron: false,
              ),
            ),
            SizedBox(
              width: SettingsExpanderTokens.chevronButtonSize,
              height: SettingsExpanderTokens.chevronButtonSize,
              child: Tooltip(
                message: _expanded ? '收起设置' : '展开设置',
                child: IconButton(
                  key: widget.toggleKey,
                  onPressed: widget.enabled ? _toggle : null,
                  icon: AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: _expanded
                        ? SettingsExpanderTokens.expandDuration
                        : SettingsExpanderTokens.collapseDuration,
                    curve: _expanded
                        ? SettingsExpanderTokens.expandCurve
                        : SettingsExpanderTokens.collapseCurve,
                    child: const Icon(
                      FluentIcons.chevron_down,
                      size: SettingsExpanderTokens.chevronIconSize,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        AnimatedSize(
          key: SettingsExpanderTokens.bodyKey,
          duration: _expanded
              ? SettingsExpanderTokens.expandDuration
              : SettingsExpanderTokens.collapseDuration,
          curve: _expanded
              ? SettingsExpanderTokens.expandCurve
              : SettingsExpanderTokens.collapseCurve,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.items,
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}

/// Expander 子项：无圆角、左缩进 58、最小高 52、顶部 1px 分隔线的设置卡。
class SettingsExpanderItem extends StatelessWidget {
  const SettingsExpanderItem({
    super.key,
    this.header,
    this.description,
    this.headerIcon,
    this.content,
    this.enabled = true,
  });

  final Widget? header;
  final Widget? description;
  final Widget? headerIcon;
  final Widget? content;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      header: header,
      description: description,
      headerIcon: headerIcon,
      content: content,
      enabled: enabled,
      subItem: true,
    );
  }
}
