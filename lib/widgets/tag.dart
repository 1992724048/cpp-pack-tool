import 'package:cpp_nuget_pack/util/colors.dart';
import 'package:fluent_ui/fluent_ui.dart';

class Tag extends StatelessWidget {
  final String text;
  final Color? color;
  final double? fontSize;

  const Tag({super.key, required this.text, this.color, this.fontSize});

  @override
  Widget build(BuildContext context) {
    final themeContext = FluentTheme.of(context);
    final Color backgroundColor = color ?? UCColors.accent;
    final Color textColor = backgroundColor.computeLuminance() > 0.5
        ? const Color(0xFF1E1E2E)
        : Colors.white;
    return Container(
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
      child: Center(
        widthFactor: 1.0,
        heightFactor: 1.0,
        child: Text(
          text,
          style: TextStyle(
            color: textColor,
            fontSize: fontSize ?? themeContext.typography.body!.fontSize,
          ),
        ),
      ),
    );
  }
}
