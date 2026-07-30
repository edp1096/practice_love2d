# 아키텍처

## 목표

RPG Maker처럼 콘텐츠를 쉽게 편집하되 RPG 장르에 묶이지 않는 2D 제작
런타임을 만든다. 장르는 전역 모드 값이 아니라 기능 조합의 결과다.

```text
game manifest + content + map
                │
       선택한 feature 묶음
  ┌─────────────┼─────────────┐
  │             │             │
movement      action          rpg
topdown       combat          quest
platformer    ability         dialogue
              AI              inventory
  └─────────────┼─────────────┘
                │
        actor/component world
                │
 input/content/events/rules/debug
                │
              LÖVE
```

순수 액션 게임은 RPG 기능을 로드하지 않는다. 액션 RPG는 action과 rpg를
함께 선택한다. 하나의 프로젝트에서도 스테이지별로 다른 이동
컨트롤러를 사용할 수 있어야 한다.

## 의존 방향

```text
game/content  ──────▶ 공개 콘텐츠 규격
game/game.lua ──────▶ feature 선택
features      ──────▶ runtime/core 공개 인터페이스
runtime       ──────▶ core
adapters      ──────▶ LÖVE, Tiled, 운영체제
core          ──────▶ 다른 게임 도메인에 의존하지 않음
```

엔진은 `game.*` 모듈을 직접 require하지 않는다. `game/game.lua`는
부팅 시 전달되는 composition root일 뿐이다.

## 핵심 객체

### Host

선택된 feature를 의존 순서대로 등록하고 다음 레지스트리를 소유한다.

- 콘텐츠 종류
- 컴포넌트 종류
- 업데이트·렌더 시스템
- 액션과 조건
- 액션 interceptor
- 행동 gate
- feature 간 service
- 월드 time filter
- 엔티티·월드 snapshot inspector
- feature별 debug drawer
- feature별 stage section validator와 loader
- catalog 전체를 읽은 뒤 실행하는 boot validator
- 새 World마다 실행하는 순서 있는 initializer
- 입력 액션
- 애셋 캐시

### Catalog

`game/content` 아래 Lua 파일을 재귀적으로 정렬 탐색한다. 파일은
샌드박스 환경에서 실행되며 순수 테이블 하나만 반환할 수 있다.

검증은 모든 파일을 읽은 뒤 수행하므로 파일 순서는 참조 가능 여부에
영향을 주지 않는다.

### Session

`App`이 소유하는 런타임 영속 상태다. stage를 바꾸면 World와 엔티티는
새로 만들어지지만 session namespace는 유지된다.

```text
App session
 ├─ game.flow
 ├─ rpg.flags
 ├─ rpg.inventory
 ├─ rpg.equipment
 ├─ rpg.quests
 ├─ rpg.turn_battles
 ├─ rpg.economy
 └─ rpg.locale
```

feature는 `session:registerSection(feature_id, definition)`으로 자기
영역의 version, defaults, migration과 구조 validator를 함께 소유한다.
콘텐츠 reload와 save load는 session 복사본으로 새 Host와 World를 모두
검증한 뒤 성공했을 때만 교체한다. 실패하면 실행 중인 World와 원본
session을 바꾸지 않는다.

### World

stage 콘텐츠에서 actor 프리팹을 조립한다. 클래스 계층 대신 컴포넌트
보유 여부로 기능을 결정한다.

```text
NPC     = transform + sprite + body + interactable + dialogue
enemy   = transform + sprite + body + hurtbox + health + combat + AI
player  = transform + sprite + body + hurtbox + movement + control + combat
chest   = transform + sprite + body + interactable + loot
```

범용 ECS 프레임워크를 도입하지 않고 필요한 쿼리와 단계만 제공한다.

stage의 `tilemap`, `walls`, `spawn_points`, `triggers`, `portals`,
`camera`, `encounters`는 각각 소유 feature가 `stage section`으로
등록한다. base `World`에 맵 종류별 분기를 넣지 않는다.

stage의 기본 spawn과 encounter의 wave spawn은 같은 actor instance
검증 service를 사용한다. 따라서 instance ID, tag, 위치와 component
override 규격이 두 경로에서 어긋나지 않는다.

portal은 World에서 App을 직접 호출하지 않는다. 의미 있는
`stage_transition` request를 큐에 넣고 App이 새 World를 완전히 만든 뒤
원자적으로 교체한다. 목적지는 `stage ID + spawn point ID`다.

### Rules

퀘스트, 대화, 아이템, 능력, 맵 트리거는 같은 액션·조건 레지스트리를
사용한다.

현재 등록된 액션:

- `damage`
- `heal`
- `revive`
- `stagger`
- `invulnerable`
- `knockback`
- `hitstop`
- `camera_shake`
- `spawn_projectile`
- `apply_status`
- `remove_status`
- `start_encounter`
- `start_turn_battle`
- `emit`
- `set_flag`, `clear_flag`
- `give_item`, `take_item`, `use_item`
- `equip_item`, `unequip_slot`
- `start_dialogue`, `close_dialogue`
- `start_quest`
- `add_currency`, `spend_currency`
- `open_shop`, `close_shop`, `buy_item`, `sell_item`
- `set_locale`
- `show_notice`
- `finish_game`, `save_game`

현재 등록된 조건은 공통 조합인 `always`, `all`, `any`, `not` 위에
`health_at_most`, `has_status`, `encounter_state`, `flag`, `has_item`,
`item_equipped`, `dialogue_active`, `quest_state`, `quest_objective`,
`currency_at_least`, `shop_active`, `locale_is`, `turn_battle_state`,
`game_flow_state`가 있다.

각 RPG feature가 자기 어휘를 등록하므로 중앙의 거대한 `if/elseif`는
없다. 같은 action은 대화 선택지, 퀘스트 보상, 아이템 효과와 map
trigger 어디서든 사용한다.

### Events

도메인 기능은 직접 서로 호출하기보다 의미 이벤트를 발행한다.

현재 예:

- `stage.loaded`
- `entity.spawned`
- `entity.removed`
- `ability.used`
- `ability.started`
- `ability.recovery_started`
- `ability.finished`
- `ability.interrupted`
- `ability.hit`
- `actor.damaged`
- `actor.damage_blocked`
- `actor.staggered`
- `actor.recovered`
- `actor.knockback_started`
- `actor.knockback_finished`
- `actor.healed`
- `actor.killed`
- `parry.started`
- `parry.expired`
- `attack.parried`
- `hitstop.started`
- `hitstop.finished`
- `dodge.started`
- `dodge.finished`
- `projectile.spawned`
- `projectile.hit`
- `projectile.blocked`
- `projectile.expired`
- `status.applied`
- `status.refreshed`
- `status.stacked`
- `status.ticked`
- `status.resisted`
- `status.removed`
- `status.expired`
- `encounter.started`
- `encounter.wave_started`
- `encounter.wave_completed`
- `encounter.completed`
- `encounter.action_failed`
- `boss.phase_entered`
- `platformer.jumped`
- `platformer.landed`
- `trigger.entered`
- `trigger.action_failed`
- `portal.entered`
- `stage.spawn_applied`
- `flag.changed`
- `inventory.item_added`, `inventory.item_removed`,
  `inventory.item_used`
- `equipment.changed`
- `dialogue.started`, `dialogue.node_entered`,
  `dialogue.choice_selected`, `dialogue.closed`
- `quest.started`, `quest.objective_progress`, `quest.completed`
- `economy.currency_added`, `economy.currency_spent`
- `shop.opened`, `shop.item_bought`, `shop.item_sold`, `shop.closed`
- `interaction.started`, `interaction.completed`
- `locale.changed`
- `save.written`, `save.loaded`

퀘스트는 새 World가 만들어질 때 콘텐츠에 선언된 이벤트 이름을
구독한다. 현재 예제는 전투의 `actor.killed`를 필터링하므로 퀘스트
때문에 전투 코드를 수정하지 않는다.

## 기능 사이의 확장 계약

feature끼리 상대 구현을 직접 호출하지 않도록 다음 계약을 둔다.

- action: 콘텐츠가 요청하는 명시적 효과다. `damage`, `stagger`처럼
  검증 가능한 순수 데이터로 사용한다.
- interceptor: 기존 action의 실행 전후를 감싸는 규칙이다. 패링과 피격
  무적은 `damage` 구현을 수정하지 않고 피해를 차단한다.
- gate: `move`, `act` 같은 능력 채널의 현재 허용 여부다. 경직과 패링은
  이동·행동 시스템을 직접 참조하지 않고 이 채널을 잠근다.
- service: 여러 feature가 공유하는 작은 기능이다. 일반 이동, 넉백,
  회피, 플랫포머와 projectile은 모두 `motion` service를 사용해 같은
  충돌 경계를 적용한다. actor instance 검증도 stage와 encounter가
  service 하나를 공유한다.
- time filter: 메인 루프를 수정하지 않고 월드 시간 흐름을 조절한다.
  히트스톱은 실제 고정 틱은 유지하면서 게임 시스템의 dt를 0으로 만든다.
- snapshot inspector: feature가 자기 의미 상태를 디버그 snapshot에
  추가한다. 새 기능 때문에 `World:snapshot()`을 수정하지 않는다.
- stage section: feature가 canonical stage의 자기 필드만 검증하고
  로딩한다. 새 맵 기능 때문에 base stage validator를 늘리지 않는다.
- boot validator: catalog 전체가 준비된 뒤 manifest 설정과 전역
  불변식을 검사한다. locale과 font 참조가 이 경계를 사용한다.
- world initializer: stage section까지 로드된 새 World에 이벤트 구독과
  feature 상태를 붙인다. 퀘스트 구독은 stage 전환마다 여기서 다시
  연결된다.
- session section: World 수명보다 긴 feature 상태와 저장 버전을
  격리한다. 인벤토리와 퀘스트가 서로의 내부 테이블이나 migration을
  공유하지 않는다.

interceptor는 숫자 우선순위와 이름으로 결정적으로 정렬된다. 현재
`parry.guard(10)`가 `reaction.invulnerability(20)`보다 먼저 피해를
판정한다. 시스템은 phase, order, id 순으로 결정적으로 정렬된다.

현재 전투 구현의 소유 경계는 다음과 같다.

| 관심사 | 소유 feature | 공개 결합점 |
|---|---|---|
| 체력·사망 | `action.health` | `damage`, `heal` action |
| 공격 선택·예고·활성·후딜 | `action.combat` | ability 콘텐츠와 effect action, move gate |
| 공격/피격 판정 | `action.hitbox` | hitbox service, `action.hurtbox` |
| 동적·정적 이동 충돌 | `motion` + `world` | motion service, body layer/mask |
| 피격 경직·피격 무적 | `action.reaction` | `stagger`, `invulnerable`, damage interceptor, gate |
| 밀려남 | `action.knockback` | `knockback` action, motion service, gate |
| 순간 정지 | `action.hitstop` | `hitstop` action, time filter |
| 이동 회피 | `action.dodge` | 의미 입력, `invulnerable`, motion service, gate |
| 패링 판정·반격 경직 | `action.parry` | damage interceptor, `stagger`, gate |
| 발사체 수명·연속 적중 | `action.projectile` | projectile 콘텐츠, `spawn_projectile` action |
| 상태 중첩·주기·배율 | `action.status` | apply/remove action, condition, damage interceptor |
| wave·boss phase | `action.encounter` | encounter 콘텐츠와 stage section |
| 거리 유지·회전·단계별 공격 의도 | `action.behavior_ai` | entity command |
| 횡스크롤 이동·중력 | `movement.platformer` | 의미 입력, motion service, move gate |
| 플레이어 소유권 | `control` | `control.player` marker |
| 런타임·디스크 영속 범위 | `session` | feature별 versioned section |
| 소지품·소비 효과 | `rpg.inventory` | item 콘텐츠, give/take/use action |
| 장비·파생 능력치 | `rpg.equipment` + `rpg.stats` | item section, stat provider, damage interceptor |
| NPC 상호작용 | `rpg.interaction` | interactable component, action 목록, interact gate |
| 분기 대화 | `rpg.dialogue` | dialogue graph, Rules condition/action, modal gates |
| 목표·보상 | `rpg.quest` | event subscription, quest 콘텐츠 |
| 거래·소지금 | `rpg.shop` + `rpg.economy` | shop 콘텐츠, inventory service |
| 표시 언어 | `rpg.locale` | locale 콘텐츠, boot validator |
| 일자·시각·지역·월드 page | `world_state` | `world.state` save section, region edge, Rules condition/action |

따라서 방어와 슈퍼아머도 `combat.lua`의 분기를 늘리는 대신
자기 feature에서 공개 계약을 조합해 추가한다.
상세 작업 규칙은 [EXTENDING.md](EXTENDING.md)에 있다.

## 시뮬레이션 단계

고정 60Hz 틱에서 다음 순서를 사용한다.

모든 단계 앞에서 time filter가 dt를 결정한다. 히트스톱 중에도 고정 틱과
디버그 프레임 번호는 진행하지만 아래 게임 시스템과 월드 시간은
정지한다. 입력 프레임은 게임 시간이 실제로 진행된 틱에서만 소비하므로
히트스톱 중 누른 공격·회피 입력은 다음 유효 틱까지 보존된다.

1. `input`: 장치 입력을 플레이어 의도로 변환
2. `intent`: AI와 스크립트가 의도를 생성
3. `movement`: 위치와 충돌 해결
4. `combat`: 스킬과 효과 실행
5. `resolution`: 사망과 제거 등 후처리
6. `presentation`: 애니메이션 상태 갱신

렌더링은 시뮬레이션과 별도이며 시스템별 `draw_order`로 정렬한다.
world-space 시스템은 camera transform 안에서, screen-space HUD는 같은
논리 viewport에서 camera transform 없이 그린다.

## Tiled compiler 경계

Go `lovectl map compile`은 Tiled TMX를 순수 Lua canonical stage로
변환한다. 런타임은 XML, Tiled class, 레이어 이름, 원본 파일 경로를
모른다.

```text
Tiled 편집 계약 ── Go compiler ── canonical stage ── feature sections
```

컴파일러는 회전 rectangle을 polygon으로 정규화하고 tile GID flag를
보존한다. 런타임 catalog는 actor/asset/stage/action 교차 참조를 다시
검증한다. 이 이중 경계 덕분에 제작 오류는 게임 플레이 도중이 아니라
`lovectl map check` 또는 `lovectl check`에서 실패한다.

## 지켜야 할 규칙

- core에 quest, player, enemy 같은 도메인 이름을 넣지 않는다.
- 장르 전역 분기를 추가하지 않는다.
- 입력 장치 처리기에 게임 규칙을 넣지 않는다.
- 콘텐츠 파일에 함수, require, 전역 접근, 메타테이블을 넣지 않는다.
- 콘텐츠를 추가하기 위해 `init.lua`를 수정하지 않는다.
- 파일 경로를 actor나 ability에 직접 쓰지 않고 asset ID를 참조한다.
- 런타임 상태를 콘텐츠 정의 테이블에 기록하지 않는다.
- 새 feature는 자기 스키마, 시스템, 액션, 조건을 함께 등록한다.
- 디버그 프로토콜에는 임의 Lua 실행 기능을 추가하지 않는다.

현재 debug protocol v8은 검증된 content definition과 dependency
graph, semantic world snapshot, actor spawn/remove, loadout ability 요청,
dialogue 시작, 제한된 inventory/economy mutation, save/load, 의미 입력,
고정 frame step과 screenshot만 노출한다. 콘텐츠 데이터가 아닌 임의
Lua 코드나 내부 함수 호출은 받지 않는다.

## 배포 경계

`lovectl package`는 먼저 TMX를 canonical stage로 컴파일하고 전체
catalog를 실제 LÖVE로 검증한다. 그 뒤 다음 파일만 결정적 ZIP 형식의
`.love`에 넣는다.

```text
main.lua, conf.lua
engine/**/*.lua
game/game.lua
game/content/**/*.lua
catalog에 asset으로 등록된 assets/runtime 파일
recreate-build.json
```

Tiled TMX, `assets/source`, 문서, 테스트, artifacts와 Go 도구는
들어가지 않는다. build manifest에는 각 runtime 파일의 크기와 SHA-256,
콘텐츠·참조 수가 있으며 시간값은 넣지 않는다. 같은 입력은 같은
패키지 SHA-256을 만든다.

## 저장

월드 전체 객체를 직렬화하지 않고 feature가 자기 session 상태와 버전을
등록한다.

```text
save schema v1
  project ID
  stage ID + optional spawn ID
  feature sections
    section ID
    section schema version
    pure data
```

현재 RPG section은 flags, inventory, equipment, quests, economy,
locale다. 각 section은 구조를 먼저 검사하고 catalog가 준비된 뒤 저장된
content ID도 다시 검사한다. 이전 version은 feature가 등록한 순차
migration을 후보 복사본에서 거친다. 알 수 없는 section이나 더 최신
version은 묵시적으로 버리지 않고 실패한다.

App은 저장 파일을 임시 경로에 쓴 뒤 rename하고, 로드할 때 후보 Host와
World를 완전히 부팅한 후에만 현재 상태를 교체한다. projectile, 공격
phase, AI 타이머 같은 일시 World 상태는 저장하지 않는다. 세부 계약은
[SAVES.md](SAVES.md)에 있다.
