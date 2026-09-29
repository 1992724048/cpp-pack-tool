import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cpp_nuget_pack/nuget/nupkg_export_job.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('export_job_test');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  group('runExportJob', () {
    test('逐条目落盘且顺序与请求一致', () async {
      _writeBytes('${root.path}/source/a.bin', <int>[1, 2, 3]);
      _writeBytes('${root.path}/source/b.bin', <int>[4, 5]);
      final String tempPath = '${root.path}/out.zip';
      final ReceivePort commands = ReceivePort();

      final List<ExportJobEvent> events = await _runAndCollect(
        commands,
        () => runExportJob(
          ExportJobRequest(
            entries: <ExportEntrySource>[
              const ExportGeneratedEntry(
                packagePath: 'first.txt',
                content: '一',
              ),
              ExportFileEntry(
                packagePath: 'second.bin',
                absolutePath: '${root.path}/source/a.bin',
                size: 3,
              ),
              const ExportGeneratedEntry(
                packagePath: 'third.txt',
                content: '三',
              ),
              ExportFileEntry(
                packagePath: 'fourth.bin',
                absolutePath: '${root.path}/source/b.bin',
                size: 2,
              ),
            ],
            tempPath: tempPath,
            commandPort: commands.sendPort,
          ),
        ),
      );
      commands.close();

      expect(events.first, isA<ExportJobReady>());
      expect(events.last, isA<ExportJobCompleted>());
      final Archive archive = ZipDecoder().decodeBytes(
        File(tempPath).readAsBytesSync(),
      );
      expect(archive.files.map((ArchiveFile file) => file.name), <String>[
        'first.txt',
        'second.bin',
        'third.txt',
        'fourth.bin',
      ]);
      expect(archive.files[1].content, <int>[1, 2, 3]);
      expect(archive.files[3].content, <int>[4, 5]);
    });

    test('进度按字节数加权而非按条目数平均', () async {
      _writeBytes('${root.path}/source/big.bin', List<int>.filled(1000, 7));
      _writeBytes('${root.path}/source/small.bin', List<int>.filled(1, 7));
      final ReceivePort commands = ReceivePort();

      final List<ExportJobEvent> events = await _runAndCollect(
        commands,
        () => runExportJob(
          ExportJobRequest(
            entries: <ExportEntrySource>[
              ExportGeneratedEntry(
                packagePath: 'a.txt',
                content: 'x' * 999,
              ),
              ExportFileEntry(
                packagePath: 'big.bin',
                absolutePath: '${root.path}/source/big.bin',
                size: 1000,
              ),
              ExportFileEntry(
                packagePath: 'small.bin',
                absolutePath: '${root.path}/source/small.bin',
                size: 1,
              ),
            ],
            tempPath: '${root.path}/out.zip',
            commandPort: commands.sendPort,
          ),
        ),
      );
      commands.close();

      final List<double> fractions = _fractionsOf(events);
      expect(fractions, hasLength(3));
      expect(fractions[0], closeTo(999 / 2000, 1e-9));
      expect(fractions[1], closeTo(1999 / 2000, 1e-9));
      expect(fractions[2], closeTo(1, 1e-9));
      expect(fractions[0], isNot(closeTo(1 / 3, 1e-6)));
    });

    test('取消在条目边界生效：后续条目不再压缩', () async {
      // 条目数取够大：条目少时作业可能在取消消息送达前就跑完，测不出短路。
      const int entryCount = 200;
      for (int index = 0; index < entryCount; index++) {
        _writeBytes('${root.path}/source/$index.bin', List<int>.filled(64, index));
      }
      final ReceivePort commands = ReceivePort();

      final List<ExportJobEvent> events = await _runAndCollect(
        commands,
        () => runExportJob(
          ExportJobRequest(
            entries: <ExportEntrySource>[
              for (int index = 0; index < entryCount; index++)
                ExportFileEntry(
                  packagePath: '$index.bin',
                  absolutePath: '${root.path}/source/$index.bin',
                  size: 64,
                ),
            ],
            tempPath: '${root.path}/cancelled.zip',
            commandPort: commands.sendPort,
          ),
        ),
        onProgress: (int seen, ExportJobEvent event, SendPort stopPort) {
          if (seen == 2) {
            stopPort.send(null);
          }
        },
      );
      commands.close();

      expect(events.last, isA<ExportJobCancelled>());
      final int seen = _fractionsOf(events).length;
      expect(seen, lessThan(entryCount));
      // 取消走 break、不调 endEncode，中央目录未写出，故解出的条目列表为空。
      final Archive archive = ZipDecoder().decodeBytes(
        File('${root.path}/cancelled.zip').readAsBytesSync(),
      );
      expect(archive.files, isEmpty);
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('源文件缺失时以 ExportJobFailed 回传原始异常', () async {
      final ReceivePort commands = ReceivePort();

      final List<ExportJobEvent> events = await _runAndCollect(
        commands,
        () => runExportJob(
          ExportJobRequest(
            entries: <ExportEntrySource>[
              ExportFileEntry(
                packagePath: 'missing.bin',
                absolutePath: '${root.path}/source/missing.bin',
                size: 1,
              ),
            ],
            tempPath: '${root.path}/failed.zip',
            commandPort: commands.sendPort,
          ),
        ),
      );
      commands.close();

      expect(events.last, isA<ExportJobFailed>());
      expect((events.last as ExportJobFailed).error, isA<FileSystemException>());
    });

    test('空条目列表也能写出合法空 zip', () async {
      final ReceivePort commands = ReceivePort();
      final String tempPath = '${root.path}/empty.zip';

      final List<ExportJobEvent> events = await _runAndCollect(
        commands,
        () => runExportJob(
          ExportJobRequest(
            entries: const <ExportEntrySource>[],
            tempPath: tempPath,
            commandPort: commands.sendPort,
          ),
        ),
      );
      commands.close();

      expect(events.last, isA<ExportJobCompleted>());
      expect(
        ZipDecoder().decodeBytes(File(tempPath).readAsBytesSync()).files,
        isEmpty,
      );
    });
  });

  group('大文件条目', () {
    test('>10MB 的 .lib 条目流式写入且内容逐字节一致', () async {
      // 16 MB：覆盖「单条目远大于 1 MB 读缓冲」的分块读取路径。
      const int size = 16 << 20;
      final Uint8List payload = Uint8List.fromList(
        List<int>.generate(size, (int index) => (index * 31) % 256),
      );
      _writeBytes('${root.path}/source/big.lib', payload);
      final ReceivePort commands = ReceivePort();
      final String tempPath = '${root.path}/big.zip';

      final List<ExportJobEvent> events = await _runAndCollect(
        commands,
        () => runExportJob(
          ExportJobRequest(
            entries: <ExportEntrySource>[
              ExportFileEntry(
                packagePath: 'build/native/lib/big.lib',
                absolutePath: '${root.path}/source/big.lib',
                size: size,
              ),
            ],
            tempPath: tempPath,
            commandPort: commands.sendPort,
          ),
        ),
      );
      commands.close();

      expect(events.last, isA<ExportJobCompleted>());
      final ArchiveFile entry = ZipDecoder()
          .decodeBytes(File(tempPath).readAsBytesSync())
          .files
          .single;
      expect(entry.name, 'build/native/lib/big.lib');
      expect(entry.size, size);
      expect(entry.content, payload);
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('加权边界', () {
    test('全零字节条目：进度直接到 1 且不产生 NaN', () async {
      _writeBytes('${root.path}/source/empty.bin', <int>[]);
      final ReceivePort commands = ReceivePort();

      final List<ExportJobEvent> events = await _runAndCollect(
        commands,
        () => runExportJob(
          ExportJobRequest(
            entries: <ExportEntrySource>[
              const ExportGeneratedEntry(
                packagePath: 'empty.txt',
                content: '',
              ),
              ExportFileEntry(
                packagePath: 'empty.bin',
                absolutePath: '${root.path}/source/empty.bin',
                size: 0,
              ),
            ],
            tempPath: '${root.path}/zero.zip',
            commandPort: commands.sendPort,
          ),
        ),
      );
      commands.close();

      final List<double> fractions = _fractionsOf(events);
      expect(fractions, hasLength(2));
      // 0/0 会得到 NaN：断言有限值而非只断言存在。
      expect(fractions.every((double value) => value.isFinite), isTrue);
      expect(fractions, everyElement(1));
    });

    test('多字节文本条目按 UTF-8 字节数参与加权', () async {
      final ReceivePort commands = ReceivePort();

      // '包' 在 UTF-8 下占 3 字节；若误按字符数（1）计权，首个台阶是 1/4 而非 3/4。
      final List<ExportJobEvent> events = await _runAndCollect(
        commands,
        () => runExportJob(
          ExportJobRequest(
            entries: const <ExportEntrySource>[
              ExportGeneratedEntry(packagePath: 'han.txt', content: '包'),
              ExportGeneratedEntry(packagePath: 'ascii.txt', content: 'a'),
            ],
            tempPath: '${root.path}/utf8.zip',
            commandPort: commands.sendPort,
          ),
        ),
      );
      commands.close();

      expect(_fractionsOf(events), <double>[3 / 4, 1]);
    });
  });

  group('条目来源混合', () {
    test('阈值判定覆盖边界两侧', () {
      // 断言守的是「小文件走内存源」这个行为，而非复述阈值常量本身。
      expect(buffersSourceInMemory(0), isTrue);
      expect(buffersSourceInMemory(1), isTrue);
      expect(buffersSourceInMemory(inMemorySourceLimitBytes - 1), isTrue);
      expect(buffersSourceInMemory(inMemorySourceLimitBytes), isFalse);
      expect(buffersSourceInMemory(inMemorySourceLimitBytes + 1), isFalse);
    });

    test('阈值两侧的源文件条目内容与声明尺寸都逐字节一致', () async {
      // 8 MB 明显低于阈值（内存源）、24 MB 明显高于（流式源）。尺寸写死而不取自阈值
      // 常量：阈值接线由上面那条判定用例守，混在一起会让阈值被改动时以 RangeError 而
      // 非断言失败报错。
      const int belowLimit = 8 << 20;
      const int aboveLimit = 24 << 20;
      final Uint8List smallPayload = Uint8List.fromList(
        List<int>.generate(belowLimit, (int index) => (index * 131) % 256),
      );
      final Uint8List bigPayload = Uint8List.fromList(
        List<int>.generate(aboveLimit, (int index) => (index * 7 + index ~/ 97) % 256),
      );
      _writeBytes('${root.path}/source/small.bin', smallPayload);
      _writeBytes('${root.path}/source/big.bin', bigPayload);
      final ReceivePort commands = ReceivePort();
      final String tempPath = '${root.path}/mixed.zip';

      final List<ExportJobEvent> events = await _runAndCollect(
        commands,
        () => runExportJob(
          ExportJobRequest(
            entries: <ExportEntrySource>[
              ExportFileEntry(
                packagePath: 'small.bin',
                absolutePath: '${root.path}/source/small.bin',
                size: belowLimit,
              ),
              ExportFileEntry(
                packagePath: 'big.bin',
                absolutePath: '${root.path}/source/big.bin',
                size: aboveLimit,
              ),
            ],
            tempPath: tempPath,
            commandPort: commands.sendPort,
          ),
        ),
      );
      commands.close();

      expect(events.last, isA<ExportJobCompleted>());
      final Archive archive = ZipDecoder().decodeBytes(
        File(tempPath).readAsBytesSync(),
      );
      expect(archive.files.map((ArchiveFile file) => file.name), <String>[
        'small.bin',
        'big.bin',
      ]);
      expect(archive.files[0].size, belowLimit);
      expect(archive.files[0].content, smallPayload);
      expect(archive.files[1].size, aboveLimit);
      expect(archive.files[1].content, bigPayload);
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('句柄释放', () {
    test('作业回传终态后产物可立即改名，100 轮零失败', () async {
      // 终态回传后主 isolate 立刻改名，产物若仍被子 isolate 持有就撞上 Windows
      // 「另一个程序正在使用此文件」（close 不 await 时句柄会越过终态，实测 300 轮
      // 失败 15 次）。条目取小而多，让关闭成为收尾唯一的异步动作，竞态窗口最宽。
      const int rounds = 100;
      const int entryCount = 20;
      final String outDirectory = '${root.path}/out';
      Directory(outDirectory).createSync(recursive: true);
      for (int index = 0; index < entryCount; index++) {
        _writeBytes('${root.path}/source/$index.bin', List<int>.filled(64, index));
      }

      final List<String> failures = <String>[];
      for (int round = 0; round < rounds; round++) {
        final String tempPath = '$outDirectory/round$round.zip';
        final ReceivePort commands = ReceivePort();
        final List<ExportJobEvent> events = await _runAndCollect(
          commands,
          () => runExportJob(
            ExportJobRequest(
              entries: <ExportEntrySource>[
                for (int index = 0; index < entryCount; index++)
                  ExportFileEntry(
                    packagePath: '$index.bin',
                    absolutePath: '${root.path}/source/$index.bin',
                    size: 64,
                  ),
              ],
              tempPath: tempPath,
              commandPort: commands.sendPort,
            ),
          ),
        );
        commands.close();

        if (events.last is! ExportJobCompleted) {
          failures.add('round $round 终态为 ${events.last.runtimeType}');
          continue;
        }
        try {
          File(tempPath).renameSync('$outDirectory/round$round.final');
        } on FileSystemException catch (error) {
          failures.add('round $round 改名失败：${error.osError?.message}');
        }
      }

      expect(failures, isEmpty, reason: '共 $rounds 轮');
    }, timeout: const Timeout(Duration(minutes: 10)));
  });
}

void _writeBytes(String path, List<int> bytes) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}

List<double> _fractionsOf(List<ExportJobEvent> events) => <double>[
  for (final ExportJobEvent event in events)
    if (event is ExportJobProgress) event.fraction,
];

/// 跑一个作业并收集到终态。监听先于作业启动，好让 `onProgress` 能与作业并发投递取消。
Future<List<ExportJobEvent>> _runAndCollect(
  ReceivePort commands,
  Future<void> Function() start, {
  void Function(int seen, ExportJobEvent event, SendPort stopPort)? onProgress,
}) async {
  final List<ExportJobEvent> events = <ExportJobEvent>[];
  final Completer<List<ExportJobEvent>> done =
      Completer<List<ExportJobEvent>>();
  commands.listen((dynamic raw) {
    final ExportJobEvent event = raw as ExportJobEvent;
    events.add(event);
    if (event is ExportJobReady) {
      return;
    }
    if (event is ExportJobProgress) {
      onProgress?.call(
        _fractionsOf(events).length,
        event,
        _stopPortOf(events),
      );
      return;
    }
    if (!done.isCompleted) {
      done.complete(events);
    }
  });
  await start();
  return done.future;
}

SendPort _stopPortOf(List<ExportJobEvent> events) =>
    events.whereType<ExportJobReady>().single.stopPort;
