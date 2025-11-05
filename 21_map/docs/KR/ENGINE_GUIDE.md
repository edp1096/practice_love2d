# 엔진 시스템 가이드

이 가이드는 `engine/` 폴더의 모든 엔진 시스템을 문서화합니다.

---

## 🎬 씬 관리

### `engine/scene_control.lua`
씬 전환 및 씬 스택을 관리합니다.

**주요 함수:**
```lua
scene_control.switch(scene, ...)    -- 새 씬으로 전환 (현재 씬 교체)
scene_control.push(scene, ...)      -- 씬을 위에 푸시 (일시정지 메뉴 등)
scene_control.pop()                 -- 이전 씬으로 돌아가기
```

**씬 생명주기:**
```lua
function scene:enter(previous, ...) end  -- 씬 진입 시 호출
function scene:exit() end                -- 씬 종료 시 호출
function scene:resume() end              -- 푸시된 씬에서 돌아올 때 호출
function scene:update(dt) end            -- 매 프레임마다 호출
function scene:draw() end                -- 렌더링 시 호출
```

---

## 📷 카메라 시스템

### `engine/camera.lua`
카메라 효과 시스템 (흔들림, 슬로우 모션).

**주요 함수:**
```lua
camera_sys:shake(intensity, duration)    -- 화면 흔들림 효과
camera_sys:setTimeScale(scale)           -- 슬로우 모션 (0.0-1.0)
camera_sys:get_scaled_dt(dt)             -- 시간 스케일이 적용된 델타 타임 얻기
```

**사용 예시:**
```lua
-- 패리 히트 효과
camera_sys:shake(5, 0.2)
camera_sys:setTimeScale(0.3)  -- 30% 속도 (슬로우 모션)
```

---

## 🔊 사운드 시스템

### `engine/sound.lua`
오디오 관리 (BGM, SFX, 볼륨 제어, 지연 로딩).

**주요 함수:**
```lua
sound:playBGM(name, fade_time, rewind)   -- 배경 음악 재생
sound:stopBGM(fade_time)                 -- 페이드와 함께 BGM 정지
sound:playSFX(category, name)            -- 효과음 재생
sound:setMasterVolume(volume)            -- 마스터 볼륨 설정 (0.0-1.0)
sound:setBGMVolume(volume)               -- BGM 볼륨 설정
sound:setSFXVolume(volume)               -- SFX 볼륨 설정
```

**사용 예시:**
```lua
sound:playBGM("level1", 1.0, true)       -- level1 BGM 재생, 처음부터 되감기
sound:playSFX("combat", "sword_swing")   -- 검 휘두르기 사운드 재생
```

**사운드 구성:**
사운드는 `game/data/sounds.lua`에 정의됩니다:
```lua
return {
    bgm = {
        level1 = { path = "assets/bgm/level1.ogg", volume = 0.7, loop = true }
    },
    sfx = {
        combat = {
            sword_swing = { path = "assets/sound/player/sword_swing.wav", volume = 0.7 }
        }
    }
}
```

---

## 🎮 입력 시스템

### `engine/input/`
키보드, 마우스, 게임패드, 터치를 지원하는 통합 입력 시스템.

**메인 API (`engine/input/init.lua`):**
```lua
input:wasPressed("action_name")          -- 액션이 방금 눌렸는지 확인
input:isDown("action_name")              -- 액션이 눌려있는지 확인
input:getAimDirection()                  -- 조준 방향 얻기 (공격용)
input:vibrate(pattern_name)              -- 진동/햅틱 트리거
```

**입력 구성:**
액션은 `game/data/input_config.lua`에 정의됩니다:
```lua
actions = {
    move_left = { keys = {"a", "left"}, gamepad = {"dpleft"} },
    attack = { mouse = {1}, gamepad = {"a"} },
    jump = { keys = {"w", "up", "space"}, gamepad = {"b"} }
}
```

**플랫폼 지원:**
- 데스크톱: 키보드 + 마우스 + 물리 게임패드
- 모바일: 가상 온스크린 게임패드 + 터치 입력

---

## 🌍 월드 시스템

### `engine/world/`
물리 및 월드 관리 (Windfield/Box2D 래퍼).

**메인 API (`engine/world/init.lua`):**
```lua
world:new(mapPath)                       -- Tiled 맵에서 월드 생성
world:addEntity(entity)                  -- 월드에 엔티티 추가
world:removeEntity(entity)               -- 엔티티 제거
world:update(dt)                         -- 물리 및 엔티티 업데이트
world:drawEntitiesYSorted()              -- Y 정렬로 엔티티 그리기
```

**충돌 클래스:**
- `Player`, `PlayerDodging`
- `Wall`, `Portals`
- `Enemy`, `Item`

**게임 모드:**
- **Topdown:** 중력 없음, 자유로운 2D 이동
- **Platformer:** 중력 활성화, 수평 이동 + 점프

---

## 💾 세이브/로드 시스템

### `engine/save.lua`
슬롯 기반 세이브 시스템.

**주요 함수:**
```lua
save_sys:saveGame(slot, data)            -- 슬롯에 저장 (1-3)
save_sys:loadGame(slot)                  -- 슬롯에서 로드
save_sys:getAllSlotsInfo()               -- 모든 세이브 슬롯 정보 얻기
save_sys:hasSaveFiles()                  -- 세이브 파일이 있는지 확인
save_sys:deleteSave(slot)                -- 세이브 슬롯 삭제
```

**세이브 데이터 구조:**
```lua
{
    hp = 100,
    max_hp = 100,
    map = "assets/maps/level1/area1.lua",
    x = 400,
    y = 250,
    inventory = { ... }
}
```

---

## 🎒 인벤토리 시스템

### `engine/inventory.lua`
아이템 관리 시스템.

**주요 함수:**
```lua
inventory:addItem(item_id, quantity)     -- 인벤토리에 아이템 추가
inventory:removeItem(item_id, quantity)  -- 아이템 제거
inventory:useItem(slot_index, player)    -- 슬롯의 아이템 사용
inventory:selectSlot(index)              -- 슬롯 선택 (1-10)
inventory:nextItem()                     -- 다음 아이템으로 순환
inventory:prevItem()                     -- 이전 아이템으로 순환
```

**아이템 정의:**
아이템은 `game/entities/item/types/`에 정의됩니다:
```lua
-- game/entities/item/types/small_potion.lua
return {
    id = "small_potion",
    name = "Small Potion",
    icon = "assets/images/items/small_potion.png",
    max_stack = 99,
    use = function(player)
        player.health = math.min(player.health + 30, player.max_health)
    end
}
```

---

## 💬 대화 시스템

### `engine/dialogue.lua`
NPC 대화 시스템 (Talkies 라이브러리 래퍼).

**주요 함수:**
```lua
dialogue:show(messages, avatar, on_complete)  -- 대화 표시
dialogue:isActive()                           -- 대화가 활성화되어 있는지 확인
dialogue:update(dt)                           -- 대화 시스템 업데이트
dialogue:draw()                               -- 대화 상자 그리기
```

**사용 예시:**
```lua
dialogue:show(
    {"Hello, traveler!", "Welcome to our village."},
    npc.avatar,
    function() print("Dialogue finished") end
)
```

---

## 🗺️ 미니맵 시스템

### `engine/minimap.lua`
미니맵 렌더링 시스템.

**주요 함수:**
```lua
minimap:new()                                 -- 미니맵 생성
minimap:setMap(world)                         -- 미니맵을 위한 월드 설정
minimap:draw(player_x, player_y)             -- 미니맵 그리기
```

---

## 🎨 효과 시스템

### `engine/effects.lua`
파티클 효과 시스템.

**주요 함수:**
```lua
effects:hitEffect(x, y)                       -- 히트 파티클 효과
effects:deathEffect(x, y)                     -- 사망 효과
effects:update(dt)                            -- 파티클 업데이트
effects:draw()                                -- 파티클 그리기
```

---

## 📊 HUD 시스템

### `engine/hud.lua`
헤드업 디스플레이 렌더링.

**주요 함수:**
```lua
hud:draw(player, inventory)                   -- HUD 그리기 (체력, 쿨다운)
hud:drawInventoryHUD(inventory)               -- 빠른 액세스 인벤토리 그리기
hud:drawParryFeedback()                       -- 패리 성공 표시기 그리기
```

---

## 🐛 디버그 시스템

### `engine/debug.lua`
디버그 오버레이 및 시각화 (F1 토글).

**주요 기능:**
- 통합 정보 창 (FPS, 플레이어 상태, 화면 정보)
- 히트박스 시각화 (F1)
- 그리드 시각화 (F2)
- 가상 마우스 커서 (F3)
- 애니메이션 개발을 위한 손 마킹 모드

**토글:**
```lua
debug.enabled = true/false  -- F1 키가 이것을 토글합니다
debug:toggleLayer("visualizations")  -- F2가 그리드를 토글합니다
debug:toggleLayer("mouse")  -- F3이 가상 마우스를 토글합니다
```

---

## 🎮 게임 모드 시스템

### `engine/game_mode.lua`
Topdown vs Platformer 모드 관리.

**모드:**
- **topdown:** 자유로운 2D 이동, 중력 없음
- **platformer:** 수평 이동 + 점프, 중력 활성화

**Tiled 맵 속성으로 설정:**
```
Map Properties:
  game_mode = "topdown"  (또는 "platformer")
```

---

## 🔧 유틸리티

### `engine/utils/util.lua`
일반 유틸리티 함수.

### `engine/utils/restart.lua`
게임 재시작 로직 (세이브에서/현재 위치에서).

### `engine/utils/scene_ui.lua`
메뉴를 위한 재사용 가능한 UI 컴포넌트.

### `engine/utils/fonts.lua`
폰트 관리 시스템.

---

## 📐 상수

### `engine/constants.lua`
엔진 전체 상수.

**카테고리:**
- 진동 패턴
- 입력 타이밍
- 게임 시작 기본값

---

**참고:**
- [GAME_GUIDE.md](GAME_GUIDE.md) - 콘텐츠 제작 가이드
- [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) - 전체 구조 참조
