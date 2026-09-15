import 'package:fluent_ui/fluent_ui.dart';

class Tag extends StatelessWidget {
  final String text;
  final Color? color;
  final double? fontSize;

  /// 文本最大宽度；null 时按内容自适应（默认行为），非 null 时单行省略截断。
  final double? maxWidth;

  /// 悬停提示（全量文本）；null 时不包裹 Tooltip。
  final String? tooltip;

  const Tag({
    super.key,
    required this.text,
    this.color,
    this.fontSize,
    this.maxWidth,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final themeContext = FluentTheme.of(context);
    final Color backgroundColor = color ?? themeContext.accentColor;
    final Color textColor = backgroundColor.computeLuminance() > 0.5
        ? const Color(0xFF1B1B1B)
        : Colors.white;
    final TextStyle textStyle = TextStyle(
      color: textColor,
      fontSize: fontSize ?? themeContext.typography.body!.fontSize,
    );
    final Widget label = maxWidth == null
        ? Text(text, style: textStyle)
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth!),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          );
    final Widget tag = Container(
      padding: EdgeInsets.symmetric(
        horizontal: fontSize != null ? fontSize! * 0.8 : 8,
        vertical: fontSize != null ? fontSize! * 0.4 : 4,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(
          fontSize != null ? fontSize! * 8 : 50,
        ),
      ),
      child: Center(widthFactor: 1.0, heightFactor: 1.0, child: label),
    );
    final String? message = tooltip;
    if (message == null) {
      return tag;
    }
    return Tooltip(message: message, child: tag);
  }
}
