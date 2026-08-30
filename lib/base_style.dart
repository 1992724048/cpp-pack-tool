import 'package:flutter/material.dart';

final ButtonStyle buttonStyle = ButtonStyle(
  backgroundColor: const MaterialStatePropertyAll<Color>(Colors.blue),
  foregroundColor: const MaterialStatePropertyAll<Color>(Colors.white),
  textStyle: const MaterialStatePropertyAll<TextStyle>(
    TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
    ),
  ),
  padding: const MaterialStatePropertyAll<EdgeInsetsGeometry>(
    EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  ),
  shape: MaterialStatePropertyAll<OutlinedBorder>(
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(5),
    ),
  ),
);