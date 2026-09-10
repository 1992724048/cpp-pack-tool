import 'package:fluent_ui/fluent_ui.dart' show VisualDensity;

const List<String> licenseOptions = [
  'MIT',
  'Apache-2.0',
  'BSD-3-Clause',
  'GPL-2.0',
  'GPL-3.0',
  'LGPL-3.0',
  'MPL-2.0',
  'Unlicense',
];

/// fluent_ui 4.16.1 中 ComboBox 上下各有 1px 边框衬距，比单行 TextBox 高 2px；
/// visualDensity 每 1 单位调整 4px，取垂直 -0.5 恰好抵消，使下拉框与相邻输入框等高。
const VisualDensity comboBoxDensity = VisualDensity(vertical: -0.5);
