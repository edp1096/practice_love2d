# 새 게임 만들기

이 엔진으로 나만의 게임을 만드는 단계별 가이드입니다.

---

## 준비물

- LÖVE 11.5 설치
- Tiled 맵 에디터 (맵 제작용)
- Lua 기초 지식

---

## 1단계: 엔진 복사

```bash
# 전체 프로젝트 폴더 복사
cp -r 29_indoor 내_새_게임
cd 내_새_게임
```

`engine/` 폴더는 100% 재사용 가능 - 수정하지 마세요.

---

## 2단계: 게임 데이터 커스터마이징

`game/data/` 폴더의 파일들을 수정:

### `game/data/player.lua` (플레이어 스탯)
```lua
return {
    max_health = 100,
    base_damage = 10,
    move_speed = 200,
    -- ... 스탯 커스터마이징
}
```

### `game/data/entities/types.lua` (적/NPC)
```lua
enemies.goblin = {
    name = "고블린",
    hp = 50,
    dmg = 15,
    spd = 80,
    spr = "assets/images/goblin-sheet.png",
    -- ... 더 많은 적 추가
}
```

### `game/data/quests.lua` (퀘스트)
```lua
quests.my_first_quest = {
    id = "my_first_quest",
    title = "고블린 5마리 처치",
    objectives = {
        { type = "kill", target = "goblin", count = 5 }
    },
    giver_npc = "village_elder",
    rewards = { gold = 100, exp = 50 }
}
```

### `game/data/dialogues.lua` (대화 트리)
```lua
dialogues.village_elder = {
    start_node = "greeting",
    nodes = {
        greeting = {
            text = "환영하네, 여행자!",
            choices = {
                { text = "퀘스트 있나요?", next = "quest_offer" },
                { text = "안녕히 계세요", next = "end" }
            }
        }
    }
}
```

### `game/data/scenes.lua` (메뉴 설정)
```lua
scenes.menu = {
    title = "내 새 게임",
    options = {
        { text = "새 게임", action = "new_game" },
        { text = "이어하기", action = "load_recent_save" },
        { text = "종료", action = "quit" }
    }
}
```

---

## 3단계: 게임 씬 업데이트

씬은 각 6줄 - 복사해서 이름만 바꾸면 됨:

```lua
-- game/scenes/menu.lua
local builder = require "engine.scenes.builder"
local scene_configs = require "game.data.scenes"
return builder:build("menu", scene_configs)
```

---

## 4단계: 에셋 준비

### `assets/` 폴더 구조:
```
assets/
├── images/
│   ├── goblin-sheet.png  (적 스프라이트)
│   ├── player-sheet.png  (플레이어 스프라이트)
│   └── items/            (아이템 아이콘)
├── maps/
│   └── level1/
│       └── area1.tmx     (Tiled 맵)
└── sounds/
    ├── bgm/              (배경 음악)
    └── sfx/              (효과음)
```

### Tiled에서 맵 제작:
1. Tiled 실행 후 새 맵 생성
2. 레이어 추가: `Ground`, `Decos`, `Walls`, `Portals`, `Enemies`, `NPCs`
3. 맵 속성 설정:
   - `game_mode` = `"topdown"` 또는 `"platformer"`
   - `bgm` = `"level1"` (선택사항)
   - `move_mode` = `"walk"` (선택사항, 실내맵용 - 느린 걷기 속도)
4. Lua로 내보내기 (TMX 아님)

---

## 5단계: Setup 설정

`game/setup.lua`를 수정해서 데이터 주입:

```lua
-- 자동으로 로드됨 - 모든 데이터 파일이 import되는지만 확인:
local entity_types = require "game.data.entities.types"
local quests = require "game.data.quests"
local dialogues = require "game.data.dialogues"
-- ...
```

---

## 6단계: 게임 실행

```bash
love .
```

조작법:
- WASD - 이동
- 마우스 - 조준
- 좌클릭 - 공격
- F - 상호작용

---

## 빠른 체크리스트

```
[ ] engine 폴더 복사
[ ] game/data/player.lua 수정
[ ] game/data/entities/types.lua 수정 (적/NPC)
[ ] game/data/quests.lua 수정
[ ] game/data/dialogues.lua 수정
[ ] game/data/scenes.lua 수정
[ ] Tiled에서 맵 제작 (.lua로 내보내기)
[ ] 에셋 추가 (스프라이트, 사운드)
[ ] 실행: love .
```

---

## 팁

**새 적 추가 (코드 불필요):**
1. 스프라이트 생성: `assets/images/enemies/yourenemy.png`
2. Tiled 맵에 추가 (Object에 `type = "yourenemy"`)
3. 커스텀 속성 설정: `hp`, `dmg`, `spd`, `spr`

**새 퀘스트 추가:**
1. `game/data/quests.lua`에 추가
2. `game/data/dialogues.lua`에 대화 선택지 추가

**새 아이템 추가:**
1. 아이콘 생성: `assets/images/items/youritem.png`
2. `game/data/items/consumables/youritem.lua`에 추가
3. `name`, `description`, `use()` 함수 정의

**무기 변형 추가 (예: 강화 버전):**
1. `game/data/items/weapons/yourweapon.lua`에 추가
2. `weapon_type` 설정 (sword/axe/club/staff)
3. `stats` 배율 설정 (damage: 가산, range/speed: 곱연산)
4. `game/data/items/init.lua`에 등록

---

## 더 보기

- 전체 구조: [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) 참고
- 완전한 가이드: [GUIDE.md](GUIDE.md) 참고
- 빠른 시작: [README.md](README.md) 참고
