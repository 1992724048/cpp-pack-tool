import 'package:cpp_nuget_pack/widgets/floating_toast.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('入场完成后显示在右上角', (tester) async {
    await _pumpHost(tester);

    await tester.tap(find.text('成功提示'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('已保存'), findsOneWidget);
    expect(find.byIcon(WindowsIcons.completed), findsOneWidget);
    expect(
      tester.getTopRight(find.byKey(const Key('floatingToast'))),
      const Offset(1264, 16),
    );
  });

  testWidgets('按类型显示对应图标', (tester) async {
    await _pumpHost(tester);

    await tester.tap(find.text('错误提示'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byIcon(WindowsIcons.error_badge), findsOneWidget);
    expect(find.text('加载失败，请检查配置文件后重试。'), findsOneWidget);
  });

  testWidgets('到时后自动淡出并移除', (tester) async {
    await _pumpHost(tester);

    await tester.tap(find.text('成功提示'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('已保存'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(find.text('已保存'), findsNothing);
    expect(find.byKey(const Key('floatingToast')), findsNothing);
  });

  testWidgets('点击关闭按钮淡出并移除', (tester) async {
    await _pumpHost(tester);

    await tester.tap(find.text('成功提示'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byKey(const Key('floatingToastCloseButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(find.byKey(const Key('floatingToast')), findsNothing);
  });

  testWidgets('新提示立即替换旧提示', (tester) async {
    await _pumpHost(tester);

    await tester.tap(find.text('第一条'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('第一条消息'), findsOneWidget);

    await tester.tap(find.text('第二条'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('第一条消息'), findsNothing);
    expect(find.text('第二条消息'), findsOneWidget);
    expect(find.byKey(const Key('floatingToast')), findsOneWidget);
  });
}

Future<void> _pumpHost(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const FluentApp(home: _ToastHost()));
  await tester.pump();
}

class _ToastHost extends StatelessWidget {
  const _ToastHost();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Button(
            onPressed: () => showFloatingToast(context, '已保存'),
            child: const Text('成功提示'),
          ),
          Button(
            onPressed: () => showFloatingToast(
              context,
              '加载失败，请检查配置文件后重试。',
              type: FloatingToastType.error,
              duration: const Duration(seconds: 5),
            ),
            child: const Text('错误提示'),
          ),
          Button(
            onPressed: () => showFloatingToast(context, '第一条消息'),
            child: const Text('第一条'),
          ),
          Button(
            onPressed: () => showFloatingToast(context, '第二条消息'),
            child: const Text('第二条'),
          ),
        ],
      ),
    );
  }
}
