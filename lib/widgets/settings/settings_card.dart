import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

/// CommunityToolkit（PowerToys）SettingsCard XAML token；组件与测试共用，
/// 避免魔法数在实现与断言间漂移。
abstract final class SettingsCardTokens {
  static const double minHeight = 68;
  static const double subItemMinHeight = 52;
  static const double minWidth = 148;
  static const double cornerRadius = 4;
  static const EdgeInsets padding = EdgeInsets.all(16);

  /// 子项（SettingsExpander 内部）内边距：左 58 为展开层级缩进。
  static const EdgeInsets subItemPadding = EdgeInsets.fromLTRB(58, 8, 44, 8);

  static const double headerIconSize = 20;
  static const double headerIconSpacing = 20;
  static const double headerContentSpacing = 24;
  static const double descriptionFontSize = 12;
  static const double wrapThreshold = 476;
  static const double wrapNoIconThreshold = 286;
  static const double actionIconSize = 13;
  static const double actionIconSpacing = 14;
  static const Duration backgroundTransition = Duration(milliseconds: 83);
}

/// 组设置卡：左侧头部（图标 + 标题 + 描述）与右侧内容区。
///
/// 严格照 Toolkit token：最小高 68（子项 52）、内边距 16（子项 58,8,44,8）、
/// 1px 描边 + 圆角 4（子项无圆角、仅顶部 1px 分隔线）；窄窗（< 476）内容换行到
/// 头部下方，更窄（< 286）隐藏头部图标。悬停/按下背景过渡 83ms；仅
/// [onPressed] 非空（且启用）的卡有 hover/按下态与焦点环。
class SettingsCard extends StatefulWidget {
  const SettingsCard({
    super.key,
    this.header,
    this.description,
    this.headerIcon,
    this.content,
    this.onPressed,
    this.enabled = true,
    this.subItem = false,
    this.borderless = false,
    this.padding,
  });

  final Widget? header;
  final Widget? description;
  final Widget? headerIcon;
  final Widget? content;

  /// 整卡点击回调；非空且启用时卡可点、可聚焦（Enter/Space 触发）。
  final VoidCallback? onPressed;

  final bool enabled;

  /// 子项变体（SettingsExpander 子项专用）：无圆角、左缩进、最小高 52。
  final bool subItem;

  /// 无边框变体（SettingsExpander 头部：透明底、无描边、无圆角）。
  final bool borderless;

  /// 内边距覆盖（null 时按 token：16 全边 / 子项 58,8,44,8）。
  final EdgeInsetsGeometry? padding;

  @override
  State<SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<SettingsCard> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _clickable => widget.enabled && widget.onPressed != null;

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final Color background = _backgroundFor(theme);
    final Color borderColor = _borderColorFor(theme);
    final BorderRadius radius = BorderRadius.circular(
      widget.subItem || widget.borderless ? 0 : SettingsCardTokens.cornerRadius,
    );
    final BoxBorder border;
    if (widget.borderless) {
      border = Border.all(color: Colors.transparent, width: 1);
    } else if (_focused && _clickable) {
      border = Border.all(
        color: theme.resources.focusStrokeColorOuter,
        width: 2,
      );
    } else if (widget.subItem) {
      border = Border(top: BorderSide(color: borderColor));
    } else {
      border = Border.all(color: borderColor);
    }

    Widget card = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return _buildBody(context, constraints, theme);
      },
    );

    card = AnimatedContainer(
      duration: SettingsCardTokens.backgroundTransition,
      constraints: BoxConstraints(
        minWidth: SettingsCardTokens.minWidth,
        minHeight: widget.subItem
            ? SettingsCardTokens.subItemMinHeight
            : SettingsCardTokens.minHeight,
      ),
      padding:
          widget.padding ??
          (widget.subItem
              ? SettingsCardTokens.subItemPadding
              : SettingsCardTokens.padding),
      decoration: BoxDecoration(
        color: background,
        border: border,
        borderRadius: radius,
      ),
      child: card,
    );

    if (!_clickable) {
      return MouseRegion(
        cursor: MouseCursor.defer,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: card,
      );
    }

    return FocusableActionDetector(
      enabled: widget.enabled,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (bool value) => setState(() => _focused = value),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (ActivateIntent intent) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onTap: () => widget.onPressed?.call(),
          child: card,
        ),
      ),
    );
  }

  void _setHovered(bool value) {
    if (_hovered == value) {
      return;
    }
    setState(() => _hovered = value);
  }

  Color _backgroundFor(FluentThemeData theme) {
    if (!widget.enabled) {
      return theme.resources.controlFillColorDisabled;
    }
    if (widget.borderless) {
      return Colors.transparent;
    }
    if (_pressed) {
      return AppColors.pressedFill(theme);
    }
    if (_hovered && _clickable) {
      return AppColors.hoverFill(theme);
    }
    return AppColors.card(theme);
  }

  Color _borderColorFor(FluentThemeData theme) {
    if (!widget.enabled || widget.subItem) {
      return AppColors.stroke(theme);
    }
    if (_pressed || (_hovered && _clickable)) {
      return AppColors.controlStroke(theme);
    }
    return AppColors.stroke(theme);
  }

  Widget _buildBody(
    BuildContext context,
    BoxConstraints constraints,
    FluentThemeData theme,
  ) {
    final bool wrap = constraints.maxWidth < SettingsCardTokens.wrapThreshold;
    final bool hideIcon =
        constraints.maxWidth < SettingsCardTokens.wrapNoIconThreshold;
    final Widget? icon = hideIcon ? null : widget.headerIcon;
    final Widget? iconView = icon == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(
              right: SettingsCardTokens.headerIconSpacing,
            ),
            child: SizedBox(
              width: SettingsCardTokens.headerIconSize,
              height: SettingsCardTokens.headerIconSize,
              child: IconTheme.merge(
                data: IconThemeData(
                  size: SettingsCardTokens.headerIconSize,
                  color: _foregroundFor(theme),
                ),
                child: Center(child: icon),
              ),
            ),
          );
    final bool hasHeader = widget.header != null || widget.description != null;
    final Widget? headerColumn = hasHeader
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (widget.header != null)
                DefaultTextStyle.merge(
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: _foregroundFor(theme),
                  ),
                  child: widget.header!,
                ),
              if (widget.description != null)
                Padding(
                  padding: EdgeInsets.only(top: widget.header == null ? 0 : 2),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(
                      fontSize: SettingsCardTokens.descriptionFontSize,
                      color: _descriptionColorFor(theme),
                    ),
                    child: widget.description!,
                  ),
                ),
            ],
          )
        : null;
    final Widget? content = widget.content;
    if (!wrap) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          ?iconView,
          if (headerColumn != null)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: content == null
                      ? 0
                      : SettingsCardTokens.headerContentSpacing,
                ),
                child: headerColumn,
              ),
            )
          else
            const Spacer(),
          ?content,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (iconView != null || headerColumn != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              ?iconView,
              if (headerColumn != null)
                Expanded(child: headerColumn)
              else
                const Spacer(),
            ],
          ),
        if (content != null) ...<Widget>[
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: content),
        ],
      ],
    );
  }

  Color _foregroundFor(FluentThemeData theme) {
    if (!widget.enabled) {
      return AppColors.textDisabled(theme);
    }
    if (_pressed) {
      return AppColors.textSecondary(theme);
    }
    return AppColors.textPrimary(theme);
  }

  Color _descriptionColorFor(FluentThemeData theme) {
    if (!widget.enabled) {
      return AppColors.textDisabled(theme);
    }
    return AppColors.textSecondary(theme);
  }
}

/// 卡内容便捷子组件：紧凑 ToggleSwitch（MinWidth 0、高 36、右对齐）。
class SettingsCardToggle extends StatelessWidget {
  const SettingsCardToggle({
    super.key,
    required this.checked,
    required this.onChanged,
    this.enabled = true,
    this.semanticLabel,
  });

  final bool checked;
  final ValueChanged<bool>? onChanged;
  final bool enabled;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ToggleSwitchTheme(
        data: const ToggleSwitchThemeData(
          padding: EdgeInsets.zero,
          margin: EdgeInsets.zero,
        ),
        child: ToggleSwitch(
          checked: checked,
          onChanged: enabled ? onChanged : null,
          semanticLabel: semanticLabel,
        ),
      ),
    );
  }
}
