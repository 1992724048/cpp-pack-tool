import 'dart:io';

import 'package:cpp_nuget_pack/util/repo_icon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseRepoLocation', () {
    test('GitHub https 地址解析属主并规范化', () {
      final RepoLocation location = parseRepoLocation(
        'https://github.com/madler/zlib',
      )!;

      expect(location.platform, RepoPlatform.github);
      expect(location.owner, 'madler');
      expect(location.webUrl, 'https://github.com/madler/zlib');
    });

    test('去 .git 后缀与尾斜杠', () {
      final RepoLocation location = parseRepoLocation(
        'https://github.com/madler/zlib.git/',
      )!;

      expect(location.owner, 'madler');
      expect(location.webUrl, 'https://github.com/madler/zlib');
    });

    test('scp 形态转 https', () {
      final RepoLocation location = parseRepoLocation(
        'git@github.com:madler/zlib.git',
      )!;

      expect(location.platform, RepoPlatform.github);
      expect(location.owner, 'madler');
      expect(location.webUrl, 'https://github.com/madler/zlib');
    });

    test('GitLab 完整路径含子组', () {
      final RepoLocation location = parseRepoLocation(
        'https://gitlab.com/group/sub/proj.git',
      )!;

      expect(location.platform, RepoPlatform.gitlab);
      expect(location.owner, 'group/sub/proj');
      expect(location.webUrl, 'https://gitlab.com/group/sub/proj');
    });

    test('主机名大小写不敏感', () {
      expect(
        parseRepoLocation('https://GitHub.com/madler/zlib')?.platform,
        RepoPlatform.github,
      );
    });

    test('不可辨识的托管与本地路径返回 null', () {
      expect(parseRepoLocation('https://gitea.example.com/a/b'), isNull);
      expect(parseRepoLocation(r'D:\repos\zlib'), isNull);
      expect(parseRepoLocation('foo'), isNull);
      expect(parseRepoLocation(''), isNull);
    });
  });

  group('openableRepoWebUrl', () {
    test('http/https 规范化（去 .git / 去尾斜杠）', () {
      expect(
        openableRepoWebUrl('https://example.com/a/b.git'),
        'https://example.com/a/b',
      );
      expect(
        openableRepoWebUrl('http://example.com/a/'),
        'http://example.com/a',
      );
    });

    test('scp 形态转换为 https', () {
      expect(
        openableRepoWebUrl('git@gitlab.com:gnutls/gnutls.git'),
        'https://gitlab.com/gnutls/gnutls',
      );
    });

    test('本地路径与空串返回 null', () {
      expect(openableRepoWebUrl(r'D:\repos\zlib'), isNull);
      expect(openableRepoWebUrl('foo'), isNull);
      expect(openableRepoWebUrl('  '), isNull);
      expect(openableRepoWebUrl(r'git@D:\repos\zlib'), isNull);
    });
  });

  group('githubAvatarUrl', () {
    test('按属主构造头像 CDN 地址', () {
      expect(
        githubAvatarUrl('madler'),
        'https://avatars.githubusercontent.com/madler?s=128',
      );
      expect(
        githubAvatarUrl('madler', size: 64),
        'https://avatars.githubusercontent.com/madler?s=64',
      );
    });
  });

  group('extensionForContentType', () {
    test('已知类型映射扩展名', () {
      expect(extensionForContentType('image/png'), 'png');
      expect(extensionForContentType('image/jpeg'), 'jpg');
      expect(extensionForContentType('image/jpg'), 'jpg');
      expect(extensionForContentType('image/gif'), 'gif');
      expect(extensionForContentType('image/webp'), 'webp');
      expect(extensionForContentType('image/svg+xml'), 'svg');
    });

    test('带参数与大小写归一', () {
      expect(extensionForContentType('IMAGE/PNG; charset=binary'), 'png');
    });

    test('缺失或未知回退 png', () {
      expect(extensionForContentType(null), 'png');
      expect(extensionForContentType('application/octet-stream'), 'png');
    });
  });

  group('ensureRepoAvatar', () {
    test('GitHub 获取成功后落盘且二次调用命中缓存', () async {
      final Directory temp = Directory.systemTemp.createTempSync('cnp_icon');
      addTearDown(() => temp.deleteSync(recursive: true));
      final List<Uri> requests = <Uri>[];

      Future<RepoIconResponse> fetcher(
        Uri uri, {
        required Duration timeout,
      }) async {
        requests.add(uri);
        return (
          statusCode: 200,
          contentType: 'image/png',
          bytes: <int>[1, 2, 3],
        );
      }

      final String? path = await ensureRepoAvatar(
        'https://github.com/madler/zlib',
        cacheRoot: temp.path,
        fetch: fetcher,
      );

      expect(path, isNotNull);
      expect(path, endsWith('madler.png'));
      expect(File(path!).readAsBytesSync(), <int>[1, 2, 3]);
      expect(
        requests.single.toString(),
        'https://avatars.githubusercontent.com/madler?s=128',
      );
      expect(File(path).parent.path, contains('icons'));
      expect(File(path).parent.path, endsWith('github'));

      requests.clear();
      final String? cached = await ensureRepoAvatar(
        'https://github.com/madler/zlib',
        cacheRoot: temp.path,
        fetch: fetcher,
      );

      expect(cached, isNotNull);
      expect(File(cached!).readAsBytesSync(), <int>[1, 2, 3]);
      expect(requests, isEmpty, reason: '命中磁盘缓存不重复请求');
    });

    test('缓存扫描忽略 .tmp 残留', () async {
      final Directory temp = Directory.systemTemp.createTempSync('cnp_icon');
      addTearDown(() => temp.deleteSync(recursive: true));
      final Directory github = Directory('${temp.path}/icons/github');
      github.createSync(recursive: true);
      File('${github.path}/madler.png.tmp').writeAsBytesSync(<int>[1]);
      int requests = 0;

      Future<RepoIconResponse> fetcher(
        Uri uri, {
        required Duration timeout,
      }) async {
        requests++;
        return (statusCode: 200, contentType: 'image/png', bytes: <int>[7, 7]);
      }

      final String? path = await ensureRepoAvatar(
        'https://github.com/madler/zlib',
        cacheRoot: temp.path,
        fetch: fetcher,
      );

      expect(requests, 1, reason: '.tmp 残留不得当作磁盘缓存命中');
      expect(path, isNotNull);
      expect(path, endsWith('madler.png'));
      expect(File('${github.path}/madler.png.tmp').existsSync(), isFalse);
    });

    test('GitLab 经 API 解析 avatar_url 后下载', () async {
      final Directory temp = Directory.systemTemp.createTempSync('cnp_icon');
      addTearDown(() => temp.deleteSync(recursive: true));
      final List<Uri> requests = <Uri>[];

      Future<RepoIconResponse> fetcher(
        Uri uri, {
        required Duration timeout,
      }) async {
        requests.add(uri);
        if (uri.host == 'gitlab.com' && uri.path.contains('/api/v4/')) {
          return (
            statusCode: 200,
            contentType: 'application/json',
            bytes: '{"avatar_url":"/uploads/group/proj.png"}'.codeUnits,
          );
        }
        return (statusCode: 200, contentType: 'image/png', bytes: <int>[9, 8, 7]);
      }

      final String? path = await ensureRepoAvatar(
        'https://gitlab.com/group/sub/proj.git',
        cacheRoot: temp.path,
        fetch: fetcher,
      );

      expect(path, isNotNull);
      expect(path, endsWith('group_sub_proj.png'));
      expect(
        requests.first.toString(),
        'https://gitlab.com/api/v4/projects/group%2Fsub%2Fproj',
      );
      expect(
        requests.last.toString(),
        'https://gitlab.com/uploads/group/proj.png',
      );
    });

    test('GitLab avatar_url 为 null 时静默返回 null', () async {
      final Directory temp = Directory.systemTemp.createTempSync('cnp_icon');
      addTearDown(() => temp.deleteSync(recursive: true));
      int calls = 0;

      Future<RepoIconResponse> fetcher(
        Uri uri, {
        required Duration timeout,
      }) async {
        calls++;
        return (
          statusCode: 200,
          contentType: 'application/json',
          bytes: '{"avatar_url":null}'.codeUnits,
        );
      }

      final String? path = await ensureRepoAvatar(
        'https://gitlab.com/gnutls/gnutls',
        cacheRoot: temp.path,
        fetch: fetcher,
      );

      expect(path, isNull);
      expect(calls, 1, reason: 'avatar_url 为 null 时不再发起下载');
    });

    test('请求失败与仓库不可辨识均静默返回 null', () async {
      final Directory temp = Directory.systemTemp.createTempSync('cnp_icon');
      addTearDown(() => temp.deleteSync(recursive: true));

      Future<RepoIconResponse> failing(
        Uri uri, {
        required Duration timeout,
      }) async {
        throw const SocketException('网络不可达');
      }

      expect(
        await ensureRepoAvatar(
          'https://github.com/madler/zlib',
          cacheRoot: temp.path,
          fetch: failing,
        ),
        isNull,
      );
      expect(
        await ensureRepoAvatar(
          'https://gitea.example.com/a/b',
          cacheRoot: temp.path,
          fetch: failing,
        ),
        isNull,
      );
    });

    test('非 200 响应不落盘', () async {
      final Directory temp = Directory.systemTemp.createTempSync('cnp_icon');
      addTearDown(() => temp.deleteSync(recursive: true));

      Future<RepoIconResponse> notFound(
        Uri uri, {
        required Duration timeout,
      }) async => (statusCode: 404, contentType: null, bytes: <int>[]);

      expect(
        await ensureRepoAvatar(
          'https://github.com/madler/zlib',
          cacheRoot: temp.path,
          fetch: notFound,
        ),
        isNull,
      );
      expect(
        Directory('${temp.path}/icons/github').existsSync(),
        isFalse,
        reason: '失败不创建缓存文件',
      );
    });
  });
}
