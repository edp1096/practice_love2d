# RPG·액션 RPG 조립 가이드

이 문서는 엔진 코드를 수정하지 않고 `game/content`의 데이터만으로
NPC, 대화, 아이템, 장비, 퀘스트와 상점을 연결하는 가장 짧은 경로다.
전투가 필요하면 [ACTION.md](ACTION.md)의 actor와 ability를 같은
stage에 함께 배치한다.

현재 실행되는 완성 예제:

- 마을: `game/content/stages/rpg_village.lua`
- 안내인·상인: `game/content/actors/guide.lua`, `merchant.lua`
- 분기 대화: `game/content/dialogues/guide.lua`
- 처치 퀘스트: `game/content/quests/slime_patrol.lua`
- 소비·장비 아이템: `game/content/items`
- 상점: `game/content/shops/village.lua`
- 한글·영문: `game/content/locales`

## 무엇을 어디서 바꾸는가

| 만들려는 것 | 편집 위치 | 엔진 수정 |
|---|---|---|
| NPC와 상호작용 범위 | `content/actors` | 불필요 |
| 대사·선택지·분기 | `content/dialogues` | 불필요 |
| 번역 문장 | `content/locales` | 불필요 |
| 퀘스트 목표·보상 | `content/quests` | 불필요 |
| 소비품·장비 수치 | `content/items` | 불필요 |
| 판매 목록·가격 | `content/shops` | 불필요 |
| NPC·적·벽 배치 | `content/stages` 또는 Tiled | 불필요 |
| 새 효과나 새 판정 방식 | `engine/features` | 새 어휘일 때만 필요 |

콘텐츠 파일은 서로의 경로가 아니라 ID로 연결된다. 파일을 옮겨도 ID가
같으면 참조는 유지된다.

## 1. 표시 문장을 Locale에 먼저 넣는다

```lua
return {
    schema_version = 1,
    kind = "locale",
    id = "locale.ko",
    name = "한국어",
    code = "ko",
    strings = {
        ["npc.guide.name"] = "길드 안내인",
        ["dialogue.guide.greeting"] = "도와주시겠습니까?",
        ["dialogue.guide.accept"] = "제가 처리하겠습니다.",
        ["quest.slime_patrol.name"] = "동쪽 길 순찰",
        ["item.training_sword.name"] = "연습용 검",
    },
}
```

다른 언어 파일도 같은 키를 사용한다. 키가 빠지면 manifest의 fallback
locale을 찾는다. 문장 자체를 dialogue에 직접 쓸 수도 있지만 번역할
프로젝트라면 처음부터 `text_key`, `name_key`를 쓰는 편이 단순하다.

## 2. 아이템과 장비를 만든다

소비품:

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

장비:

```lua
return {
    schema_version = 1,
    kind = "item",
    id = "item.training_sword",
    name_key = "item.training_sword.name",
    stack_limit = 1,
    value = 60,
    equipment = {
        slot = "weapon",
        modifiers = {
            attack = 5,
        },
    },
}
```

장비를 쓰는 actor에는 `rpg.stats`와 `rpg.equipment`를 붙인다.

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

지원하는 기본 stat은 `attack`, `defense`, `move_speed`다. 장비
`modifiers`는 기본값에 더해진다. 장착하려면 아이템이 inventory에
먼저 있어야 한다.

```lua
actions = {
    {type = "give_item", item = "item.training_sword"},
    {type = "equip_item", item = "item.training_sword"},
}
```

## 3. Event로 진행되는 Quest를 만든다

퀘스트 목표는 다른 기능이 발행한 event 이름과 payload 필터를
구독한다.

```lua
return {
    schema_version = 1,
    kind = "quest",
    id = "quest.slime_patrol",
    name_key = "quest.slime_patrol.name",
    description_key = "quest.slime_patrol.description",
    objectives = {
        {
            id = "defeat_slimes",
            event = "actor.killed",
            count = 2,
            where = {
                actor_id = "actor.slime",
            },
        },
    },
    on_complete = {
        {type = "give_item", item = "item.potion"},
        {
            type = "add_currency",
            amount = 100,
            reason = "quest.slime_patrol",
        },
        {
            type = "set_flag",
            name = "quest.slime_patrol.rewarded",
        },
    },
}
```

`where`의 모든 필드가 event payload와 같을 때만 한 번 진행된다. 예를
들어 특정 배치만 세려면 event가 제공하는 `target_id`를 필터에 넣고,
같은 종류의 적 전체를 세려면 `actor_id`를 쓴다.

퀘스트 정의는 진행 중인 모든 World에서 자동 구독된다. stage를
바꾸어도 진행도는 session에 유지되고 새 World의 event에 다시
연결된다.

## 4. 조건부 Dialogue를 만든다

```lua
return {
    schema_version = 1,
    kind = "dialogue",
    id = "dialogue.guide",
    name_key = "dialogue.guide.name",
    start = "greeting",
    nodes = {
        greeting = {
            speaker_key = "npc.guide.name",
            text_key = "dialogue.guide.greeting",
            choices = {
                {
                    id = "accept",
                    text_key = "dialogue.guide.accept",
                    condition = {
                        type = "quest_state",
                        quest = "quest.slime_patrol",
                        state = "inactive",
                    },
                    actions = {
                        {
                            type = "start_quest",
                            quest = "quest.slime_patrol",
                        },
                        {
                            type = "give_item",
                            item = "item.training_sword",
                        },
                        {
                            type = "equip_item",
                            item = "item.training_sword",
                        },
                    },
                    next = "accepted",
                },
            },
        },
        accepted = {
            speaker_key = "npc.guide.name",
            text_key = "dialogue.guide.accepted",
        },
    },
}
```

node의 `actions`는 node 진입 때, choice의 `actions`는 선택 때
실행된다. `next`가 없으면 확인 뒤 대화가 닫힌다. 존재하지 않는 node,
quest, item이나 잘못 쓴 필드는 실행 전에 오류가 난다.

퀘스트 상태별 choice를 각각 두면 한 NPC가 수락 전, 진행 중, 완료 후
대사를 모두 담당할 수 있다.

## 5. NPC가 Dialogue나 Shop을 열게 한다

대화 NPC:

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

상점 NPC:

```lua
["rpg.interactable"] = {
    input = "interact",
    range = 70,
    prompt_key = "interaction.shop",
    actions = {
        {
            type = "open_shop",
            shop = "shop.village",
        },
    },
}
```

상점 목록:

```lua
return {
    schema_version = 1,
    kind = "shop",
    id = "shop.village",
    name_key = "shop.village.name",
    offers = {
        {
            item = "item.potion",
            buy_price = 25,
            sell_price = 10,
        },
        {
            item = "item.training_sword",
            sell_price = 30,
        },
    },
}
```

`buy_price`만 있으면 판매 전용, `sell_price`만 있으면 매입 전용으로
쓸 수 있다. 구매는 stack limit과 소지금을 먼저 확인하고, 판매는
inventory 제거가 허용된 뒤에만 돈을 더한다. 따라서 실패한 거래가
수량이나 잔액 일부만 바꾸지 않는다.

## 6. Stage에는 ID로 배치한다

```lua
spawns = {
    {
        id = "player",
        actor = "actor.hero",
        position = {x = 150, y = 270},
    },
    {
        id = "guide",
        actor = "actor.guide",
        position = {x = 260, y = 240},
    },
    {
        id = "quest.slime.1",
        actor = "actor.slime",
        position = {x = 620, y = 215},
    },
}
```

stage는 퀘스트 로직을 알지 않는다. 퀘스트는 `actor.killed` event를
듣고, dialogue는 quest condition을 읽는다. 같은 slime actor를 다른
stage에 놓아도 필요하면 같은 목표에 포함시킬 수 있다.

## 7. 순수 RPG 턴제 전투를 연결한다

순수 RPG profile은 실시간 hitbox 대신 `rpg.turn_battle` feature를
사용한다. 스킬은 효과·대상·위력만 가진 데이터다.

```lua
return {
    schema_version = 1,
    kind = "turn_skill",
    id = "turn_skill.strike",
    name_key = "skill.strike.name",
    effect = "damage",
    target = "enemy",
    power = 12,
}
```

플레이어와 적 actor에는 체력·스탯·사용 스킬을 조합한다.

```lua
["action.health"] = {max = 100, remove_on_death = false},
["rpg.stats"] = {attack = 2, defense = 1, move_speed = 1},
["rpg.turn_battler"] = {
    skills = {"turn_skill.strike", "turn_skill.mend"},
},
```

전투 정의는 적 actor 편성과 승리·도주·패배 뒤 명령을 소유한다.

```lua
return {
    schema_version = 1,
    kind = "turn_battle",
    id = "turn_battle.training_slime",
    name_key = "battle.training_slime.name",
    allow_escape = true,
    enemies = {
        {id = "slime", actor = "actor.turn_slime"},
    },
    on_victory = {
        {type = "set_flag", name = "battle.slime.cleared"},
    },
}
```

NPC 상호작용이나 trigger에서
`{type = "start_turn_battle", battle = "turn_battle.training_slime"}`
을 실행하면 전투 화면이 열린다. 플레이어의 실제 HP와 장비 포함
attack·defense를 사용하고 결과는 `rpg.turn_battles` save section에
남는다. 기본 전투는 한 번 승리하면 다시 열리지 않으며 반복 전투는
`repeatable = true`로 명시한다.

승리 시 `turn_battle.won` event가 `battle_id`와 함께 발행되므로 퀘스트
목표가 직접 구독할 수 있다. `turn_battle_state` 조건은 `never`,
`active`, `won`, `lost`, `escaped`를 검사한다. 생성 profile의
`turn_battle.training_slime`이 의뢰 수락부터 엔딩까지의 완전한 예다.

## 자주 쓰는 RPG Rules 어휘

액션:

- 상태: `set_flag`, `clear_flag`, `set_locale`
- 소지품: `give_item`, `take_item`, `use_item`
- 장비: `equip_item`, `unequip_slot`
- 대화·퀘스트·전투: `start_dialogue`, `close_dialogue`, `start_quest`,
  `start_turn_battle`
- 경제·상점: `add_currency`, `spend_currency`, `open_shop`,
  `close_shop`, `buy_item`, `sell_item`
- 화면 피드백: `show_notice`
- 전투와 공용: `heal`, `damage`, `apply_status`, `emit` 등

조건:

- 조합: `always`, `all`, `any`, `not`
- 상태: `flag`, `locale_is`
- 소지품·장비: `has_item`, `item_equipped`
- 대화·퀘스트: `dialogue_active`, `quest_state`,
  `quest_objective`
- 경제·상점: `currency_at_least`, `shop_active`
- 전투: `health_at_most`, `has_status`, `encounter_state`
- 턴제 전투: `turn_battle_state`

정확한 필드는 실제 예제와 [CONTENT.md](CONTENT.md)를 기준으로 한다.
필드명을 추측해 추가하면 validator가 거부한다.

## 확인 순서

```bash
go run ./tools/lovectl check
go run ./tools/lovectl run
```

게임을 켠 채 다른 터미널에서 마을을 열 수 있다.

```bash
go run ./tools/lovectl stage stage.rpg_village
go run ./tools/lovectl world
go run ./tools/lovectl screenshot artifacts/rpg_manual.png
```

전체 RPG 흐름까지 자동 검증하려면:

```bash
go run ./tools/lovectl test --artifacts artifacts/final
```

이 테스트는 한글 대화 열기, 퀘스트 수락, 검 획득·장착, 장비가 반영된
실제 공격, 두 슬라임 처치, 보상, 구매·판매 보호와 stage 전환 뒤 상태
보존을 실제 LÖVE 프레임으로 확인한다.
