# LÖVE2D 게임 엔진 - 빠른 시작

깔끔한 **Engine/Game 분리** 아키텍처를 가진 LÖVE2D 게임 프로젝트입니다.

---

## 프로젝트 철학

### **Engine (100% 재사용 가능)** 
`engine/` 폴더는 **모든** 게임 시스템과 엔티티를 포함합니다:
- **핵심 시스템:** lifecycle, input, display, sound, save, camera, debug
- **서브시스템:** world (물리), effects, lighting, parallax, HUD, collision
- **엔티티:** player, enemy, weapon, NPC, item, healing_point (**모두 engine에!**)
- **UI:** 메뉴 시스템, 화면, 대화, 프롬프트, 위젯
- **씬 빌더:** 데이터 기반 씬 팩토리, 컷씬, 게임플레이

### **Game (데이터 + 최소 코드)**
`game/` 폴더는 **오직** 게임 특화 콘텐츠만 포함합니다:
- **씬:** 4개 데이터 기반 메뉴 (각 6줄!), 복잡한 씬들 (play, settings, inventory, load)
- **데이터 설정:** 플레이어 스탯, 적 타입, 메뉴 설정, 사운드, 입력 매핑
- **엔티티 폴더 없음!** (engine으로 이동)

### **장점**
- **손쉬운 신규 게임 제작**: `engine/` 복사, 새 `game/` 콘텐츠 생성
- **깔끔한 분리**: 엔진 코드 vs 게임 콘텐츠
- **쉬운 유지보수**: 명확한 폴더 구조
- **콘텐츠 중심 워크플로우**: 게임 디자인에 집중, 엔진 코드 불필요
- **61% 코드 감소**: 약 3,000줄 vs 기존 7,649줄

---

## 빠른 시작

### 설치

1. LÖVE 11.5 설치: https://love2d.org/
2. 프로젝트 클론 또는 다운로드
3. 실행:
   - **데스크톱:** `love .`
   - **웹:** 아래 [웹 빌드](#-웹-빌드) 섹션 참조

### 조작법

**데스크톱:**
- **WASD / 화살표 키** - 이동 (Topdown) / 이동 + 점프 (Platformer)
- **마우스** - 무기 조준
- **좌클릭 / Z** - 공격
- **우클릭 / X** - 패리 (완벽한 타이밍 = 슬로우 모션!)
- **Shift / C** - 회피 (무적 프레임)
- **F** - 상호작용 (NPC, 세이브 포인트, 아이템)
- **I / J** - 인벤토리/퀘스트 로그 토글 (탭 컨테이너 열림)
- **Q / E** - 컨테이너 내 탭 전환 (인벤토리 ↔ 퀘스트)
- **Q** - 선택한 아이템 사용 (게임플레이 중)
- **Tab** - 아이템 순환 (게임플레이 중)
- **1-5** - 인벤토리 슬롯 빠른 선택 (게임플레이 중)
- **Escape** - 일시정지 / 메뉴 닫기
- **F11** - 전체화면 토글

**디버그 모드 (`APP_CONFIG.is_debug = true`인 경우):**
- **F1** - 디버그 UI 토글
- **F2** - 충돌 그리드 토글
- **F3** - 마우스 좌표 토글
- **F4** - 가상 게임패드 토글 (PC 테스트용)
- **F5** - 이펙트 디버그 토글
- **F6** - 마우스 위치에 이펙트 테스트

**게임패드 (Xbox / DualSense):**
- **좌 스틱 / D-Pad** - 이동
- **우 스틱** - 무기 조준 / 퀘스트 목록 스크롤
- **A / Cross (✕)** - 공격 / 상호작용
- **B / Circle (○)** - 점프 / 대화 스킵 (0.5초 홀드) / 메뉴 닫기
- **X / Square (□)** - 패리
- **Y / Triangle (△)** - 상호작용 (NPC/세이브 포인트)
- **LB / L1** - 이전 탭 (컨테이너 내)
- **LT / L2** - 다음 아이템 (게임플레이 중)
- **RB / R1** - 다음 탭 / 회피 (게임플레이 중)
- **RT / R2** - 인벤토리/퀘스트 로그 컨테이너 토글
- **Start / Options** - 일시정지

**모바일 (터치):**
- **가상 게임패드** - 화면 컨트롤 (Android/iOS에서 자동 표시)
- **화면 터치** - 메뉴 탐색 / 대화 진행
- **스와이프** - 퀘스트 로그에서 퀘스트 목록 스크롤

---

## 프로젝트 구조

```
29_indoor/
├── engine/           # 재사용 가능 게임 엔진 (100% 재사용 가능)
│   ├── core/         # 핵심 시스템 (lifecycle, input, scene, quest 등)
│   ├── systems/      # 서브시스템 (world, effects, lighting, hud, prompt, entity_factory)
│   ├── entities/     # 모든 엔티티 (player, enemy, weapon, npc, item)
│   ├── scenes/       # 씬 빌더 (builder, cutscene, gameplay - 모듈형 7개 파일)
│   ├── ui/           # UI 시스템 (menu, dialogue, questlog, widgets)
│   └── utils/        # 유틸리티 (fonts, text, util, colors 등)
├── game/             # 게임 특화 콘텐츠
│   ├── data/         # 설정 파일 (player, quests, scenes, sounds 등)
│   └── scenes/       # 게임 씬 (menu, play, settings, inventory, load)
├── assets/           # 게임 리소스 (maps, images, sounds)
├── vendor/           # 외부 라이브러리 (STI, Windfield, anim8 등)
├── docs/             # 문서
├── main.lua          # 진입점 (의존성 주입)
├── conf.lua          # LÖVE 설정
└── startup.lua       # 초기화 유틸리티
```

**핵심 개념:**
- **engine/** = "어떻게 작동하는가" (100% 재사용 가능)
- **game/** = "무엇을 보여주는가" (데이터 + 씬)
- **의존성 주입** = `main.lua`를 통해 게임 설정을 엔진에 주입

---

## 첫 단계

### 1. 게임 탐험
- 시작: `love .`
- 새 게임 → 세이브 슬롯 생성
- WASD로 이동
- 좌클릭으로 적 공격
- F키로 NPC와 대화
- 빛나는 원(세이브 포인트)에서 F키로 저장

### 2. 다양한 게임 모드 시도
- **Topdown** (level1/area1-3): 자유로운 2D 이동, 중력 없음
- **Platformer** (level2/area1): 수평 이동 + 점프, 중력 활성화

### 3. 전투 테스트
- **공격:** 좌클릭 / A 버튼
- **패리:** 우클릭 / X 버튼 (완벽한 타이밍 = 슬로우 모션!)
- **회피:** Shift / R1 버튼 (무적 프레임)

### 4. 인벤토리 & 퀘스트 시스템
- **I** 또는 **R2**로 인벤토리 탭 열기
- **J**로 퀘스트 로그 탭 열기
- 둘 다 동일한 **탭 컨테이너** 열림
- 탭 전환: **Q/E** (키보드) 또는 **LB/RB** (게임패드)
- 닫기: **ESC** 또는 **R2** (토글)
- 아이템 사용: **Q** / **L1** (게임플레이 중)
- 아이템 순환: **Tab** / **L2** (게임플레이 중)
- 빠른 선택: **1-5** 키 (게임플레이 중)
- 퀘스트 스크롤: **마우스 휠** / **우 스틱** / **스와이프** (모바일)

### 5. 지속성 시스템
- **일회성 아이템:** 시작 무기(지팡이, 검) 한 번만 획득
- **일회성 적:** 보스를 한 번 처치하면 계속 죽어있음
- **리스폰:** 일반 아이템/적은 기본적으로 리스폰
- Tiled에서 `respawn = false`로 설정하여 일회성으로 만들기

---

## 콘텐츠 만들기

### 새 적 추가하기  (데이터 기반 - 코드 불필요!)

**방법 1: Tiled에서 직접 (빠름)**
1. 맵 열기: `assets/maps/level1/area1.tmx`
2. "Enemies" 레이어에 오브젝트 추가
3. 오브젝트 타입 설정: `slime`, `goblin` 등
4. 커스텀 속성 추가:
   ```
   hp = 100           (체력)
   dmg = 10           (데미지)
   spd = 50           (속도)
   det_rng = 200      (감지 범위)
   respawn = false    (선택: 일회성 처치, 기본값: true)
   spr = "assets/images/enemies/yourenemy.png"
   ```
5. Lua로 내보내기 - 완료!

**방법 2: 적 타입 레지스트리 (재사용 가능)**
`game/data/entities/types.lua`에 추가:
```lua
enemies = {
  yourenemy = {
    hp = 100,
    damage = 15,
    speed = 80,
    sprite = "assets/images/enemies/yourenemy.png",
    detection_range = 250,
    attack_range = 50
  }
}
```

그 다음 Tiled에서 `type = "yourenemy"`만 설정하면 됩니다.

### 새 메뉴 추가하기  (데이터 기반 - 6줄!)

1. `game/data/scenes.lua`에 추가:
```lua
scenes.mymenu = {
  type = "menu",
  title = "내 메뉴",
  options = {"플레이", "설정", "종료"},
  actions = {
    ["플레이"] = {action = "switch_scene", scene = "play"},
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

2. `game/scenes/mymenu.lua` 생성:
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
   - **Walls** - 충돌 오브젝트
   - **Portals** - 맵 전환
   - **Enemies** - 적 스폰 지점
   - **NPCs** - NPC 스폰 지점
   - **WorldItems** - 획득 가능 아이템
   - **SavePoints** - 세이브 포인트
   - **HealingPoints** - 체력 회복 지점

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

### NPC 대화 추가하기

게임은 두 가지 대화 모드를 지원합니다: **간단한 대화**와 **트리 대화** (선택 기반).

#### 방법 1: 간단한 대화 (빠른 메시지)

단순 메시지의 경우, Tiled에서 설정:
```
NPC 속성: dlg = "안녕하세요, 여행자님!"
```

#### 방법 2: 트리 대화 (RPG 스타일 선택 기반)

상호작용적인 대화를 위해:

1. `game/data/dialogues.lua`에 대화 트리 생성:
```lua
dialogues.shopkeeper = {
  start_node = "greeting",
  nodes = {
    greeting = {
      text = "제 가게에 오신 걸 환영합니다!",
      speaker = "상점주인",
      next = "main_menu"
    },
    main_menu = {
      text = "무엇을 도와드릴까요?",
      speaker = "상점주인",
      choices = {
        { text = "아이템에 대해 알려주세요", next = "items" },
        { text = "이야기를 들려주세요", next = "story" },
        { text = "안녕히 계세요", next = "end" }
      }
    },
    items = {
      text = "물약과 무기를 팝니다!",
      speaker = "상점주인",
      next = "main_menu"  -- 메뉴로 되돌아감
    },
    story = {
      pages = {  -- 다중 페이지 대화 (비주얼 노벨 스타일)
        "옛날 옛적에...",
        "위대한 왕국이 있었답니다...",
        "그리고 그렇게 전설이 시작되었지요!"
      },
      speaker = "상점주인",
      next = "main_menu"
    },
    ["end"] = {
      text = "또 오세요!",
      speaker = "상점주인"
      -- choices나 next 없음 = 대화 종료
    }
  }
}
```

2. Tiled에서 NPC 속성 설정:
```
dlg = "shopkeeper"
```

3. 완료! 플레이어는 이제:
   - 키보드로 선택 탐색 (Up/Down, WASD)
   - 마우스로 호버 + 클릭
   - 게임패드 사용 (A 버튼으로 선택)
   - 메인 메뉴로 반복해서 돌아가기

**대화 노드 속성:**
- `text` - 단일 메시지 (문자열)
- `pages` - 다중 페이지 대화 (문자열 배열)
- `speaker` - 캐릭터 이름 (대화 상자 위에 표시)
- `choices` - 플레이어 선택지: `{ text = "...", next = "node_id" }`
- `next` - 다음 노드로 자동 진행 (선택지가 없을 때)

---

## 문서

- **[GUIDE.md](GUIDE.md)** - 완전한 개발 가이드 (개념, 워크플로우, 모범 사례)
- **[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)** - 상세한 프로젝트 구조 참조
- **[../CLAUDE.md](../CLAUDE.md)** - 전체 API 참조 및 Claude Code 지침
- **[../DEVELOPMENT_JOURNAL.md](../DEVELOPMENT_JOURNAL.md)** - 최근 변경사항 및 패턴

---

## 문제 해결

### 게임이 시작되지 않음
- LÖVE 버전 확인: `love --version` (11.5 필요)
- Lua 버전 확인: `lua -v` (5.1 호환 필요)
- 콘솔에서 에러 확인

### 파일을 찾을 수 없음 에러
- require 경로에 점 사용: `require "engine.core.sound"`
- 파일 경로에 슬래시 사용: `"assets/maps/level1/area1.lua"`
- 절대 혼용하지 마세요!

### 사운드 없음
- `config.ini`의 볼륨이 0이 아닌지 확인
- 파일 존재 확인: `assets/bgm/`, `assets/sound/`
- `game/data/sounds.lua` 정의 확인

### 맵이 로드되지 않음
- Tiled 맵을 Lua 형식으로 내보내기 (`.lua` 파일)
- 필요한 레이어 존재 확인 (Ground, Walls 등)
- 맵 속성 `game_mode` 설정 확인
- 맵 속성 `name` 설정 확인 (지속성용)

### 아이템/적이 리스폰되지 않아야 하는데 됨
- 맵에 `name` 속성 있는지 확인
- 오브젝트에 `respawn = false` 속성 있는지 확인
- 세이브/로드 작동 확인 (세이브 데이터에 `picked_items`, `killed_enemies` 포함)

---

## 웹 빌드

**love.js** (LÖVE to WebAssembly 컴파일러)를 사용하여 웹 브라우저에 게임을 배포할 수 있습니다.

### 요구사항

- **Node.js** 및 **npm** 설치
- **Lua 5.1 호환 코드** (아래 제한사항 참조)

### 빌드 과정

1. **love.js 전역 설치:**
   ```bash
   npm install -g love.js
   ```

2. **웹용 빌드:**
   ```bash
   npm run build
   ```

   `web_build/game.data`에 모든 게임 파일이 생성됩니다.

3. **로컬 서버 실행:**
   ```bash
   cd web_build
   lua server.lua 8080
   ```

   또는 Node.js 사용:
   ```bash
   cd web_build
   npx http-server -p 8080
   ```

4. **브라우저 열기:**
   - `http://localhost:8080` 접속
   - `127.0.0.1`이 아닌 `localhost` 사용 권장

### Lua 5.1 호환성

**웹 빌드는 Lua 5.1 사용 (LuaJIT 아님).** 코드베이스는 이미 호환됩니다:

**피해야 할 기능:**
- `goto`와 레이블 (Lua 5.2+)
- FFI 모듈 (LuaJIT 전용)
- 호환성을 위해 `loadstring or load` 사용

**플랫폼 감지:**
```lua
local os = love.system.getOS()
if os == "Web" then
  -- 웹 전용 동작
end
```

### 웹 플랫폼 제한사항

**브라우저 제한:**
- **탭 블러 시 실행 일시정지:** 탭을 벗어나면 BGM과 날씨 중지
- **포커스 시 자동 재개:** 탭으로 돌아오면 BGM 자동 재생
- **"종료" 버튼 없음:** 웹 빌드에서 자동으로 숨김
- **전체화면 제한:** 사용자 제스처 필요 (버튼 클릭)

**저장소:**
- 저장 파일은 브라우저 IndexedDB에 저장
- 브라우저 데이터 삭제 = 저장 파일 손실
- 브라우저 간 이동 불가

### 배포

**옵션 1: Lua 기반 서버 (Node.js 불필요)**
```bash
cd web_build
lua server.lua 8080
```

**옵션 2: 모든 HTTP 서버**
```bash
# Python
python -m http.server 8080

# Node.js
npx http-server -p 8080

# PHP
php -S localhost:8080
```

**프로덕션 배포:**
- `web_build/` 내용물을 웹 호스트에 업로드
- MIME 타입 설정: `.wasm` = `application/wasm`, `.data` = `application/octet-stream`
- `.data`, `.js`, `.wasm` 파일에 gzip 압축 활성화
- 필요 시 적절한 CORS 헤더 설정

---

## 다음 단계

1. **GUIDE.md 읽기** - 콘텐츠 제작 워크플로우 학습
2. **CLAUDE.md 읽기** - 전체 API 참조
3. **실험** - 기존 콘텐츠 수정
4. **제작** - 자신만의 게임 만들기!

---

**프레임워크:** LÖVE 11.5 + Lua 5.1
**아키텍처:** 계층형 피라미드 아키텍처 (99.8% 깔끔함) + Engine/Game 분리 + 의존성 주입 + 데이터 기반 + 컨트롤러 지원
**마지막 업데이트:** 2025-11-19

### 최신 변경사항 (2025-11-19)
- **인벤토리 리팩토링** - 중복 그리드 순회 및 정렬 로직 제거 (5곳 → 2개 헬퍼 함수, -19줄)
- **디버그 정리** - 대화, 인벤토리, 적, 입력 시스템에서 29개 디버그 프린트 제거
- **코드 구조** - 모든 `goto` 문 제거 (4개), 깔끔한 if-else 패턴으로 대체
- **상수화** - 매직 넘버를 명명된 상수로 추출 (DEFAULT_GRID_WIDTH, DEFAULT_GRID_HEIGHT)
- **컨트롤러 입력** - PlayStation은 색상 버튼 모양(✕○□△), Xbox는 문자(ABXY) 표시
- **리스폰 시스템** - 리스폰 로직 수정 - 명시적으로 `respawn=true` 속성이 있는 엔티티만 맵 재로드 시 리스폰
