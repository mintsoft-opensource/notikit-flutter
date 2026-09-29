/// Notikit Flutter SDK — 유저 중심 푸시 등록/식별.
///
/// FCM 토큰은 firebase_messaging 플러그인이 획득하고, 이 SDK 가 서버에 등록한다.
library notikit;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:http/http.dart' as http;

class NotikitException implements Exception {
  final String message;
  final int status;
  NotikitException(this.message, this.status);
  @override
  String toString() => 'NotikitException($status): $message';
}

/// [Notikit.rotateToken] 이 실제로 한 일.
enum TokenRotationOutcome {
  /// 서버가 기존 행의 토큰을 제자리에서 바꿨다 — 기기 id·토픽 구독·클릭 이력이 그대로다.
  rotated,

  /// 서버가 교체하지 못해(`rotated: false`) 새 토큰을 [Notikit.registerDevice] 로 등록했다.
  registered,

  /// 옛 토큰과 새 토큰이 같아 아무 요청도 보내지 않았다.
  unchanged,
}

/// [Notikit.rotateToken] 의 결과.
///
/// 0.1.x 는 서버 응답 `Map` 을 그대로 돌려줬다. 그 호출부(`r['rotated']`)가 깨지지 않도록
/// 응답 Map 을 그대로 감싸고 [outcome] 만 더한다.
class TokenRotation extends MapView<String, dynamic> {
  final TokenRotationOutcome outcome;
  TokenRotation(this.outcome, Map<String, dynamic> response) : super(response);
}

class Notikit {
  final String baseUrl;

  /// 공개 api-key 만 사용 (발송용 api-secret 은 클라이언트에 넣지 않음).
  final String apiKey;
  final http.Client _client;
  /// 우리가 만든 클라이언트만 닫는다 — 주입받은 것은 소유자가 따로 있다
  final bool _ownsClient;

  Notikit({
    required String baseUrl,
    required this.apiKey,
    http.Client? client,
  })  : baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// 연결 풀을 해제한다. 직접 만든 클라이언트가 아니면 아무것도 하지 않는다.
  /// 없으면 SDK 를 버려도 내부 클라이언트의 연결이 남는다.
  void close() {
    if (_ownsClient) _client.close();
  }

  /// 미지정(null) 필드를 제거하고 전송 — 서버가 기존 값을 유지하게 한다.
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) {
    return _postRaw(path, Map<String, dynamic>.from(body)..removeWhere((_, v) => v == null));
  }

  /// null 을 그대로 실어 전송 — 명시적 해제(user_id: null)와 미지정을 구분해야 할 때.
  Future<Map<String, dynamic>> _postRaw(String path, Map<String, dynamic> body) async {
    final headers = <String, String>{
      'content-type': 'application/json',
      'api-key': apiKey,
    };

    final res = await _client.post(Uri.parse('$baseUrl$path'), headers: headers, body: jsonEncode(body));

    Map<String, dynamic> json;
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw NotikitException('Invalid response', res.statusCode);
    }
    // `as String?` 로 단정하면 안 된다 — 게이트웨이나 프록시가 error 를 객체로 주면
    // NotikitException 대신 raw TypeError 가 튀어 방어적 파싱이 무의미해진다.
    if (res.statusCode >= 400 || json['success'] != true) {
      final err = json['error'];
      throw NotikitException(err is String ? err : 'Request failed', res.statusCode);
    }
    final data = json['data'];
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  /// 마지막으로 등록에 성공한 토큰·플랫폼·유저. 토큰 교체가 서버에서 거절될 때
  /// 새 토큰을 같은 유저로 다시 등록하려면 앱에 되묻지 않고 알고 있어야 한다.
  ///
  /// 프로세스 메모리에만 둔다 — 앱은 시작할 때마다 [registerDevice] 를 부르므로 그때 다시 채워진다.
  String? _lastToken;
  String? _lastPlatform;
  String? _userId;
  String? _identityHash;

  /// 디바이스/토큰 등록 (user id 바인딩 시 identityHash 필요)
  ///
  /// user id 없이 부르면 서버는 기존 바인딩을 유지한다 — 그래서 기억해 둔 유저도 지우지 않는다.
  /// 유저를 떼려면 [unbindDevice] 를 부른다.
  Future<Map<String, dynamic>> registerDevice({
    required String token,
    required String platform,
    String? userId,
    @Deprecated('Use userId') String? externalId,
    String? identityHash,
    String? locale,
    String? timezone,
  }) async {
    final uid = userId ?? externalId;
    final data = await _post('/api/v1/devices', {
      'token': token,
      'platform': platform,
      'user_id': uid,
      'identity_hash': uid != null ? identityHash : null,
      'locale': locale,
      'timezone': timezone,
    });
    _lastToken = token;
    _lastPlatform = platform;
    if (uid != null) {
      _userId = uid;
      _identityHash = identityHash;
    }
    return data;
  }

  /// 유저 식별 — userId 는 고객 서비스의 유저 id
  Future<Map<String, dynamic>> identify({
    String? userId,
    @Deprecated('Use userId') String? externalId,
    String? identityHash,
    Map<String, dynamic>? attributes,
    /// 치환 변수 {{name}} 과 콘솔 표시에 쓰인다
    String? name,
  }) {
    final uid = userId ?? externalId;
    if (uid == null) throw ArgumentError('userId is required');
    return _post('/api/v1/users/identify', {
      'user_id': uid,
      'identity_hash': identityHash,
      'name': name,
      'attributes': attributes,
    });
  }

  /// 앱 열림 보고 — 접속 통계(DAU/WAU/MAU)의 원천.
  ///
  /// registerDevice 는 무거우므로 앱을 열 때마다는 이쪽을 쓴다.
  Future<Map<String, dynamic>> ping(String token) {
    return _post('/api/v1/devices/ping', {'token': token});
  }

  /// 토픽 구독.
  ///
  /// 규칙으로 채워지는 토픽은 명단이 자동으로 정해지므로 409 가 온다.
  Future<Map<String, dynamic>> subscribe(String topic, String token) {
    return _post('/api/v1/topics/subscribe', {'topic': topic, 'token': token});
  }

  /// 토픽 구독 해지.
  ///
  /// 알림 설정 토글을 끄는 경로다. 이게 없으면 유저가 한 번 켠 토픽을 앱에서 끌 수 없다.
  /// 구독과 달리 없는 토픽을 만들지 않는다 — 없으면 404.
  Future<Map<String, dynamic>> unsubscribe(String topic, String token) {
    return _post('/api/v1/topics/unsubscribe', {'topic': topic, 'token': token});
  }

  /// 푸시 토큰 교체 (FirebaseMessaging.onTokenRefresh).
  ///
  /// 새 토큰으로 registerDevice 를 부르면 **행이 하나 더 생긴다** — 옛 행이 유저
  /// 바인딩을 유지한 채 활성으로 남아 같은 사람에게 중복 발송된다. 서버가 기존 행의
  /// 토큰을 제자리 갱신하게 해 기기 id·토픽 구독·클릭 이력을 보존한다.
  ///
  /// 서버는 교체하지 못해도(모르는 옛 토큰·identity 증명 실패·충돌) 202 `{rotated: false}` 로
  /// 답한다 — 오라클이 되지 않으려고 이유를 가르지 않는다. 그걸 성공으로 보면 새 토큰은
  /// 어디에도 등록되지 않아 이 기기로 발송이 끊긴다. 그래서 마지막 [registerDevice] 의
  /// 유저·identityHash 로(없으면 익명으로) 새 토큰을 직접 등록한다. 그것마저 실패하면 던진다.
  ///
  /// [identityHash] 를 주지 않으면 기억해 둔 값을 쓴다. [platform] 은 재등록에만 쓰이며,
  /// 주지 않으면 마지막 등록의 플랫폼을 쓴다 — 둘 다 없으면 재등록할 수 없어 [StateError].
  ///
  /// 반환값은 서버 응답 Map 이기도 해서 기존 `r['rotated']` 호출부가 그대로 동작한다.
  Future<TokenRotation> rotateToken({
    required String oldToken,
    required String newToken,
    String? identityHash,
    String? platform,
  }) async {
    if (oldToken == newToken) {
      return TokenRotation(TokenRotationOutcome.unchanged, {'rotated': false});
    }
    final hash = identityHash ?? _identityHash;
    final res = await _post('/api/v1/devices/rotate', {
      'old_token': oldToken,
      'new_token': newToken,
      'identity_hash': hash,
    });
    if (res['rotated'] == true) {
      if (_lastToken == oldToken) _lastToken = newToken;
      return TokenRotation(TokenRotationOutcome.rotated, res);
    }

    final plat = platform ?? _lastPlatform;
    if (plat == null) {
      throw StateError('rotateToken: server did not rotate and no platform is known to re-register');
    }
    // registerDevice 가 성공하면 _lastToken 도 새 토큰으로 옮겨진다
    await registerDevice(token: newToken, platform: plat, userId: _userId, identityHash: hash);
    return TokenRotation(TokenRotationOutcome.registered, res);
  }

  /// 토큰 갱신 스트림을 붙여 교체를 자동화한다.
  ///
  /// firebase_messaging 에 의존하지 않으려고 스트림을 **인자로 받는다**:
  ///
  ///     final sub = notikit.attachTokenRefresh(FirebaseMessaging.instance.onTokenRefresh);
  ///
  /// 옛 토큰은 마지막으로 등록(또는 교체)에 성공한 토큰이다. 아직 [registerDevice] 가
  /// 성공한 적이 없으면 갱신을 건너뛴다 — 앱 시작 시 등록이 새 토큰을 싣고 간다.
  ///
  /// 갱신은 **하나씩 순서대로** 처리한다. 겹치면 두 번째 교체가 첫 교체 결과를 모른 채
  /// 같은 옛 토큰에서 출발해 서버가 거절하고 불필요한 재등록이 나간다.
  /// 실패는 [onError] 로만 알린다 — 토큰 갱신 실패가 앱을 죽이면 안 된다. 실패하면
  /// 옛 토큰이 그대로 남아 다음 갱신이 거기서 다시 시도한다.
  ///
  /// 반환한 구독은 앱 종료 시 취소한다.
  StreamSubscription<String> attachTokenRefresh(
    Stream<String> onRefresh, {
    void Function(Object error)? onError,
  }) {
    var chain = Future<void>.value();
    return onRefresh.listen(
      (fresh) {
        chain = chain.then((_) async {
          final old = _lastToken;
          if (old == null) return;
          try {
            await rotateToken(oldToken: old, newToken: fresh);
          } catch (e) {
            onError?.call(e);
          }
        });
      },
      onError: (Object e) => onError?.call(e),
    );
  }

  /// 디바이스 바인딩 해제 (로그아웃/계정전환).
  ///
  /// 해제하지 않으면 이후 클릭이 이전 계정에 계속 귀속된다.
  /// `_post` 가 null 값을 제거하므로 명시적 해제는 별도 경로로 보낸다.
  Future<Map<String, dynamic>> unbindDevice({
    required String token,
    required String platform,
    String? identityHash,
  }) {
    // 요청 **전에** 잊는다 — 해제가 실패해도 이후 토큰 교체가 로그아웃한 유저로 재등록하면 안 된다
    _userId = null;
    _identityHash = null;
    return _postRaw('/api/v1/devices', {
      'token': token,
      'platform': platform,
      // 서버가 현재 바인딩된 유저의 해시를 검증한다 — 남의 토큰으로 해제하는 것을 막는다
      if (identityHash != null) 'identity_hash': identityHash,
      'user_id': null,
    });
  }

  /// 푸시 클릭(알림 탭) 보고.
  ///
  /// 유저는 서버가 토큰의 바인딩에서 해석하므로 user id 를 보내지 않는다.
  Future<Map<String, dynamic>> reportClick({
    required String logId,
    required String token,
    String? destination,
  }) {
    return _post('/api/v1/messages/click', {
      'log_id': logId,
      'token': token,
      'destination': destination,
    });
  }

  /// 수신 보고 중복 방지 — 이미 보고한 발송 id. 삽입 순서를 지켜 오래된 것부터 버린다.
  ///
  /// FCM·APNs 는 같은 메시지를 다시 배달할 수 있다. 서버가 (발송, 기기) 유니크로 한 번만
  /// 세지만, 기억하지 않으면 재배달마다 요청이 한 번씩 더 나가 수신 보고 rate limit 을
  /// 깎아먹는다. 프로세스 안에서만 유효한 기억이다 — 놓친 중복은 낭비된 요청 한 건으로 끝난다.
  final LinkedHashSet<String> _receivedLogIds = LinkedHashSet<String>();

  /// 한 프로세스가 기억하는 수신 보고 발송 id 수
  static const int receiptDedupeSize = 200;

  /// 푸시 **수신** 보고 — 단말이 실제로 알림을 받았다는 사실을 남긴다.
  ///
  /// FCM 접수(발송 성공)는 기기가 꺼져 있어도 성공한다. 앱이 이걸 부르지 않으면 콘솔의
  /// "도달" 칸은 영원히 0 이다. 부르는 자리는 **알림을 받은 순간** —
  /// `FirebaseMessaging.onMessage`(포그라운드)와 `onBackgroundMessage`(백그라운드) 핸들러다.
  ///
  /// 같은 발송을 두 번 이상 부르면 요청을 내보내지 않고 `null` 을 돌려준다.
  /// 보고했으면 서버가 새로 기록했는지(`recorded`)를 돌려준다.
  Future<bool?> reportReceived({required String logId, required String token}) async {
    // 보고 **전에** 잡아 둔다 — 두 번째 배달이 첫 요청의 응답을 기다리는 사이에 끼어들 수 있다
    if (logId.isEmpty || !_receivedLogIds.add(logId)) return null;
    if (_receivedLogIds.length > receiptDedupeSize) _receivedLogIds.remove(_receivedLogIds.first);
    try {
      final data = await _post('/api/v1/messages/received', {'log_id': logId, 'token': token});
      return data['recorded'] == true;
    } catch (e) {
      // 4xx 는 다시 보내도 같은 답이다(없는 발송·수신자 아님) — 기억을 유지한다.
      // 네트워크 장애·5xx·429 만 풀어 줘서 다음 배달·재시도에 다시 보고하게 한다.
      if (e is! NotikitException || e.status >= 500 || e.status == 429) _receivedLogIds.remove(logId);
      rethrow;
    }
  }

  /// 알림 탭 처리 — `RemoteMessage.data` 를 그대로 넘기면 된다.
  ///
  /// 탭 스트림(`FirebaseMessaging.onMessageOpenedApp`, `getInitialMessage`)은 앱이
  /// 구독하는 것이라 SDK 가 가로챌 수 없다. 앱에서 이렇게 연결한다:
  ///
  ///     FirebaseMessaging.onMessageOpenedApp.listen((m) {
  ///       notikit.handleNotificationOpen(data: m.data, token: token);
  ///     });
  ///     final initial = await FirebaseMessaging.instance.getInitialMessage();
  ///     if (initial != null) await notikit.handleNotificationOpen(data: initial.data, token: token);
  ///
  /// notikit 이 보낸 알림이 아니면 아무 것도 하지 않는다 — 다른 경로의 알림까지
  /// 클릭으로 세면 클릭률이 부풀려진다.
  Future<bool> handleNotificationOpen({
    required Map<String, dynamic>? data,
    required String token,
    String? destination,
  }) async {
    final logId = logIdFromPayload(data);
    if (logId == null) return false;
    await reportClick(logId: logId, token: token, destination: destination);
    return true;
  }

  /// 알림 탭 스트림을 붙여 클릭 보고를 자동화한다.
  ///
  /// firebase_messaging 에 의존하지 않으려고 스트림과 초기 메시지를 **인자로 받는다**.
  /// 앱에서 한 번만 연결하면 이후 탭은 자동으로 보고된다:
  ///
  ///     final sub = notikit.attachTapStream(
  ///       onOpened: FirebaseMessaging.onMessageOpenedApp.map((m) => m.data),
  ///       initialMessage: (await FirebaseMessaging.instance.getInitialMessage())?.data,
  ///       token: () => currentToken,
  ///     );
  ///
  /// 토큰은 갱신될 수 있어 값이 아니라 콜백으로 받는다 — 값으로 받으면 갱신 후
  /// 클릭이 서버에서 매칭되지 않는다.
  ///
  /// 반환한 구독은 앱 종료 시 취소한다.
  StreamSubscription<Map<String, dynamic>> attachTapStream({
    required Stream<Map<String, dynamic>> onOpened,
    required String? Function() token,
    Map<String, dynamic>? initialMessage,
  }) {
    // 앱이 알림 탭으로 콜드 스타트된 경우 — 스트림에는 오지 않으므로 따로 처리한다
    if (initialMessage != null) {
      _reportTap(initialMessage, token);
    }

    return onOpened.listen(
      (data) => _reportTap(data, token),
      // onError 가 없으면 스트림 자체의 에러가 uncaught 로 샌다.
      // 탭 보고 실패가 앱을 죽이면 안 된다.
      onError: (_) {},
    );
  }

  /// 이미 보고한 발송 — initState/hot reload 로 attachTapStream 이 두 번 불리면
  /// 구독이 둘 다 살아 탭당 2회, initialMessage 도 다시 보고된다. 서버가 (발송, 기기)
  /// 유니크로 막아 통계는 안 틀리지만 불필요한 요청이 그대로 나간다.
  final Set<String> _reportedLogIds = {};

  void _reportTap(Map<String, dynamic> data, String? Function() token) {
    final logId = logIdFromPayload(data);
    if (logId == null || !_reportedLogIds.add(logId)) return;
    final tok = token();
    if (tok == null) {
      _reportedLogIds.remove(logId); // 토큰이 생기면 다시 시도할 수 있게 되돌린다
      return;
    }
    // 보고 실패가 앱 흐름을 막지 않는다. 실패하면 기억을 되돌려 다음 탭이 다시 보고하게 한다 —
    // 남겨 두면 오프라인에서 한 번 실패한 탭은 영영 보고되지 않는다.
    unawaited(handleNotificationOpen(data: data, token: tok).catchError((_) {
      _reportedLogIds.remove(logId);
      return false;
    }));
  }

  /// 푸시 페이로드에서 notikit 이 예약해 쓰는 data 키
  static const String logIdKey = 'notikit_log_id';

  /// FCM data 에서 발송 id 추출 — 없으면 notikit 발송이 아니다
  static String? logIdFromPayload(Map<String, dynamic>? data) {
    final v = data?[logIdKey];
    return (v is String && v.isNotEmpty) ? v : null;
  }

  /// 푸시 data 에서 딥링크 추출
  static String? deepLinkFromPayload(Map<String, dynamic>? data) {
    final v = data?['deep_link'];
    return (v is String && v.isNotEmpty) ? v : null;
  }

  /// notikit·FCM 이 쓰는 키. 이것을 뺀 나머지가 발송 때 넣은 커스텀 필드다(서버의 금지 키 목록과 같다).
  static const Set<String> _internalKeys = {
    'deep_link', logIdKey, 'actions', 'title', 'body', 'icon', 'image',
    'aps', 'from', 'collapse_key', 'notification', 'message_type', 'fcm_options',
  };
  static const List<String> _internalPrefixes = ['google.', 'gcm.'];

  /// 발송 때 넣은 커스텀 필드(템플릿 필드 포함)만 골라낸다. `RemoteMessage.data` 를 그대로 넘기면 된다.
  static Map<String, String> customDataFromPayload(Map<String, dynamic>? data) {
    final out = <String, String>{};
    data?.forEach((k, v) {
      if (_internalKeys.contains(k) || _internalPrefixes.any(k.startsWith)) return;
      if (v is String) out[k] = v;
    });
    return out;
  }
}
