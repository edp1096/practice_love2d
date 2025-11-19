# 프로젝트 구조

LÖVE2D 게임 엔진 프로젝트 구조 완전 참조 문서입니다.

---

## 루트 디렉토리

```
28_quest/
├── main.lua              - 진입점 (의존성 주입)
├── conf.lua              - LÖVE 설정
├── startup.lua           - 초기화 유틸리티
├── system.lua            - 시스템 레벨 핸들러
├── locker.lua            - 프로세스 잠금 (데스크톱)
├── config.ini            - 사용자 설정
├── package.json          - npm 스크립트 (웹 빌드)
│
├── engine/               - 100% 재사용 가능 게임 엔진
├── game/                 - 게임 특화 콘텐츠
├── vendor/               - 외부 라이브러리
├── assets/               - 게임 리소스
├── docs/                 - 문서
└── web_build/            - 웹 배포 (npm run build로 생성)
    ├── index.html        - 진입점
    ├── game.js           - LÖVE 런타임 (love.js)
    ├── game.wasm         - WebAssembly 바이너리
    ├── game.data         - 게임 파일 (생성됨)
    ├── theme.css         - 스타일링
    └── server.lua        - Lua HTTP 서버 (Node.js 불필요)
```

---

## Engine 폴더

**목적:** 레이어 구조를 가진 100% 재사용 가능 게임 엔진.

### 핵심 시스템 (`engine/core/`)

```
core/
├── lifecycle.lua         - 애플리케이션 생명주기
├── scene_control.lua     - 씬 스택 관리
├── camera.lua            - 카메라 효과 (shake, 슬로우 모션)
├── coords.lua            - 통합 좌표 시스템
├── sound.lua             - 오디오 시스템 (BGM, SFX)
├── save.lua              - 저장/로드 시스템 (슬롯 기반)
├── quest.lua             - 퀘스트 시스템 (kill, collect, talk, explore, deliver)
├── debug.lua             - 디버그 오버레이 (F1-F6)
├── constants.lua         - 엔진 상수
│
├── display/
│   └── init.lua          - 가상 화면 (스케일링, 레터박스)
│
└── input/
    ├── dispatcher.lua    - 입력 이벤트 디스패처
    ├── sources/          - 입력 소스 (키보드, 마우스, 게임패드)
    └── virtual_gamepad/  - 모바일 터치 컨트롤
```

### 서브시스템 (`engine/systems/`)

```
systems/
├── collision.lua         - 충돌 시스템
│                           - topdown용 이중 충돌체
│                           - 게임 모드 인식 NPC 충돌체
├── inventory.lua         - 인벤토리 시스템
├── entity_factory.lua    - Tiled 속성으로부터 엔티티 생성
├── prompt.lua            - 상호작용 프롬프트 (동적 버튼 아이콘)
│
├── world/                - 물리 & 맵 시스템
│   ├── init.lua          - World 코디네이터 (Windfield + STI)
│   ├── loaders.lua       - 맵 로딩 (Tiled + entity factory)
│   ├── entities.lua      - 엔티티 관리  지속성 추적!
│   └── rendering.lua     - Y-정렬 렌더링
│
├── effects/              - 시각 효과
│   ├── particles/        - 파티클 효과
│   └── screen/           - 스크린 효과 (플래시, 비네트)
│
├── lighting/             - 동적 조명 시스템
│   ├── init.lua          - 조명 관리자
│   └── source.lua        - 광원 클래스
│
├── parallax/             - 패럴랙스 배경 시스템
│   ├── init.lua          - 패럴랙스 관리자 (display 통합)
│   ├── layer.lua         - 개별 레이어 (부드러운 스크롤)
│   └── tiled_loader.lua  - Tiled 맵에서 로드
│
├── weather/              - 동적 날씨 시스템
│   ├── init.lua          - 날씨 관리자 (풀, 전환)
│   ├── rain.lua          - 비 효과 (1000 파티클/s)
│   ├── snow.lua          - 눈 효과 (300 파티클/s, 8초 지속)
│   ├── fog.lua           - 안개/미스트 효과 (8개 이동 레이어)
│   └── storm.lua         - 폭풍 효과 (비 + 바람)
│
└── hud/                  - 인게임 HUD
    ├── status.lua        - 체력바, 쿨다운, 패리 UI
    ├── minimap.lua       - 미니맵 렌더링 (75% 불투명도)
    ├── quickslots.lua    - 퀵슬롯 벨트 UI (하단 중앙)
    └── quest_tracker.lua - 퀘스트 트래커 HUD (활성 퀘스트 3개)
```

### 엔티티 (`engine/entities/`)

**모든 엔티티가 100% 재사용 가능! 게임 특화 코드 없음.**

```
entities/
├── player/               - 플레이어 시스템 (config 주입)
│   ├── init.lua          - 메인 코디네이터
│   ├── animation.lua     - 애니메이션 상태 머신
│   ├── combat.lua        - 체력, 공격, 패리, 회피
│   ├── render.lua        - 그리기 로직
│   └── sound.lua         - 사운드 효과
│
├── enemy/                - 적 시스템 (type_registry 주입)
│   ├── init.lua          - Enemy 기본 클래스
│   ├── ai.lua            - AI 상태 머신
│   ├── render.lua        - 그리기 로직
│   ├── sound.lua         - 사운드 효과
│   ├── spawner.lua       - 스폰 로직
│   └── factory.lua       - Tiled로부터 생성
│
├── weapon/               - 무기 시스템 (config 주입)
│   ├── init.lua          - 메인 코디네이터
│   ├── combat.lua        - 히트 감지, 데미지
│   ├── render.lua        - 그리기 로직
│   └── config/           - 손 앵커, 스윙 설정
│
├── npc/                  - NPC 시스템
│   ├── init.lua          - NPC 기본 클래스
│   └── types/            - NPC 타입 정의
│
├── item/                 - 아이템 시스템
│   ├── init.lua          - Item 기본 클래스
│   └── types/            - 아이템 타입 정의
│
├── world_item/           - 드롭 아이템 시스템  지속성!
│   └── init.lua          - 리스폰 제어를 가진 world item
│
└── healing_point/        - 체력 회복 지점
    └── init.lua          - 회복 로직
```

**지속성 속성:**
- `world_item`과 `enemy`는 `map_id`와 `respawn` 속성 보유
- `map_id` 형식: `"{map_name}_obj_{object_id}"`
- `respawn = false`로 설정하면 일회성 아이템/적
- `picked_items`와 `killed_enemies` 테이블로 추적

### 씬 (`engine/scenes/`)

```
scenes/
├── builder.lua           - 데이터 기반 씬 팩토리
├── cutscene.lua          - 컷씬/인트로 씬
└── gameplay/             - 메인 게임플레이 씬 (모듈화, ~2,100줄)
    ├── init.lua          - 씬 코디네이터 (~195줄)
    ├── scene_setup.lua   - 초기화 & 생명주기 (~505줄)
    ├── save_manager.lua  - 저장/로드 시스템 (~45줄)
    ├── quest_interactions.lua - 퀘스트 NPC 상호작용 (~195줄)
    ├── update.lua        - 게임 루프 (~460줄)
    ├── render.lua        - 그리기 (~170줄)
    └── input.lua         - 입력 처리 (~555줄)
```

### UI 시스템 (`engine/ui/`)

```
ui/
├── menu/                 - 메뉴 UI 시스템
│   ├── base.lua          - MenuSceneBase (기본 클래스)
│   └── helpers.lua       - 메뉴 헬퍼 (레이아웃, 네비게이션)
│
├── screens/              - 재사용 가능 UI 화면
│   ├── container.lua     - 탭 컨테이너 (인벤토리 + 퀘스트 로그)
│   ├── newgame.lua       - 새 게임 슬롯 선택
│   ├── saveslot.lua      - 저장 화면
│   ├── load/             - 로드 화면 (모듈형)
│   ├── inventory/        - 인벤토리 UI (모듈형)
│   ├── questlog/         - 퀘스트 로그 UI (모듈형)
│   └── settings/         - 설정 화면 (모듈형)
│
├── dialogue/             - 대화 시스템 (모듈화, ~1,350줄)
│   ├── init.lua          - 메인 API (facade 패턴)
│   ├── core.lua          - 핵심 로직 (트리, 상태, 입력)
│   ├── render.lua        - 렌더링 (페이징, 선택지, 버튼)
│   └── helpers.lua       - 헬퍼 (플래그, 히스토리, 액션)
│                           기능:
│                           - 간단한 대화 (문자열 메시지)
│                           - 트리 대화 (선택 기반 대화)
│                           - 다중 페이지 대화 (비주얼 노벨 스타일)
│                           - 네비게이션: 키보드, 마우스, 게임패드, 터치
│                           - 동적 선택지 색상 (방문 추적)
│
├── constants.lua         - UI 상수 (공유 크기)
└── widgets/              - 재사용 가능 위젯
    └── button/
        ├── skip.lua      - 스킵 버튼 (0.5초 홀드 충전)
        └── next.lua      - 다음 버튼 (대화 진행용)
```

### 유틸리티 (`engine/utils/`)

```
utils/
├── util.lua              - 일반 유틸리티
├── text.lua              - 텍스트 렌더링 래퍼
├── fonts.lua             - 폰트 관리
├── shapes.lua            - 도형 렌더링 (버튼, 다이얼로그)
├── colors.lua            - 중앙집중식 색상 시스템
│                           - 기본 팔레트 + 시맨틱 매핑
│                           - 헬퍼 함수 (apply, withAlpha 등)
├── restart.lua           - 게임 재시작 로직
├── convert.lua           - 데이터 변환
└── ini.lua               - INI 파일 파서
```

**색상 시스템 (`utils/colors.lua`):**
- **6가지 헬퍼 함수:** `apply()`, `withAlpha()`, `unpackRGB()`, `unpackRGBA()`, `toVertex()`, `reset()`
- **기본 팔레트:** 순수 색상 (WHITE, DARK_CHARCOAL, SKY_BLUE 등)
- **시맨틱 매핑:** 목적 기반 이름 (for_text_normal, for_menu_selected 등)
- **적용 범위:** 모든 HUD & UI 화면이 중앙집중식 색상 사용

---

## Game 폴더

**목적:** 게임 특화 콘텐츠 (데이터 기반, 최소 코드).

**핵심:** `game/entities/` 폴더 **완전 삭제!** 모든 엔티티는 `engine/entities/`에!

```
game/
├── scenes/               - 게임 화면
│   ├── menu.lua          - 메인 메뉴 (6줄!) 
│   ├── pause.lua         - 일시정지 메뉴 (6줄!) 
│   ├── gameover.lua      - 게임 오버 (6줄!) 
│   ├── ending.lua        - 엔딩 화면 (6줄!) 
│   │
│   ├── play/             - 게임플레이 씬 (모듈형)
│   ├── settings/         - 설정 메뉴 (모듈형)
│   ├── load/             - 로드 게임 씬 (모듈형)
│   └── inventory/        - 인벤토리 오버레이 (모듈형)
│
└── data/                 - 설정 파일
    ├── player.lua        - 플레이어 스탯 (엔진에 주입)
    ├── entities/
    │   └── types.lua     - 적 타입 (엔진에 주입)
    ├── scenes.lua        - 메뉴 설정 (builder 사용)
    ├── sounds.lua        - 사운드 정의
    ├── input_config.lua  - 입력 매핑
    ├── intro_configs.lua - 컷씬 설정
    ├── quests.lua        - 퀘스트 정의 (5가지 타입: kill, collect, talk, explore, deliver)
    └── dialogues.lua     - NPC 대화 트리 (선택 기반 대화)
                            - 퀘스트 조회용 npc_id 필드 포함
```

**데이터 기반 메뉴 예시:**
```lua
-- game/scenes/menu.lua (6줄!)
local builder = require "engine.scenes.builder"
local configs = require "game.data.scenes"
return builder:build("menu", configs)
```

**의존성 주입 (main.lua):**
```lua
-- 게임 설정을 엔진에 주입
local player_module = require "engine.entities.player"
local enemy_module = require "engine.entities.enemy"
local weapon_module = require "engine.entities.weapon"

local player_config = require "game.data.player"
local entity_types = require "game.data.entities.types"

player_module.config = player_config
enemy_module.type_registry = entity_types.enemies
weapon_module.type_registry = entity_types.weapons
```

---

## Assets 폴더

```
assets/
├── maps/                 - Tiled 맵 (TMX + Lua 내보내기)
│   ├── level1/
│   │   ├── area1.tmx     - Tiled 소스  여기서 respawn=false 설정!
│   │   ├── area1.lua     - Lua 내보내기
│   │   ├── area2.tmx
│   │   └── area2.lua
│   └── level2/
│       └── area1.tmx
│
├── images/               - 스프라이트, 타일셋
│   ├── player/
│   ├── enemies/
│   ├── items/
│   └── tilesets/
│
├── backgrounds/          - 패럴랙스 배경 레이어
│   ├── layer1_sky.png
│   ├── layer2_mountains.png
│   ├── layer3_clouds.png
│   └── layer4_trees.png
│
├── sounds/               - 사운드 효과
│   ├── combat/
│   ├── ui/
│   └── ambient/
│
├── bgm/                  - 배경음악
│
└── fonts/                - 폰트 파일
```

**지속성을 위한 맵 요구사항:**
```
맵 속성:
  name = "level1_area1"    ← 지속성을 위해 필수!
  game_mode = "topdown"    (또는 "platformer")
  bgm = "level1"           (선택)
  ambient = "day"          (선택)

WorldItems 오브젝트 속성:
  item_type = "sword"
  quantity = 1
  respawn = false          ← 일회성 획득!

Enemies 오브젝트 속성:
  type = "boss_slime"
  respawn = false          ← 일회성 처치!

Parallax 레이어 ("Parallax" objectgroup에 배치):
  오브젝트 속성:
    Type = "parallax"              ← 커스텀 속성 (문자열)
    image = "assets/backgrounds/layer1_sky.png"
    parallax_factor = 0.1          (0.0 = 고정, 1.0 = 일반 속도)
    z_index = 1                    (렌더링 순서: 낮을수록 뒤에)
    repeat_x = true                (가로 타일링)
    offset_y = 0                   (세로 위치 조정)
    auto_scroll_x = 10             (선택: 자동 스크롤 속도 px/s)
```

**패럴랙스 시스템 기능:**
- **가상 해상도 통합** - 960x540 가상 좌표 사용
- **Display 변환** - 적절한 레터박스 오프셋 + 스케일
- **창 크기 조절 지원** - 전체화면 토글과 함께 올바르게 스케일링

---

## Vendor 폴더

외부 라이브러리 (100% 수정 없음):

```
vendor/
├── anim8/                - 스프라이트 애니메이션
├── hump/                 - 유틸리티 (camera, timer, vector)
├── sti/                  - Tiled 맵 로더
├── windfield/            - Box2D 래퍼 (물리)
└── talkies/              - 대화 시스템
```

---

## 지속성 시스템

**NEW!** 일회성 아이템과 적이 맵과 저장/로드 간에 지속됩니다.

### 저장 데이터 구조

```lua
save_data = {
  hp = 100,
  max_hp = 100,
  map = "assets/maps/level1/area1.lua",
  x = 500,
  y = 300,
  inventory = {...},

  -- 지속성 추적 
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

### Map ID 생성

형식: `"{map_name}_obj_{object_id}"`

예시:
- `"level1_area1_obj_46"` - level1_area1에서 id=46인 아이템
- `"level2_area3_obj_120"` - level2_area3에서 id=120인 적

### 워크플로우

1. **맵 로드** (`engine/systems/world/loaders.lua`):
   - `picked_items` / `killed_enemies` 테이블 확인
   - `respawn = false`이고 이미 획득/처치했으면 스폰 스킵

2. **획득/처치** (`engine/scenes/gameplay/input.lua`, `engine/systems/world/entities.lua`):
   - `map_id`를 `picked_items` / `killed_enemies` 테이블에 추가
   - `respawn = false`인 아이템/적에 대해서만

3. **저장** (`engine/scenes/gameplay/init.lua:saveGame()`):
   - `picked_items`와 `killed_enemies`를 저장 파일에 저장

4. **로드** (`engine/scenes/gameplay/init.lua:enter()`):
   - 저장 파일로부터 `picked_items`와 `killed_enemies` 로드
   - 필터링을 위해 `world:new()`에 전달

---

## 코드 통계

**리팩토링 전:**
- Game 폴더: 7,649줄 (48 파일)
- Entities가 game/entities/에 위치

**리팩토링 후:**
- Game 폴더: 4,174줄 (23 파일) **-45% 감소**
- 모든 entities가 engine/entities/에 **100% 재사용 가능**
- 메뉴 씬: 358 → 24줄 **-93% 감소**

**새 게임 제작:**
- `engine/` 복사 (100% 재사용 가능)
- `game/data/` 생성 (약 600줄의 설정)
- `game/scenes/` 생성 (약 2,400줄의 로직)
- 총: 약 3,000줄 vs 기존 7,649줄 **61% 코드 감소**

---

## 주요 파일 참조

**진입점:**
- `main.lua` - 의존성 주입, LÖVE 콜백
- `conf.lua` - LÖVE 설정
- `startup.lua` - 초기화 (에러 핸들러, 플랫폼 감지)
- `game/setup.lua` - 게임별 설정 주입

**Engine 핵심:**
- `engine/core/lifecycle.lua` - 메인 게임 루프 오케스트레이터
- `engine/core/scene_control.lua` - 씬 관리
- `engine/core/quest.lua` - 퀘스트 시스템 (5가지 타입, 상태 관리)
- `engine/core/level.lua` - 레벨/경험치 시스템
- `engine/core/coords.lua` - 통합 좌표 변환
- `engine/systems/world/init.lua` - 물리 & 맵 시스템
- `engine/systems/collision.lua` - 충돌 시스템 (이중 충돌체)
- `engine/scenes/gameplay/` - 메인 게임플레이 씬 (모듈화)

**엔티티 & 생성 시스템:**
- `engine/systems/entity_factory.lua` - Tiled로부터 엔티티 생성
- `engine/entities/player/` - 플레이어 시스템 (전투, 애니메이션, 렌더링)
- `engine/entities/enemy/` - 적 AI (팩토리 기반, 리스폰 제어)
- `engine/entities/weapon/` - 무기 전투 시스템
- `engine/entities/npc/` - NPC 상호작용
- `engine/entities/world_item/` - 드롭된 아이템 (리스폰 제어)

**UI 시스템:**
- `engine/utils/colors.lua` - 중앙집중식 색상 시스템
- `engine/ui/dialogue/` - 대화 시스템 (모듈화)
- `engine/ui/screens/questlog/` - 퀘스트 로그 UI
- `engine/ui/screens/inventory/` - 인벤토리 UI
- `engine/systems/hud/status.lua` - 체력 바, 패리 UI
- `engine/systems/hud/quest_tracker.lua` - 퀘스트 HUD 트래커
- `engine/systems/hud/quickslots.lua` - 퀵슬롯 벨트
- `engine/systems/prompt.lua` - 상호작용 프롬프트

**Game 설정:**
- `game/data/player.lua` - 플레이어 스탯 (주입됨)
- `game/data/entities/` - 엔티티 타입 정의 (주입됨)
  - `types.lua` - 통합 export (하위 호환성 유지)
  - `defaults.lua` - Tiled 커스텀 프로퍼티 기본값
  - `humans/` - 인간 엔티티 타입
    - `bandits.lua` - 적대적 인간 (bandit, rogue, warrior, guard)
    - `common.lua` - 우호적 NPC (merchant, villager, elder, guard)
    - `erratic.lua` - 불규칙한 행동 (deceiver, surrendered_bandit)
  - `monsters/` - 몬스터 엔티티 타입
    - `slimes.lua` - 슬라임 변종 (red, green, blue, purple)
- `game/data/scenes.lua` - 메뉴 설정 (데이터 기반)
- `game/data/quests.lua` - 퀘스트 정의

**맵 파일:**
- `assets/maps/level1/area1.tmx` - Tiled 소스  여기서 respawn 설정!
- `assets/maps/level1/area1.lua` - Lua 내보내기

---

**마지막 업데이트:** 2025-11-19
**프레임워크:** LÖVE 11.5 + Lua 5.1
**아키텍처:** Engine/Game 분리 + 의존성 주입 + 데이터 기반 + 레이어드 피라미드 (99.2% clean)
