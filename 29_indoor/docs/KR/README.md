# LÖVE2D 게임 엔진 - 빠른 시작

깔끔한 **Engine/Game 분리** 아키텍처를 가진 LÖVE2D 게임 엔진입니다.

---

## 철학

### Engine (100% 재사용)
- `engine/` - 모든 시스템과 엔티티, 완전히 재사용 가능
- Core: lifecycle, input, display, sound, save, camera, quest, inventory
- Systems: world (물리), effects, lighting, parallax, HUD, collision
- Entities: player, enemy, weapon, NPC, item, healing_point
- UI: menu, dialogue, screens, widgets

### Game (데이터 + 최소 코드)
- `game/data/` - 설정 파일 (player, quests, scenes, entities, sounds)
- `game/scenes/` - 4개 데이터 기반 메뉴 (각 6줄), 복잡한 UI 화면들
- **엔티티 폴더 없음** - 모두 engine으로 이동

---

## 빠른 시작

### 설치
1. LÖVE 11.5 설치: https://love2d.org/
2. 실행: `love .`

### 조작법
**데스크톱:**
- **WASD / 화살표** - 이동 / 점프
- **마우스** - 조준
- **좌클릭 / Z** - 공격
- **우클릭 / X** - 패리 (완벽한 타이밍 = 슬로우 모션)
- **Shift / C** - 회피
- **F** - 상호작용 (NPC, 세이브 포인트, 아이템)
- **I / J** - 인벤토리 / 퀘스트 로그
- **Q / E** - 탭 전환
- **Q** - 아이템 사용 (게임플레이)
- **Tab** - 아이템 순환
- **1-5** - 빠른 선택
- **ESC** - 일시정지 / 닫기
- **F11** - 전체화면

**게임패드 (Xbox / PlayStation):**
- **좌 스틱 / D-Pad** - 이동
- **우 스틱** - 조준 / 스크롤
- **A / Cross (✕)** - 공격 / 상호작용
- **B / Circle (○)** - 점프 / 스킵 / 닫기
- **X / Square (□)** - 패리
- **Y / Triangle (△)** - 상호작용
- **LB / L1** - 이전 탭
- **LT / L2** - 이전 아이템
- **RB / R1** - 다음 탭 / 회피
- **RT / R2** - 인벤토리 / 퀘스트 로그
- **Start** - 일시정지

**디버그 (`APP_CONFIG.is_debug = true`):**
- **F1** - 디버그 모드 토글
- **F2** - 콜라이더/그리드 | **F3** - FPS/효과 | **F4** - 플레이어 정보 | **F5** - 화면 정보
- **F6** - 퀘스트 디버그 | **F7** - 핫 리로드 | **F8** - 효과 테스트
- **F9** - 가상 마우스 | **F10** - 가상 게임패드 | **F11** - 전체화면

---

## 첫 단계

1. **게임 시작**: `love .`
2. **New Game** → 세이브 슬롯 생성
3. **WASD**로 이동, **좌클릭**으로 공격
4. **NPC 대화** (F키), **세이브** (빛나는 원)
5. **인벤토리** (I), **퀘스트 로그** (J)

### 게임 모드
- **Topdown** (level1): 자유 2D 이동, 중력 없음
- **Platformer** (level2): 수평 + 점프, 중력 활성화

### 맵 속성
- **`move_mode`**: `"walk"` 설정 시 실내맵용 (느린 속도, 걷기 애니메이션)

### 계단 (Topdown 전용)
**시각적 고도 효과** - 계단 위에서 플레이어가 시각적으로 오르내림 (물리 변화 없음).

**Tiled 설정:**
1. "Stairs" 레이어 생성 (Object Layer)
2. **polygon** 모양으로 대각선 계단 영역 그리기 (권장)
3. polygon 모양에서 방향 자동 감지

**hill_direction 값:**
- **`left`**: 왼쪽 이동 = 오르막 (45° 대각선), 오른쪽 = 내리막
- **`right`**: 오른쪽 이동 = 오르막 (45° 대각선), 왼쪽 = 내리막
- **`up`**: 위로 이동 = 30% 느림 (좌우는 그대로)
- **`down`**: 아래로 이동 = 30% 느림 (좌우는 그대로)

**가드레일:** 플레이어는 계단 끝(위/아래)으로만 나갈 수 있음 (옆으로 나가기 불가).

**디버그:** F2로 계단 polygon 표시 (오렌지색) + 방향 화살표, F4로 "Stair: X.X" 오프셋 표시.

---

## 콘텐츠 생성

### 적 추가 (코드 불필요!)
1. 맵 열기: `assets/maps/level1/area1.tmx`
2. "Enemies" 레이어에 오브젝트 추가, 타입 설정: `slime`
3. 커스텀 프로퍼티 추가: `hp`, `dmg`, `spd`, `det_rng`
4. Lua로 내보내기 - 완료!

**또는** `game/data/entities/types.lua`에 재사용 가능한 적 타입 추가.

### 메뉴 추가 (6줄!)
1. `game/data/scenes.lua`에 추가:
```lua
scenes.mymenu = {
  type = "menu",
  title = "My Menu",
  options = {"Play", "Quit"},
  actions = {
    ["Play"] = {action = "switch_scene", scene = "play"},
    ["Quit"] = {action = "quit"}
  },
  back_action = {action = "quit"}
}
```

2. `game/scenes/mymenu.lua` 생성:
```lua
local builder = require "engine.scenes.builder"
local configs = require "game.data.scenes"
return builder:build("mymenu", configs)
```

### 아이템 추가
1. 아이콘: `assets/images/items/myitem.png`
2. 타입: `engine/entities/item/types/myitem.lua`:
```lua
return {
  name = "My Item",
  description = "유용한 아이템",
  icon = "assets/images/items/myitem.png",
  consumable = true,
  effect = function(player)
    player.health = math.min(player.health + 50, player.max_health)
  end
}
```

### 맵 추가
1. Tiled에서 생성: `assets/maps/level1/newarea.tmx`
2. 프로퍼티 설정: `name`, `game_mode`, `bgm`, `ambient`
3. 레이어 추가: Ground, Decos, Walls, Portals, Enemies, NPCs, Props
4. Lua로 내보내기
5. 이전 맵에서 포털 생성

### Props 추가 (이동/파괴 가능한 오브젝트)
**Tiled 설정:**
1. "Props" 레이어 생성 (Object Layer)
2. 타일 오브젝트를 추가하여 시각적 표현 (동일한 `group` 속성 공유)
3. `type = "collider"`와 동일한 `group`을 가진 투명 사각형 추가

**Collider 프로퍼티:**
- `group` - 타일과 콜라이더 연결 (예: "crate1")
- `type = "collider"` - 물리 콜라이더로 표시
- `movable = true` - 플레이어가 밀 수 있음
- `breakable = true` - 공격으로 파괴 가능
- `hp = 10` - 체력 (breakable 전용)
- `respawn = true` - 맵 전환 시 재생성 (기본값: false)

**예시 (2타일 높이 곰인형):**
```
Tile Object 1: gid=136, group="teddybear1"
Tile Object 2: gid=152, group="teddybear1"
Collider: type="collider", group="teddybear1", movable=true, breakable=true, hp=30
```

### 대화 추가
**간단:** NPC 프로퍼티 `dlg = "안녕!"`

**트리 (선택지):** `game/data/dialogues.lua`에 생성:
```lua
dialogues.shopkeeper = {
  start_node = "greeting",
  nodes = {
    greeting = {
      text = "환영합니다!",
      choices = {
        { text = "상점", next = "shop" },
        { text = "안녕", next = "end" }
      }
    }
  }
}
```

---

## 문서

- **[CLAUDE.md](../CLAUDE.md)** - 완전한 API 레퍼런스 및 지침
- **[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)** - 상세 폴더 구조
- **[DEVELOPMENT_JOURNAL.md](../DEVELOPMENT_JOURNAL.md)** - 현재 상태 요약

---

## 문제 해결

### 게임 실행 안됨
- LÖVE 버전 확인: `love --version` (11.5 필요)
- 콘솔 에러 확인

### 파일을 찾을 수 없음
- require에는 점 사용: `require "engine.core.sound"`
- 경로에는 슬래시 사용: `"assets/maps/level1/area1.lua"`

### 맵 로드 안됨
- Lua 포맷으로 내보내기 (`.lua`)
- 필수 레이어 존재 확인 (Ground, Walls)
- 맵 프로퍼티 확인: `game_mode`, `name`

### 아이템/적 리스폰
- Tiled 오브젝트 프로퍼티에 `respawn = false` 설정

---

## 웹 빌드

```bash
npm install -g love.js
npm run build
cd web_build && lua server.lua 8080
```

열기: `http://localhost:8080`

---

**프레임워크:** LÖVE 11.5 + Lua 5.1
**아키텍처:** Engine/Game 분리 + 데이터 기반
**최종 업데이트:** 2025-12-01
