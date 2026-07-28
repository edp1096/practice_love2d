# 기능 확장 가이드

목표는 게임 제작자와 엔진 기능 개발자가 서로의 파일을 거의 건드리지
않고 작업하는 것이다. 모든 것을 하나의 추상 인터페이스로 숨기지 않고,
변경 이유가 다른 부분을 명시적인 계약으로 나눈다.

## 작업자의 경계

### 게임 제작자

`game/content`의 데이터와 `assets`를 편집한다.

- actor 조합과 수치
- ability의 예고·활성·후딜, 이동 잠금, 범위, 재사용 시간, effect 목록
- projectile, status, encounter와 boss phase
- 탑다운 또는 플랫포머 actor 조합과 stage 배치
- Tiled의 class 기반 actor, wall, trigger, portal 배치
- sprite clip과 asset ID
- item, 장비 수치와 상점 가격
- NPC interactable과 dialogue graph
- event 기반 quest 목표와 action 보상
- locale 문자열

새 파일은 자동 탐색되므로 중앙 등록 파일을 고치지 않는다. 기존
컴포넌트와 action만으로 표현되는 변경에는 엔진 코드가 필요 없다.
액션 제작은 [ACTION.md](ACTION.md), RPG 제작은 [RPG.md](RPG.md)의
완성 예제를 복제해 ID와 데이터부터 바꾼다.

### feature 개발자

새 동작이 기존 데이터 어휘로 표현되지 않을 때
`engine/features/<영역>/<이름>.lua` 하나를 소유한다. feature는 필요한
항목만 등록한다.

- content kind: 새로운 독립 데이터 종류
- stage section: stage에 추가할 검증·로딩 가능한 데이터 영역
- boot validator: catalog 준비 뒤 manifest와 전역 참조 검증
- world initializer: 새 World마다 상태 초기화와 event 구독
- component: actor에 붙는 설정과 런타임 상태
- action/condition: 콘텐츠에서 사용하는 효과와 판정
- action interceptor: 기존 효과를 차단하거나 변환하는 규칙
- gate: 이동이나 행동을 일시적으로 막는 규칙
- service: 여러 feature가 공유하는 범용 연산
- time filter: 월드의 dt를 결정하는 시간 제어
- snapshot inspector: 자기 상태를 원격 디버그 데이터에 노출
- debug drawer: 오버레이에 자기 판정과 방향을 표시
- system: 시간에 따라 갱신되는 동작과 표시
- event: 다른 기능이 구독할 의미 있는 결과
- session section: stage보다 오래 유지되는 feature 소유 상태와
  저장 schema version·migration

다른 feature 파일의 지역 함수나 내부 테이블을 직접 호출하지 않는다.
필요한 결합점이 없다면 core에 가장 작은 범용 계약을 먼저 추가한다.

맵 입력 형식을 추가할 때 런타임이 TMX 레이어 이름을 읽게 하지 않는다.
도구가 canonical stage section으로 변환하고 해당 feature가 section을
검증·로딩한다.

session 상태가 필요하면 임의 테이블을 `host.session`에 쓰지 않는다.
`session:registerSection`으로 defaults, version, validator를 선언하고
저장된 콘텐츠 ID는 catalog 로드 뒤 boot validator에서 확인한다. 이미
배포된 구조를 바꿀 때는 버전을 올리고 각 이전 버전의 migration을
제공한다. 전체 예시는 [SAVES.md](SAVES.md)에 있다.

### 도구·어댑터 개발자

`tools/lovectl`, `engine/debug`, 향후 Tiled compiler처럼 런타임 외부
경계를 담당한다. 게임 규칙을 재구현하지 않고 의미 입력, snapshot,
검증 결과 같은 공개 표면을 사용한다.

## 새 feature의 최소 형태

```lua
local feature = {
    id = "action.example",
    requires = {"engine.features.action.health"},
}

function feature:register(host)
    host:registerComponent("action.example", {
        validate = function(config, validator, path)
            if not validator:table(config, path, true) then return end
            validator:keys(config, {"power"}, path)
            validator:positive(config.power, path .. ".power", true)
        end,
        create = function(config)
            return {
                power = config.power,
                remaining = 0,
            }
        end,
    })

    host:registerSystem({
        id = "action.example.update",
        phase = "resolution",
        order = 0,
        update = function(_, world, dt)
            -- query components and update only owned runtime state
        end,
    })
end

return feature
```

그 뒤 `game/game.lua`의 `features`에 모듈을 선택하고 actor에 컴포넌트를
붙인다. feature가 선택되지 않았는데 콘텐츠가 해당 컴포넌트를 쓰면
부팅 검증이 실패한다.

## 현재 전투가 확장되는 방식

패링은 좋은 기준 사례다.

1. `action.combat`은 ability의 `damage`를 실행한다.
2. `action.parry` interceptor가 방향과 시간 창을 검사한다.
3. 성공하면 damage와 이후 effect를 중단하고 공용 `stagger` action을
   공격자에게 실행한다.
4. `action.reaction`의 gate가 경직된 공격자의 `move`와 `act`를 막는다.
5. `action.knockback`은 `motion` service로 대상을 밀고,
   `action.hitstop`은 time filter로 다음 틱들을 정지한다.
6. 각 feature가 자기 표시, 이벤트, snapshot inspector를 소유한다.

이 과정에서 health의 피해 계산이나 combat의 입력 코드에
`if parrying` 분기가 들어가지 않는다. 이미 같은 계약으로 다음 기능을
분리했다.

- 발사체: activation action, projectile 콘텐츠, motion과 연속 hurtbox 판정
- 상태 이상: 자기 component와 timer, action/condition, damage interceptor
- encounter: 자기 stage section, wave spawn과 boss phase action
- 플랫포머: 전역 장르 분기 없이 별도 이동 component와 motion service

다음 기능도 같은 방식으로 독립 추가한다.

- 방패: damage interceptor에서 각도와 방어력을 적용
- 슈퍼아머: stagger action interceptor로 경직만 차단
- 다른 회피 방식: 의미 입력과 gate, 공용 `invulnerable` action 조합
- 퀘스트: 전투 이벤트 구독과 자기 상태 저장

RPG 구현도 같은 기준 사례다. inventory는 item의 기본 section과
give/take/use action만 소유하고, equipment가 inventory 확장 section과
제거 guard를 등록한다. stats는 provider로 장비 수치를 합성하고 damage
interceptor에서 전투에 연결한다. quest는 `actor.killed`를 구독할 뿐
health나 combat 구현을 참조하지 않는다.

interceptor가 수치나 context를 바꿔 다음 실행기로 넘겨야 할 때는 원본
콘텐츠 테이블을 수정하지 않고 `nextHandler(next_action, next_context)`에
새 테이블을 전달한다. status의 피해 배율이 이 방식의 기준 사례다.

## 완료 기준

새 feature 작업은 다음을 함께 제공해야 한다.

1. 엄격한 스키마와 잘못된 필드·참조의 실패 테스트
2. 핵심 규칙의 Lua 단위 테스트
3. 다른 feature와 결합할 때의 이벤트·우선순위 테스트
4. 화면 동작이면 `lovectl test`의 실제 LÖVE 프레임 검증
5. 제작자가 만질 필드와 예제를 `CONTENT.md`에 기록

최종 확인은 규칙 검사와 실제 화면 검사를 차례로 수행한다.

```bash
go run ./tools/lovectl check
go run ./tools/lovectl test
```
