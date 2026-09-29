# notikit (Flutter)

> Notikit Flutter SDK — 유저 중심 푸시 디바이스 등록/식별.

[소개](https://notikit.mint-soft.com) · [서버](https://github.com/mintsoft-opensource/notikit) · 다른 SDK: [JS](https://github.com/mintsoft-opensource/notikit-js) · [iOS](https://github.com/mintsoft-opensource/notikit-ios) · [Android](https://github.com/mintsoft-opensource/notikit-android)

## 설치
```yaml
dependencies:
  notikit: ^0.2.0
  firebase_messaging: ^15.0.0
```

## 사용
```dart
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:notikit/notikit.dart';

final notikit = Notikit(
  baseUrl: 'https://push.example.com',
  apiKey: 'nk_xxx', // 공개키만
);

await FirebaseMessaging.instance.requestPermission();
final token = await FirebaseMessaging.instance.getToken();
await notikit.registerDevice(
  token: token!,
  platform: Platform.isIOS ? 'ios' : 'android',
  userId: 'user-123', // 고객 서비스의 유저 id
  identityHash: '<서버계산 HMAC>',
);
```

### 수신(도달) 보고
콘솔의 "도달" 수는 앱이 `reportReceived` 를 불러야 올라간다 — 부르지 않으면 늘 0 이다.
알림을 **받은 순간**(포그라운드 `onMessage`, 백그라운드 `onBackgroundMessage`)에 부른다.
같은 발송을 다시 받으면 요청 없이 `null` 을 돌려준다.

```dart
FirebaseMessaging.onMessage.listen((m) async {
  final logId = Notikit.logIdFromPayload(m.data);
  final token = await FirebaseMessaging.instance.getToken();
  if (logId != null && token != null) await notikit.reportReceived(logId: logId, token: token);
});

// 백그라운드 핸들러는 최상위 함수여야 한다(별도 isolate 에서 실행)
@pragma('vm:entry-point')
Future<void> onBackground(RemoteMessage m) async {
  final logId = Notikit.logIdFromPayload(m.data);
  final token = await FirebaseMessaging.instance.getToken();
  if (logId == null || token == null) return;
  final notikit = Notikit(baseUrl: 'https://push.example.com', apiKey: 'nk_xxx');
  try {
    await notikit.reportReceived(logId: logId, token: token);
  } finally {
    notikit.close();
  }
}

FirebaseMessaging.onBackgroundMessage(onBackground);
```

### 토큰 교체
FCM 토큰은 언제든 바뀐다. 새 토큰으로 `registerDevice` 를 다시 부르면 행이 하나 더 생겨
같은 사람에게 중복 발송되므로, 갱신 스트림을 한 번만 붙인다:

```dart
final sub = notikit.attachTokenRefresh(
  FirebaseMessaging.instance.onTokenRefresh,
  onError: (e) => debugPrint('notikit token rotation failed: $e'),
);
```

SDK 는 마지막으로 등록에 성공한 토큰에서 새 토큰으로 `rotateToken` 을 부른다. 서버가 교체하지
못하면(`rotated: false` — 모르는 옛 토큰·identity 증명 실패·충돌) 마지막 `registerDevice` 의
`userId`·`identityHash` 로(없으면 익명으로) 새 토큰을 **자동 재등록**한다. 로그아웃
(`unbindDevice`) 뒤에는 유저를 잊으므로 익명으로 재등록된다. 기억은 프로세스 메모리에만 있으니
앱 시작 시 `registerDevice` 는 계속 부른다.

직접 부를 때는 결과로 무슨 일이 있었는지 알 수 있다:

```dart
final r = await notikit.rotateToken(oldToken: old, newToken: fresh);
switch (r.outcome) {
  case TokenRotationOutcome.rotated: // 제자리 교체 — 기기 id·구독·이력 유지
  case TokenRotationOutcome.registered: // 교체 거절 → 새 토큰으로 재등록
  case TokenRotationOutcome.unchanged: // 같은 토큰 — 요청 없음
}
```

재등록마저 실패하면 예외를 던진다. `r['rotated']` 처럼 응답 Map 으로 읽던 0.1.x 코드도 그대로 동작한다.

## API
| | 설명 |
|---|---|
| `registerDevice(...)` | FCM 토큰 등록 |
| `identify(userId: ...)` | 유저 식별 |
| `subscribe(topic, token)` | 토픽 구독 |
| `unsubscribe(topic, token)` | 토픽 구독 해지 |
| `rotateToken(oldToken: ..., newToken: ...)` | 토큰 교체. 서버가 거절하면 새 토큰을 자동 재등록 |
| `attachTokenRefresh(onTokenRefresh)` | 토큰 갱신 스트림을 붙여 교체 자동화 |
| `unbindDevice(token: ..., platform: ...)` | 로그아웃 — 유저 바인딩 해제 |
| `reportReceived(logId: ..., token: ...)` | 수신(도달) 보고. 이미 보고한 발송이면 요청 없이 `null` |
| `Notikit.customDataFromPayload(message.data)` | 받은 푸시에서 커스텀 필드(템플릿 필드 포함)만 꺼내기 |
| `Notikit.deepLinkFromPayload(message.data)` | 받은 푸시의 딥링크 |

> `externalId` 파라미터(서버 필드 `external_id`)도 계속 동작하지만 deprecated 다 — `userId` 를 쓴다. SDK 는 항상 `user_id` 로 전송한다.

## 라이선스
Apache-2.0
