/// 日志模型与控制器：供打包/扫描等耗时操作增量追加日志。
///
/// [LogController] 为 [ChangeNotifier]，日志面板用 `reverse: true` 的
/// `ListView` 订阅并追加；新行 append 到列表末尾（逆序视图自然贴底）。
library;

import 'package:flutter/foundation.dart';

/// 日志级别。
enum LogLevel { info, warn, error }

/// 单条日志。
class LogEntry {
  LogEntry({required this.time, required this.level, required this.message});

  /// 产生时间。
  final DateTime time;

  /// 级别。
  final LogLevel level;

  /// 消息文本。
  final String message;
}

/// 日志控制器（可监听）。
class LogController extends ChangeNotifier {
  final List<LogEntry> _entries = <LogEntry>[];

  /// 当前全部日志（只读视图，旧→新）。
  List<LogEntry> get entries => List<LogEntry>.unmodifiable(_entries);

  /// 是否有日志。
  bool get isEmpty => _entries.isEmpty;

  /// 追加一条 [level] 日志。
  void append(LogLevel level, String message) {
    _entries.add(
      LogEntry(time: DateTime.now(), level: level, message: message),
    );
    notifyListeners();
  }

  /// 追加 info 级日志。
  void info(String message) => append(LogLevel.info, message);

  /// 追加 warn 级日志。
  void warn(String message) => append(LogLevel.warn, message);

  /// 追加 error 级日志。
  void error(String message) => append(LogLevel.error, message);

  /// 清空全部日志。
  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
