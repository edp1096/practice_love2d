# 프로젝트 구조

폴더 구성 완전 레퍼런스.

---

## 루트 디렉토리

```
29_indoor/
├── main.lua              - 진입점 (의존성 주입)
├── conf.lua              - LÖVE 설정
├── startup.lua           - 초기화 유틸리티
├── system.lua            - 시스템 핸들러
├── config.ini            - 사용자 설정
│
├── engine/               - 100% 재사용 가능 게임 엔진
├── game/                 - 게임 특화 콘텐츠
├── vendor/               - 외부 라이브러리
├── assets/               - 게임 리소스
└── docs/                 - 문서
```

---

## Engine 폴더

### 핵심 시스템 (`engine/core/`)

```
core/
├── lifecycle.lua         - 애플리케이션 생명주기
├── scene_control.lua     - 씬 스택 관리
├── camera.lua            - 카메라 효과 (흔들림, 슬로우 모션)
├── coords.lua            - 통합 좌표 변환
├── sound.lua             - 오디오 시스템
├── save.lua              - 저장/로드 (슬롯 기반)
├── quest.lua             - 퀘스트 시스템 (5가지 타입)
├── level.lua             - 레벨/경험치 시스템
├── debug.lua             - 디버그 오버레이
├── display/              - 가상 화면 (스케일링, 레터박스)
└── input/                - 입력 디스패처 + 소스
```

### 서브시스템 (`engine/systems/`)

```
systems/
├── collision.lua         - 충돌 (topdown용 이중 콜라이더)
├── inventory.lua         - 인벤토리 시스템
├── entity_factory.lua    - Tiled에서 엔티티 생성
├── prompt.lua            - 상호작용 프롬프트 (동적 아이콘)
├── loot.lua              - 랜덤 전리품 드롭
│
├── world/                - 물리 & 맵
│   ├── init.lua          - 월드 코디네이터
│   ├── loaders.lua       - 맵 로딩 + 엔티티 팩토리
│   ├── entities.lua      - 엔티티 관리 + 영속성
│   └── rendering.lua     - Y축 정렬 렌더링
│
├── effects/              - 시각 효과 (파티클, 화면)
├── lighting/             - 동적 조명
├── parallax/             - 패럴랙스 배경
├── weather/              - 날씨 시스템 (비, 눈, 안개, 폭풍)
│
└── hud/                  - 인게임 HUD
    ├── status.lua        - 체력 바, 쿨다운
    ├── minimap.lua       - 미니맵 (패럴랙스 포함!)
    ├── quickslots.lua    - 퀵슬롯 벨트
    └── quest_tracker.lua - 퀘스트 HUD (3개 활성 퀘스트)
```

### 엔티티 (`engine/entities/`)

**모든 엔티티 100% 재사용 가능!**

```
entities/
├── player/               - 플레이어 시스템 (config 주입)
│   ├── init.lua          - 코디네이터
│   ├── animation.lua     - 애니메이션 상태 머신
│   ├── combat.lua        - 체력, 공격, 패리, 회피
│   ├── render.lua        - 그리기
│   └── sound.lua         - 사운드 효과
│
├── enemy/                - 적 시스템 (type_registry 주입)
│   ├── init.lua          - 기본 클래스
│   ├── ai.lua            - AI 상태 머신
│   └── render.lua        - 그리기
│
├── weapon/               - 무기 시스템 (config 주입)
│   ├── init.lua          - 코디네이터
│   ├── combat.lua        - 히트 감지, 데미지
│   └── render.lua        - 그리기
│
├── npc/                  - NPC 시스템
├── item/                 - 아이템 시스템
├── world_item/           - 드롭 아이템 (리스폰 제어)
└── healing_point/        - 체력 회복
```

### 씬 (`engine/scenes/`)

```
scenes/
├── builder.lua           - 데이터 기반 씬 팩토리
├── cutscene.lua          - 컷씬/인트로
└── gameplay/             - 메인 게임플레이 (모듈형)
    ├── init.lua          - 코디네이터
    ├── scene_setup.lua   - 초기화
    ├── save_manager.lua  - 저장/로드
    ├── update.lua        - 게임 루프
    ├── render.lua        - 그리기
    └── input.lua         - 입력 처리
```

### UI 시스템 (`engine/ui/`)

```
ui/
├── menu/                 - 메뉴 기본 + 헬퍼
├── screens/              - 재사용 가능 화면
│   ├── container.lua     - 탭 컨테이너 (인벤토리 + 퀘스트 로그)
│   ├── newgame.lua       - 새 게임 슬롯
│   ├── saveslot.lua      - 저장 화면
│   ├── load/             - 로드 화면 (모듈형)
│   ├── inventory/        - 인벤토리 UI (모듈형)
│   ├── questlog/         - 퀘스트 로그 UI (모듈형)
│   └── settings/         - 설정 (모듈형)
│
├── dialogue/             - 대화 시스템 (모듈형)
│   ├── init.lua          - 메인 API
│   ├── core.lua          - 핵심 로직 (트리, 상태, 입력)
│   ├── render.lua        - 렌더링
│   └── helpers.lua       - 헬퍼
│
└── widgets/              - 재사용 가능 위젯
    └── button/           - 스킵/다음 버튼
```

### 유틸리티 (`engine/utils/`)

```
utils/
├── util.lua              - 일반 유틸리티
├── text.lua              - 텍스트 렌더링
├── fonts.lua             - 폰트 관리
├── shapes.lua            - 도형 렌더링
├── colors.lua            - 중앙집중 색상 시스템
├── helpers.lua           - 헬퍼 함수
└── button_icons.lua      - PlayStation/Xbox 버튼 아이콘
```

---

## Game 폴더

**`game/entities/` 폴더 삭제됨!** 모든 엔티티는 `engine/`에.

```
game/
├── scenes/               - 게임 화면
│   ├── menu.lua          - 메인 메뉴 (6줄!)
│   ├── pause.lua         - 일시정지 메뉴 (6줄!)
│   ├── gameover.lua      - 게임 오버 (6줄!)
│   ├── ending.lua        - 엔딩 (6줄!)
│   │
│   ├── play/             - 게임플레이 씬 (모듈형)
│   ├── settings/         - 설정 메뉴 (모듈형)
│   ├── load/             - 로드 게임 씬 (모듈형)
│   └── inventory/        - 인벤토리 오버레이 (모듈형)
│
└── data/                 - 설정 파일
    ├── player.lua        - 플레이어 스탯 (주입됨)
    ├── entities/
    │   └── types.lua     - 적 타입 (주입됨)
    ├── scenes.lua        - 메뉴 설정
    ├── sounds.lua        - 사운드 정의
    ├── input_config.lua  - 입력 매핑
    ├── quests.lua        - 퀘스트 정의
    └── dialogues.lua     - NPC 대화 트리
```

**의존성 주입 (main.lua):**
```lua
local player_module = require "engine.entities.player"
local player_config = require "game.data.player"
player_module.config = player_config  -- 게임 config 주입
```

---

## Assets 폴더

```
assets/
├── maps/                 - Tiled 맵 (TMX + Lua 내보내기)
│   ├── level1/
│   │   ├── area1.tmx     - Tiled 소스
│   │   └── area1.lua     - Lua 내보내기
│   └── level2/
│
├── images/               - 스프라이트, 타일셋
│   ├── player/
│   ├── enemies/
│   ├── items/
│   ├── parallax/         - 패럴랙스 배경
│   └── tilesets/
│
├── sounds/               - 사운드 효과
├── bgm/                  - 배경 음악
└── fonts/                - 폰트 파일
```

**맵 프로퍼티:**
```
name = "level1_area1"    ← 영속성 필수!
game_mode = "topdown"    (또는 "platformer")
bgm = "level1"           (선택)
ambient = "day"          (선택)
```

**오브젝트 프로퍼티:**
```
WorldItems:
  item_type = "sword"
  respawn = false        ← 일회성 픽업!

Enemies:
  type = "boss_slime"
  respawn = false        ← 일회성 처치!

Parallax ("Parallax" objectgroup):
  Type = "parallax"
  image = "assets/images/parallax/layer1_sky.png"
  parallax_factor = 0.1  (0.0=고정, 1.0=정상)
  z_index = 1
  repeat_x = true
  offset_y = 0
```

---

## Vendor 폴더

외부 라이브러리 (수정 안됨):
```
vendor/
├── anim8/                - 스프라이트 애니메이션
├── hump/                 - 유틸리티 (camera, timer, vector)
├── sti/                  - Tiled 맵 로더
├── windfield/            - Box2D 래퍼
└── talkies/              - 대화 시스템
```

---

## 영속성 시스템

**저장 데이터 구조:**
```lua
save_data = {
  hp = 100,
  map = "assets/maps/level1/area1.lua",
  x = 500, y = 300,
  inventory = {...},

  -- 영속성 추적
  picked_items = {
    ["level1_area1_obj_46"] = true,  -- 스태프 획득
  },
  killed_enemies = {
    ["level1_area1_obj_40"] = true,  -- 보스 처치
  }
}
```

**맵 ID 포맷:** `"{map_name}_obj_{object_id}"`

**워크플로우:**
1. 맵 로드: 테이블 확인, `respawn=false`이고 이미 획득/처치됨이면 스킵
2. 획득/처치: 테이블에 `map_id` 추가 (`respawn=false`만)
3. 저장: 테이블을 저장 파일에 포함
4. 로드: 테이블 복원, `world:new()`에 전달

---

## 코드 통계

**이전:** 7,649줄 (game 폴더)
**이후:** 4,174줄 **-45% 감소**
- 모든 엔티티가 engine에 (100% 재사용)
- 메뉴 씬: 358 → 24줄 **-93%**

**새 게임 제작:**
- `engine/` 복사 (100% 재사용)
- `game/data/` 생성 (~600줄 설정)
- `game/scenes/` 생성 (~2,400줄 로직)
- **총: ~3,000줄 vs 7,649줄 (61% 적은 코드)**

---

**최종 업데이트:** 2025-11-25
**프레임워크:** LÖVE 11.5 + Lua 5.1
