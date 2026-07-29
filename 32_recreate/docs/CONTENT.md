# 콘텐츠 작성 규격

## 기본 규칙

각 파일은 전역 접근 없이 순수 Lua 테이블 하나를 반환한다.

```lua
return {
    schema_version = 1,
    kind = "actor",
    id = "actor.example",
}
```

- ID 형식: `namespace.name`
- 소문자, 숫자, 밑줄, 점, 하이픈만 사용
- ID는 프로젝트 전체에서 유일
- 모든 참조는 파일 경로가 아니라 ID 사용
- 함수, userdata, thread, metatable, 순환 테이블 금지
- 알려지지 않은 필드도 오류로 처리

파일명과 디렉터리는 정리를 위한 것이며 등록 역할을 하지 않는다.
`game/content` 아래 어느 하위 디렉터리에 놓아도 자동 탐색된다.

## 프로젝트와 game flow

새 프로젝트의 composition root는 `game/game.lua`다. RPG, 액션 RPG,
순수 액션 모두 완전한 게임으로 시작하려면 `game_flow` feature와 의미
입력을 함께 선언한다.

```lua
features = {
    "engine.features.game_flow",
    -- 선택한 이동·액션·RPG feature
},
flow = {
    save_slot = "campaign",
    start_stage = "stage.start",
    -- start_spawn = "default", -- 생략하면 stage 기본 진입점
},
input = {
    actions = {
        menu_up = {keys = {"w", "up"}, buttons = {"dpup"}},
        menu_down = {keys = {"s", "down"}, buttons = {"dpdown"}},
        menu_confirm = {keys = {"return"}, buttons = {"a"}},
        menu_cancel = {keys = {"escape"}, buttons = {"b"}},
        pause = {keys = {"p", "escape"}, buttons = {"start"}},
    },
},
```

처음 실행하면 `new_game`, `quit`가 있는 title이 열린다. 저장이
검증되면 `continue`가 추가되고, 플레이 중 `pause`로 저장·타이틀 메뉴를
연다. 플레이어 사망은 gameover를 열며 콘텐츠 action
`{type = "finish_game"}`은 ending을 연다. `{type = "save_game"}`은
manifest의 슬롯에 저장하고 `game_flow_state` 조건은 `started` 또는
`completed`를 검사한다. 시작·완료 여부는 save의 `game.flow` v1
section에 들어간다.

`lovectl init --profile rpg|action-rpg|action`이 이 계약을 포함한
독립 프로젝트를 생성하므로 처음부터 직접 작성할 필요는 없다.

## Actor

actor는 런타임 엔티티 프리팹이다.

```lua
return {
    schema_version = 1,
    kind = "actor",
    id = "actor.training_dummy",
    name = "Training Dummy",
    tags = {"enemy"},

    components = {
        transform = {},
        body = {
            shape = "circle",
            radius = 14,
            solid = true,
        },
        ["action.hurtbox"] = {
            radius = 14,
        },
        ["action.health"] = {
            max = 200,
        },
        ["action.knockback"] = {
            resistance = 0.2,
        },
    },
}
```

컴포넌트를 제공하는 feature가 manifest에 없으면 검증 오류가 발생한다.
actor에는 `transform`이 반드시 있어야 한다.

`body.collision_layer`는 actor가 속한 물리 계층이고
`body.collision_mask`는 막힐 상대 계층 목록이다. 동적 actor의 기본값은
각각 `actor`, `{"world", "actor"}`다. 양쪽 mask가 서로의 layer를
허용해야 충돌하며 `solid = false`는 물리 차단을 끈다.

실제 예:

- `game/content/actors/hero.lua`
- `game/content/actors/slime.lua`
- `game/content/actors/wall.lua`

## Ability

ability의 효과는 공통 액션 목록이다.

```lua
return {
    schema_version = 1,
    kind = "ability",
    id = "ability.heavy_slash",
    name = "Heavy Slash",
    hitbox = {
        shape = "arc",
        reach = 56,
        arc_degrees = 90,
    },
    cooldown = 0.7,
    windup = 0.18,
    duration = 0.16,
    recovery = 0.22,
    lock_movement = true,
    effects = {
        {type = "damage", amount = 45},
        {type = "stagger", duration = 0.3},
        {type = "knockback", distance = 28, duration = 0.14},
        {type = "hitstop", duration = 0.06},
    },
}
```

`windup`은 효과가 발생하기 전의 공격 예고 시간, `duration`은 효과
발생 뒤 활성 시간, `recovery`는 다시 행동할 수 있기 전의 후딜이다.
`lock_movement`는 이 세 단계에서 이동까지 묶을지 정하며 기본값은
`true`다. 이동 사격처럼 공격 중 움직일 수 있어야 하면 `false`로 둔다.

효과는 위에서 아래로 실행된다. 피해가 패링이나 무적으로 차단되어
`stop_effects`를 반환하면 뒤의 경직·넉백·히트스톱도 적용되지 않는다.

`hitbox.reach`는 공격자 hurtbox 바깥으로 뻗는 거리다. 실제 판정 반경은
공격자 hurtbox 반경 + reach + 대상 hurtbox 반경이다. `duration` 동안
매 틱 겹침을 검사하지만 하나의 공격은 같은 대상에 한 번만 적중한다.
따라서 공격이 시작될 때 밖에 있던 대상도 활성 시간 안에 들어오면
맞는다.

다단 공격은 hitbox에 재적중 간격과 상한을 함께 둔다.

```lua
hitbox = {
    shape = "arc",
    reach = 42,
    arc_degrees = 360,
    repeat_interval = 0.15,
    max_hits = 3,
}
```

hitbox 없이 시작 시점의 action만 실행하는 ability도 가능하다. 발사체
능력이 대표적인 예다.

```lua
activation = {
    {type = "spawn_projectile", projectile = "projectile.fire_bolt"},
}
```

actor가 여러 능력을 쓰면 loadout과 의미 입력의 대응을 명시한다.

```lua
["action.combat"] = {
    team = "player",
    abilities = {"ability.heavy_slash", "ability.fire_bolt"},
    primary = "ability.heavy_slash",
},
["action.combat_input"] = {
    bindings = {
        {input = "attack", ability = "ability.heavy_slash"},
        {input = "special", ability = "ability.fire_bolt"},
    },
},
```

새 피해 공식을 콘텐츠 함수로 작성하지 않는다. 새 규칙이 필요하면
feature가 `Rules:registerAction()`으로 명시적인 액션 종류를 추가한다.

## 피격 반응과 패링

actor가 피격 경직과 짧은 피격 무적을 받으려면 다음 컴포넌트를
추가한다.

```lua
["action.reaction"] = {
    hit_invulnerability = 0.35,
    flash_duration = 0.18,
},
```

플레이어처럼 패링 가능한 actor에는 별도의 컴포넌트를 추가한다.

```lua
["action.parry"] = {
    input = "parry",
    window = 0.32,
    perfect_window = 0.12,
    cooldown = 0.75,
    success_cooldown = 0.18,
    arc_degrees = 170,
    stagger = 0.55,
    perfect_stagger = 1.1,
    hitstop = 0.035,
    perfect_hitstop = 0.06,
},
```

패링은 바라보는 방향의 `arc_degrees` 안에서 들어온 피해만 막는다.
`window` 시작부터 `perfect_window` 안에 맞으면 공격자에게
`perfect_stagger`, 나머지 성공 구간에는 `stagger`를 적용한다. 키와
게임패드 버튼 자체는 actor가 아니라 `game/game.lua`의 의미 입력
`parry`에 연결한다.

플레이어의 이동 회피는 별도 컴포넌트다.

```lua
["action.dodge"] = {
    input = "dodge",
    duration = 0.22,
    distance = 78,
    invulnerability = 0.18,
    cooldown = 0.48,
},
```

입력 방향이 있으면 그 방향으로, 없으면 바라보는 방향으로 이동한다.
회피 이동도 일반 이동과 같은 벽 충돌을 사용한다. 무적 시간은 전체
회피 시간보다 길 수 없다.

## Projectile

projectile은 표시와 body를 가진 actor를 참조하고 비행 규칙과 적중
action을 선언한다.

```lua
return {
    schema_version = 1,
    kind = "projectile",
    id = "projectile.fire_bolt",
    actor = "actor.fire_bolt",
    speed = 420,
    lifetime = 1.8,
    spawn_offset = 25,
    pierce = 0,
    destroy_on_wall = true,
    effects = {
        {type = "damage", amount = 18},
        {type = "apply_status", status = "status.burning"},
    },
}
```

참조 actor에는 circle `body`, `motion.facing`, `motion.kinematics`가
필요하다. 발사체는 한 틱의 출발점부터 도착점까지 연속 판정하므로
속도가 빨라도 중간 hurtbox를 건너뛰지 않는다.

## Status

상태 효과는 지속 시간, 중첩 방식, 주기 action과 배율을 선언한다.

```lua
return {
    schema_version = 1,
    kind = "status",
    id = "status.burning",
    duration = 1.5,
    stacking = "stack",
    max_stacks = 3,
    tick_interval = 0.5,
    tick_actions = {
        {type = "damage", amount = 3},
    },
    modifiers = {
        move_speed = 0.85,
        damage_dealt = 1.1,
        damage_taken = 1.2,
    },
}
```

`stacking`은 `refresh` 또는 `stack`이다. 상태를 받을 actor에는
`["action.status"] = {}`를 붙이며 `immune` 목록으로 특정 상태를
거부할 수 있다. `apply_status`, `remove_status` action과 `has_status`
condition은 ability, trigger, encounter에서 동일하게 사용한다.

## RPG 콘텐츠

RPG도 별도 스크립트가 아니라 순수 데이터와 공통 Rules 어휘로
구성한다. 실행 중 진행 상태는 session에 있고 정의 테이블은 절대
수정하지 않는다.

### Item, Stats와 Equipment

소비 아이템은 effect action을 위에서 아래로 실행한 뒤 한 개를
차감한다.

```lua
return {
    schema_version = 1,
    kind = "item",
    id = "item.potion",
    name_key = "item.potion.name",
    description_key = "item.potion.description",
    stack_limit = 10,
    consumable = true,
    effects = {
        {type = "heal", amount = 25},
    },
    value = 25,
}
```

장비는 같은 item에 `equipment` section을 붙인다.

```lua
equipment = {
    slot = "weapon",
    modifiers = {
        attack = 5,
    },
}
```

장비를 받을 actor에는 다음 두 component가 필요하다.

```lua
["rpg.stats"] = {
    attack = 0,
    defense = 0,
    move_speed = 1,
},
["rpg.equipment"] = {
    loadout = "hero",
    slots = {"weapon", "armor", "accessory"},
},
```

`loadout` ID의 장비 상태는 stage 전환 뒤에도 유지된다. 장착 중인
수량은 판매·제거할 수 없다. 일반 피해는
`ability damage + attack - defense`, 최소 1로 계산하고 주기 상태 피해는
이 보정을 거치지 않는다.

### Locale

표시 문자열은 locale 콘텐츠에 모은다.

```lua
return {
    schema_version = 1,
    kind = "locale",
    id = "locale.ko",
    name = "한국어",
    code = "ko",
    strings = {
        ["item.potion.name"] = "회복 물약",
        ["quest.slime_patrol.name"] = "동쪽 길 순찰",
    },
}
```

`game/game.lua`에서 기본값과 fallback을 선택한다.

```lua
locale = {
    default = "locale.ko",
    fallback = "locale.en",
}
```

선택 언어에 키가 없으면 fallback, 콘텐츠의 직접 문자열, 마지막으로
키 자체 순서로 표시한다. `set_locale` action으로 실행 중 변경할 수
있다.

### Interaction, Dialogue, Quest와 Shop

NPC는 `rpg.interactable`에 입력 범위와 action 목록만 선언한다.

```lua
["rpg.interactable"] = {
    input = "interact",
    range = 70,
    prompt_key = "interaction.talk",
    actions = {
        {
            type = "start_dialogue",
            dialogue = "dialogue.guide",
        },
    },
}
```

dialogue는 node, choice, condition, action과 다음 node ID로 구성한다.
quest는 구독할 event와 payload의 `where` 필터, 목표 횟수와 완료
action을 선언한다. shop은 item ID별 구매가·판매가만 소유하며
inventory와 economy service가 실제 거래를 원자적으로 처리한다.

실제 파일을 따라 NPC 한 명과 퀘스트를 만드는 순서는
[RPG.md](RPG.md)에 정리되어 있다.

## 이동 Controller

탑다운 actor는 `movement.topdown`, 횡스크롤 actor는
`movement.platformer`를 사용하며 한 actor에 둘을 함께 붙일 수 없다.

```lua
["movement.platformer"] = {
    speed = 220,
    acceleration = 1500,
    air_acceleration = 900,
    deceleration = 1800,
    gravity = 1500,
    jump_speed = 600,
    max_fall_speed = 900,
    coyote_time = 0.1,
    jump_buffer = 0.1,
}
```

플랫포머도 공용 motion 충돌, move gate와 상태 효과의 `move_speed`
배율을 사용한다. 장르는 stage의 `mode` 문자열이 아니라 배치된 actor의
컴포넌트 조합으로 결정된다.

## Canonical Stage

stage는 actor와 월드 섹션을 조합한다. 직접 Lua로 작성할 수도 있고
Tiled TMX를 같은 형식으로 컴파일할 수도 있다.

```lua
return {
    schema_version = 1,
    kind = "stage",
    id = "stage.example",
    name = "Example",
    width = 960,
    height = 540,
    background = {0.07, 0.08, 0.11, 1},
    camera = {
        viewport_width = 800,
        viewport_height = 450,
        follow_tag = "player",
    },

    spawns = {
        {
            id = "player",
            actor = "actor.hero",
            position = {x = 180, y = 270},
        },
    },
    spawn_points = {
        {id = "west_entry", x = 96, y = 270},
    },
    walls = {
        {
            id = "north_wall",
            shape = {
                type = "rectangle",
                x = 480,
                y = 16,
                width = 960,
                height = 32,
            },
        },
    },
    portals = {
        {
            id = "to_grove",
            shape = {
                type = "rectangle",
                x = 944,
                y = 270,
                width = 32,
                height = 128,
            },
            target_stage = "stage.grove",
            target_spawn = "west_entry",
        },
    },
}
```

한 배치에서만 값을 바꾸려면 `components` override를 사용한다.

```lua
{
    id = "boss",
    actor = "actor.slime",
    position = {x = 700, y = 270},
    components = {
        ["action.health"] = {max = 500},
        ["movement.topdown"] = {speed = 90},
    },
}
```

`walls`는 actor가 아니라 stage geometry라서 rectangle과 polygon을
가볍게 많이 배치할 수 있다. `trigger.actions`와 `condition`은 ability와
같은 Rules registry를 사용한다. `portal`은 파일 경로나 좌표가 아니라
`target_stage`와 `target_spawn` ID를 쓴다.

재사용 가능한 전투 배치는 별도 `encounter` 콘텐츠에 wave, 상대 spawn,
boss health phase와 action을 정의하고 stage에서 배치한다.

```lua
encounters = {
    {
        id = "arena",
        encounter = "encounter.slime_trial",
        position = {x = 480, y = 80},
        auto_start = true,
    },
}
```

`auto_start = false`이면 trigger의
`{type = "start_encounter", encounter = "arena"}`로 시작한다. 전체 예제와
필드 조합은 [ACTION.md](ACTION.md)에 있다.

TMX의 tileset과 tile layer는 `tilemap` 섹션으로 컴파일된다. 생성된
`game/content/stages/generated/*.lua`는 직접 수정하지 않는다. Tiled
입력 규격과 명령은 [MAPS.md](MAPS.md)에 정리되어 있다.

## Asset과 Sprite

물리 파일을 먼저 asset ID로 등록한다.

```lua
return {
    schema_version = 1,
    kind = "asset",
    id = "image.hero_sheet",
    asset_type = "image",
    path = "assets/runtime/images/hero.png",
    width = 384,
    height = 960,
    filter = "nearest",
}
```

sprite 콘텐츠는 프레임과 클립을 선언한다.

```lua
return {
    schema_version = 1,
    kind = "sprite",
    id = "sprite.hero",
    asset = "image.hero_sheet",
    frame_width = 48,
    frame_height = 48,
    scale = 2,
    default_clip = "idle_down",
    clips = {
        idle_down = {
            frames = {{1, 1}, {2, 1}},
            fps = 6,
        },
    },
    state_map = {
        idle_down = "idle_down",
    },
}
```

검증기는 파일 존재 여부, 선언한 이미지 크기, 프레임 격자, 시트 범위,
clip과 state 참조를 확인한다.

한글 UI처럼 외부 글꼴이 필요하면 font asset을 등록하고 manifest에서
ID로 선택한다.

```lua
-- game/content/assets/ui_font.lua
return {
    schema_version = 1,
    kind = "asset",
    id = "font.ui",
    asset_type = "font",
    path = "assets/runtime/fonts/MyFont.ttf",
}
```

```lua
-- game/game.lua
font = {
    asset = "font.ui",
    size = 16,
}
```

기존 애셋의 현재 이식 내역은 `assets/SOURCES.md`에 기록한다. 모든
46MB를 미리 복사하지 않고 실제로 이식된 기능이 참조하는 runtime
애셋만 가져온다.

## 작업 흐름

```bash
go run ./tools/lovectl new actor training_dummy
go run ./tools/lovectl new item large_potion
go run ./tools/lovectl new dialogue gate_guard
go run ./tools/lovectl map compile
go run ./tools/lovectl check
go run ./tools/lovectl run
```

게임이 실행 중이면 콘텐츠 수정 후 다른 터미널에서:

```bash
go run ./tools/lovectl reload
```

오류가 있으면 새 콘텐츠는 적용되지 않고 실행 중인 정상 월드는
유지된다.

수동 reload 대신 `lovectl watch`를 켜 두어도 된다. 템플릿 전체 목록,
참조 graph, preview와 runtime-only 패키징은 [TOOLS.md](TOOLS.md)에
정리되어 있다.
