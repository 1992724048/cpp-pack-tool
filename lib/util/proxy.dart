import 'dart:io';

import 'package:cpp_nuget_pack/models/settings_model.dart';

/// 手动代理地址缺省端口（地址未声明端口且端口字段留空时使用）。
const int defaultManualProxyPort = 1080;

/// 代理相关环境变量键（关闭模式清除快照既有同名键时同样使用）。
const List<String> proxyEnvironmentKeys = <String>[
  'HTTP_PROXY',
  'HTTPS_PROXY',
  'NO_PROXY',
];

/// 本地地址恒不作为代理对象（NO_PROXY 基础条目）。
const List<String> _localNoProxyEntries = <String>['localhost', '127.0.0.1'];

/// 用户注册表键（`ProxySettingsPerUser` 非 0 时的数据源）。
const String proxyUserRegistryKey =
    r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

/// 机器注册表键（`ProxySettingsPerUser = 0` 时的数据源）。
const String proxyMachineRegistryKey =
    r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings';

/// 注册表读取执行器（`reg query`）；测试可注入替代实现。
typedef ProxyRegistryRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// 代理端点（scheme 缺省 `http`；`userInfo` 供环境变量 URL 携带凭据）。
class ProxyEndpoint {
  const ProxyEndpoint({
    required this.host,
    required this.port,
    this.scheme = 'http',
    this.userInfo = '',
  });

  final String host;
  final int port;
  final String scheme;

  /// `user:password`（可空）；`findProxy` 串不支持凭据，仅在环境变量 URL 中携带。
  final String userInfo;

  /// `host:port`（`findProxy` 串与 NO_PROXY 语义）。
  String get authority => '$host:$port';

  /// 完整 URL（`scheme://[user:pass@]host:port`），供环境变量使用。
  String get url =>
      userInfo.isEmpty ? '$scheme://$authority' : '$scheme://$userInfo@$authority';
}

/// 解析后的代理配置：off / auto / manual 归一为「用哪个代理 / 直连」。
///
/// [findProxyFor] / [environmentEntries] / [gitGlobalArguments] 是设置到运行侧的
/// 唯一来源，避免各调用点各自解释设置。
class ProxyResolution {
  const ProxyResolution({
    required this.mode,
    this.httpProxy,
    this.httpsProxy,
    this.noProxyEntries = const <String>[],
  });

  final ProxyModeSetting mode;
  final ProxyEndpoint? httpProxy;
  final ProxyEndpoint? httpsProxy;

  /// 系统 `ProxyOverride` 映射出的附加 NO_PROXY 条目。
  final List<String> noProxyEntries;

  bool get isActive => httpProxy != null || httpsProxy != null;

  /// Dart `HttpClient.findProxy` 回调串：`PROXY host:port; DIRECT`——连接失败时
  /// 由 Dart 自动回退直连；无可用代理时为 `DIRECT`。
  String findProxyFor(Uri uri) {
    final ProxyEndpoint? endpoint = uri.scheme == 'https'
        ? (httpsProxy ?? httpProxy)
        : (httpProxy ?? httpsProxy);
    return endpoint == null ? 'DIRECT' : 'PROXY ${endpoint.authority}; DIRECT';
  }

  /// 子进程环境变量条目（大写键）：HTTP_PROXY / HTTPS_PROXY / NO_PROXY；
  /// 直连时为空表。
  Map<String, String> environmentEntries() {
    if (!isActive) {
      return const <String, String>{};
    }
    final Map<String, String> entries = <String, String>{};
    final ProxyEndpoint? http = httpProxy ?? httpsProxy;
    final ProxyEndpoint? https = httpsProxy ?? httpProxy;
    if (http != null) {
      entries['HTTP_PROXY'] = http.url;
    }
    if (https != null) {
      entries['HTTPS_PROXY'] = https.url;
    }
    entries['NO_PROXY'] = noProxyValue();
    return entries;
  }

  /// NO_PROXY 值：附加条目 + 恒含 `localhost,127.0.0.1`，按序去重。
  String noProxyValue() {
    final List<String> entries = <String>[];
    final Set<String> seen = <String>{};
    for (final String entry in <String>[
      ..._localNoProxyEntries,
      ...noProxyEntries,
    ]) {
      if (seen.add(entry)) {
        entries.add(entry);
      }
    }
    return entries.join(',');
  }

  /// git 命令全局参数（手动模式；配置优先于环境变量）：`-c http.proxy=<url>`。
  List<String> gitGlobalArguments() {
    if (mode != ProxyModeSetting.manual) {
      return const <String>[];
    }
    final ProxyEndpoint? endpoint = httpProxy ?? httpsProxy;
    return endpoint == null
        ? const <String>[]
        : <String>['-c', 'http.proxy=${endpoint.url}'];
  }
}

/// 设置 → 代理解析（应用网络请求与构建子进程的统一入口）。
Future<ProxyResolution> resolveProxyFromSettings(
  SettingsModel settings, {
  ProxyRegistryRunner runner = Process.run,
}) async {
  switch (settings.proxyMode) {
    case ProxyModeSetting.off:
      return const ProxyResolution(mode: ProxyModeSetting.off);
    case ProxyModeSetting.manual:
      final ProxyEndpoint? endpoint = parseManualProxy(
        settings.proxyHost,
        settings.proxyPort,
      );
      return ProxyResolution(
        mode: ProxyModeSetting.manual,
        httpProxy: endpoint,
        httpsProxy: endpoint,
      );
    case ProxyModeSetting.auto:
      return detectSystemProxy(runner: runner);
  }
}

/// 手动设置解析：地址支持 `host` / `host:port` / `scheme://host:port` /
/// `user:pass@host:port`；[port] 非空时覆盖地址中声明的端口，地址与端口均未
/// 声明端口时用 [defaultManualProxyPort]；地址为空返回 null（直连）。
ProxyEndpoint? parseManualProxy(String host, int? port) {
  final String trimmed = host.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (port != null && port >= 1 && port <= 65535) {
    final ProxyEndpoint? endpoint = parseProxyEndpoint(trimmed);
    if (endpoint == null) {
      return null;
    }
    return ProxyEndpoint(
      host: endpoint.host,
      port: port,
      scheme: endpoint.scheme,
      userInfo: endpoint.userInfo,
    );
  }
  return parseProxyEndpoint(trimmed);
}

/// 代理地址字面量解析（见 [parseManualProxy]）；无法解析或 host 为空返回 null。
ProxyEndpoint? parseProxyEndpoint(String value, {int defaultPort = 1080}) {
  final String raw = value.trim();
  if (raw.isEmpty) {
    return null;
  }
  if (raw.contains('://')) {
    final Uri? uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }
    final int port = uri.hasPort ? uri.port : defaultPort;
    if (port < 1 || port > 65535) {
      return null;
    }
    return ProxyEndpoint(
      host: uri.host,
      port: port,
      scheme: uri.scheme.isEmpty ? 'http' : uri.scheme,
      userInfo: uri.userInfo,
    );
  }
  String authority = raw;
  String userInfo = '';
  final int at = authority.lastIndexOf('@');
  if (at >= 0) {
    userInfo = authority.substring(0, at);
    authority = authority.substring(at + 1);
  }
  if (authority.startsWith('[')) {
    final int close = authority.indexOf(']');
    if (close < 0) {
      return null;
    }
    final String host = authority.substring(1, close);
    final String rest = authority.substring(close + 1);
    if (host.isEmpty) {
      return null;
    }
    if (rest.isEmpty) {
      return ProxyEndpoint(host: host, port: defaultPort, userInfo: userInfo);
    }
    if (!rest.startsWith(':')) {
      return null;
    }
    final int? port = int.tryParse(rest.substring(1));
    if (port == null || port < 1 || port > 65535) {
      return null;
    }
    return ProxyEndpoint(host: host, port: port, userInfo: userInfo);
  }
  final int colon = authority.lastIndexOf(':');
  if (colon >= 0) {
    final String host = authority.substring(0, colon);
    final int? port = int.tryParse(authority.substring(colon + 1));
    if (host.isEmpty || port == null || port < 1 || port > 65535) {
      return null;
    }
    return ProxyEndpoint(host: host, port: port, userInfo: userInfo);
  }
  if (authority.isEmpty) {
    return null;
  }
  return ProxyEndpoint(host: authority, port: defaultPort, userInfo: userInfo);
}

/// Windows `ProxyServer` 值：`host:port` 通用形态或 `http=`/`https=` 分协议形态。
class WindowsProxyServerValue {
  const WindowsProxyServerValue({this.common, this.http, this.https});

  final ProxyEndpoint? common;
  final ProxyEndpoint? http;
  final ProxyEndpoint? https;
}

/// 解析 Windows `ProxyServer` 注册表值（`socks=` 等其他协议条目本期不透传）。
WindowsProxyServerValue parseWindowsProxyServer(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    return const WindowsProxyServerValue();
  }
  if (!trimmed.contains('=')) {
    return WindowsProxyServerValue(common: parseProxyEndpoint(trimmed));
  }
  ProxyEndpoint? http;
  ProxyEndpoint? https;
  for (final String part in trimmed.split(';')) {
    final int separator = part.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    final String key = part.substring(0, separator).trim().toLowerCase();
    final ProxyEndpoint? endpoint = parseProxyEndpoint(
      part.substring(separator + 1),
    );
    if (endpoint == null) {
      continue;
    }
    switch (key) {
      case 'http':
        http = endpoint;
      case 'https':
        https = endpoint;
    }
  }
  return WindowsProxyServerValue(http: http, https: https);
}

/// `ProxyOverride` 分号列表 → Dart NO_PROXY 条目（后缀匹配语义）：
/// `*`（全部绕过）与 `<local>`（内网直连）无对应语义，忽略；
/// `*.example.com` 归一为 `.example.com`；其余含 `*` 的条目（如 `192.168.*`）
/// 无法表达，忽略。
List<String> parseWindowsProxyOverride(String value) {
  final List<String> entries = <String>[];
  for (final String raw in value.split(';')) {
    final String entry = raw.trim();
    if (entry.isEmpty || entry == '*' || entry.startsWith('<')) {
      continue;
    }
    final String normalized = entry.startsWith('*.')
        ? entry.substring(1)
        : entry;
    if (normalized.contains('*')) {
      continue;
    }
    entries.add(normalized);
  }
  return entries;
}

/// `reg query` 输出解析：`    ProxyEnable    REG_DWORD    0x1` → 值名到值；
/// 空值条目保留空串，无法识别的行忽略。
Map<String, String> parseRegistryQueryOutput(String output) {
  final Map<String, String> values = <String, String>{};
  final RegExp pattern = RegExp(r'^\s+(\S+)\s+(REG_[A-Z_]+)(?:\s+(.*))?$');
  for (final String line in output.split(RegExp(r'\r?\n'))) {
    final RegExpMatch? match = pattern.firstMatch(line);
    if (match == null) {
      continue;
    }
    values[match.group(1)!] = (match.group(3) ?? '').trim();
  }
  return values;
}

/// 自动检测：读 Windows 系统代理设置。
///
/// 先查 `ProxySettingsPerUser`（HKLM）：为 0 时以 HKLM 同名键为数据源（机器级），
/// 否则用 HKCU；`ProxyEnable = 1` 且 `ProxyServer` 可解析出端点时启用静态代理，
/// 否则直连——`AutoConfigURL`（PAC）本期不支持，按不可用退直连。
Future<ProxyResolution> detectSystemProxy({
  ProxyRegistryRunner runner = Process.run,
}) async {
  final Map<String, String> machineValues = await _queryRegistryKey(
    runner,
    proxyMachineRegistryKey,
  );
  final bool perUser = _registryInt(machineValues['ProxySettingsPerUser']) != 0;
  final Map<String, String> values = perUser
      ? await _queryRegistryKey(runner, proxyUserRegistryKey)
      : machineValues;
  if (_registryInt(values['ProxyEnable']) != 1) {
    return const ProxyResolution(mode: ProxyModeSetting.auto);
  }
  final WindowsProxyServerValue server = parseWindowsProxyServer(
    values['ProxyServer'] ?? '',
  );
  final ProxyEndpoint? http = server.http ?? server.common;
  final ProxyEndpoint? https = server.https ?? server.common;
  if (http == null && https == null) {
    return const ProxyResolution(mode: ProxyModeSetting.auto);
  }
  return ProxyResolution(
    mode: ProxyModeSetting.auto,
    httpProxy: http,
    httpsProxy: https,
    noProxyEntries: parseWindowsProxyOverride(
      values['ProxyOverride'] ?? '',
    ),
  );
}

/// 给 [client] 应用代理解析（`findProxy` 三档都显式赋值，覆盖框架默认的
/// 环境变量读取）与可选超时。
void configureHttpClient(
  HttpClient client,
  ProxyResolution resolution, {
  Duration? connectionTimeout,
  Duration? idleTimeout,
}) {
  client.findProxy = resolution.findProxyFor;
  if (connectionTimeout != null) {
    client.connectionTimeout = connectionTimeout;
  }
  if (idleTimeout != null) {
    client.idleTimeout = idleTimeout;
  }
}

/// 生成子进程代理环境覆盖层：
/// - 启用：`HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY`（大写，不双写）；
/// - 关闭 / 直连：[inherited]（缺省 `Platform.environment`）中存在的大小写变体
///   以空串覆盖——Dart 子进程默认合并父环境，删除键无法阻止继承，空串等效关闭。
Map<String, String> proxyEnvironmentOverrides(
  ProxyResolution resolution, {
  Map<String, String>? inherited,
}) {
  if (resolution.isActive) {
    return resolution.environmentEntries();
  }
  final Map<String, String> overrides = <String, String>{};
  final Map<String, String> base = inherited ?? Platform.environment;
  for (final String key in proxyEnvironmentKeys) {
    final String? existing = _findKeyIgnoreCase(base, key);
    if (existing != null) {
      overrides[existing] = '';
    }
  }
  return overrides;
}

/// 把 [resolution] 写入构建环境快照（大小写不敏感、保留原键名，值按覆盖层
/// 语义：启用时写入代理 URL，关闭时置空清除）。
void applyProxyEnvironment(
  Map<String, String> environment,
  ProxyResolution resolution,
) {
  for (final MapEntry<String, String> entry
      in proxyEnvironmentOverrides(resolution, inherited: environment).entries) {
    _setEnvironmentValue(environment, entry.key, entry.value);
  }
}

Future<Map<String, String>> _queryRegistryKey(
  ProxyRegistryRunner runner,
  String key,
) async {
  try {
    final ProcessResult result = await runner('reg', <String>['query', key]);
    if (result.exitCode != 0) {
      return const <String, String>{};
    }
    return parseRegistryQueryOutput('${result.stdout}');
  } on ProcessException {
    return const <String, String>{};
  }
}

int? _registryInt(String? value) {
  if (value == null) {
    return null;
  }
  final String raw = value.trim();
  if (raw.isEmpty) {
    return null;
  }
  try {
    if (raw.startsWith('0x') || raw.startsWith('0X')) {
      return int.parse(raw.substring(2), radix: 16);
    }
    return int.parse(raw);
  } on FormatException {
    return null;
  }
}

String? _findKeyIgnoreCase(Map<String, String> environment, String key) {
  final String normalized = key.toLowerCase();
  for (final String candidate in environment.keys) {
    if (candidate.toLowerCase() == normalized) {
      return candidate;
    }
  }
  return null;
}

void _setEnvironmentValue(
  Map<String, String> environment,
  String key,
  String value,
) {
  final String? existing = _findKeyIgnoreCase(environment, key);
  if (existing != null && existing != key) {
    environment.remove(existing);
  }
  environment[key] = value;
}
