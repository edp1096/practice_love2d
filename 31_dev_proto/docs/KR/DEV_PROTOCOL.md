# 31_dev_proto 디버그·테스트 프로토콜

`31_dev_proto`에는 실제 LÖVE 프레임버퍼와 Lua 월드 객체를 함께 다루는
로컬 개발 프로토콜이 있다. 일반 실행에서는 모듈 자체를 로드하지 않는다.

## 실행

Lua 라이브러리용 `vendor/`와 Go 모듈이 충돌하지 않도록 컨트롤러는
`tools/lovectl` 안에서 독립 모듈로 관리한다.

```bash
cd 31_dev_proto/tools/lovectl
go build -o /tmp/lovectl .
```

첫 번째 터미널에서 디버그 브리지가 활성화된 LÖVE를 실행한다.

```bash
/tmp/lovectl run
```

기본 주소는 `127.0.0.1:19785`이다. 포트를 바꾸려면 실행과 제어 명령
모두에 `--port 19800`을 지정한다. 서버는 외부 인터페이스에 바인딩하지
않으며 임의 Lua 실행 기능도 제공하지 않는다.

두 번째 터미널의 CLI 예:

```bash
/tmp/lovectl ping
/tmp/lovectl state
/tmp/lovectl start
/tmp/lovectl pause true
/tmp/lovectl world
/tmp/lovectl position player 200 160
/tmp/lovectl health player 50
/tmp/lovectl step --frames 1
/tmp/lovectl overlay true
/tmp/lovectl screenshot /tmp/game.png
/tmp/lovectl quit
```

## 객체 모델

`World.getSnapshot`은 한 프레임의 다음 정보를 JSON으로 반환한다.

- 맵 크기·타일 크기·게임 모드와 카메라
- 플레이어, 적, NPC, 아이템, 소품, 탈것, 회복점, 세이브포인트
- 벽 충돌체, 전환 구역, 데스존, 대미지존
- 월드 좌표, 물리 속도·충돌 클래스·AABB
- 실제 창 기준 화면 좌표와 현재 가시성

각 객체에는 같은 월드가 유지되는 동안 안정적인 `id`가 붙는다.
플레이어 ID는 항상 `player`이다. 맵 ID가 있는 객체는
`enemy:level1_area1_obj_40` 같은 형태가 된다.

허용된 제어 명령은 다음과 같다.

| 명령 | 용도 |
| --- | --- |
| `Entity.get` | ID로 현재 객체 상태 조회 |
| `Entity.setPosition` | 객체와 연결된 충돌체를 함께 이동 |
| `Entity.setHealth` | `health` 또는 `hp` 변경 |
| `Entity.setProperty` | 제한된 속성만 타입을 검사해 변경 |
| `World.worldToScreen` | 월드 좌표를 실제 창 좌표로 변환 |
| `Overlay.set` | 객체 ID·AABB·벽을 실제 화면에 중첩 |

`Entity.setProperty`의 허용 속성은 `active`, `can_interact`, `cooldown`,
`direction`, `health`, `hp`, `max_health`, `max_hp`, `quantity`,
`state`이다. 새 제어가 필요하면 inspector의 명시적 허용 목록에 추가한다.

## 결정적 테스트 제어

`Test.setPaused`로 게임 시뮬레이션만 멈춰도 창 렌더와 디버그 소켓은 계속
동작한다. `Test.step`은 정해진 `dt`로 1~600 프레임을 진행한다. 입력,
상태 조회, 스크린샷을 프레임 경계에 맞춰 재현할 때 사용한다.

## 자동 검사

빠른 검사는 모든 Lua 소스 문법, Go 프로토콜 테스트, Lua 단위 테스트를
실행한다.

```bash
cd 31_dev_proto/tools/lovectl
go run . check
```

`check`는 `web/game.love` 안의 파일까지 현재 소스와 바이트 단위로
비교한다. 소스가 바뀌어 웹 패키지가 오래된 상태면 다음 명령으로 정해진
파일만 정렬·고정 시각으로 다시 묶는다.

```bash
go run . package
```

패키지에는 실행에 필요한 `assets`, `engine`, `game`, `vendor`와 루트
런타임 파일만 들어가며 `.claude`, 문서, 테스트, 도구와 웹 파일 자체는
들어가지 않는다. 로컬 사용자 설정인 `config.ini`도 포함하지 않고
`conf.lua`의 기본값을 사용한다.

시각 통합 테스트는 LÖVE 프로세스를 직접 띄워 메뉴와 게임 화면을 캡처하고,
월드 조회, 플레이어 좌표·체력 제어, 적 조회, 고정 프레임 진행, 오버레이를
검증한 뒤 프로세스를 정상 종료한다.

```bash
cd 31_dev_proto/tools/lovectl
go run . test
```

결과 PNG, JSON 보고서, LÖVE 로그는 출력된 임시 폴더에 남는다. 경로를
고정하려면 `go run . test --artifacts /tmp/love-test`를 사용한다.
테스트 프로세스는 인스턴스 락을 사용하지 않으므로 정상
플레이 실행과 충돌하거나 권한 창을 띄우지 않는다. Go 컨트롤러는 표준
라이브러리만 사용하며 별도 런타임이나 외부 Go 모듈에 의존하지 않는다.
