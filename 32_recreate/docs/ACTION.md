# 액션 게임 조립 가이드

이 문서는 엔진 코드를 수정하지 않고 `game/content`의 데이터로 탑다운
액션, 액션 RPG, 플랫포머 액션을 조립하는 가장 짧은 경로다. 현재
실행되는 완성 예제는 다음 파일에 있다.

- 탑다운 플레이어: `game/content/actors/hero.lua`
- 플랫포머 플레이어: `game/content/actors/runner.lua`
- 근접·발사체·다단 능력: `game/content/abilities`
- 상태 효과: `game/content/statuses`
- wave와 boss phase: `game/content/encounters/slime_trial.lua`
- 각 기능의 독립 화면: `game/content/stages/action_room.lua`,
  `encounter_room.lua`, `platformer_room.lua`

## 1. Actor에 필요한 능력만 조합한다

모든 actor는 `transform`이 필요하다. 움직이는 전투 actor의 공통
뼈대는 다음과 같다.

```lua
components = {
    transform = {},
    body = {
        shape = "circle",
        radius = 15,
        solid = true,
    },
    ["motion.facing"] = {},
    ["motion.kinematics"] = {},
    ["action.hurtbox"] = {radius = 15},
    ["action.health"] = {max = 100},
    ["action.status"] = {},
}
```

탑다운 actor에는 다음 중 하나를 붙인다.

```lua
["movement.topdown"] = {speed = 190}
```

플랫포머 actor에는 그 대신 다음을 붙인다.

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

두 이동 컴포넌트는 한 actor에 동시에 붙일 수 없다. 전역 장르 모드는
없으며 stage에 어느 actor를 배치했는지가 이동 방식을 결정한다.

`body`의 기본 동적 layer는 `actor`, 기본 mask는 `world`, `actor`다.
필요하면 명시적으로 분리한다.

```lua
body = {
    shape = "circle",
    radius = 6,
    solid = true,
    collision_layer = "projectile",
    collision_mask = {"world"},
}
```

양쪽 body의 mask가 상대 layer를 허용할 때만 물리적으로 서로 막는다.
`solid = false`인 body는 표시·검사에는 남지만 이동을 막지 않는다.

## 2. Ability를 정의하고 입력에 연결한다

근접 공격은 시간축 hitbox와 action 목록으로 만든다.

```lua
return {
    schema_version = 1,
    kind = "ability",
    id = "ability.heavy_slash",

    hitbox = {
        shape = "arc",
        reach = 56,
        arc_degrees = 100,
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
        {type = "hitstop", duration = 0.05},
    },
}
```

`effects`는 적중한 대상에 위에서 아래로 적용된다. 차단된 피해가
`stop_effects`를 반환하면 뒤의 경직과 넉백도 실행되지 않는다.

같은 활성 hitbox가 일정 간격으로 다시 맞히게 하려면 두 값을 함께
지정한다.

```lua
hitbox = {
    shape = "arc",
    reach = 42,
    arc_degrees = 360,
    repeat_interval = 0.15,
    max_hits = 3,
}
```

actor의 loadout과 의미 입력을 명시적으로 연결한다.

```lua
["action.combat"] = {
    team = "player",
    abilities = {
        "ability.heavy_slash",
        "ability.fire_bolt",
    },
    primary = "ability.heavy_slash",
},
["action.combat_input"] = {
    bindings = {
        {input = "attack", ability = "ability.heavy_slash"},
        {input = "special", ability = "ability.fire_bolt"},
    },
},
```

`attack`, `special` 같은 이름은 `game/game.lua`에서 키보드, 게임패드,
자동화 입력에 한 번만 연결한다.

## 3. 발사체를 Ability에서 생성한다

발사체는 외형·body를 가진 actor와 이동·효과를 가진 projectile 정의를
나눈다.

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

그 projectile을 ability의 활성 action으로 생성한다.

```lua
activation = {
    {type = "spawn_projectile", projectile = "projectile.fire_bolt"},
}
```

빠른 발사체도 이전 위치부터 현재 위치까지 연속 판정한다. `pierce = 0`은
첫 대상에서 소멸하며 값 `N`은 첫 대상 뒤 추가로 `N`명을 관통한다.

## 4. 상태 효과를 재사용한다

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
        damage_taken = 1.1,
    },
    color = {1.0, 0.35, 0.08, 1.0},
}
```

지원 배율은 `move_speed`, `damage_dealt`, `damage_taken`이다. 중첩
배율은 곱으로 합성된다. `move_speed`는 탑다운과 플랫포머 이동 모두에
적용된다.

어느 effect·trigger·boss phase에서도 같은 action을 쓴다.

```lua
{type = "apply_status", status = "status.burning", stacks = 1}
{type = "remove_status", status = "status.burning"}
```

면역은 받는 actor에 선언한다.

```lua
["action.status"] = {
    immune = {"status.burning"},
}
```

조건은 다음처럼 쓴다.

```lua
{
    type = "has_status",
    status = "status.burning",
    stacks_at_least = 2,
}
```

## 5. Encounter로 적 배치를 반복 사용한다

encounter 정의는 wave마다 stage 위치에 대한 상대 좌표로 actor를
생성한다.

```lua
return {
    schema_version = 1,
    kind = "encounter",
    id = "encounter.arena",
    target_tag = "player",
    waves = {
        {
            id = "guards",
            delay = 0.2,
            spawns = {
                {
                    id = "left",
                    actor = "actor.slime",
                    position = {x = -80, y = 40},
                },
                {
                    id = "right",
                    actor = "actor.slime",
                    position = {x = 80, y = 40},
                },
            },
        },
        {
            id = "boss",
            spawns = {
                {
                    id = "champion",
                    actor = "actor.slime",
                    tags = {"boss"},
                    position = {x = 0, y = 40},
                    components = {
                        ["action.health"] = {max = 500},
                    },
                },
            },
            boss_phases = {
                {
                    id = "enraged",
                    spawn = "champion",
                    health_ratio_at_most = 0.5,
                    actions = {
                        {
                            type = "apply_status",
                            status = "status.enraged",
                        },
                    },
                },
            },
        },
    },
    on_complete = {
        {type = "emit", name = "arena.completed"},
    },
}
```

stage에는 콘텐츠 ID와 이 stage 안에서 쓸 배치 ID를 함께 둔다.

```lua
encounters = {
    {
        id = "arena_1",
        encounter = "encounter.arena",
        position = {x = 480, y = 100},
        auto_start = true,
    },
}
```

`auto_start = false`라면 trigger에서 배치 ID로 시작할 수 있다.

```lua
actions = {
    {type = "start_encounter", encounter = "arena_1"},
}
```

`encounter_state` 조건은 `idle`, `pending`, `active`, `completed`를
검사한다.

## 6. 작은 수직 단면부터 검증한다

콘텐츠를 수정할 때마다 정적 검사와 실제 화면 검사를 구분해 실행한다.

```bash
go run ./tools/lovectl check
go run ./tools/lovectl test --artifacts artifacts/final
```

빠르게 한 장면만 확인하려면 게임을 열고 다른 터미널에서 원하는 stage를
지정한다.

```bash
go run ./tools/lovectl run
go run ./tools/lovectl stage stage.platformer_room
go run ./tools/lovectl overlay true
go run ./tools/lovectl screenshot artifacts/manual.png
```

화면 결과뿐 아니라 `lovectl world`로 위치, 속도, 충돌 layer, 체력,
현재 상태 효과, encounter wave와 boss phase를 함께 확인한다. 새 기능의
데이터 필드가 기존 어휘로 표현되지 않을 때만 feature를 추가한다.

같은 플레이어에 장비 능력치, NPC 대화, 처치 퀘스트와 상점을 붙여
액션 RPG로 만드는 흐름은 [RPG.md](RPG.md)에 이어진다.
