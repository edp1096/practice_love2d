# 개발 가이드

LÖVE2D 게임 엔진 개발을 위한 실용적인 가이드입니다. 자세한 API 참조는 [CLAUDE.md](../CLAUDE.md)를 참조하세요.

---

## 목차

1. [빠른 시작](#빠른-시작)
2. [핵심 개념](#핵심-개념)
3. [콘텐츠 만들기](#콘텐츠-만들기)
4. [지속성 시스템](#지속성-시스템)
5. [일반 작업](#일반-작업)
6. [모범 사례](#모범-사례)

---

## 빠른 시작

### 게임 실행

```bash
# 데스크톱
love .

# 웹 (웹 개발 섹션 참조)
npm run build && cd web_build && lua server.lua 8080

# 문법 검사
luac -p **/*.lua
```

### 프로젝트 구조

```
29_indoor/
├── engine/           # 재사용 가능 게임 엔진 (100% 재사용 가능)
├── game/             # 게임 특화 콘텐츠
│   ├── data/         # 설정 파일 (player, quests, dialogues 등)
│   └── scenes/       # 게임 씬
├── vendor/           # 외부 라이브러리
├── assets/           # 게임 리소스
├── main.lua          # 진입점 (의존성 주입)
└── conf.lua          # LÖVE 설정
```

### 첫 단계

1. **플레이어 스탯 수정:** `game/data/player.lua` 편집
2. **메뉴 변경:** `game/data/scenes.lua` 편집
3. **적 추가:** Tiled 맵에 속성과 함께 배치
4. **맵 만들기:** Tiled 사용, Lua로 내보내기

---

## 핵심 개념

### Engine/Game 분리

**규칙:** Engine은 절대 game 파일을 import하지 않음, game만 engine을 import.

```lua
-- 좋음: game/scenes/menu.lua
local builder = require "engine.scenes.builder"

-- 나쁨: engine/core/sound.lua
local sounds = require "game.data.sounds"  -- 절대 하지 마세요!
```

**해결책:** `main.lua`에서 의존성 주입:

```lua
local player_module = require "engine.entities.player"
local player_config = require "game.data.player"
player_module.config = player_config  -- 게임 설정 주입!
```

### 게임 모드

두 가지 모드 지원: **topdown**과 **platformer**.

Tiled 맵 속성에서 설정: `game_mode = "topdown"`

**주요 차이점:**
- **Topdown:** 중력 없음, 자유 2D 이동, 이중 충돌체 (foot + main)
- **Platformer:** 중력 활성화, 점프 메커니즘, 수평 거리 체크

### 좌표 시스템

변환에는 항상 `engine/core/coords.lua` 사용:

```lua
local coords = require "engine.core.coords"

-- World ↔ Camera (렌더링용)
local cam_x, cam_y = coords:worldToCamera(x, y, camera)

-- Physical ↔ Virtual (터치 입력용)
local vx, vy = coords:physicalToVirtual(touch_x, touch_y, display)
```

### 씬 관리

```lua
local scene_control = require "engine.core.scene_control"

scene_control.switch(scene, ...)  -- 새 씬으로 전환
scene_control.push(scene, ...)    -- 스택에 푸시 (일시정지 메뉴)
scene_control.pop()               -- 이전 씬으로 복귀
```

---

## 콘텐츠 만들기

### 새 적 추가하기 (데이터 기반!)

**코드 불필요!** Tiled에서만 설정:

1. 맵 열기: `assets/maps/level1/area1.tmx`
2. "Enemies" 레이어에 오브젝트 추가
3. 오브젝트 타입 설정: `slime`, `goblin` 등
4. 커스텀 속성 추가 (선택):
   ```
   hp = 100          (체력)
   dmg = 10          (데미지)
   spd = 50          (속도)
   det_rng = 200     (감지 범위)
   respawn = false   (일회성 적, 기본값: true)
   ```
5. Lua로 내보내기
6. 완료! 해당 스탯으로 적이 스폰됩니다.

**사용 가능한 적 타입:** `game/data/entities/types.lua` 참조

**팩토리 기본값:** `engine/systems/entity_factory.lua` DEFAULTS 섹션 참조

### 새 메뉴 씬 추가하기 (데이터 기반!)

1. `game/data/scenes.lua`에 추가:

```lua
scenes.mymenu = {
  type = "menu",
  title = "내 메뉴",
  options = {"시작", "설정", "종료"},
  actions = {
    ["시작"] = {action = "switch_scene", scene = "play"},
    ["설정"] = {action = "switch_scene", scene = "settings"},
    ["종료"] = {action = "quit"}
  },
  back_action = {action = "quit"},

  -- 선택: 플래시 효과
  flash = {
    enabled = true,
    color = {1, 0, 0},     -- 빨간색 플래시
    initial_alpha = 1.0,
    fade_speed = 2.0
  }
}
```

2. 파일 생성 `game/scenes/mymenu.lua`:

```lua
local builder = require "engine.scenes.builder"
local configs = require "game.data.scenes"
return builder:build("mymenu", configs)
```

완료! 단 6줄입니다.

### 새 아이템 추가하기

1. 아이콘 생성: `assets/images/items/youritem.png`
2. 타입 생성: `engine/entities/item/types/youritem.lua`:

```lua
local youritem = {
  name = "내 아이템",
  description = "유용한 아이템",
  icon = "assets/images/items/youritem.png",
  max_stack = 99,

  -- 선택: 장비
  equipment_slot = "weapon",  -- 또는 "armor", "accessory"
  weapon_type = "sword",      -- 무기인 경우

  -- 선택: 소모품
  consumable = true,
  effect = function(player)
    player.health = math.min(player.health + 50, player.max_health)
  end
}

return youritem
```

3. 월드 또는 인벤토리에 추가:

```lua
-- 월드에 드롭
world:addWorldItem("youritem", x, y, quantity)

-- 인벤토리에 추가
inventory:addItem("youritem", 1)
```

### NPC 대화 추가하기

게임은 두 가지 대화 모드를 지원합니다: **간단한 대화**와 **트리 대화** (선택지 기반 대화).

#### 간단한 대화 (빠른 메시지)

기본 NPC 메시지의 경우, Tiled에서 직접 설정:

```
NPC 속성: dlg = "안녕하세요, 여행자님! 우리 마을에 오신 것을 환영합니다."
```

여러 메시지 (세미콜론으로 구분):

```
dlg = "환영합니다!;무엇을 도와드릴까요?;다시 오세요!"
```

**플레이어는 다음으로 진행:**
- **키보드:** F 키 / Z 키 / Enter
- **게임패드:** A 버튼 (Xbox) / Cross (PS) / Y 버튼
- **마우스/터치:** 대화창 아무 곳이나 클릭

#### 트리 대화 (RPG 스타일 대화)

플레이어 선택지가 있는 인터랙티브 대화의 경우, 대화 트리를 생성합니다.

**1단계: `game/data/dialogues.lua`에 대화 트리 생성**

```lua
local dialogues = {}

dialogues.shopkeeper = {
  start_node = "greeting",
  nodes = {
    -- 초기 인사 (자동 진행)
    greeting = {
      text = "제 상점에 오신 것을 환영합니다!",
      speaker = "상점주인",
      next = "main_menu"
    },

    -- 선택지가 있는 메인 메뉴
    main_menu = {
      text = "오늘 무엇을 도와드릴까요?",
      speaker = "상점주인",
      choices = {
        { text = "판매하는 물건에 대해 알려주세요", next = "items" },
        { text = "최근 소문이 있나요?", next = "rumors" },
        { text = "물건을 사고 싶어요", next = "shop" },
        { text = "안녕히 계세요", next = "end" }
      }
    },

    -- 아이템 정보 (메뉴로 루프백)
    items = {
      text = "포션, 무기, 방어구를 판매합니다. 모두 최고급이에요!",
      speaker = "상점주인",
      next = "main_menu"  -- 메뉴로 루프백
    },

    -- 소문 (다중 페이지 대화)
    rumors = {
      pages = {
        "들으셨나요? 북쪽 숲에서 이상한 활동이 있다고 해요...",
        "여행자들이 밤에 이상한 불빛을 봤다고 보고했어요.",
        "어떤 사람들은 마법이라고 하고, 다른 사람들은 그냥 반딧불이라고 해요.",
        "저라면 가까이 가지 않을 거예요!"
      },
      speaker = "상점주인",
      next = "main_menu"  -- 메뉴로 루프백
    },

    -- 상점 (실제 게임에서는 상점 UI 열림)
    shop = {
      text = "이게 제가 가진 재고예요. 구경하세요!",
      speaker = "상점주인",
      next = "main_menu"
    },

    -- 종료
    ["end"] = {
      text = "언제든 다시 오세요! 안전한 여행 되세요!",
      speaker = "상점주인"
      -- choices 없음, next 없음 = 대화 종료
    }
  }
}

return dialogues
```

**2단계: Tiled에서 NPC 속성 설정**

```
dlg = "shopkeeper"
```

**3단계: 완료!** NPC가 인터랙티브 대화 트리를 표시합니다.

#### 대화 네비게이션

**키보드:**
- **위/아래** 또는 **W/S** - 선택지 탐색
- **Enter** 또는 **Z** - 선택지 선택
- **F** - 대화 진행 (선택지 없을 때)

**마우스/터치:**
- **호버** - 선택지 강조
- **클릭** - 선택지 선택 / 대화 진행

**게임패드:**
- **D-Pad** 또는 **Left Stick** - 선택지 탐색
- **A 버튼** (Xbox) / Cross (PS) - 선택 / 진행
- **Y 버튼** (Xbox) / Triangle (PS) - A와 동일
- **B 버튼** (Xbox) / Circle (PS) - 0.5초 홀드로 대화 건너뛰기 (충전 인디케이터)

#### 대화 노드 속성

**필수:**
- `text` (string) - 단일 메시지
- 또는 `pages` (array) - 다중 페이지 대화 (비주얼 노벨 스타일)

**선택:**
- `speaker` (string) - 캐릭터 이름 (대화창 위에 표시)
- `choices` (array) - 플레이어 선택지: `{ text = "...", next = "node_id" }`
- `next` (string) - 다음 노드로 자동 진행 (선택지 없을 때)

**`next` 없고 `choices` 없음 = 대화 종료**

#### 고급: 다중 페이지 대화

더 긴 대화의 경우, `text` 대신 `pages` 사용:

```lua
story = {
  pages = {
    "오래 전, 먼 땅에서...",
    "알드릭이라는 강력한 마법사가 살았습니다.",
    "그는 많은 마법 아이템을 만들었어요.",
    "그 중 하나가 전설의 빛의 수정이었습니다!",
    "하지만 그건 다음 기회에 이야기해 드릴게요..."
  },
  speaker = "장로",
  next = "main_menu"
}
```

플레이어는 동일한 컨트롤로 페이지를 진행합니다 (F 키, 클릭, A 버튼).

#### RPG 대화 패턴 (권장)

**모범 사례:** 인사 → 메인 메뉴 → 선택지가 메뉴로 루프백

```lua
dialogues.quest_giver = {
  start_node = "greeting",
  nodes = {
    greeting = {
      text = "아, 모험가시군요! 딱 좋은 타이밍이에요!",
      speaker = "퀘스트 제공자",
      next = "main_menu"  -- 메뉴로 자동 진행
    },
    main_menu = {
      text = "무엇을 도와드릴까요?",
      speaker = "퀘스트 제공자",
      choices = {
        { text = "퀘스트가 있나요?", next = "quest" },
        { text = "이 마을에 대해 알려주세요", next = "town" },
        { text = "이제 가보겠습니다", next = "end" }
      }
    },
    quest = {
      text = "네! 동굴에서 잃어버린 물건을 찾아올 사람이 필요해요.",
      speaker = "퀘스트 제공자",
      next = "main_menu"  -- 루프백!
    },
    town = {
      text = "우리 마을은 평화로웠는데, 최근 몬스터가 나타나기 시작했어요.",
      speaker = "퀘스트 제공자",
      next = "main_menu"  -- 루프백!
    },
    ["end"] = {
      text = "여정에 행운을 빕니다!",
      speaker = "퀘스트 제공자"
    }
  }
}
```

**장점:**
- 플레이어가 대화를 다시 시작하지 않고 여러 질문 가능
- 자연스러운 RPG 대화 흐름
- 새 대화 분기 추가가 쉬움

### 새 맵 만들기

1. Tiled에서 생성: `assets/maps/level1/newarea.tmx`

2. 맵 속성 설정:
   ```
   name = "level1_newarea"      (필수: 지속성용)
   game_mode = "topdown"        (또는 "platformer")
   bgm = "level1"               (선택)
   ambient = "day"              (선택: day, night, cave, dusk, indoor, underground)
   ```

3. 필요한 레이어 추가:
   - **Ground** - 지형 타일
   - **Trees** - 깊이가 있는 타일 (topdown에서 Y-정렬)
   - **Walls** - 충돌 오브젝트 (rectangle, polygon, polyline, ellipse)
   - **Portals** - 맵 전환
   - **Enemies**, **NPCs** - 스폰 지점
   - **WorldItems** - 획득 가능 아이템
   - **SavePoints**, **HealingPoints** - 상호작용 지점

4. Lua로 내보내기

5. 이전 맵에서 포털 생성:
   ```
   type = "portal"
   target_map = "assets/maps/level1/newarea.lua"
   spawn_x = 100
   spawn_y = 200
   ```

### 배경음악 추가하기

1. 파일 배치: `assets/bgm/yourmusic.ogg`
2. `game/data/sounds.lua`에 등록:

```lua
bgm = {
  yourmusic = {
    path = "assets/bgm/yourmusic.ogg",
    volume = 0.7,
    loop = true
  }
}
```

3. Tiled 맵 속성에 설정: `bgm = "yourmusic"`

### 패럴랙스 배경 추가하기

깊이감 있는 다중 레이어 스크롤 배경을 만듭니다.

1. **이미지 준비:**
   - `assets/backgrounds/`에 배치
   - 예: `layer1_sky.png`, `layer2_mountains.png` 등

2. **Tiled 맵에서 "Parallax" objectgroup 레이어 생성**

3. **오브젝트 추가 (레이어당 하나씩) 및 커스텀 속성 설정:**

```
오브젝트 1 (하늘):
  Name: "sky" (참고용)
  Type: 비워둠 (Tiled에 type 필드 없을 수 있음)

  커스텀 속성 (추가 필수!):
    Type (string) = "parallax"                       ← 필수!
    image (string) = "assets/backgrounds/layer1_sky.png"
    parallax_factor (float) = 0.1                    (0.0 = 고정, 1.0 = 일반)
    z_index (int) = 1                                (낮을수록 뒤에)
    repeat_x (bool) = true                           (가로 타일링)
    offset_y (float) = 0                             (세로 위치)
    auto_scroll_x (float) = 0                        (선택: 자동 스크롤)

오브젝트 2 (산):
  커스텀 속성:
    Type = "parallax"
    image = "assets/backgrounds/layer2_mountains.png"
    parallax_factor = 0.3
    z_index = 2
    repeat_x = true
    offset_y = 0

오브젝트 3 (구름):
  커스텀 속성:
    Type = "parallax"
    image = "assets/backgrounds/layer3_clouds.png"
    parallax_factor = 0.5
    z_index = 3
    repeat_x = true
    offset_y = 0
    auto_scroll_x = 10                               ← 구름 표류 효과!
```

4. **맵을 Lua로 내보내기**

**결과:** 깊이감 있는 무한 스크롤 배경!

**팁:**
- parallax_factor가 낮을수록 = 느린 스크롤 = 멀리 있음
- offset_y로 세로 위치 조정
- auto_scroll_x로 표류 효과 (구름, 안개 등)
- 탑다운/플랫포머 모드 모두 작동

---

## 고급 기능

### 엔티티 변환 시스템

**런타임 NPC ↔ 적 변환**으로 완전한 지속성 제공:

#### NPC → 적 (적대적 변환)

대화 액션으로 트리거:

```lua
-- game/data/dialogues.lua
dialogues.deceiver_greeting = {
    start_node = "start",
    nodes = {
        hostile = {
            text = "이제 넌 살아서 돌아갈 수 없어!",
            speaker = "사기꾼",
            action = {
                type = "transform_to_enemy",
                enemy_type = "deceiver_01"
            }
        }
    }
}
```

**작동 방식:**
1. 대화 노드 액션 실행 (`engine/ui/dialogue/core.lua:396`)
2. `dialogue.world:transformNPCToEnemy(npc_id, enemy_type)` 호출
3. NPC 제거, 같은 위치에 적 생성
4. 적 즉시 공격 모드 (state = "chase")
5. 대화 자동 종료

#### 적 → NPC (항복)

적 타입 설정:

```lua
-- game/data/entities/types.lua
enemies = {
    bandit = {
        health = 120,
        surrender_threshold = 0.3,  -- HP 30%에서 항복
        surrender_npc = "surrendered_bandit"
    }
}
```

**작동 방식:**
1. 적 HP가 임계값 이하로 떨어짐
2. `world:transformEnemyToNPC()` 자동 호출
3. 적 제거, 대화 가능한 NPC 생성
4. 원본 적은 "처치됨"으로 표시 (리스폰 안 됨)
5. 변환 정보 디스크에 저장

#### 지속성

변환은 다음 상황에서도 유지:
- 맵 전환
- 저장/로드
- 게임 재시작

저장 파일 형식:
```lua
transformed_npcs = {
    ["enemy_123"] = {
        npc_type = "surrendered_bandit",
        x = 1664,
        y = 368,
        facing = "down",
        map_name = "area3"
    }
}
```

---

## 지속성 시스템

**NEW!** 일회성 획득과 적 처치가 맵과 저장/로드 간에 지속됩니다.

### 일회성 아이템

`respawn = false`인 아이템은 한 번만 스폰됩니다:

```lua
-- Tiled에서 (WorldItems 레이어)
item_type = "sword"
quantity = 1
respawn = false  -- 한 번 획득, 리스폰 안 됨
```

**작동 방식:**
1. 아이템은 고유한 `map_id` 보유: `"level1_area1_obj_46"`
2. 획득 시, `picked_items` 테이블에 추가
3. 저장 파일에 저장
4. 맵 로드 시, 이미 획득했으면 필터링

**기본값:** 아이템 리스폰 (`respawn = true`)

### 일회성 적

`respawn = false`인 적은 죽으면 계속 죽어있습니다:

```lua
-- Tiled에서 (Enemies 레이어)
type = "boss_slime"
hp = 500
respawn = false  -- 한 번 처치, 계속 죽어있음
```

**작동 방식:**
1. 적은 고유한 `map_id` 보유: `"level1_area1_obj_40"`
2. 처치 시 (2초 죽음 타이머 후), `killed_enemies` 테이블에 추가
3. 저장 파일에 저장
4. 맵 로드 시, 이미 처치했으면 필터링

**기본값:** 적 리스폰 (`respawn = true`)

### Map ID 생성

형식: `"{map_name}_obj_{object_id}"`

예시:
- `"level1_area1_obj_46"` - level1_area1에서 id=46인 아이템
- `"level2_area3_obj_120"` - level2_area3에서 id=120인 적

**요구사항:**
- 맵에 `name` 속성 필요 (예: `name = "level1_area1"`)
- 오브젝트에 고유 id 필요 (Tiled가 자동 할당)

### 저장 데이터 구조

```lua
save_data = {
  hp = 100,
  max_hp = 100,
  map = "assets/maps/level1/area1.lua",
  x = 500,
  y = 300,
  inventory = {...},
  picked_items = {
    ["level1_area1_obj_46"] = true,  -- 지팡이 획득
    ["level1_area2_obj_12"] = true,  -- 포션 획득
  },
  killed_enemies = {
    ["level1_area1_obj_40"] = true,  -- 보스 슬라임 처치
    ["level2_area1_obj_8"] = true,   -- 미니 보스 처치
  }
}
```

---

## 일반 작업

### 디버깅

**F1** 키로 디버그 오버레이 토글 (`APP_CONFIG.is_debug = true`인 경우):

- **F1** - 디버그 UI 토글
- **F2** - 충돌 그리드 토글
- **F3** - 마우스 좌표 토글
- **F11** - 전체화면 토글

디버그 출력:

```lua
dprint("내 디버그 메시지")  -- debug.enabled = true일 때만 표시
```

### 맵 전환 테스트

1. 테스트 맵에 포털 추가
2. 속성 설정: `target_map`, `spawn_x`, `spawn_y`
3. 포털로 이동
4. 지속성 확인: 아이템/적이 획득/처치된 상태 유지

### 충돌체 확인

충돌 디버그 활성화 (F2)로 확인:
- 플레이어 충돌체 (foot는 녹색, main은 파란색)
- 적 충돌체 (foot는 빨간색, main은 주황색)
- 벽 (흰색)

**Topdown 모드:**
- Main 충돌체는 서로 무시 (통과)
- Foot 충돌체는 벽 및 서로 충돌

**Platformer 모드:**
- Main 충돌체만 사용
- 지면 감지는 raycast 사용

### 플레이어 스탯 조정

`game/data/player.lua` 편집:

```lua
return {
  health = 100,
  speed = 150,
  jump_force = -600,  -- Platformer만

  abilities = {
    can_attack = true,
    can_dodge = true,
    can_parry = true,
  },

  dodge = {
    cooldown = 1.0,
    speed_multiplier = 2.5,
    duration = 0.3,
  }
}
```

### 입력 바인딩 변경

`game/data/input_config.lua` 편집:

```lua
keyboard = {
  move_left = "a",
  move_right = "d",
  move_up = "w",
  move_down = "s",
  jump = "space",
  attack = "j",
  dodge = "lshift",
  -- ... 등등
}
```

---

## 모범 사례

### 파일 구성

```lua
-- 1. 모듈 선언
local mymodule = {}

-- 2. Require
local engine_system = require "engine.core.something"

-- 3. 로컬 함수
local function _helper()
  -- 프라이빗 헬퍼
end

-- 4. 공개 함수
function mymodule:publicMethod()
  -- 공개 API
end

-- 5. 모듈 반환
return mymodule
```

### Require 경로

```lua
-- 좋음: 점 사용
require "engine.core.sound"
require "game.data.player"

-- 나쁨: 슬래시 사용
require "engine/core/sound"
```

**예외:** 파일 경로는 슬래시 사용:

```lua
"assets/maps/level1/area1.lua"  -- 파일 경로, require 아님
```

### 명명 규칙

```lua
local module_name = {}        -- lowercase_with_underscores
function obj:methodName() end  -- camelCase
local CONSTANT_VALUE = 100     -- UPPER_CASE
```

### 엔티티 생명주기

**생성:**
```lua
-- Tiled 오브젝트용 팩토리 사용
local entity_factory = require "engine.systems.entity_factory"
local enemy = entity_factory:createEnemy(obj, enemy_class, map_name)

-- 또는 직접 생성
local player = player_module:new(x, y, config)
```

**파괴:**
```lua
-- 항상 world 전에 충돌체 파괴
if entity.collider then
  entity.collider:destroy()
  entity.collider = nil
end
if entity.foot_collider then
  entity.foot_collider:destroy()
  entity.foot_collider = nil
end

-- 그 다음 world 파괴
world:destroy()
```

### 충돌 클래스

**사용 가능한 클래스:**
- `Player`, `PlayerFoot`, `PlayerDodging`
- `Enemy`, `EnemyFoot`
- `Wall`, `WallBase`
- `NPC`
- `DeathZone`, `DamageZone`

**Topdown 무시 규칙:**
- Player main ↔ Enemy main (통과)
- PlayerFoot ↔ EnemyFoot (벽 충돌용 충돌)

**Platformer:**
- Main 충돌체만 사용
- 모든 엔티티 정상 충돌

### 시간 스케일링

슬로우 모션 효과에 스케일된 시간 사용:

```lua
local scaled_dt = camera_sys:get_scaled_dt(dt)
enemy:update(scaled_dt, player.x, player.y)
```

### Y-정렬 (Topdown)

엔티티는 **foot_collider 하단 가장자리**로 정렬:

```lua
-- Player
player.y_sort = foot_collider:getY() + (collider_height * 0.1875) / 2

-- Humanoid enemy
enemy.y_sort = foot_collider:getY() + (collider_height * 0.125) / 2

-- Slime enemy
enemy.y_sort = foot_collider:getY() + (collider_height * 0.6) / 2
```

Tiled 맵의 Trees 타일도 Y-정렬됩니다.

**Platformer:** Y-정렬 없음, Trees 레이어 정상 그리기.

---

## 웹 개발

### 웹용 빌드

게임은 **love.js**를 사용하여 WebAssembly로 컴파일되어 브라우저에 배포됩니다.

**빌드 명령:**
```bash
npm run build
```

실행 내용: `love.js -c -t "LÖVE2D RPG Game" -m 67108864 . web_build/game.data`

**파라미터:**
- `-c` - 호환 모드 (SharedArrayBuffer 불필요)
- `-t` - 브라우저 탭 제목
- `-m 67108864` - 64MB 메모리 할당

**출력:** `web_build/game.data` (모든 게임 파일 포함)

### 로컬 테스트

**옵션 1: Lua 서버 (권장)**
```bash
cd web_build
lua server.lua 8080
```

**옵션 2: Node.js**
```bash
cd web_build
npx http-server -p 8080
```

**접속:** `http://localhost:8080` (`127.0.0.1`이 아닌 `localhost` 사용)

### Lua 5.1 호환성 규칙

**웹 빌드는 Lua 5.1 사용 (LuaJIT 아님).** 다음 규칙을 따르세요:

**피하기:**
```lua
-- Lua 5.2+ goto (지원 안 됨)
goto continue
::continue::

-- FFI 모듈 (LuaJIT 전용)
local ffi = require("ffi")

-- 문자열과 함께 load() (Lua 5.2+)
local func = load("return " .. str)
```

**대신 사용:**
```lua
-- goto 대신 중첩 조건문
if condition then
  -- 처리
end

-- FFI용 플랫폼 감지
local os = love.system.getOS()
if os == "Windows" or os == "Linux" or os == "OS X" then
  local ffi = require("ffi")
  -- FFI 사용
end

-- 호환 가능한 load
local func = (loadstring or load)("return " .. str)
```

### 웹 전용 코드

**플랫폼 감지:**
```lua
local os = love.system.getOS()

if os == "Web" then
  -- 웹 전용 코드
  -- 예: 종료 버튼 숨김
elseif os == "Android" or os == "iOS" then
  -- 모바일 코드
else
  -- 데스크톱 코드
end
```

**사용 예:**
```lua
-- engine/scenes/builder.lua
local function onEnter(self, previous, ...)
  -- 웹에서 "종료" 필터링
  local os = love.system.getOS()
  if os == "Web" and self.options then
    local filtered = {}
    for _, opt in ipairs(self.options) do
      if opt ~= "Quit" then
        table.insert(filtered, opt)
      end
    end
    self.options = filtered
  end
end
```

### 웹 플랫폼 제한사항

**브라우저 동작:**
- **탭 블러:** 탭을 벗어나면 실행 일시정지
  - BGM 중지 (`love.focus()`로 자동 재개)
  - 날씨 효과 일시정지
  - 모든 타이머/애니메이션 정지
- **종료 불가:** `love.event.quit()` 효과 없음
- **전체화면:** 사용자 제스처 필요 (버튼 클릭)

**저장소:**
- 저장은 브라우저 IndexedDB에 저장 (파일 아님)
- 브라우저별 (이식 불가)
- 브라우저 데이터와 함께 삭제

**성능:**
- 60 FPS 제한 (브라우저 강제)
- 메모리 제한 (빌드 명령에서 설정)
- JIT 컴파일 없음 (Lua 5.1 인터프리터)

### 배포 체크리스트

**배포 전:**
- [ ] 여러 브라우저에서 테스트 (Chrome, Firefox, Safari)
- [ ] 탭 블러/포커스 동작 테스트
- [ ] 브라우저 저장소에서 저장/로드 테스트
- [ ] 메모리 사용량 확인 (브라우저 개발자 도구)
- [ ] 모든 에셋 정상 로드 확인

**웹 서버:**
- [ ] MIME 타입 설정:
  - `.wasm` → `application/wasm`
  - `.data` → `application/octet-stream`
  - `.js` → `application/javascript`
- [ ] `.data`, `.js`, `.wasm`에 gzip 활성화
- [ ] 적절한 CORS 헤더 설정
- [ ] 정적 에셋용 캐시 헤더 설정

**프로덕션:**
- [ ] `web_build/` 내용물 업로드
- [ ] 실제 호스팅 환경에서 테스트
- [ ] 브라우저 콘솔 에러 모니터링
- [ ] 모바일 브라우저에서 테스트 (터치 컨트롤)

---

## 참조

자세한 API 문서는 다음 참조:
- **[CLAUDE.md](../CLAUDE.md)** - 완전한 참조 및 지침
- **[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)** - 파일 구조
- **[README.md](README.md)** - 빠른 시작

코드 예제는 다음 참조:
- **[DEVELOPMENT_JOURNAL.md](../DEVELOPMENT_JOURNAL.md)** - 최근 변경사항 및 패턴

---

**마지막 업데이트:** 2025-11-22
**엔진 버전:** 29_indoor (미니맵 패럴랙스 통합)
**LÖVE 버전:** 11.5
