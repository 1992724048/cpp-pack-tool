import 'dart:async';

import 'package:cpp_nuget_pack/script_editor/editor_save_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EditorSaveQueue', () {
    test('初始状态为已保存', () {
      final EditorSaveQueue queue = EditorSaveQueue(
        save: () async => true,
        debounce: const Duration(milliseconds: 20),
      );
      addTearDown(queue.dispose);

      expect(queue.status, EditorSaveStatus.saved);
    });

    test('连续 markDirty 在防抖窗口内合并为一次保存', () async {
      int calls = 0;
      final EditorSaveQueue queue = EditorSaveQueue(
        save: () async {
          calls++;
          return true;
        },
        debounce: const Duration(milliseconds: 20),
      );
      addTearDown(queue.dispose);

      queue.markDirty();
      await Future<void>.delayed(const Duration(milliseconds: 8));
      expect(queue.status, EditorSaveStatus.unsaved);
      queue.markDirty();
      await Future<void>.delayed(const Duration(milliseconds: 8));
      queue.markDirty();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(calls, 1);
      expect(queue.status, EditorSaveStatus.saved);
    });

    test('防抖窗口内 flush 跳过等待立即保存', () async {
      int calls = 0;
      final EditorSaveQueue queue = EditorSaveQueue(
        save: () async {
          calls++;
          return true;
        },
        debounce: const Duration(milliseconds: 400),
      );
      addTearDown(queue.dispose);

      queue.markDirty();
      final bool result = await queue.flush();

      expect(calls, 1);
      expect(result, isTrue);
      expect(queue.status, EditorSaveStatus.saved);

      // 原防抖计时已取消：继续等待不会重复保存。
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(calls, 1);
    });

    test('保存中 markDirty：完成后追加一次且状态保持保存中', () async {
      final List<Completer<bool>> pending = <Completer<bool>>[];
      final EditorSaveQueue queue = EditorSaveQueue(
        save: () {
          final Completer<bool> completer = Completer<bool>();
          pending.add(completer);
          return completer.future;
        },
        debounce: const Duration(milliseconds: 20),
      );
      addTearDown(queue.dispose);

      queue.markDirty();
      final Future<bool> flush = queue.flush();
      expect(pending, hasLength(1));
      expect(queue.status, EditorSaveStatus.saving);

      queue.markDirty();
      expect(queue.status, EditorSaveStatus.saving);

      pending[0].complete(true);
      await Future<void>.delayed(Duration.zero);

      expect(pending, hasLength(2));
      expect(queue.status, EditorSaveStatus.saving);

      pending[1].complete(true);
      await Future<void>.delayed(Duration.zero);

      expect(await flush, isTrue);
      expect(queue.status, EditorSaveStatus.saved);
    });

    test('保存返回 false：状态保存失败，flush 重试成功后恢复已保存', () async {
      bool succeed = false;
      int calls = 0;
      final EditorSaveQueue queue = EditorSaveQueue(
        save: () async {
          calls++;
          return succeed;
        },
        debounce: const Duration(milliseconds: 20),
      );
      addTearDown(queue.dispose);

      queue.markDirty();
      expect(await queue.flush(), isFalse);
      expect(queue.status, EditorSaveStatus.failed);
      expect(calls, 1);

      succeed = true;
      expect(await queue.flush(), isTrue);
      expect(queue.status, EditorSaveStatus.saved);
      expect(calls, 2);
    });

    test('保存失败后 markDirty 重新防抖保存', () async {
      bool succeed = false;
      int calls = 0;
      final EditorSaveQueue queue = EditorSaveQueue(
        save: () async {
          calls++;
          return succeed;
        },
        debounce: const Duration(milliseconds: 20),
      );
      addTearDown(queue.dispose);

      queue.markDirty();
      await queue.flush();
      expect(queue.status, EditorSaveStatus.failed);

      succeed = true;
      queue.markDirty();
      expect(queue.status, EditorSaveStatus.unsaved);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(calls, 2);
      expect(queue.status, EditorSaveStatus.saved);
    });

    test('waitIdle 等待在途与追加保存完成', () async {
      final List<Completer<bool>> pending = <Completer<bool>>[];
      int calls = 0;
      final EditorSaveQueue queue = EditorSaveQueue(
        save: () {
          calls++;
          final Completer<bool> completer = Completer<bool>();
          pending.add(completer);
          return completer.future;
        },
        debounce: const Duration(milliseconds: 20),
      );
      addTearDown(queue.dispose);

      queue.markDirty();
      final Future<bool> flush = queue.flush();
      bool idle = false;
      unawaited(queue.waitIdle().then((_) => idle = true));
      await Future<void>.delayed(Duration.zero);
      expect(idle, isFalse);

      queue.markDirty();
      pending[0].complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);

      pending[1].complete(true);
      await Future<void>.delayed(Duration.zero);

      expect(idle, isTrue);
      expect(await flush, isTrue);
      expect(queue.status, EditorSaveStatus.saved);
    });

    test('状态变化经 onStatusChanged 按序通知', () async {
      late final EditorSaveQueue queue;
      final List<EditorSaveStatus> states = <EditorSaveStatus>[];
      queue = EditorSaveQueue(
        save: () async => true,
        debounce: const Duration(milliseconds: 20),
        onStatusChanged: () => states.add(queue.status),
      );
      addTearDown(queue.dispose);

      queue.markDirty();
      await queue.flush();

      expect(states, <EditorSaveStatus>[
        EditorSaveStatus.unsaved,
        EditorSaveStatus.saving,
        EditorSaveStatus.saved,
      ]);
    });

    test('dispose 取消未触发的防抖保存', () async {
      int calls = 0;
      final EditorSaveQueue queue = EditorSaveQueue(
        save: () async {
          calls++;
          return true;
        },
        debounce: const Duration(milliseconds: 20),
      );

      queue.markDirty();
      queue.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(calls, 0);
    });
  });
}
