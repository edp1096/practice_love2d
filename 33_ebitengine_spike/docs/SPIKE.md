# Ebitengine 전환 검증

기준일: 2026-07-29

## 결론

Ebitengine은 이 프로젝트의 **차기 런타임 후보로 적합하다.**
LÖVE보다 공개 저장소 안에 콘솔별 진입점이 실제로 존재하고, gameplay를
Go의 플랫폼 중립 코드로 유지하기 쉽다. 이번 spike로 콘텐츠 변환,
결정적 액션 RPG 시뮬레이션, 실제 Ubuntu arm64 화면, 원격 자동화까지
하나의 실행본으로 연결했다.

다만 `32_recreate`를 지금 삭제하거나 본 런타임을 즉시 교체하면 안 된다.
현재는 프로세스 재시작을 포함한 샘플 캠페인의 headless 실행 계약과
authored tilemap visual gate, secondary combat fixture까지 통과했다.
다만 sprite clip·전체 오디오와 encounter/platformer fixture가 아직
남아 있으므로 시각·기능 전체가 `32_recreate`와 동등하다는 뜻은
아니다.
콘솔도 일반 `go build` 대상이 아니며 각 제조사 승인, SDK, 개발기와
비공개 Ebitengine 도구가 필요하다.

## 콘솔 범용성의 정확한 의미

| 대상 | 현재 공개 근거 | 이 프로젝트의 판정 |
| --- | --- | --- |
| Windows/macOS/Linux | [Ebitengine 정식 대상](https://ebitengine.org/en/documents/features.html) | 구조와 Windows 빌드는 확인. macOS 실행은 macOS 호스트에서 별도 검증 |
| Web/Android/iOS | [Ebitengine 정식 대상](https://ebitengine.org/en/documents/features.html) | 엔진 경로는 존재하지만 이번 spike에서 아직 패키징하지 않음 |
| Nintendo Switch | [Ebitengine이 공식 지원을 명시](https://ebitengine.org/en/blog/nintendo_switch.html) | 도구 일부는 비공개이며 Nintendo 계약 이후에만 검증 가능 |
| Xbox | [저장소가 지원을 명시하지만 모든 사용자에게 공개된 상태는 아니라고 명시](https://github.com/hajimehoshi/ebiten/blob/v2.9.9/README.md#platforms) | Microsoft GDK 승인과 접근 확보가 출시 gate |
| PlayStation 5 | [v2.9.9에 `playstation5` build tag가 있음](https://github.com/hajimehoshi/ebiten/blob/v2.9.9/playstation5/doc_playstaton5.go) | 실제 구현 일부는 별도 저장소가 제공한다고 코드에 명시. Sony SDK/도구 없이는 출시 가능 판정 불가 |

즉 “Ebitengine을 쓰면 콘솔 버튼 하나로 출력된다”는 뜻은 아니다.
정확한 장점은 **게임 로직과 콘텐츠 경계를 미리 콘솔 이식 가능한
형태로 만들고, 승인 뒤 플랫폼 adapter만 교체할 수 있다는 것**이다.

[LÖVE 공식 사이트](https://www.love2d.org/?page=documentation)가 공개
배포 대상으로 나열하는 것은 Windows, macOS, Linux, Android, iOS다.
따라서 처음 LÖVE를 선택한 이유가 Switch/Xbox/PS5라면 Ebitengine
쪽이 더 직접적인 후보인 것은 맞다.

## 이번에 증명한 구조

```text
32_recreate/game/content/*.lua
              │ build-time only
              ▼
       canonical catalog.json
              │
              ▼
     typed gamebuild translation
              │
              ▼
 deterministic fixed-point sim
       ├─ Ebitengine View
       ├─ protocol v8 snapshot/control
       └─ atomic session storage
```

핵심 경계:

1. Lua는 authoring importer에만 있다. 배포 런타임은 Lua/LuaJIT를
   포함하지 않는다.
2. `internal/sim`은 Ebitengine을 import하지 않는다.
3. 입력은 키 코드가 아니라 attack, parry, dodge 같은 의미 action이다.
4. 렌더러는 mutable gameplay 객체 대신 분리된 snapshot을 받는다.
5. 파일 저장소는 interface 뒤에 있어 콘솔 user-storage 구현으로
   교체할 수 있다.
6. 디버그 프로토콜과 실제 키보드 입력은 같은 simulation 경계를
   통과한다.

## 검증 결과

### 통과

- Ubuntu 22.04 arm64 실제 창과 960×540 PNG 캡처
- 기존 hero, slime, guide, merchant, slash, font 애셋 로딩
- catalog image manifest, stage background와 authored tilemap의
  `gamebuild → View → renderer` 변환
- tile layer opacity·카메라 culling·Tiled horizontal/vertical/diagonal
  flip flag를 보존한 실제 960×540 visual acceptance
- 기존 콘텐츠 정의 44개와 dependency path 86개 보존
- canonical catalog SHA-256:
  `a8c64856d22cb4e6039f88737602fe3ba08bbd7c24bd5a4193cb3e2ed413d0e9`
- `game/game.lua`의 project manifest를 schema v2 catalog에 함께 컴파일
- 고정소수점 60 tick 이동과 swept wall collision
- 공격 windup/active/recovery와 cooldown
- 피해, 경직, 넉백, 히트스톱, 피격 flash, 카메라 흔들림
- 방향 판정 패링, 퍼펙트 패링, 회피와 무적
- attack/special/technique 의미 입력과 ID별 독립 cooldown
- fire bolt의 연속 swept wall/actor 충돌, 안정적인 동일 시각 ID 순서,
  관통·벽 차단·수명 종료
- burning 상태의 stack/refresh, 주기 피해, 이동·공격·피격 배율과 면역
- whirlwind의 repeat interval과 대상별 3회 multi-hit
- 살아 있는 projectile·status·정확한 ability/cooldown을 보존하는
  simulation session v3
- 콘텐츠 수치로 동작하는 chase/attack AI
- 대화 시작, 퀘스트 시작·진행·완료
- 전체 session 저장·불러오기와 원자적 검증
- protocol v8의 상태·콘텐츠·월드·엔티티·입력·프레임·화면·저장 제어
- ID가 보존된 wall 조회·검증·runtime 형상 제어
- wall ID를 simulation까지 직접 보존하며 현재 entity 위치를 기준으로
  원자적으로 형상을 교체
- hub/grove의 convex polygon wall을 정확한 authored vertex와 고정소수점
  SAT 충돌로 보존하고 고속 이동·spawn·session load에서 관통 방지
- Campaign의 장기 상태와 stage별 World를 분리하고
  village → hub → grove 왕복 portal을 원자적으로 전환
- rectangle·convex polygon portal이 wall과 같은 고정소수점 SAT 및
  strict edge-touch 규칙을 공유
- 7개 stage, 모든 entry spawn과 2개 locale의 22개 조합을 `contentc`
  단계에서 실제 simulation으로 사전 구성
- versioned Campaign save가 stage entry, locale, flag, inventory,
  equipment, 다중 목표 quest, 재화를 보존하고 프로세스 재시작 시
  stage-local World를 새로 구성
- typed rule executor가 대화 조건·action, quest 완료 보상, 상점 거래를
  한 Campaign transaction으로 처리
- 대화 세션이 선택 조건을 action과 같은 transaction에서 재검사하고
  `thanks` 진입의 `finish_game`까지 정확히 한 번 실행
- 실제 키보드·게임패드 의미 입력과 같은 모델을 사용하는 dialogue,
  shop, inventory, title, pause, gameover, ending 화면
- item 사용·구매·판매·장착·해제와 장비 기반 파생 공격력을 Campaign,
  World rebuild, UI, protocol에 일관되게 반영
- `Flow.getState`, `Flow.move`, `Flow.activate`로 현재 게임 흐름 화면을
  의미 ID 기반으로 조회·제어
- title 또는 pause 같은 semantic flow가 활성화된 동안
  `Emulation.step`을 거부해 숨은 World 진행 방지
- 새 게임 → 퀘스트 수락 → 상점 → pause save → 새 Runtime의 continue
  → 실제 전투 → portal 왕복 → 보상 → ending 전체 headless acceptance
- 32 wire와 수명주기를 보존한 `Entity.spawn`, queued
  `Entity.remove`, optional-speaker `Dialogue.start`
- 동적 actor의 sprite/tag/chase metadata까지 renderer, AI, snapshot에
  반영하고 player save와 Maker preview topology를 분리
- stage 밖 actor/dialogue도 같은 catalog translator로 변환하며 instance
  name/tag/component override와 start-node quest 의미를 보존
- 월드 좌표와 960×540 논리 화면 좌표 동시 조회
- screenshot의 정확한 render tick/revision 응답
- 실행 중인 실제 창에서 protocol로 player/slime을 재배치하고 fire bolt를
  발사해 화면상 투사체와 명중 후 burning 상태를 같은 tick의 `world`
  응답으로 대조
- 취소된 다중 frame step의 전체 rollback
- 대기 ability와 실제 player 이동·패링·회피·상호작용 입력 병합
- 13개 콘텐츠 kind, action 32종, condition 17종, stage section 7종의
  미사용 정의까지 포함한 semantic validation
- 32-compatible `schema_valid`, adapter coverage인 `fully_applied`, 실제
  preview 재구축 가능성인 `runtime_compatible` 분리
- 호환 session reload와 구조 변경용 `App.startNewGame` 분리
- 실행 위치에 의존하지 않는 embedded 기본 catalog
- 선택형 shared-secret 인증과 loopback 강제
- 포트 bind 실패 선검출 및 `App.quit` 응답 후 종료
- `Emulation.step`이 실행 전 automation pause 상태를 복원하여 실행
  중인 창을 멈춘 채 남기지 않는 수명주기
- 명시적인 `pause true` 동안만 화면 overlay를 표시하고 정밀 캡처 뒤
  `pause false`로 재개하는 자동화 수명주기
- 창을 생성하지 않는 protocol/runtime 통합 회귀 테스트
- `go test ./...`
- `go test -race ./...`
- `go vet ./...`
- Windows amd64 전체 실행본 교차 빌드
- 순수 simulation의 Windows amd64/macOS arm64 교차 빌드

### 호스트가 필요한 검증

- Linux에서 macOS 전체 Ebitengine 실행본을 교차 빌드하면 macOS
  CGo/graphics 부분에서 실패한다. macOS + Xcode 도구로 빌드·실행해야
  한다.
- Nintendo Switch, Xbox, PS5는 제조사 계약·SDK·개발기 없이는
  compile/run acceptance를 수행할 수 없다.

## 아직 기능 동등하지 않은 부분

다음 항목은 `32_recreate`가 계속 기준 명세여야 하는 이유다.

- platformer, arena 등 나머지 fixture stage
- sprite clip·ability visual의 완전한 data-driven 렌더링과 전체 오디오
- 장비 공격력 이외의 확장 RPG stat·상태이상 계산
- 실행 중 정의 반영과 stage/entity 생성 편집
- 모바일·웹 패키징
- 콘솔별 storage, suspend/resume, safe-area, controller-user 정책

## 다음 구현 gate

1. ~~protocol에 Maker preview 생성·삭제·대화 계약을 추가한다.~~ 완료
2. complete campaign 기반의 manifest, Campaign/World 분리, dialogue,
   quest, inventory, equipment, economy, shop, flow 이식은 완료했다.
   검증된 stage factory와 portal 위에 tilemap presentation도 옮겼다.
3. `32_recreate`와 같은 **프로세스 재시작을 포함한** headless campaign
   acceptance와 실제 창 tilemap capture를 통과해 visual campaign gate를
   닫았다.
4. ~~secondary ability, projectile, status, multi-hit을 옮긴다.~~ 완료
   이어서 encounter와 platformer fixture stage를 옮긴다.
5. Maker가 LÖVE/Ebitengine backend를 선택해 같은 프로젝트를 미리 볼
   수 있게 한다.
6. Windows 실기와 macOS 실기 패키징을 통과시킨다.
7. 제조사 승인을 확보한 플랫폼만 별도 adapter·SDK branch에서
   개발기 acceptance를 수행한다.

4번의 남은 encounter/platformer fixture와 presentation gate를
통과하기 전에는
`33_ebitengine_spike`를 본 런타임으로 승격하지 않는다.

자동화의 `Emulation.step` 정지는 위 game-flow의 pause menu와 별도
상태다. 전자는 테스트 clock만 멈추고, 후자는 게임 안의 UI/세션
상태이므로 둘을 같은 boolean으로 합치지 않는다.
