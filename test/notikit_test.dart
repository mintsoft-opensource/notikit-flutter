import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:notikit/notikit.dart';

void main() {
  group('Notikit', () {
    test('registerDevice sends api-key and mapped payload', () async {
      late http.Request captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(jsonEncode({'success': true, 'data': {'device': {}}, 'error': null}), 201);
      });
      final notikit = Notikit(baseUrl: 'https://push.test/', apiKey: 'nk_test', client: mock);

      await notikit.registerDevice(token: 't1', platform: 'android', userId: 'u1', identityHash: 'h');

      expect(captured.headers['api-key'], 'nk_test');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['user_id'], 'u1');
      expect(body.containsKey('external_id'), isFalse);
      expect(body['identity_hash'], 'h');
      expect(body.containsKey('locale'), isFalse); // null 제거
    });

    test('throws NotikitException on failure', () async {
      final mock = MockClient((req) async =>
          http.Response(jsonEncode({'success': false, 'data': null, 'error': 'Unauthorized'}), 401));
      final notikit = Notikit(baseUrl: 'https://push.test', apiKey: 'nk', client: mock);

      expect(() => notikit.identify(userId: 'u1'), throwsA(isA<NotikitException>()));
    });

    test('omits api-secret when not provided', () async {
      late http.Request captured;
      final mock = MockClient((req) async {
        captured = req;
        return http.Response(jsonEncode({'success': true, 'data': {}, 'error': null}), 200);
      });
      final notikit = Notikit(baseUrl: 'https://push.test', apiKey: 'nk', client: mock);
      await notikit.subscribe('news', 't1');
      expect(captured.headers.containsKey('api-secret'), isFalse);
    });

    test('identify sends name and omits it when not given', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({'success': true, 'data': {'user': {}}, 'error': null}), 200);
      });
      final n = Notikit(baseUrl: 'https://push.test', apiKey: 'nk', client: client);
      await n.identify(userId: 'u1', name: '김민지');
      await n.identify(userId: 'u1');
      expect(bodies[0]['name'], '김민지');
      expect(bodies[1].containsKey('name'), isFalse);
    });

    group('deprecated externalId', () {
      late List<Map<String, dynamic>> bodies;
      late Notikit n;
      setUp(() {
        bodies = [];
        n = Notikit(
          baseUrl: 'https://push.test',
          apiKey: 'nk',
          client: MockClient((req) async {
            bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
            return http.Response(jsonEncode({'success': true, 'data': {}, 'error': null}), 200);
          }),
        );
      });

      test('registerDevice still binds, sent as user_id', () async {
        // ignore: deprecated_member_use_from_same_package
        await n.registerDevice(token: 't1', platform: 'ios', externalId: 'u1', identityHash: 'h');
        expect(bodies.single['user_id'], 'u1');
        expect(bodies.single['identity_hash'], 'h');
        expect(bodies.single.containsKey('external_id'), isFalse);
      });

      test('identify still works, sent as user_id', () async {
        // ignore: deprecated_member_use_from_same_package
        await n.identify(externalId: 'u1');
        expect(bodies.single['user_id'], 'u1');
        expect(bodies.single.containsKey('external_id'), isFalse);
      });

      test('userId wins over externalId', () async {
        // ignore: deprecated_member_use_from_same_package
        await n.identify(userId: 'new', externalId: 'old');
        expect(bodies.single['user_id'], 'new');
      });
    });

    test('identify without any user id throws ArgumentError', () {
      final n = Notikit(baseUrl: 'https://push.test', apiKey: 'nk', client: MockClient((_) async => http.Response('{}', 200)));
      expect(() => n.identify(), throwsArgumentError);
    });

    test('registerDevice without user id omits user_id and identity_hash', () async {
      late Map<String, dynamic> body;
      final n = Notikit(
        baseUrl: 'https://push.test',
        apiKey: 'nk',
        client: MockClient((req) async {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'success': true, 'data': {}, 'error': null}), 200);
        }),
      );
      await n.registerDevice(token: 't1', platform: 'android', identityHash: 'h');
      expect(body.containsKey('user_id'), isFalse);
      expect(body.containsKey('identity_hash'), isFalse);
    });

    test('unbindDevice sends explicit user_id null', () async {
      late Map<String, dynamic> body;
      final n = Notikit(
        baseUrl: 'https://push.test',
        apiKey: 'nk',
        client: MockClient((req) async {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'success': true, 'data': {}, 'error': null}), 200);
        }),
      );
      await n.unbindDevice(token: 't1', platform: 'android', identityHash: 'h');
      expect(body.containsKey('user_id'), isTrue);
      expect(body['user_id'], isNull);
      expect(body.containsKey('external_id'), isFalse);
      expect(body['identity_hash'], 'h');
    });

    test('customDataFromPayload skips notikit and FCM keys', () {
      final payload = <String, dynamic>{
        'notikit_log_id': 'log1',
        'deep_link': 'myapp://orders',
        'google.message_id': 'x',
        'gcm.n.e': '1',
        'from': '123',
        'order_id': 'A-1',
        'screen': 'order',
      };
      expect(Notikit.customDataFromPayload(payload), {'order_id': 'A-1', 'screen': 'order'});
      expect(Notikit.deepLinkFromPayload(payload), 'myapp://orders');
      expect(Notikit.customDataFromPayload(null), isEmpty);
    });

    test('customDataFromPayload skips actions', () {
      final payload = <String, dynamic>{
        'actions': '[{"id":"a","title":"A"}]',
        'order_id': 'A-1',
      };
      expect(Notikit.customDataFromPayload(payload), {'order_id': 'A-1'});
    });

    test('failed tap report can be reported again on a later tap', () async {
      var calls = 0;
      final n = Notikit(
        baseUrl: 'https://push.test',
        apiKey: 'nk',
        client: MockClient((req) async {
          calls++;
          if (calls == 1) {
            return http.Response(jsonEncode({'success': false, 'data': null, 'error': 'down'}), 503);
          }
          return http.Response(jsonEncode({'success': true, 'data': {'recorded': true}, 'error': null}), 202);
        }),
      );
      final taps = StreamController<Map<String, dynamic>>();
      final sub = n.attachTapStream(onOpened: taps.stream, token: () => 't1');
      taps.add({'notikit_log_id': 'log1'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      taps.add({'notikit_log_id': 'log1'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      taps.add({'notikit_log_id': 'log1'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, 2); // 실패 후 1회 재시도, 성공한 뒤로는 다시 보내지 않는다
      await sub.cancel();
      await taps.close();
    });

    group('reportReceived', () {
      late List<http.Request> requests;
      late List<int> statuses;
      late Notikit n;
      setUp(() {
        requests = [];
        statuses = [];
        n = Notikit(
          baseUrl: 'https://push.test',
          apiKey: 'nk',
          client: MockClient((req) async {
            requests.add(req);
            final status = statuses.isEmpty ? 202 : statuses.removeAt(0);
            if (status >= 400) {
              return http.Response(jsonEncode({'success': false, 'data': null, 'error': 'x'}), status);
            }
            return http.Response(jsonEncode({'success': true, 'data': {'recorded': true}, 'error': null}), status);
          }),
        );
      });

      test('posts log_id and token, then skips the same log', () async {
        expect(await n.reportReceived(logId: 'log1', token: 't1'), isTrue);
        expect(await n.reportReceived(logId: 'log1', token: 't1'), isNull);
        expect(requests, hasLength(1));
        expect(requests.single.url.path, '/api/v1/messages/received');
        expect(jsonDecode(requests.single.body), {'log_id': 'log1', 'token': 't1'});
      });

      test('empty log id sends nothing', () async {
        expect(await n.reportReceived(logId: '', token: 't1'), isNull);
        expect(requests, isEmpty);
      });

      test('forgets the log on 5xx and 429 so it can retry', () async {
        statuses.addAll([500, 429]);
        await expectLater(n.reportReceived(logId: 'log1', token: 't1'), throwsA(isA<NotikitException>()));
        await expectLater(n.reportReceived(logId: 'log1', token: 't1'), throwsA(isA<NotikitException>()));
        expect(await n.reportReceived(logId: 'log1', token: 't1'), isTrue);
        expect(requests, hasLength(3));
      });

      test('forgets the log on network error', () async {
        final flaky = Notikit(
          baseUrl: 'https://push.test',
          apiKey: 'nk',
          client: MockClient((req) async {
            requests.add(req);
            if (requests.length == 1) throw http.ClientException('offline');
            return http.Response(jsonEncode({'success': true, 'data': {'recorded': true}, 'error': null}), 202);
          }),
        );
        await expectLater(flaky.reportReceived(logId: 'log1', token: 't1'), throwsA(isA<http.ClientException>()));
        expect(await flaky.reportReceived(logId: 'log1', token: 't1'), isTrue);
      });

      test('keeps the log on 4xx so it is not retried', () async {
        statuses.add(404);
        await expectLater(n.reportReceived(logId: 'log1', token: 't1'), throwsA(isA<NotikitException>()));
        expect(await n.reportReceived(logId: 'log1', token: 't1'), isNull);
        expect(requests, hasLength(1));
      });

      test('remembers at most 200 logs, dropping the oldest', () async {
        for (var i = 0; i < 201; i++) {
          await n.reportReceived(logId: 'log$i', token: 't1');
        }
        expect(await n.reportReceived(logId: 'log0', token: 't1'), isTrue);
        expect(await n.reportReceived(logId: 'log200', token: 't1'), isNull);
      });
    });

    group('rotateToken', () {
      late List<http.Request> requests;
      late bool rotated;
      late int registerStatus;
      late Notikit n;

      http.Response ok(Map<String, dynamic> data, int status) =>
          http.Response(jsonEncode({'success': true, 'data': data, 'error': null}), status);

      List<String> paths() => requests.map((r) => r.url.path).toList();
      Map<String, dynamic> bodyOf(http.Request r) => jsonDecode(r.body) as Map<String, dynamic>;

      setUp(() {
        requests = [];
        rotated = true;
        registerStatus = 201;
        n = Notikit(
          baseUrl: 'https://push.test',
          apiKey: 'nk',
          client: MockClient((req) async {
            requests.add(req);
            if (req.url.path == '/api/v1/devices/rotate') return ok({'rotated': rotated}, 202);
            if (registerStatus >= 400) {
              return http.Response(jsonEncode({'success': false, 'data': null, 'error': 'x'}), registerStatus);
            }
            return ok({'device': {}}, registerStatus);
          }),
        );
      });

      test('same token does nothing', () async {
        final r = await n.rotateToken(oldToken: 't1', newToken: 't1');
        expect(r.outcome, TokenRotationOutcome.unchanged);
        expect(requests, isEmpty);
      });

      test('rotated in place does not re-register', () async {
        await n.registerDevice(token: 't1', platform: 'ios', userId: 'u1', identityHash: 'h');
        requests.clear();
        final r = await n.rotateToken(oldToken: 't1', newToken: 't2');
        expect(r.outcome, TokenRotationOutcome.rotated);
        expect(r['rotated'], isTrue);
        expect(paths(), ['/api/v1/devices/rotate']);
        expect(bodyOf(requests.single), {'old_token': 't1', 'new_token': 't2', 'identity_hash': 'h'});
      });

      test('rotated:false re-registers the new token with the remembered user', () async {
        await n.registerDevice(token: 't1', platform: 'ios', userId: 'u1', identityHash: 'h');
        requests.clear();
        rotated = false;
        final r = await n.rotateToken(oldToken: 't1', newToken: 't2');
        expect(r.outcome, TokenRotationOutcome.registered);
        expect(r['rotated'], isFalse);
        expect(paths(), ['/api/v1/devices/rotate', '/api/v1/devices']);
        expect(bodyOf(requests[1]), {'token': 't2', 'platform': 'ios', 'user_id': 'u1', 'identity_hash': 'h'});
      });

      test('rotated:false with no remembered user registers anonymously', () async {
        rotated = false;
        final r = await n.rotateToken(oldToken: 't1', newToken: 't2', platform: 'android');
        expect(r.outcome, TokenRotationOutcome.registered);
        expect(bodyOf(requests[1]), {'token': 't2', 'platform': 'android'});
      });

      test('rotated:false without a known platform throws StateError', () async {
        rotated = false;
        await expectLater(n.rotateToken(oldToken: 't1', newToken: 't2'), throwsStateError);
      });

      test('throws when the fallback registration also fails', () async {
        await n.registerDevice(token: 't1', platform: 'ios', userId: 'u1', identityHash: 'h');
        rotated = false;
        registerStatus = 403;
        await expectLater(n.rotateToken(oldToken: 't1', newToken: 't2'), throwsA(isA<NotikitException>()));
      });

      test('unbindDevice forgets the user so the fallback is anonymous', () async {
        await n.registerDevice(token: 't1', platform: 'ios', userId: 'u1', identityHash: 'h');
        await n.unbindDevice(token: 't1', platform: 'ios', identityHash: 'h');
        requests.clear();
        rotated = false;
        await n.rotateToken(oldToken: 't1', newToken: 't2');
        expect(bodyOf(requests.first).containsKey('identity_hash'), isFalse);
        expect(bodyOf(requests[1]), {'token': 't2', 'platform': 'ios'});
      });

      test('registering without a user keeps the remembered user', () async {
        await n.registerDevice(token: 't1', platform: 'ios', userId: 'u1', identityHash: 'h');
        await n.registerDevice(token: 't1', platform: 'ios');
        requests.clear();
        rotated = false;
        await n.rotateToken(oldToken: 't1', newToken: 't2');
        expect(bodyOf(requests[1])['user_id'], 'u1');
      });

      test('explicit identityHash wins over the remembered one', () async {
        await n.registerDevice(token: 't1', platform: 'ios', userId: 'u1', identityHash: 'h');
        requests.clear();
        await n.rotateToken(oldToken: 't1', newToken: 't2', identityHash: 'h2');
        expect(bodyOf(requests.single)['identity_hash'], 'h2');
      });

      test('result is still a Map for existing callers', () async {
        final Map<String, dynamic> r = await n.rotateToken(oldToken: 't1', newToken: 't2');
        expect(r['rotated'], isTrue);
      });
    });

    group('attachTokenRefresh', () {
      late List<http.Request> requests;
      late bool rotated;
      late Notikit n;

      setUp(() {
        requests = [];
        rotated = true;
        n = Notikit(
          baseUrl: 'https://push.test',
          apiKey: 'nk',
          client: MockClient((req) async {
            requests.add(req);
            final data = req.url.path == '/api/v1/devices/rotate' ? {'rotated': rotated} : {'device': {}};
            return http.Response(jsonEncode({'success': true, 'data': data, 'error': null}), 202);
          }),
        );
      });

      test('rotates from the last registered token, chaining successive refreshes', () async {
        await n.registerDevice(token: 't1', platform: 'ios', userId: 'u1', identityHash: 'h');
        requests.clear();
        final refresh = StreamController<String>();
        final sub = n.attachTokenRefresh(refresh.stream);
        refresh.add('t2');
        refresh.add('t3');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final bodies = requests.map((r) => jsonDecode(r.body) as Map<String, dynamic>).toList();
        expect(bodies.map((b) => [b['old_token'], b['new_token']]).toList(), [
          ['t1', 't2'],
          ['t2', 't3'],
        ]);
        await sub.cancel();
        await refresh.close();
      });

      test('ignores refreshes before any registration', () async {
        final refresh = StreamController<String>();
        final sub = n.attachTokenRefresh(refresh.stream);
        refresh.add('t2');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(requests, isEmpty);
        await sub.cancel();
        await refresh.close();
      });

      test('reports failures to onError and keeps the old token for the next try', () async {
        final errors = <Object>[];
        final failing = Notikit(
          baseUrl: 'https://push.test',
          apiKey: 'nk',
          client: MockClient((req) async {
            requests.add(req);
            if (req.url.path == '/api/v1/devices/rotate' && requests.length == 1) {
              throw http.ClientException('offline');
            }
            final data = req.url.path == '/api/v1/devices/rotate' ? {'rotated': true} : {'device': {}};
            return http.Response(jsonEncode({'success': true, 'data': data, 'error': null}), 202);
          }),
        );
        await failing.registerDevice(token: 't1', platform: 'ios');
        requests.clear();
        final refresh = StreamController<String>();
        final sub = failing.attachTokenRefresh(refresh.stream, onError: errors.add);
        refresh.add('t2');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(errors.single, isA<http.ClientException>());
        refresh.add('t3');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final last = jsonDecode(requests.last.body) as Map<String, dynamic>;
        expect([last['old_token'], last['new_token']], ['t1', 't3']);
        await sub.cancel();
        await refresh.close();
      });
    });
  });
}
