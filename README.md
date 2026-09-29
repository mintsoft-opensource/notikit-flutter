# notikit (Flutter)

> Notikit Flutter SDK — 유저 중심 푸시 디바이스 등록/식별.

[소개](https://notikit.mint-soft.com) · [서버](https://github.com/mintsoft-opensource/notikit) · 다른 SDK: [JS](https://github.com/mintsoft-opensource/notikit-js) · [iOS](https://github.com/mintsoft-opensource/notikit-ios) · [Android](https://github.com/mintsoft-opensource/notikit-android)

## 설치
```yaml
dependencies:
  notikit: ^0.1.0
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

## API
| | 설명 |
|---|---|
| `registerDevice(...)` | FCM 토큰 등록 |
| `identify(userId: ...)` | 유저 식별 |
| `subscribe(topic, token)` | 토픽 구독 |
| `unsubscribe(topic, token)` | 토픽 구독 해지 |
| `reportReceived(logId: ..., token: ...)` | 수신(도달) 보고. 이미 보고한 발송이면 요청 없이 `null` |
| `Notikit.customDataFromPayload(message.data)` | 받은 푸시에서 커스텀 필드(템플릿 필드 포함)만 꺼내기 |
| `Notikit.deepLinkFromPayload(message.data)` | 받은 푸시의 딥링크 |

> `externalId` 파라미터(서버 필드 `external_id`)도 계속 동작하지만 deprecated 다 — `userId` 를 쓴다. SDK 는 항상 `user_id` 로 전송한다.

## 라이선스
Apache-2.0
