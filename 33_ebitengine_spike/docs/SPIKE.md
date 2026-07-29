# Ebitengine 전환 검증

기준일: 2026-07-29

## 결론

Ebitengine은 이 프로젝트의 **차기 런타임 후보로 적합하다.**
LÖVE보다 공개 저장소 안에 콘솔별 진입점이 실제로 존재하고, gameplay를
Go의 플랫폼 중립 코드로 유지하기 쉽다. 이번 spike로 콘텐츠 변환,
결정적 액션 RPG 시뮬레이션, 실제 Ubuntu arm64 화면, 원격 자동화까지
하나의 실행본으로 연결했다.

다만 `32_recreate`를 지금 삭제하거나 본 런타임을 즉시 교체하면 안 된다.
이번 결과는 village vertical slice의 구조 검증이지 전체 샘플 게임의
기능 동등성 검증이 아니다. 콘솔도 일반 `go build` 대상이 아니며 각
제조사 승인, SDK, 개발기와 비공개 Ebitengine 도구가 필요하다.

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
- 기존 콘텐츠 정의 44개와 dependency path 86개 보존
- canonical catalog SHA-256:
  `40b17e1bef28e5b01fc4dd7d20e16196e0779b4fc18a03542852450331d33ec0`
- 고정소수점 60 tick 이동과 swept wall collision
- 공격 windup/active/recovery와 cooldown
- 피해, 경직, 넉백, 히트스톱, 피격 flash, 카메라 흔들림
- 방향 판정 패링, 퍼펙트 패링, 회피와 무적
- 콘텐츠 수치로 동작하는 chase/attack AI
- 대화 시작, 퀘스트 시작·진행·완료
- 전체 session 저장·불러오기와 원자적 검증
- protocol v8의 상태·콘텐츠·월드·엔티티·입력·프레임·화면·저장 제어
- ID가 보존된 wall 조회·검증·runtime 형상 제어
- wall ID를 simulation까지 직접 보존하며 현재 entity 위치를 기준으로
  원자적으로 형상을 교체
- 월드 좌표와 960×540 논리 화면 좌표 동시 조회
- screenshot의 정확한 render tick/revision 응답
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
- `Emulation.step` 뒤 의도적인 pause를 화면 overlay로 명시하고
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

- world hub, grove, platformer, arena 등 나머지 stage와 portal 전환
- fire bolt, whirlwind, projectile와 다중 hit
- shop, inventory, equipment, economy, item use
- 메뉴, 새 게임, 캠페인 완료와 ending
- merchant interaction의 실제 shop 화면
- tilemap 렌더링과 전체 오디오
- status effect와 RPG stat 계산
- Maker preview가 쓰는 `Entity.spawn`, `Entity.remove`,
  `Dialogue.start`
- 실행 중 정의 반영과 stage/entity 생성 편집
- 모바일·웹 패키징
- 콘솔별 storage, suspend/resume, safe-area, controller-user 정책

## 다음 구현 gate

1. protocol에 Maker preview 생성·삭제·대화 계약을 추가한다.
2. `32_recreate`의 complete campaign을 같은 catalog와 scripted
   acceptance로 Ebitengine에서 재현한다.
3. shop/inventory/equipment와 secondary ability/projectile을 renderer와
   무관한 simulation feature로 옮긴다.
4. stage 전환과 portal을 구현하고 모든 샘플 stage를 렌더링한다.
5. Maker가 LÖVE/Ebitengine backend를 선택해 같은 프로젝트를 미리 볼
   수 있게 한다.
6. Windows 실기와 macOS 실기 패키징을 통과시킨다.
7. 제조사 승인을 확보한 플랫폼만 별도 adapter·SDK branch에서
   개발기 acceptance를 수행한다.

2번까지 통과하기 전에는 `33_ebitengine_spike`를 본 런타임으로
승격하지 않는다.
