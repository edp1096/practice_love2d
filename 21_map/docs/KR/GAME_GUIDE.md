# 게임 콘텐츠 제작 가이드

이 가이드는 `game/` 폴더에서 게임 콘텐츠를 제작하는 방법을 소개합니다 - **RPG Maker 스타일**.

---

## 🎯 철학: 코드보다 콘텐츠

`game/` 폴더는 엔진 프로그래밍이 아닌 **콘텐츠 제작**을 위해 설계되었습니다:
- **최소한의 코드** - 주로 데이터 정의
- **간단한 API** - 엔진 함수 호출
- **빠른 반복** - 엔진을 건드리지 않고 콘텐츠 변경

---

## 🎬 씬(Scene) 만들기

### 씬 구조
씬은 `game/scenes/`에 위치합니다. 간단한 씬은 단일 파일로, 복잡한 씬은 모듈화된 폴더로 구성해야 합니다.

**단일 파일 씬 예제:**
```lua
-- game/scenes/credits.lua
local credits = {}

local scene_control = require "engine.scene_control"
local screen = require "lib.screen"

function credits:enter(previous, ...)
    self.text = "Thanks for playing!"
end

function credits:update(dt)
    -- Update logic
end

function credits:draw()
    love.graphics.print(self.text, 100, 100)
end

function credits:keypressed(key)
    if key == "escape" then
        local menu = require "game.scenes.menu"
        scene_control.switch(menu)
    end
end

return credits
```

**모듈화된 씬 예제:**
```
game/scenes/shop/
├── init.lua          - 씬 코디네이터
├── items.lua         - 상점 아이템 정의
├── render.lua        - UI 렌더링
└── input.lua         - 입력 처리
```

### 씬에서 엔진 시스템 사용하기
```lua
-- game/scenes/yourscene.lua
local scene_control = require "engine.scene_control"
local sound = require "engine.sound"
local input = require "engine.input"
local save_sys = require "engine.save"

function yourscene:enter()
    sound:playBGM("menu", 1.0, true)  -- 메뉴 음악 재생
end

function yourscene:keypressed(key)
    if input:wasPressed("confirm") then
        sound:playSFX("ui", "select")
        -- 무언가 수행
    end
end
```

---

## 🎮 엔티티 만들기

### 적(Enemy) 타입 예제
```lua
-- game/entities/enemy/types/goblin.lua
return {
    -- 스탯
    name = "Goblin",
    max_health = 50,
    damage = 10,
    speed = 120,

    -- 비주얼
    sprite_path = "assets/images/enemies/goblin.png",
    sprite_width = 32,
    sprite_height = 32,
    collider_width = 28,
    collider_height = 28,

    -- AI
    ai_type = "aggressive",
    chase_range = 200,
    attack_range = 40,
    patrol_speed = 60,

    -- 애니메이션
    animations = {
        idle = { frames = "1-4", fps = 8 },
        walk = { frames = "5-8", fps = 12 },
        attack = { frames = "9-12", fps = 16 }
    },

    -- 사운드
    sounds = {
        hurt = "enemy_hurt",
        death = "enemy_death",
        attack = "enemy_attack"
    }
}
```

### NPC 타입 예제
```lua
-- game/entities/npc/types/shopkeeper.lua
return {
    name = "Shopkeeper",
    sprite_path = "assets/images/npcs/shopkeeper.png",

    -- 대화
    dialogue = {
        "Welcome to my shop!",
        "What can I get you today?",
        "Come back soon!"
    },

    -- 상호작용
    on_interact = function(player, npc)
        local dialogue = require "engine.dialogue"
        dialogue:show(npc.config.dialogue, npc.avatar)
    end
}
```

### 아이템 타입 예제
```lua
-- game/entities/item/types/mega_potion.lua
return {
    id = "mega_potion",
    name = "Mega Potion",
    description = "Restores 100 HP",
    icon = "assets/images/items/mega_potion.png",
    max_stack = 50,

    use = function(player)
        local sound = require "engine.sound"

        if player.health < player.max_health then
            player.health = math.min(player.health + 100, player.max_health)
            sound:playSFX("player", "heal")
            return true  -- 아이템 소비됨
        else
            sound:playSFX("ui", "error")
            return false  -- 아이템 소비되지 않음
        end
    end
}
```

---

## 🎵 사운드 추가하기

### 1. 오디오 파일 추가
`assets/bgm/` 또는 `assets/sound/`에 파일을 배치하세요:
```
assets/
├── bgm/
│   └── dungeon.ogg
└── sound/
    ├── player/
    │   └── magic_cast.wav
    └── ui/
        └── coin.wav
```

### 2. 사운드 설정에 등록
`game/data/sounds.lua` 편집:
```lua
return {
    bgm = {
        dungeon = {
            path = "assets/bgm/dungeon.ogg",
            volume = 0.7,
            loop = true
        }
    },

    sfx = {
        player = {
            magic_cast = {
                path = "assets/sound/player/magic_cast.wav",
                volume = 0.8,
                pitch_variation = "normal"
            }
        },
        ui = {
            coin = {
                path = "assets/sound/ui/coin.wav",
                volume = 0.9
            }
        }
    }
}
```

### 3. 게임에서 재생
```lua
local sound = require "engine.sound"
sound:playBGM("dungeon")              -- 던전 BGM 재생
sound:playSFX("player", "magic_cast") -- 마법 캐스팅 사운드 재생
sound:playSFX("ui", "coin")           -- 코인 사운드 재생
```

---

## 🗺️ 맵 만들기

### 1. Tiled에서 맵 생성
- Tiled Map Editor를 사용하여 `.tmx` 파일 생성
- `assets/maps/levelX/`에 배치
- Lua 포맷(`.lua` 파일)으로 익스포트

### 2. 맵 속성 설정
Tiled에서 맵 커스텀 속성 설정:
```
Map Properties:
  game_mode = "topdown"  (또는 "platformer")
  bgm = "dungeon"        (선택사항 - sounds.lua의 BGM 이름)
```

### 3. 맵 레이어
필수 레이어:
- **Ground** - 지형 레이어
- **Trees** - 상단 장식 (엔티티 위에 그려짐)
- **Walls** - 충돌 오브젝트 (사각형, 다각형)
- **Portals** - 전환 구역
- **Enemies** - 적 스폰 포인트
- **NPCs** - NPC 위치
- **SavePoints** - 세이브 포인트 위치
- **HealingPoints** - 회복 구역

### 4. 포탈 추가
**Portals** 레이어에 오브젝트 생성:
```
Object Properties:
  type = "portal"
  target_map = "assets/maps/level1/area2.lua"
  spawn_x = 100
  spawn_y = 200
```

### 5. 적 추가
**Enemies** 레이어에 오브젝트 생성:
```
Object Properties:
  type = "goblin"  (game/entities/enemy/types/의 파일명과 일치)
  patrol_points = "100,200;300,200;300,400"  (선택사항)
```

### 6. 게임에서 맵 로드
```lua
-- 씬에서
local world = require "engine.world"
self.world = world:new("assets/maps/level1/dungeon.lua")
```

---

## ⌨️ 입력 설정하기

### 입력 설정 편집
`game/data/input_config.lua` 편집:
```lua
return {
    actions = {
        -- 이동
        move_left = {
            keys = {"a", "left"},
            gamepad = {"dpleft"}
        },
        move_right = {
            keys = {"d", "right"},
            gamepad = {"dpright"}
        },

        -- 전투
        attack = {
            mouse = {1},  -- 왼쪽 마우스 버튼
            gamepad = {"a"}
        },
        special_attack = {
            mouse = {2},  -- 오른쪽 마우스 버튼
            gamepad = {"x"},
            keys = {"e"}
        },

        -- 커스텀 액션
        magic = {
            keys = {"q"},
            gamepad = {"y"}
        }
    },

    -- 모드별 오버라이드
    mode_overrides = {
        platformer = {
            jump = { keys = {"w", "up", "space"}, gamepad = {"b"} }
        }
    }
}
```

### 게임에서 사용
```lua
local input = require "engine.input"

function play:update(dt)
    if input:wasPressed("magic") then
        -- 마법 시전
    end

    if input:isDown("attack") then
        -- 공격 차징
    end
end
```

---

## 🎞️ 컷씬 만들기

### 1. 컷씬 정의
`game/data/intro_configs.lua` 편집:
```lua
return {
    chapter1_intro = {
        background = "assets/images/cutscenes/chapter1_bg.png",
        bgm = "dramatic",
        messages = {
            "Long ago, in a distant land...",
            "A great evil awakened...",
            "Only one hero can stop it..."
        },
        speaker = "Narrator"
    }
}
```

### 2. 컷씬 트리거
```lua
local scene_control = require "engine.scene_control"
local intro = require "game.scenes.intro"

-- 인트로 표시 후 플레이 씬으로 이동
scene_control.switch(
    intro,
    "chapter1_intro",                    -- 인트로 ID
    "assets/maps/level1/area1.lua",      -- 인트로 후 타겟 맵
    400, 250,                             -- 스폰 위치
    1                                     -- 세이브 슬롯
)
```

---

## 💾 세이브 시스템 사용하기

### 게임 저장
```lua
local save_sys = require "engine.save"

function play:saveGame()
    local save_data = {
        hp = self.player.health,
        max_hp = self.player.max_health,
        map = self.current_map_path,
        x = self.player.x,
        y = self.player.y,
        inventory = self.inventory:save()
    }

    save_sys:saveGame(self.current_save_slot, save_data)
end
```

### 게임 로드
```lua
local save_sys = require "engine.save"

function menu:loadGame(slot)
    local save_data = save_sys:loadGame(slot)

    if save_data then
        local play = require "game.scenes.play"
        scene_control.switch(play, save_data.map, save_data.x, save_data.y, slot)
    end
end
```

---

## 🎨 HUD 커스터마이징

HUD는 `engine/hud.lua`에서 렌더링되지만, 색상/레이아웃을 커스터마이징할 수 있습니다:

```lua
-- 플레이 씬에서
local hud = require "engine.hud"

function play:draw()
    -- ... 게임 월드 그리기 ...

    -- 커스텀 색상으로 HUD 그리기
    love.graphics.setColor(1, 1, 1)
    hud:draw(self.player, self.inventory)
end
```

주요 HUD 변경이 필요한 경우, 엔진 함수를 호출하는 커스텀 HUD를 `game/`에 생성하는 것을 고려하세요.

---

## 🚀 빠른 레시피

### 새 레벨 추가
1. Tiled에서 맵 생성: `assets/maps/level2/castle.tmx`
2. Lua로 익스포트: `assets/maps/level2/castle.lua`
3. BGM 추가: `game/data/sounds.lua` → `bgm.castle = { ... }`
4. 맵 속성 설정: `bgm = "castle"`
5. 이전 레벨에서 포탈 생성

### 새 적 추가
1. 스프라이트 생성: `assets/images/enemies/dragon.png`
2. 타입 생성: `game/entities/enemy/types/dragon.lua`
3. Tiled 맵에 배치: Object type = "dragon"

### 새 아이템 추가
1. 아이콘 생성: `assets/images/items/sword.png`
2. 타입 생성: `game/entities/item/types/sword.lua`
3. 인벤토리에 추가: `inventory:addItem("sword", 1)`

### 새 메뉴 추가
1. 씬 생성: `game/scenes/credits.lua`
2. 메인 메뉴 옵션에 추가: `{ "Credits", ... }`
3. 전환: `scene_control.switch(credits)`

---

## 📋 체크리스트: 엔진으로 새 게임 시작하기

이 엔진을 사용하여 새 게임 시작하기:

1. ✅ `engine/` 폴더 복사
2. ✅ `game/` 폴더 삭제
3. ✅ 새 `game/` 생성:
   - `game/scenes/` - 게임 씬
   - `game/entities/` - 캐릭터들
   - `game/data/` - 설정 파일들
4. ✅ 리소스가 포함된 `assets/` 생성
5. ✅ 게임 타이틀로 `conf.lua` 업데이트
6. ✅ 첫 번째 씬을 로드하도록 `main.lua` 업데이트
7. ✅ 콘텐츠 제작 시작!

---

**참고 자료:**
- [ENGINE_GUIDE.md](ENGINE_GUIDE.md) - 엔진 시스템 레퍼런스
- [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) - 전체 구조
