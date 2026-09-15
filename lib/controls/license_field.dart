import 'package:cpp_nuget_pack/util/licenses.dart';
import 'package:fluent_ui/fluent_ui.dart';

enum _LicenseMode { none, spdx, custom }

/// 许可证选择控件：下拉（无 / SPDX 预设 / 「自定义…」）+ 自定义文本框双态。
///
/// [onChanged] 汇报 `(许可证值, 是否可提交)`：自定义模式文本为空时
/// `(null, false)`，其余情况 `(值, true)`；「无」为 `(null, true)`。
/// 自定义文本在模式切换间保留（误切换不丢内容）；外部回显仅在
/// `value != 上一次发射值` 时重推导，打字中途的父级回写不重置文本框。
class LicenseField extends StatefulWidget {
  const LicenseField({
    super.key,
    required this.value,
    required this.onChanged,
    this.comboBoxKey,
    this.customFieldKey,
    this.errorKey,
  });

  final String? value;
  final void Function(String? license, bool isValid) onChanged;
  final Key? comboBoxKey;
  final Key? customFieldKey;
  final Key? errorKey;

  @override
  State<LicenseField> createState() => _LicenseFieldState();
}

class _LicenseFieldState extends State<LicenseField> {
  final TextEditingController _customController = TextEditingController();

  _LicenseMode _mode = _LicenseMode.none;
  String? _spdxValue;
  String? _lastEmitted;

  @override
  void initState() {
    super.initState();
    _applyValue(widget.value);
  }

  @override
  void didUpdateWidget(covariant LicenseField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _lastEmitted) {
      _applyValue(widget.value);
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _applyValue(String? value) {
    if (value == null) {
      _mode = _LicenseMode.none;
      _spdxValue = null;
    } else if (licenseOptions.contains(value)) {
      _mode = _LicenseMode.spdx;
      _spdxValue = value;
    } else {
      _mode = _LicenseMode.custom;
      _customController.text = value;
    }
  }

  bool get _customValid => _customController.text.trim().isNotEmpty;

  void _emit(String? license, bool isValid) {
    _lastEmitted = license;
    widget.onChanged(license, isValid);
  }

  void _onComboChanged(String? selected) {
    setState(() {
      if (selected == customLicenseEntry) {
        _mode = _LicenseMode.custom;
      } else if (selected == null) {
        _mode = _LicenseMode.none;
        _spdxValue = null;
      } else {
        _mode = _LicenseMode.spdx;
        _spdxValue = selected;
      }
    });
    if (selected == customLicenseEntry) {
      final String trimmed = _customController.text.trim();
      _emit(trimmed.isEmpty ? null : trimmed, trimmed.isNotEmpty);
    } else {
      _emit(selected, true);
    }
  }

  void _onCustomChanged(String text) {
    final String trimmed = text.trim();
    _emit(trimmed.isEmpty ? null : trimmed, trimmed.isNotEmpty);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final FluentThemeData theme = FluentTheme.of(context);
    final String? comboValue = switch (_mode) {
      _LicenseMode.none => null,
      _LicenseMode.spdx => _spdxValue,
      _LicenseMode.custom => customLicenseEntry,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        FluentTheme(
          data: theme.copyWith(visualDensity: comboBoxDensity),
          child: ComboBox<String?>(
            key: widget.comboBoxKey,
            value: comboValue,
            placeholder: const Text('无'),
            isExpanded: true,
            onChanged: _onComboChanged,
            items: <ComboBoxItem<String?>>[
              const ComboBoxItem<String?>(value: null, child: Text('无')),
              for (final String option in licenseOptions)
                ComboBoxItem<String?>(value: option, child: Text(option)),
              const ComboBoxItem<String?>(
                value: customLicenseEntry,
                child: Text(customLicenseEntry),
              ),
            ],
          ),
        ),
        if (_mode == _LicenseMode.custom) ...<Widget>[
          const SizedBox(height: 8),
          TextBox(
            key: widget.customFieldKey,
            controller: _customController,
            placeholder: '自定义许可证',
            onChanged: _onCustomChanged,
          ),
          const SizedBox(height: 4),
          Text(
            _customValid ? '自定义值将作为许可证表达式原样写入包；建议使用 SPDX 标识符。' : '请输入自定义许可证',
            key: widget.errorKey,
            style: TextStyle(
              fontSize: 12,
              color: _customValid
                  ? theme.resources.textFillColorSecondary
                  : theme.resources.systemFillColorCritical,
            ),
          ),
        ],
      ],
    );
  }
}
