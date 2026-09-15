import 'dart:io';

import 'package:cpp_nuget_pack/models/settings_model.dart';
import 'package:cpp_nuget_pack/util/proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseProxyEndpoint', () {
    test('host 缺端口用缺省 1080', () {
      final ProxyEndpoint endpoint = parseProxyEndpoint('127.0.0.1')!;

      expect(endpoint.host, '127.0.0.1');
      expect(endpoint.port, defaultManualProxyPort);
      expect(endpoint.scheme, 'http');
      expect(endpoint.authority, '127.0.0.1:1080');
      expect(endpoint.url, 'http://127.0.0.1:1080');
    });

    test('host:port / scheme://host:port / user:pass@host:port', () {
      final ProxyEndpoint bare = parseProxyEndpoint('10.0.0.1:7890')!;
      expect(bare.host, '10.0.0.1');
      expect(bare.port, 7890);

      final ProxyEndpoint scheme = parseProxyEndpoint('http://proxy.corp:8080')!;
      expect(scheme.host, 'proxy.corp');
      expect(scheme.port, 8080);
      expect(scheme.url, 'http://proxy.corp:8080');

      final ProxyEndpoint credentials = parseProxyEndpoint(
        'user:pass@10.0.0.1:3128',
      )!;
      expect(credentials.host, '10.0.0.1');
      expect(credentials.port, 3128);
      expect(credentials.userInfo, 'user:pass');
      expect(credentials.url, 'http://user:pass@10.0.0.1:3128');
      expect(credentials.authority, '10.0.0.1:3128');
    });

    test('IPv6 字面量与非法输入', () {
      final ProxyEndpoint ipv6 = parseProxyEndpoint('[::1]:8080')!;
      expect(ipv6.host, '::1');
      expect(ipv6.port, 8080);

      expect(parseProxyEndpoint(''), isNull);
      expect(parseProxyEndpoint('   '), isNull);
      expect(parseProxyEndpoint('http://'), isNull);
      expect(parseProxyEndpoint('host:0'), isNull);
      expect(parseProxyEndpoint('host:70000'), isNull);
      expect(parseProxyEndpoint('host:abc'), isNull);
    });

    test('parseManualProxy：空地址直连、端口字段覆盖地址端口', () {
      expect(parseManualProxy('', 7890), isNull);
      expect(parseManualProxy('   ', null), isNull);

      final ProxyEndpoint fromHost = parseManualProxy('127.0.0.1:8888', null)!;
      expect(fromHost.port, 8888);

      final ProxyEndpoint overridden = parseManualProxy(
        'http://127.0.0.1:8888',
        7890,
      )!;
      expect(overridden.host, '127.0.0.1');
      expect(overridden.port, 7890);
      expect(overridden.scheme, 'http');
    });
  });

  group('parseWindowsProxyServer', () {
    test('单一 host:port 为通用端点', () {
      final WindowsProxyServerValue value = parseWindowsProxyServer(
        '127.0.0.1:7890',
      );

      expect(value.common?.authority, '127.0.0.1:7890');
      expect(value.http, isNull);
      expect(value.https, isNull);
    });

    test('http=/https= 分协议；socks 等其他协议忽略', () {
      final WindowsProxyServerValue value = parseWindowsProxyServer(
        'http=proxy-a:80;https=proxy-b:443;socks=socks5:1080',
      );

      expect(value.common, isNull);
      expect(value.http?.authority, 'proxy-a:80');
      expect(value.https?.authority, 'proxy-b:443');
    });

    test('空值与非法值不产生端点', () {
      expect(parseWindowsProxyServer('').common, isNull);
      expect(parseWindowsProxyServer('http=').http, isNull);
      expect(parseWindowsProxyServer('host:0').common, isNull);
    });
  });

  test('parseWindowsProxyOverride：* 与 <local> 忽略、*.example.com 归一为后缀', () {
    expect(
      parseWindowsProxyOverride('*.example.com; <local>; *; 10.0.0.0/8;'),
      <String>['.example.com', '10.0.0.0/8'],
    );
    expect(parseWindowsProxyOverride('192.168.*'), isEmpty);
    expect(parseWindowsProxyOverride(''), isEmpty);
  });

  test('parseRegistryQueryOutput：值名/类型/值解析，空值保留空串', () {
    const String output = '''
HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings
    ProxyEnable    REG_DWORD    0x1
    ProxyServer    REG_SZ    127.0.0.1:7890
    ProxyOverride    REG_SZ    <local>
    AutoConfigURL    REG_SZ
''';

    final Map<String, String> values = parseRegistryQueryOutput(output);

    expect(values['ProxyEnable'], '0x1');
    expect(values['ProxyServer'], '127.0.0.1:7890');
    expect(values['ProxyOverride'], '<local>');
    expect(values['AutoConfigURL'], '');
  });

  group('ProxyResolution', () {
    const ProxyEndpoint manual = ProxyEndpoint(host: '127.0.0.1', port: 7890);

    test('findProxyFor：通用端点双协议可用，无代理 DIRECT', () {
      const ProxyResolution resolution = ProxyResolution(
        mode: ProxyModeSetting.manual,
        httpProxy: manual,
        httpsProxy: manual,
      );

      expect(
        resolution.findProxyFor(Uri.parse('https://github.com')),
        'PROXY 127.0.0.1:7890; DIRECT',
      );
      expect(
        resolution.findProxyFor(Uri.parse('http://example.com')),
        'PROXY 127.0.0.1:7890; DIRECT',
      );

      const ProxyResolution direct = ProxyResolution(mode: ProxyModeSetting.off);
      expect(direct.findProxyFor(Uri.parse('https://github.com')), 'DIRECT');
      expect(
        const ProxyResolution(mode: ProxyModeSetting.auto).findProxyFor(
          Uri.parse('https://github.com'),
        ),
        'DIRECT',
      );
    });

    test('findProxyFor：分协议端点各取所需', () {
      const ProxyResolution resolution = ProxyResolution(
        mode: ProxyModeSetting.auto,
        httpProxy: ProxyEndpoint(host: 'proxy-a', port: 80),
        httpsProxy: ProxyEndpoint(host: 'proxy-b', port: 443),
      );

      expect(
        resolution.findProxyFor(Uri.parse('http://x')),
        'PROXY proxy-a:80; DIRECT',
      );
      expect(
        resolution.findProxyFor(Uri.parse('https://x')),
        'PROXY proxy-b:443; DIRECT',
      );
    });

    test('environmentEntries：HTTP/HTTPS/NO_PROXY；直连为空', () {
      const ProxyResolution resolution = ProxyResolution(
        mode: ProxyModeSetting.auto,
        httpProxy: ProxyEndpoint(host: 'proxy-a', port: 80),
        httpsProxy: ProxyEndpoint(host: 'proxy-b', port: 443),
        noProxyEntries: <String>['.example.com'],
      );

      final Map<String, String> entries = resolution.environmentEntries();

      expect(entries['HTTP_PROXY'], 'http://proxy-a:80');
      expect(entries['HTTPS_PROXY'], 'http://proxy-b:443');
      expect(entries['NO_PROXY'], 'localhost,127.0.0.1,.example.com');
      expect(
        const ProxyResolution(mode: ProxyModeSetting.off).environmentEntries(),
        isEmpty,
      );
    });

    test('gitGlobalArguments：仅手动模式输出 -c http.proxy', () {
      const ProxyResolution manualResolution = ProxyResolution(
        mode: ProxyModeSetting.manual,
        httpProxy: manual,
        httpsProxy: manual,
      );
      expect(
        manualResolution.gitGlobalArguments(),
        <String>['-c', 'http.proxy=http://127.0.0.1:7890'],
      );

      const ProxyResolution auto = ProxyResolution(
        mode: ProxyModeSetting.auto,
        httpProxy: manual,
      );
      expect(auto.gitGlobalArguments(), isEmpty);
      expect(
        const ProxyResolution(mode: ProxyModeSetting.off).gitGlobalArguments(),
        isEmpty,
      );
    });
  });

  group('environment overrides', () {
    test('启用：写入大写键并按大小写不敏感替换既有键', () {
      const ProxyResolution resolution = ProxyResolution(
        mode: ProxyModeSetting.manual,
        httpProxy: ProxyEndpoint(host: '127.0.0.1', port: 7890),
        httpsProxy: ProxyEndpoint(host: '127.0.0.1', port: 7890),
      );
      final Map<String, String> environment = <String, String>{
        'http_proxy': 'http://old:1',
        'HTTPS_PROXY': 'http://old:2',
        'Path': r'C:\bin',
      };

      applyProxyEnvironment(environment, resolution);

      expect(environment['HTTP_PROXY'], 'http://127.0.0.1:7890');
      expect(environment['HTTPS_PROXY'], 'http://127.0.0.1:7890');
      expect(environment['NO_PROXY'], 'localhost,127.0.0.1');
      expect(environment.containsKey('http_proxy'), isFalse);
      expect(environment['Path'], r'C:\bin');
    });

    test('关闭：快照既有代理变量清空（保留键名）', () {
      final Map<String, String> environment = <String, String>{
        'HTTP_PROXY': 'http://old:1',
        'no_proxy': 'example.com',
        'Path': r'C:\bin',
      };

      applyProxyEnvironment(
        environment,
        const ProxyResolution(mode: ProxyModeSetting.off),
      );

      expect(environment['HTTP_PROXY'], '');
      expect(environment['no_proxy'], '');
      expect(environment['Path'], r'C:\bin');
    });

    test('proxyEnvironmentOverrides：无继承时关闭模式不写入任何键', () {
      expect(
        proxyEnvironmentOverrides(
          const ProxyResolution(mode: ProxyModeSetting.off),
          inherited: <String, String>{'Path': r'C:\bin'},
        ),
        isEmpty,
      );
      expect(
        proxyEnvironmentOverrides(
          const ProxyResolution(mode: ProxyModeSetting.off),
          inherited: <String, String>{'https_proxy': 'http://old'},
        ),
        <String, String>{'https_proxy': ''},
      );
    });
  });

  group('detectSystemProxy', () {
    test('ProxyEnable=1 时按 ProxyServer/ProxyOverride 启用', () async {
      final ProxyResolution resolution = await detectSystemProxy(
        runner: _runner(<String, Map<String, String>>{
          proxyMachineRegistryKey: <String, String>{
            'ProxySettingsPerUser': '0x1',
          },
          proxyUserRegistryKey: <String, String>{
            'ProxyEnable': '0x1',
            'ProxyServer': 'http=proxy-a:80;https=proxy-b:443',
            'ProxyOverride': '*.example.com;<local>;*',
          },
        }),
      );

      expect(resolution.mode, ProxyModeSetting.auto);
      expect(resolution.httpProxy?.authority, 'proxy-a:80');
      expect(resolution.httpsProxy?.authority, 'proxy-b:443');
      expect(resolution.noProxyEntries, <String>['.example.com']);
    });

    test('ProxyEnable=0 时直连（含仅配置 PAC 的场景）', () async {
      final ProxyResolution disabled = await detectSystemProxy(
        runner: _runner(<String, Map<String, String>>{
          proxyUserRegistryKey: <String, String>{
            'ProxyEnable': '0x0',
            'ProxyServer': '127.0.0.1:7890',
          },
        }),
      );
      expect(disabled.isActive, isFalse);

      final ProxyResolution pacOnly = await detectSystemProxy(
        runner: _runner(<String, Map<String, String>>{
          proxyUserRegistryKey: <String, String>{
            'ProxyEnable': '0x0',
            'AutoConfigURL': 'http://wpad/wpad.dat',
          },
        }),
      );
      expect(pacOnly.isActive, isFalse);
      expect(pacOnly.findProxyFor(Uri.parse('https://x')), 'DIRECT');
    });

    test('ProxySettingsPerUser=0 时以 HKLM 同名键为数据源', () async {
      final ProxyResolution resolution = await detectSystemProxy(
        runner: _runner(<String, Map<String, String>>{
          proxyMachineRegistryKey: <String, String>{
            'ProxySettingsPerUser': '0x0',
            'ProxyEnable': '0x1',
            'ProxyServer': 'proxy.corp:8080',
          },
          proxyUserRegistryKey: <String, String>{
            'ProxyEnable': '0x0',
          },
        }),
      );

      expect(resolution.httpProxy?.authority, 'proxy.corp:8080');
      expect(resolution.httpsProxy?.authority, 'proxy.corp:8080');
    });

    test('注册表读取失败（非零退出/异常）退直连', () async {
      final ProxyResolution failed = await detectSystemProxy(
        runner: (String executable, List<String> arguments) async =>
            ProcessResult(0, 1, '', ''),
      );
      expect(failed.isActive, isFalse);

      final ProxyResolution thrown = await detectSystemProxy(
        runner: (String executable, List<String> arguments) async =>
            throw ProcessException(executable, arguments),
      );
      expect(thrown.isActive, isFalse);
    });
  });

  test('resolveProxyFromSettings：off/manual/auto 与旧配置默认', () async {
    final ProxyResolution off = await resolveProxyFromSettings(
      const SettingsModel(),
      runner: _runner(const <String, Map<String, String>>{}),
    );
    expect(off.mode, ProxyModeSetting.off);

    final ProxyResolution manual = await resolveProxyFromSettings(
      const SettingsModel(
        proxyMode: ProxyModeSetting.manual,
        proxyHost: '127.0.0.1',
        proxyPort: 7890,
      ),
    );
    expect(manual.gitGlobalArguments(), <String>[
      '-c',
      'http.proxy=http://127.0.0.1:7890',
    ]);

    final ProxyResolution auto = await resolveProxyFromSettings(
      const SettingsModel(proxyMode: ProxyModeSetting.auto),
      runner: _runner(<String, Map<String, String>>{
        proxyUserRegistryKey: <String, String>{
          'ProxyEnable': '0x1',
          'ProxyServer': '127.0.0.1:1080',
        },
      }),
    );
    expect(auto.httpProxy?.authority, '127.0.0.1:1080');
  });
}

/// 注册表查询替身：按键返回 `reg query` 形态输出，未知键返回非零退出。
ProxyRegistryRunner _runner(Map<String, Map<String, String>> byKey) {
  return (String executable, List<String> arguments) async {
    final String key = arguments.length >= 2 ? arguments[1] : '';
    final Map<String, String>? values = byKey[key];
    if (values == null) {
      return ProcessResult(0, 1, '', '');
    }
    final StringBuffer buffer = StringBuffer('$key\r\n');
    for (final MapEntry<String, String> entry in values.entries) {
      final String type = entry.value.startsWith('0x') ? 'REG_DWORD' : 'REG_SZ';
      buffer.write('    ${entry.key}    $type    ${entry.value}\r\n');
    }
    return ProcessResult(0, 0, buffer.toString(), '');
  };
}
