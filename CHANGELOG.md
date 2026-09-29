# Changelog

## 0.2.0

- 토큰 교체 자동화: `rotateToken` 이 서버의 `rotated: false`(모르는 옛 토큰·identity 증명 실패·충돌)를 받으면 마지막 `registerDevice` 의 유저·identityHash 로(없으면 익명으로) 새 토큰을 재등록한다. 재등록도 실패하면 던진다. 같은 토큰이면 요청하지 않는다.
- `rotateToken` 은 `TokenRotation` 을 돌려준다 — `outcome`(`rotated`·`registered`·`unchanged`)이 더해진 응답 Map 이라 기존 `r['rotated']` 호출부는 그대로 동작한다. 재등록용 `platform` 인자(생략 시 마지막 등록의 플랫폼)를 추가했다.
- `attachTokenRefresh(stream)`: `FirebaseMessaging.instance.onTokenRefresh` 를 넘기면 마지막 등록 토큰에서 순서대로 교체한다. firebase 의존성은 추가하지 않았다.
- `unbindDevice` 는 기억해 둔 유저를 잊는다 — 로그아웃 뒤 교체가 이전 유저로 재등록하지 않게.
- `reportReceived(logId:, token:)`: 푸시 수신(도달) 보고. 같은 발송은 한 번만 보내고, 네트워크 오류·5xx·429 일 때만 다시 보낼 수 있게 한다.
- 알림 탭 보고가 실패하면 기억을 되돌려 다음 탭에서 다시 보고한다.
- `customDataFromPayload` 가 `actions` 키를 커스텀 필드에서 뺀다.
- README: 예제가 `Platform` 을 쓰도록 `dart:io` import 를 추가했다.

## 0.1.1

- 문서: 홈페이지를 notikit.mint-soft.com 으로 바꾸고, README 에 소개 사이트·서버·다른 SDK 링크를 추가했다. 코드 변경 없음.

## 0.1.0

- 최초 릴리즈: 디바이스 등록, 유저 바인딩/해제, 알림 탭 보고(`attachTapStream`), 콜드 스타트 초기 메시지 처리.
