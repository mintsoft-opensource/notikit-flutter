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
  });
}
