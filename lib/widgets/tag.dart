import 'package:flutter/material.dart';

class Tag extends StatelessWidget {
  final String text;
  final Color? color;
  final double? fontSize;

  const Tag({super.key, required this.text, this.color, this.fontSize});

  @override
  Widget build(BuildContext context) {
    final themeContext = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: fontSize != null ? fontSize! * 0.8 : 8, vertical: fontSize != null ? fontSize! * 0.4 : 4),
      decoration: BoxDecoration(color: color ?? themeContext.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(fontSize != null ? fontSize! * 8 : 50)),
      child: Text(
        text,
        style: TextStyle(fontSize: fontSize ?? 12, color: themeContext.colorScheme.onPrimaryContainer),
      ),
    );
  }
}
