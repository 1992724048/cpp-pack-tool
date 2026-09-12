import 'dart:async';

/// 保存状态四态（视觉规范 §3.3）。
enum EditorSaveStatus { saved, unsaved, saving, failed }

/// 节点编辑器的串行保存队列（视觉规范 §10.4）。
///
/// 变更经 [markDirty] 进入 400ms 防抖（可注入）；防抖窗口结束或 [flush]
/// 立即触发一次保存，保存严格串行。「保存中」期间的新变更在本次完成后
/// 追加保存一次（last-write-wins），状态不回「未保存」而是续「保存中」；
/// 失败置「保存失败」，由 [flush]（重试按钮）或再次 [markDirty] 恢复。
class EditorSaveQueue {
  EditorSaveQueue({
    required this._save,
    this.debounce = const Duration(milliseconds: 400),
    this.onStatusChanged,
  });

  final Future<bool> Function() _save;
  final Duration debounce;
  final void Function()? onStatusChanged;

  EditorSaveStatus _status = EditorSaveStatus.saved;
  bool _dirty = false;
  bool _running = false;
  bool _disposed = false;
  Timer? _debounceTimer;
  final List<Completer<bool>> _flushWaiters = <Completer<bool>>[];
  final List<Completer<void>> _idleWaiters = <Completer<void>>[];

  EditorSaveStatus get status => _status;

  /// 没有在途保存、没有待触发的防抖、没有未保存改动；「保存失败」视为
  /// 终止态（等待用户重试或仍返回），否则失败后 [waitIdle] 将永不完成。
  bool get _idle =>
      !_running &&
      _debounceTimer == null &&
      (!_dirty || _status == EditorSaveStatus.failed);

  /// 标记有未保存改动并重置防抖计时（编辑器任意变更的统一入口）。
  void markDirty() {
    if (_disposed) {
      return;
    }
    _dirty = true;
    if (_running) {
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, _startSave);
    _setStatus(EditorSaveStatus.unsaved);
  }

  /// 跳过防抖立即入队（Ctrl+S / 项目切换 / 返回）。
  ///
  /// 返回的 Future 在本次触发的保存链结束（成功或失败）后完成，成功为
  /// true；无待保存内容且未处于失败态时立即返回当前是否已保存。
  Future<bool> flush() {
    if (_disposed) {
      return Future<bool>.value(false);
    }
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (!_dirty && !_running && _status != EditorSaveStatus.failed) {
      return Future<bool>.value(_status == EditorSaveStatus.saved);
    }
    final Completer<bool> waiter = Completer<bool>();
    _flushWaiters.add(waiter);
    if (!_running) {
      _startSave();
    }
    return waiter.future;
  }

  /// 等待在途与排队的保存完成（返回按钮）；失败态立即完成。
  Future<void> waitIdle() {
    if (_idle) {
      return Future<void>.value();
    }
    final Completer<void> waiter = Completer<void>();
    _idleWaiters.add(waiter);
    return waiter.future;
  }

  /// 取消防抖计时并放弃通知；在途保存完成后不再追加。
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _completeFlushWaiters(false);
    _completeIdleWaiters();
  }

  void _startSave() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_disposed || _running || !_dirty) {
      _completeIdleWaitersIfIdle();
      return;
    }
    _running = true;
    _dirty = false;
    _setStatus(EditorSaveStatus.saving);
    Future<bool> result;
    try {
      result = _save();
    } catch (error) {
      result = Future<bool>.value(false);
    }
    result.then(
      (bool success) => _completeSave(success),
      onError: (Object error, StackTrace stackTrace) => _completeSave(false),
    );
  }

  void _completeSave(bool success) {
    _running = false;
    if (_disposed) {
      _completeFlushWaiters(false);
      _completeIdleWaiters();
      return;
    }
    if (!success) {
      _dirty = true;
      _setStatus(EditorSaveStatus.failed);
      _completeFlushWaiters(false);
      _completeIdleWaiters();
      return;
    }
    if (_dirty) {
      _startSave();
      return;
    }
    _setStatus(EditorSaveStatus.saved);
    _completeFlushWaiters(true);
    _completeIdleWaiters();
  }

  void _setStatus(EditorSaveStatus next) {
    if (_status == next) {
      return;
    }
    _status = next;
    onStatusChanged?.call();
  }

  void _completeFlushWaiters(bool result) {
    if (_flushWaiters.isEmpty) {
      return;
    }
    final List<Completer<bool>> waiters = List<Completer<bool>>.of(
      _flushWaiters,
    );
    _flushWaiters.clear();
    for (final Completer<bool> waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.complete(result);
      }
    }
  }

  void _completeIdleWaitersIfIdle() {
    if (_idle) {
      _completeIdleWaiters();
    }
  }

  void _completeIdleWaiters() {
    if (_idleWaiters.isEmpty) {
      return;
    }
    final List<Completer<void>> waiters = List<Completer<void>>.of(
      _idleWaiters,
    );
    _idleWaiters.clear();
    for (final Completer<void> waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }
}
