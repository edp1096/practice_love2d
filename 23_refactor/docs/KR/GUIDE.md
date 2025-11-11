# 완전한 개발 가이드

엔진 시스템, 게임 콘텐츠 제작, 개발 워크플로우, 시각 효과를 다루는 포괄적인 가이드입니다.

---

## 목차

### [Part 1: 엔진 시스템](#part-1-엔진-시스템)
- [씬 관리](#씬-관리)
- [애플리케이션 생명주기](#애플리케이션-생명주기)
- [좌표계 시스템](#좌표계-시스템)
- [카메라 시스템](#카메라-시스템)
- [사운드 시스템](#사운드-시스템)
- [입력 시스템](#입력-시스템)
- [월드 시스템](#월드-시스템)
- [세이브/로드 시스템](#세이브로드-시스템)
- [인벤토리 시스템](#인벤토리-시스템)
- [대화 시스템](#대화-시스템)
- [미니맵 시스템](#미니맵-시스템)
- [HUD 시스템](#hud-시스템)
- [디버그 시스템](#디버그-시스템)
- [게임 모드 시스템](#게임-모드-시스템)
- [유틸리티](#유틸리티)

### [Part 2: 시각 효과 & 조명](#part-2-시각-효과--조명)
- [이펙트 시스템](#이펙트-시스템)
- [라이팅 시스템](#라이팅-시스템)
- [렌더링 파이프라인](#렌더링-파이프라인)
- [일반적인 패턴](#일반적인-패턴)

### [Part 3: 게임 콘텐츠 제작](#part-3-게임-콘텐츠-제작)
- [씬 만들기](#씬-만들기)
- [엔티티 만들기](#엔티티-만들기)
- [사운드 추가하기](#사운드-추가하기)
- [맵 만들기](#맵-만들기)
- [입력 설정하기](#입력-설정하기)
- [컷씬 만들기](#컷씬-만들기)
- [세이브 시스템 사용하기](#세이브-시스템-사용하기)
- [빠른 레시피](#빠른-레시피)

### [Part 4: 개발 워크플로우](#part-4-개발-워크플로우)
- [아키텍처 원칙](#아키텍처-원칙)
- [개발 워크플로우](#개발-워크플로우-1)
- [코드 스타일](#코드-스타일)
- [디버깅](#디버깅)
- [테스팅](#테스팅)
- [빌드 및 배포](#빌드-및-배포)
- [버전 관리](#버전-관리)
- [성능 팁](#성능-팁)

---

# Part 1: 엔진 시스템

이 섹션은 `engine/` 폴더의 모든 엔진 시스템을 문서화합니다.

## 씬 관리

### `engine/core/scene_control.lua`
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

## 애플리케이션 생명주기

### `engine/core/lifecycle.lua`
애플리케이션 생명주기(초기화, 업데이트, 렌더링, 리사이즈, 종료)를 관리합니다.
모든 엔진 시스템을 오케스트레이션하고 scene_control에 위임합니다.

**주요 함수:**
```lua
lifecycle:initialize(initial_scene)  -- 모든 시스템 초기화 및 첫 씬 시작
lifecycle:update(dt)                 -- 입력, 가상 게임패드, 현재 씬 업데이트
lifecycle:draw()                     -- 씬, 가상 게임패드, 디버그 오버레이 그리기
lifecycle:resize(w, h)               -- 윈도우 리사이즈 처리
lifecycle:quit()                     -- 정리 및 설정 저장
```

**설정 (main.lua):**
```lua
-- 의존성 설정
lifecycle.display = display
lifecycle.input = input
lifecycle.scene_control = scene_control
-- ... (기타 의존성)

-- 애플리케이션 초기화
lifecycle:initialize(menu)
```

**목적:**
- main.lua의 복잡한 초기화 로직을 캡슐화
- 여러 엔진 시스템 조정 (input, display, fonts, sound)
- LÖVE 콜백과 비즈니스 로직 간의 깔끔한 분리 제공
- 시스템 초기화 에러 처리 중앙화

---

## 좌표계 시스템

### `engine/coords.lua`
모든 엔진 시스템을 위한 통합 좌표계 관리. 다양한 좌표 공간 간 변환을 처리합니다.

**좌표계:**

1. **WORLD** - 게임 월드 좌표
   - 원점: 맵 원점 (0,0)
   - 단위: 게임 월드의 픽셀
   - 사용처: 엔티티, 콜라이더, 맵 타일

2. **CAMERA** - 카메라 변환 좌표
   - 원점: 캔버스 중앙
   - 변환: `camera:attach()`로 적용됨
   - 사용처: 캔버스 내 렌더링

3. **VIRTUAL** - 가상 화면 좌표
   - 원점: 좌상단 (0,0)
   - 해상도: 고정 (기본 960x540)
   - 사용처: UI, HUD, 메뉴

4. **PHYSICAL** - 물리 화면 좌표
   - 원점: 좌상단 (0,0)
   - 해상도: 실제 기기 화면
   - 사용처: 윈도우, 원시 입력 이벤트

5. **CANVAS** - 캔버스 픽셀 좌표
   - 원점: 캔버스 좌상단 (0,0)
   - 사용처: 셰이더, 저수준 렌더링

**주요 함수:**
```lua
-- 변환 함수
coords:worldToCamera(wx, wy, camera)
coords:cameraToWorld(cx, cy, camera)
coords:virtualToPhysical(vx, vy, display)
coords:physicalToVirtual(px, py, display)
coords:worldToVirtual(wx, wy, camera, display)
coords:virtualToWorld(vx, vy, camera, display)

-- 유틸리티 함수
coords:debugPoint(x, y, camera, display, label)
coords:isVisibleInCamera(wx, wy, camera, margin)
coords:isVisibleInVirtual(vx, vy, display)
coords:distanceWorld(x1, y1, x2, y2)
coords:distanceCamera(x1, y1, x2, y2, camera)
```

**일반적인 사용 사례:**

1. **마우스 클릭 → 월드 위치:**
```lua
local mx, my = love.mouse.getPosition()  -- Physical
local vx, vy = coords:physicalToVirtual(mx, my, display)
local wx, wy = coords:virtualToWorld(vx, vy, cam, display)
-- 이제 (wx, wy)가 월드 위치
```

2. **월드 오브젝트에 UI 오버레이:**
```lua
-- 적 위에 체력바 표시
local cx, cy = coords:worldToCamera(enemy.x, enemy.y, cam)
local vx, vy = coords:physicalToVirtual(cx, cy, display)
-- 가상 좌표 (vx, vy)에 그리기
```

3. **좌표 디버깅:**
```lua
coords:debugPoint(player.x, player.y, cam, display, "Player")
-- 모든 좌표 표현 출력
```

**중요 사항:**
- 각 컨텍스트에 올바른 좌표계 사용
- 게임 로직 및 물리: 월드 좌표
- UI 렌더링: 가상 좌표
- 원시 입력: 물리 좌표
- 월드 렌더링: 카메라 좌표
- 셰이더: 캔버스 좌표

**중요 - 사용 규칙:**
- ✅ **항상** `coords:worldToCamera()` 및 `coords:cameraToWorld()` 사용
- ✅ **항상** `coords:physicalToVirtual()` 및 `coords:virtualToPhysical()` 사용
- ❌ **절대** `camera:cameraCoords()` 또는 `camera:worldCoords()` 직접 사용 금지
- ❌ **절대** `display:ToVirtualCoords()` 또는 `display:ToScreenCoords()` 직접 사용 금지
- coords 모듈은 통합 인터페이스를 제공하며 자동으로 nil 체크를 처리합니다

---

## 엔티티 좌표계 시스템

`game/data/entities/types.lua`에서 엔티티를 정의할 때, 엔티티 위치와 렌더링을 제어하는 세 가지 좌표 오프셋 필드를 이해해야 합니다.

### 좌표 계층 구조

엔티티 위치 지정은 3단계 좌표 시스템을 사용합니다:

```
Tiled 객체 (x, y)  ← Tiled 맵 에디터의 top-left 원점
    ↓ + collider_offset_x/y
Collider 중심 (cx, cy)  ← Box2D 물리 엔진은 center 원점 사용
    ↓ + sprite_draw_offset_x/y
Sprite 그리기 위치  ← 스프라이트 이미지가 실제로 그려지는 위치
```

**왜 3단계인가?**
- **Tiled**는 top-left 원점 사용 (타일 기반 에디터 표준)
- **Box2D** (물리 엔진)는 center 원점 사용 (물리 엔진 표준)
- **Sprite**는 임의의 크기, collider 기준으로 수동 위치 지정 필요

### 필드 정의

#### `collider_offset_x/y`
**목적:** Tiled 객체 위치(top-left)에서 collider 중심까지의 오프셋.

**사용 시기:**
- collider를 객체의 정확한 위치에 배치하려면 보통 `0, 0`
- Tiled 객체와 collider 중심이 달라야 하면 0이 아닌 값

**예시:**
```lua
collider_offset_x = 0   -- Collider 중심이 Tiled 객체 X 위치
collider_offset_y = 0   -- Collider 중심이 Tiled 객체 Y 위치
```

**코드 참조:** `engine/entities/base/entity.lua:47-49` (getColliderCenter)

#### `sprite_draw_offset_x/y`
**목적:** Collider 중심에서 sprite 그리기 위치까지의 오프셋.

**왜 음수 값인가?**
- 스프라이트가 보통 collider보다 큼
- 음수 값은 sprite를 collider 왼쪽/위쪽에 그림
- 이를 통해 sprite가 collider 중심에 오도록 함

**자동 계산:**
지정하지 않으면 엔진이 자동 계산 (`engine/entities/base/entity.lua:22-27` 참조):
```lua
sprite_draw_offset_x = -(sprite_width * sprite_scale - collider_width) / 2
sprite_draw_offset_y = -(sprite_height * sprite_scale - collider_height)
```

**예시:**
```lua
-- 16x32 sprite를 scale 4 (64x128 렌더)로, 32x32 collider인 경우:
sprite_draw_offset_x = -32   -- (64 - 32) / 2 = 16, 하지만 위치 지정을 위해 -32
sprite_draw_offset_y = -112  -- Sprite를 collider 하단 위에 위치
```

**코드 참조:** `engine/entities/base/entity.lua:53-56` (getSpritePosition)

#### `sprite_origin_x/y`
**목적:** 스프라이트 이미지 내부의 피벗 포인트 (회전용).

**좌표계:** 스프라이트 내부 픽셀 (0,0 = 스프라이트 이미지의 top-left 모서리)

**일반적인 값:**
```lua
-- 회전 없음 (기본값)
sprite_origin_x = 0
sprite_origin_y = 0

-- 중심 피벗 (무기 같은 회전 엔티티)
sprite_origin_x = sprite_width / 2
sprite_origin_y = sprite_height / 2
```

**예시:**
```lua
-- 48x48 sprite의 중심 회전:
sprite_origin_x = 24  -- 중심 X (48/2)
sprite_origin_y = 24  -- 중심 Y (48/2)
```

### 올바른 오프셋 값 찾기

**Hand Marking** 디버그 도구를 사용하여 올바른 오프셋 값을 찾으세요:

**1단계: 디버그 모드 활성화**
```
1. config.ini에서 IsDebug=true 설정
2. 게임 실행: love .
3. F1 키를 눌러 디버그 모드 활성화
```

**2단계: Hand Marking 활성화**
```
H 키 누르기 - 애니메이션 일시정지, hand marking 모드 진입
콘솔 출력:
  === HAND MARKING MODE ENABLED ===
  Animation PAUSED
  Current animation: walk_right
  Current frame: 1
```

**3단계: 애니메이션 프레임 이동**
```
PgUp  - 이전 프레임
PgDn  - 다음 프레임

콘솔 프레임 정보 표시:
  walk_right Frame: 2 / 6
```

**4단계: 위치 마킹**
```
1. 마우스를 원하는 위치로 이동 (예: 무기 앵커용 손 위치)
2. P 키를 눌러 위치 마킹

콘솔 Lua 코드 출력:
  MARKED: walk_right[2] = {x = 10, y = -5, angle = math.pi / 4},
```

**5단계: 설정 파일에 복사**
```
모든 프레임 마킹 완료 시, 콘솔에 완전한 테이블 출력:
  === COMPLETE walk_right ===
  walk_right = {
      {x = 8, y = -3, angle = 0},
      {x = 10, y = -5, angle = math.pi / 4},
      ...
  },

이 코드를 설정 파일에 복사 (예: game/data/entities/types.lua 또는 weapon hand_anchors.lua)
```

**팁:**
- 완전한 커버리지를 위해 애니메이션의 모든 프레임 마킹
- 콘솔에서 진행 상황 표시 (예: "marked 3 / 6 frames")
- 무기 손 위치, 스프라이트 오프셋, 부착점 등에 사용

### 전체 엔티티 예시

```lua
-- game/data/entities/types.lua
red_slime = {
    -- 기본 스탯
    sprite_sheet = "assets/images/enemy-sheet-slime-red.png",
    health = 100,
    damage = 10,
    speed = 100,
    attack_cooldown = 1.0,
    detection_range = 200,
    attack_range = 50,

    -- 스프라이트 크기
    sprite_width = 16,
    sprite_height = 32,
    sprite_scale = 4,  -- 64x128 픽셀로 렌더 (16*4 x 32*4)

    -- 물리 collider (Box2D는 center 원점 사용)
    collider_width = 32,
    collider_height = 32,
    collider_offset_x = 0,   -- Collider 중심이 Tiled 객체 위치
    collider_offset_y = 0,

    -- 스프라이트 위치 지정 (collider 중심 기준)
    sprite_draw_offset_x = -32,   -- Sprite를 collider 중심 왼쪽 32px에 그림
    sprite_draw_offset_y = -112,  -- Sprite를 collider 중심 위 112px에 그림

    -- 회전 피벗 (0,0 = top-left, 회전하지 않는 엔티티용)
    sprite_origin_x = 0,
    sprite_origin_y = 0,

    -- 선택사항: 색상 교체 (빨간 슬라임을 초록으로 변경)
    source_color = nil,  -- 빨간 슬라임은 색상 교체 없음
    target_color = nil,
}
```

### 일반적인 함정

1. **스케일 팩터 잊음:**
   - `sprite_width * sprite_scale`이 실제 렌더 크기
   - 예: 16px 스프라이트 scale 4 = 화면에 64px

2. **잘못된 좌표계:**
   - Tiled 객체는 top-left 원점 사용
   - Box2D collider는 center 원점 사용
   - 변환을 위해 항상 `collider_offset` 추가

3. **자동 계산 무시:**
   - 오프셋이 이상하면 `sprite_draw_offset_x/y` 생략 시도
   - 엔진이 합리적인 기본값 계산 (sprite를 collider에 중심 배치)

4. **피벗 없이 회전:**
   - 엔티티가 회전하면 (예: 무기), `sprite_origin`을 중심으로 설정
   - 회전하지 않는 엔티티는 (0, 0) 사용 가능

5. **Collider와 sprite 크기 불일치:**
   - Collider는 게임플레이 히트박스에 맞춰야 함 (sprite 크기 아님)
   - 예: 픽셀 단위 충돌을 위해 큰 sprite에 작은 collider

### 참조: 좌표 변환 함수

`engine/entities/base/entity.lua`에서:

```lua
-- Collider 중심 위치 얻기 (Tiled 위치 + offset)
function entity:getColliderCenter()
    return self.x + self.collider_offset_x,
           self.y + self.collider_offset_y
end

-- Sprite 그리기 위치 얻기 (collider 중심 + sprite offset)
function entity:getSpritePosition()
    local cx, cy = self:getColliderCenter()
    return cx + self.sprite_draw_offset_x,
           cy + self.sprite_draw_offset_y
end
```

이 함수들이 위에서 설명한 3단계 좌표 계층 구조를 구현합니다.

---

## 카메라 시스템

### `engine/core/camera.lua`
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

## 사운드 시스템

### `engine/core/sound.lua`
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

## 입력 시스템

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

**입력 이벤트 디스패처 (`engine/input/dispatcher.lua`):**
우선순위 시스템으로 LÖVE 입력 이벤트를 적절한 핸들러로 라우팅합니다:
```lua
-- 터치 이벤트 우선순위:
-- 1. 디버그 버튼 (최우선)
-- 2. 씬 touchpressed (인벤토리, 대화 오버레이)
-- 3. 가상 게임패드 (씬에서 처리하지 않은 경우)
-- 4. 마우스 이벤트로 폴백 (데스크톱 테스트용)

-- 설정 (main.lua에서)
input_dispatcher.scene_control = scene_control
input_dispatcher.virtual_gamepad = virtual_gamepad
input_dispatcher.input = input
```

**가상 게임패드 (`engine/core/input/virtual_gamepad/`):**
터치 컨트롤이 있는 모바일 온스크린 게임패드 (모듈화 구현):
- **D-pad** (좌하단): 이동 (8방향 입력)
- **조준 스틱** (중앙 우측): 조준 방향
- **액션 버튼** (우하단): A, B, X, Y (다이아몬드 레이아웃)
- **숄더 버튼** (상단): L1, L2, R1, R2
- **메뉴 버튼** (좌상단): 일시정지/메뉴 접근
- 모바일(Android/iOS)에서 자동 활성화
- PC에서 F4 디버그 키로 테스트 가능

```lua
-- 가상 게임패드 표시/숨김 (씬에서 자동 처리)
virtual_gamepad:show()   -- 게임플레이에서 표시
virtual_gamepad:hide()   -- 메뉴에서 숨김

-- 가상 게임패드에서 입력 받기
local stick_x, stick_y = virtual_gamepad:getStickAxis()
local aim_angle, is_aiming = virtual_gamepad:getAimDirection(player.x, player.y, cam)
```

---

## 월드 시스템

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

## 세이브/로드 시스템

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

## 인벤토리 시스템

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

---

## 대화 시스템

### `engine/ui/dialogue.lua`
모바일 UI 버튼이 포함된 NPC 대화 시스템 (Talkies 라이브러리 래퍼).

**주요 함수:**
```lua
dialogue:initialize()                        -- 대화 시스템 초기화
dialogue:setDisplay(display)                 -- 버튼용 display 참조 설정
dialogue:showSimple(name, message)           -- 단일 메시지 표시
dialogue:showMultiple(name, messages)        -- 여러 메시지 표시
dialogue:isOpen()                            -- 대화가 활성화되어 있는지 확인
dialogue:update(dt)                          -- 대화 시스템 업데이트
dialogue:draw()                              -- 대화 상자와 버튼 그리기
dialogue:onAction()                          -- 다음 메시지로 진행
dialogue:clear()                             -- 모든 대화 닫기
dialogue:handleInput(source, ...)           -- 통합 입력 핸들러
```

**모바일 UI:**
- **NEXT 버튼** (녹색): 다음 메시지로 진행
- **SKIP 버튼** (회색): 모든 대화 즉시 닫기
- 우측 하단에 자동 배치
- 터치 및 마우스 입력 모두 지원

**입력 처리:**
```lua
-- 키보드
if dialogue:handleInput("keyboard") then return end

-- 마우스
if dialogue:handleInput("mouse", x, y) then return end
if dialogue:handleInput("mouse_release", x, y) then return end

-- 터치
if dialogue:handleInput("touch", id, x, y) then return true end
if dialogue:handleInput("touch_release", id, x, y) then return true end
if dialogue:handleInput("touch_move", id, x, y) then return true end
```

**사용 예제:**
```lua
-- 초기화 (scene:enter에서)
dialogue:initialize()
dialogue:setDisplay(display)

-- 대화 표시
local npc = world:getInteractableNPC(player.x, player.y)
if npc then
    local messages = npc:interact()
    dialogue:showMultiple(npc.name, messages)
end

-- 입력 처리 (scene 입력 핸들러에서)
function scene:keypressed(key)
    if key == "return" or key == "space" then
        if dialogue:handleInput("keyboard") then return end
    end
end

function scene:mousepressed(x, y, button)
    if button == 1 then
        dialogue:handleInput("mouse", x, y)
    end
end

function scene:touchpressed(id, x, y, dx, dy, pressure)
    return dialogue:handleInput("touch", id, x, y)
end
```

**위젯:**
- `engine/ui/widgets/skip_button.lua` - SKIP 버튼 위젯 (0.5초 충전 시스템)
- `engine/ui/widgets/next_button.lua` - NEXT 버튼 위젯

---

## UI 헬퍼 모듈

### `engine/ui/prompt.lua`
활성화된 입력 방식에 따라 동적 버튼 아이콘으로 상호작용 프롬프트를 그립니다.

**주요 기능:**
- 적절한 버튼 라벨 표시 (키보드는 F, 게임패드는 Y, 터치는 B)
- 활성 입력 소스 자동 감지
- 일관된 원형 버튼 디자인

**사용법:**
```lua
local prompt = require "engine.ui.prompt"

-- NPC 위에 상호작용 프롬프트 그리기
prompt:draw("interact", npc_center_x, npc_center_y, -60)

-- 선택사항: 커스텀 색상과 오프셋
prompt:draw("interact", x, y, -30, {1, 1, 0, 1})  -- 노란색
```

### `engine/ui/shapes.lua`
일관된 UI 요소를 위한 도형 렌더링 유틸리티.

**주요 함수:**
```lua
shapes:drawBox(x, y, w, h, color, border_color, border_width, rounding)
shapes:drawPanel(x, y, w, h, bg_color, border_color, rounding)
shapes:drawButton(x, y, w, h, state, rounding)
shapes:drawCloseButton(x, y, size, is_hovered)  -- 빨간 배경!
shapes:drawConfirmDialog(x, y, w, h, message, message_font, yes_hover, no_hover)
```

**닫기 버튼 (빨강):**
```lua
-- 빨간 X 버튼 그리기 (삭제/닫기 동작용)
local is_hovered = check_mouse_over(x, y, size)
shapes:drawCloseButton(x, y, 30, is_hovered)

-- 색상:
-- 보통: {0.5, 0.2, 0.2, 0.7} (어두운 빨강)
-- 호버: {0.8, 0.2, 0.2, 0.9} (밝은 빨강)
```

---

## 메뉴 UI 시스템

### `engine/ui/menu.lua`
메뉴 씬의 코드 중복을 제거하기 위한 공통 UI 유틸리티.

**레이아웃 함수:**
```lua
ui_scene.createMenuLayout(vh)               -- 표준 메뉴 레이아웃 생성
ui_scene.createMenuFonts()                  -- 표준 폰트 생성
```

**그리기 함수:**
```lua
ui_scene.drawTitle(text, font, y, width, color)
ui_scene.drawOptions(options, selected, mouse_over, font, layout, width)
ui_scene.drawOverlay(width, height, alpha)
ui_scene.drawControlHints(font, layout, width, custom_text)
ui_scene.drawConfirmDialog(title, subtitle, button_labels, selected, mouse_over, fonts, width, height)
```

**입력 처리 함수:**
```lua
ui_scene.handleKeyboardNav(key, current_selection, option_count)
ui_scene.handleGamepadNav(button, current_selection, option_count)
ui_scene.handleMouseSelection(button, mouse_over)

-- 터치 입력 (신규)
ui_scene.handleTouchPress(options, layout, width, font, x, y, display)
ui_scene.handleSlotTouchPress(slots, layout, width, x, y, display)
```

**마우스 감지 함수:**
```lua
ui_scene.updateMouseOver(options, layout, width, font)
ui_scene.updateConfirmMouseOver(width, height, button_count)
```

**사용 예시 (메뉴 씬):**
```lua
local ui_scene = require "engine.ui.menu"
local display = require "engine.display"
local sound = require "engine.sound"

function menu:enter(previous)
    self.options = {"계속하기", "새 게임", "설정", "종료"}
    self.selected = 1
    self.mouse_over = 0

    local vw, vh = display:GetVirtualDimensions()
    self.virtual_width = vw
    self.virtual_height = vh
    self.fonts = ui_scene.createMenuFonts()
    self.layout = ui_scene.createMenuLayout(vh)
end

function menu:update(dt)
    -- 마우스 오버 감지 업데이트
    self.mouse_over = ui_scene.updateMouseOver(
        self.options, self.layout, self.virtual_width, self.fonts.option)
end

function menu:draw()
    display:Attach()
    ui_scene.drawTitle("메인 메뉴", self.fonts.title, self.layout.title_y, self.virtual_width)
    ui_scene.drawOptions(self.options, self.selected, self.mouse_over,
        self.fonts.option, self.layout, self.virtual_width)
    ui_scene.drawControlHints(self.fonts.hint, self.layout, self.virtual_width)
    display:Detach()
end

function menu:keypressed(key)
    local nav_result = ui_scene.handleKeyboardNav(key, self.selected, #self.options)
    if nav_result.action == "navigate" then
        self.selected = nav_result.new_selection
    elseif nav_result.action == "select" then
        self:executeOption(self.selected)
    end
end

function menu:mousereleased(x, y, button)
    if button == 1 and self.mouse_over > 0 then
        self.selected = self.mouse_over
        sound:playSFX("menu", "select")
        self:executeOption(self.selected)
    end
end

-- 터치 입력 (모바일 지원)
function menu:touchpressed(id, x, y, dx, dy, pressure)
    self.mouse_over = ui_scene.handleTouchPress(
        self.options, self.layout, self.virtual_width, self.fonts.option, x, y, display)
    return false
end

function menu:touchreleased(id, x, y, dx, dy, pressure)
    local touched = ui_scene.handleTouchPress(
        self.options, self.layout, self.virtual_width, self.fonts.option, x, y, display)
    if touched > 0 then
        self.selected = touched
        sound:playSFX("menu", "select")
        self:executeOption(self.selected)
        return true
    end
    return false
end
```

**슬롯 기반 메뉴 예시 (저장/로드):**
```lua
function saveslot:touchpressed(id, x, y, dx, dy, pressure)
    self.mouse_over = ui_scene.handleSlotTouchPress(
        self.slots, self.layout, self.virtual_width, x, y, display)
    return false
end

function saveslot:touchreleased(id, x, y, dx, dy, pressure)
    local touched = ui_scene.handleSlotTouchPress(
        self.slots, self.layout, self.virtual_width, x, y, display)
    if touched > 0 then
        self.selected = touched
        self:selectSlot(self.selected)
        return true
    end
    return false
end
```

**장점:**
- 메뉴 씬 간 코드 중복 제거
- 모든 메뉴에서 일관된 UI 동작
- 모바일 터치 지원 내장
- 유지보수 및 확장이 용이

---

## 미니맵 시스템

### `engine/minimap.lua`
미니맵 렌더링 시스템.

---

## HUD 시스템

### `engine/hud.lua`
헤드업 디스플레이 렌더링.

---

## 디버그 시스템

### `engine/debug.lua`
config.ini로 제어되는 디버그 오버레이 및 시각화.

**설정:**
- `config.ini` → `[Game]` → `IsDebug = true/false`
- `IsDebug = true`일 때: F1-F6 키 활성화
- `IsDebug = false`일 때: F1-F6 키 비활성화
- 디버그 UI는 기본적으로 **꺼진 상태** (F1을 눌러 활성화)

**주요 기능:**
- 통합 정보 창 (FPS, 플레이어 상태, 화면 정보)
- 히트박스 시각화 (F1)
- 그리드 시각화 (F2)
- 가상 마우스 커서 (F3)
- 가상 게임패드 테스트 (F4, PC 전용)
- 효과 디버그 (F5)
- 효과 테스트 (F6)
- 애니메이션 개발용 손 마킹 모드

**상태:**
```lua
debug.allowed = true/false   -- APP_CONFIG.is_debug에서 설정 (F1-F6 허용 여부)
debug.enabled = true/false   -- 디버그 UI 표시 여부 (F1로 토글)

-- F1: 디버그 UI 토글 (allowed = true 필요)
debug:toggle()

-- F2-F6: 레이어 토글 (enabled = true 필요)
debug:toggleLayer("visualizations")    -- F2: 그리드
debug:toggleLayer("mouse")             -- F3: 가상 마우스
debug:toggleLayer("virtual_gamepad")   -- F4: 가상 게임패드 (PC)
debug:toggleLayer("effects")           -- F5: 효과 디버그
```

**개발자 참고사항:**
- `IsDebug`는 config.ini의 개발자 전용 설정
- 사용자 설정 저장 시 덮어쓰지 않음
- 버전은 conf.lua에 하드코딩, config.ini에 저장하지 않음

---

## 게임 모드 시스템

### `engine/game_mode.lua`
Topdown vs Platformer 모드 관리.

**모드:**
- **topdown:** 자유로운 2D 이동, 중력 없음
- **platformer:** 수평 이동 + 점프, 중력 활성화

### 이중 콜라이더 시스템 (Topdown)

**Topdown 모드**는 벽 충돌과 깊이 정렬을 위해 이중 콜라이더를 사용합니다:

**플레이어 콜라이더:**
- `player.collider` - 메인 콜라이더 (중앙 원점, 전신, 전투용)
- `player.foot_collider` - 하단 25% 콜라이더 (벽 충돌, 이동용)

**벽 콜라이더:**
- 메인 콜라이더 - 전체 벽 몸체 (전투/물리용)
- `base_collider` - 하단 15% 표면 (발 충돌용)

**충돌 규칙:**
- `PlayerFoot` (foot_collider)가 충돌하는 대상:
  - `Wall` (메인 벽) - 모든 방향에서 차단
  - `WallBase` (base_collider) - 표면 충돌
- 메인 플레이어 콜라이더는 전투, 적 감지에 사용

**Y-정렬:**
- 엔티티들을 **발 위치** 기준으로 정렬하여 올바른 깊이 렌더링
- 플레이어: `y + collider_height / 2` (중앙 + 절반 = 하단)
- 적/NPC: `y + collider_offset_y + collider_height`
- Trees 타일을 Tiled 맵에서 추출하여 엔티티와 함께 Y-정렬
- 결과: 올바른 시각적 깊이 (벽 뒤 엔티티가 뒤에 표시됨)

**Platformer 모드:**
- 메인 콜라이더만 사용 (foot_collider 없음)
- Y-정렬 불필요 (고정 레이어 순서)
- Trees 레이어를 SpriteBatch로 일반 렌더링

**구현:**
- `engine/systems/collision.lua` - 콜라이더 생성 함수
- `engine/systems/world/rendering.lua` - Y-정렬 로직
- `engine/systems/world/loaders.lua` - Trees 타일 추출 (topdown 전용)

---

## 유틸리티

### `engine/utils/util.lua`
일반 유틸리티 함수.

### `engine/utils/restart.lua`
게임 재시작 로직.

### `engine/utils/fonts.lua`
폰트 관리 시스템.

### `engine/constants.lua`
엔진 전체 상수.

---

# Part 2: 시각 효과 & 조명

## 이펙트 시스템

### `engine/effects/`
파티클 및 화면 효과를 포함한 시각 효과 시스템.

**서브시스템:**
- `effects.particles` - 파티클 효과
- `effects.screen` - 화면 효과

### 파티클 효과

```lua
local effects = require "engine.effects"

-- 파티클 생성
effects:spawn("blood", x, y)                  -- 피 튀김
effects:spawn("spark", x, y, angle)           -- 불꽃
effects:spawn("dust", x, y)                   -- 먼지
effects:spawn("slash", x, y, angle)           -- 참격

-- 프리셋
effects:spawnHitEffect(x, y, "player")        -- 플레이어 피격
effects:spawnParryEffect(x, y, angle, true)   -- 패리
effects:spawnWeaponTrail(x, y, angle)         -- 무기 자국

-- 시스템
effects:update(dt)
effects:draw()
```

### 화면 효과

```lua
-- 데미지 & 힐
effects.screen:damage()                       -- 빨간 플래시
effects.screen:heal()                         -- 초록 플래시

-- 상태 효과
effects.screen:poison(5.0)                    -- 초록 비네트
effects.screen:invincible(2.0)                -- 흰색 펄스
effects.screen:stun(0.5)                      -- 회색 오버레이

-- 특수 효과
effects.screen:death(2.0)                     -- 빨간 페이드인
effects.screen:low_health()                   -- 빨간 펄스
effects.screen:teleport()                     -- 흰색 플래시

-- 시스템
effects.screen:update(dt)
effects.screen:draw()
```

---

## 라이팅 시스템

### `engine/lighting/`
이미지 기반 렌더링을 사용하는 동적 조명 시스템.

**구현 방식:** 포인트 라이트에 프로그래밍 방식으로 생성된 원형 그라디언트 이미지를 사용하여 크로스 플랫폼 호환성 제공 (셰이더 이슈 없음).

### 주변광

```lua
local lighting = require "engine.lighting"

-- 프리셋
lighting:setAmbient("day")        -- 밝음 (0.95, 0.95, 1.0)
lighting:setAmbient("dusk")       -- 황혼 (0.7, 0.6, 0.8)
lighting:setAmbient("night")      -- 어두움 (0.05, 0.05, 0.15)
lighting:setAmbient("cave")       -- 매우 어두움 (0.05, 0.05, 0.1)
lighting:setAmbient("indoor")     -- 실내 (0.5, 0.5, 0.55)
lighting:setAmbient("underground")-- 지하 (0.1, 0.1, 0.12)

-- 커스텀
lighting:setAmbient(0.2, 0.3, 0.4)
```

### 포인트 라이트

```lua
-- 횃불
local torch = lighting:addLight({
    type = "point",
    x = 100, y = 100,
    radius = 150,
    color = {1, 0.8, 0.5},       -- 따뜻한 오렌지
    intensity = 1.0,
    flicker = true,              -- 선택사항
    flicker_speed = 5.0,         -- 선택사항
    flicker_amount = 0.3         -- 선택사항 (0.0-1.0)
})

-- 플레이어 광원 (따라다님)
function player:new()
    self.light = lighting:addLight({
        type = "point",
        x = self.x, y = self.y,
        radius = 100,
        color = {1, 0.9, 0.7},
        intensity = 0.8
    })
end

function player:update(dt)
    self.light:setPosition(self.x, self.y)
end
```

### 스포트라이트

**방향성 원뿔 모양 조명:**

```lua
local torch = lighting:addLight({
    type = "spotlight",
    x = 100,
    y = 200,
    radius = 200,              -- 원뿔 길이/너비
    angle = math.pi / 2,       -- 방향 (0 = 아래, -π/2 = 오른쪽, π = 위, π/2 = 왼쪽)
    color = {1, 0.9, 0.7},     -- 따뜻한 횃불 색상
    intensity = 1.0,
    flicker = true,            -- 선택사항: 깜빡임 효과
    flicker_speed = 5.0,
    flicker_amount = 0.2
})

-- 스포트라이트 회전 (예: 플레이어 방향 추적)
torch.angle = player.facing_angle
```

**구현 방식:** 원뿔 모양 그라디언트 이미지를 회전하여 방향 제어

### 광원 제어

```lua
light:setPosition(x, y)
light:setColor(r, g, b)
light:setIntensity(1.5)
light:setEnabled(false)            -- 끄기

lighting:removeLight(light)
lighting:clearLights()
```

### 시스템 업데이트 및 그리기

```lua
lighting:update(dt)                -- 업데이트 (깜빡임 등)
lighting:draw(camera)              -- 그리기 (반드시 camera 전달!)
lighting:setEnabled(false)         -- 전체 시스템 비활성화
```

---

## 렌더링 파이프라인

올바른 효과 및 조명 렌더링 순서:

```lua
function scene:draw()
    camera:attach()

    -- 1. 씬
    world:draw()
    entities:draw()

    -- 2. 파티클 효과 (카메라 안)
    effects:draw()

    camera:detach()

    -- 3. 조명 (카메라 후)
    lighting:draw(camera)

    -- 4. 화면 효과 (카메라 후)
    effects.screen:draw()

    -- 5. UI (영향 없음)
    hud:draw()
end
```

---

## 일반적인 패턴

### 전투 타격

```lua
-- 타격 효과
effects:spawnHitEffect(enemy.x, enemy.y, "enemy")

-- 플레이어 피격 시 화면 플래시
if target == player then
    effects.screen:damage()
end
```

### 체력 부족 경고

```lua
if player.health < player.max_health * 0.2 then
    effects.screen:low_health()
end

-- 회복 시 제거
if player.health >= player.max_health * 0.2 then
    effects.screen:clearEffects("vignette")
end
```

### 엔티티 따라가는 동적 광원

```lua
-- 생성
entity.light = lighting:addLight({
    type = "point",
    x = entity.x, y = entity.y,
    radius = 120,
    color = {1, 0.8, 0.5},
    intensity = 1.0
})

-- 업데이트
entity.light:setPosition(entity.x, entity.y)

-- 제거
lighting:removeLight(entity.light)
```

### 맵 기반 조명

```lua
-- Tiled에서 맵 속성 설정
-- Map Properties:
--   ambient = "night"  (또는 "day", "dusk", "cave", "indoor", "underground")

-- scene:enter() 또는 scene:switchMap()에서
function play:setupLighting()
    lighting:clearLights()
    local ambient = self.world.map.properties.ambient or "day"
    lighting:setAmbient(ambient)

    -- 어두운 환경에서만 광원 추가
    if ambient ~= "day" then
        -- 플레이어 광원 추가
        self.player.light = lighting:addLight({
            type = "point",
            x = self.player.x,
            y = self.player.y,
            radius = 250,
            color = {1, 0.9, 0.7},
            intensity = 1.0
        })

        -- 적, NPC, 세이브 포인트 등에 광원 추가
        -- (전체 구현은 game/scenes/play/init.lua:setupLighting 참조)
    end
end

-- scene:enter()와 scene:switchMap()에서 호출
self:setupLighting()
```

### 중요 사항

1. **화면 효과**는 카메라 후에 그림 (스크린 좌표)
2. **조명**은 camera 파라미터 필수: `lighting:draw(camera)`
3. **파티클**은 카메라 안에서 그림 (월드 좌표)
4. 성능: 광원 ~10-20개, 화면 효과 ~2-3개 동시
5. 무한 화면 효과 (`duration = -1`)는 수동 제거 필요
6. 많은 광원 사용 시 라이트 컬링 권장 (카메라 거리 체크)
7. **라이팅 시스템**은 크로스 플랫폼 호환성을 위해 이미지 기반 렌더링 사용 (셰이더 없음)
8. 광원 이미지는 초기화 시에 생성됨 (256x256, 이차 감쇠)

---

# Part 3: 게임 콘텐츠 제작

## 철학: 코드보다 콘텐츠

`game/` 폴더는 엔진 프로그래밍이 아닌 **콘텐츠 제작**을 위해 설계되었습니다:
- **최소한의 코드** - 주로 데이터 정의
- **간단한 API** - 엔진 함수 호출
- **빠른 반복** - 엔진을 건드리지 않고 콘텐츠 변경

---

## 씬 만들기

### 씬 구조
씬은 `game/scenes/`에 위치합니다.

**단일 파일 씬:**
```lua
-- game/scenes/credits.lua
local credits = {}

function credits:enter(previous, ...)
    self.text = "Thanks for playing!"
end

function credits:update(dt)
    -- Update logic
end

function credits:draw()
    love.graphics.print(self.text, 100, 100)
end

return credits
```

**모듈화된 씬:**
```
game/scenes/shop/
├── init.lua          - 씬 코디네이터
├── items.lua         - 상점 아이템 정의
├── render.lua        - UI 렌더링
└── input.lua         - 입력 처리
```

---

## 엔티티 만들기

### 적 타입 예제

```lua
-- engine/entities/enemy/types/goblin.lua
return {
    name = "Goblin",
    max_health = 50,
    damage = 10,
    speed = 120,
    sprite_path = "assets/images/enemies/goblin.png",
    ai_type = "aggressive",
    animations = {
        idle = { frames = "1-4", fps = 8 },
        walk = { frames = "5-8", fps = 12 }
    }
}
```

### 아이템 타입 예제

```lua
-- engine/item/types/potion.lua
return {
    id = "potion",
    name = "Potion",
    icon = "assets/images/items/potion.png",
    max_stack = 99,
    use = function(player)
        player.health = math.min(player.health + 30, player.max_health)
        return true
    end
}
```

---

## 사운드 추가하기

### 1. 오디오 파일 추가
```
assets/
├── bgm/
│   └── dungeon.ogg
└── sound/
    └── player/
        └── magic_cast.wav
```

### 2. 사운드 설정에 등록
```lua
-- game/data/sounds.lua
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
                volume = 0.8
            }
        }
    }
}
```

### 3. 게임에서 재생
```lua
local sound = require "engine.sound"
sound:playBGM("dungeon")
sound:playSFX("player", "magic_cast")
```

---

## 맵 만들기

### 1. Tiled에서 맵 생성
- Tiled Map Editor 사용
- `assets/maps/levelX/`에 배치
- Lua 포맷으로 익스포트

### 2. 맵 속성 설정
```
Map Properties:
  game_mode = "topdown"
  bgm = "dungeon"
  ambient = "night"
```

### 3. 필수 레이어
- **Ground** - 지형
- **Trees** - 상단 장식
- **Walls** - 충돌
- **Portals** - 전환 구역
- **Enemies** - 적 스폰
- **Lights** - 광원 (선택)

### 4. 포탈 추가
```
Object Properties:
  type = "portal"
  target_map = "assets/maps/level1/area2.lua"
  spawn_x = 100
  spawn_y = 200
```

---

## 입력 설정하기

### 입력 설정 편집
```lua
-- game/data/input_config.lua
return {
    actions = {
        move_left = {
            keys = {"a", "left"},
            gamepad = {"dpleft"}
        },
        attack = {
            mouse = {1},
            gamepad = {"a"}
        },
        magic = {
            keys = {"q"},
            gamepad = {"y"}
        }
    }
}
```

---

## 컷씬 만들기

### 컷씬 정의
```lua
-- game/data/intro_configs.lua
return {
    chapter1_intro = {
        background = "assets/images/cutscenes/chapter1_bg.png",
        bgm = "dramatic",
        messages = {
            "오래 전, 먼 나라에서...",
            "거대한 악이 깨어났다...",
            "오직 한 영웅만이 막을 수 있다..."
        },
        speaker = "내레이터"
    }
}
```

---

## 세이브 시스템 사용하기

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
function menu:loadGame(slot)
    local save_data = save_sys:loadGame(slot)

    if save_data then
        local play = require "game.scenes.play"
        scene_control.switch(play, save_data.map, save_data.x, save_data.y, slot)
    end
end
```

---

## 빠른 레시피

### 새 레벨 추가
1. Tiled에서 맵 생성: `assets/maps/level2/castle.tmx`
2. Lua로 익스포트: `assets/maps/level2/castle.lua`
3. BGM 추가: `game/data/sounds.lua`
4. 맵 속성 설정: `bgm = "castle"`
5. 이전 레벨에서 포탈 생성

### 새 적 추가
1. 스프라이트: `assets/images/enemies/dragon.png`
2. 타입: `engine/entities/enemy/types/dragon.lua`
3. Tiled 맵에 배치: `type = "dragon"`

### 새 아이템 추가
1. 아이콘: `assets/images/items/sword.png`
2. 타입: `engine/item/types/sword.lua`
3. 인벤토리에 추가: `inventory:addItem("sword", 1)`

---

# Part 4: 개발 워크플로우

## 아키텍처 원칙

### 1. 엔진/게임 분리
**목표:** 엔진은 재사용 가능하고, 게임은 콘텐츠입니다.

**규칙:**
- ✅ 엔진 파일은 게임 파일을 임포트하면 안 됨
- ✅ 게임 파일은 엔진 파일을 임포트할 수 있음
- ✅ 엔진은 범용적이고 설정 가능해야 함
- ✅ 게임은 데이터 기반이어야 함

### 2. 모듈식 아키텍처
**목표:** 각 파일은 단일 책임을 가집니다.

**파일을 분할해야 하는 경우:**
- 파일이 500줄을 초과
- 관련 없는 여러 책임
- 탐색이 어려움

### 3. 데이터 주도 설계
**목표:** game/ 폴더의 코드를 최소화하고 데이터를 최대화합니다.

---

## 개발 워크플로우

### 새로운 엔진 시스템 추가

1. **시스템 파일 생성:**
   ```lua
   -- engine/yoursystem.lua
   local yoursystem = {}

   function yoursystem:init(config)
       -- 설정으로 초기화
   end

   return yoursystem
   ```

2. **범용적으로 유지**
3. **문서화**

### 새로운 게임 씬 추가

1. **씬 구조 생성**
2. **씬 라이프사이클 구현**
3. **씬 컨트롤에 연결**

---

## 코드 스타일

### 네이밍 규칙
```lua
-- 모듈: 언더스코어를 사용한 소문자
local scene_control = require "engine.scene.control"

-- 함수: camelCase
function player:updateAnimation(dt)

-- 상수: UPPER_CASE
local MAX_HEALTH = 100

-- Private 함수: 언더스코어 접두사
local function _internalHelper()
```

### 파일 구성
```lua
-- 1. 모듈 선언
local mymodule = {}

-- 2. Requires
local engine_system = require "engine.something"

-- 3. 로컬 상수
local MAX_ITEMS = 10

-- 4. 로컬 함수
local function _helper()
end

-- 5. Public 함수
function mymodule:publicMethod()
end

-- 6. 모듈 반환
return mymodule
```

---

## 디버깅

### 디버그 모드 (F1)
- F1: 디버그 정보 + 히트박스
- F2: 그리드 시각화
- F3: 가상 마우스

### Print 디버깅

```lua
-- 디버그 메시지
dprint("Player HP:", player.health)

-- 중요한 에러/경고
print("ERROR: Failed to load map")
```

---

## 테스팅

### 수동 테스트 체크리스트
- [ ] 게임 시작
- [ ] 모든 씬 접근
- [ ] 컨트롤 작동
- [ ] 사운드 재생
- [ ] 저장/로드
- [ ] 전투 시스템
- [ ] 맵 전환
- [ ] 효과 및 조명

---

## 빌드 및 배포

### .love 파일 생성
```bash
zip -9 -r game.love . -x "*.git*" "*.md" "docs/*"
```

### Windows
```bash
cat love.exe game.love > mygame.exe
```

---

## 버전 관리

### Git 워크플로우
```bash
# 불필요한 파일 무시
echo "config.ini" >> .gitignore

# 구조 변경 커밋
git add engine/ game/
git commit -m "Refactor: Separate engine and game folders"
```

---

## 성능 팁

### 핫 패스에서 피해야 할 것
```lua
-- ❌ 나쁨: 매 프레임마다 테이블 생성
function update(dt)
    local pos = {x = player.x, y = player.y}
end

-- ✅ 좋음: 테이블 재사용
local temp_pos = {x = 0, y = 0}
function update(dt)
    temp_pos.x = player.x
    temp_pos.y = player.y
end
```

---

**프레임워크:** LÖVE 11.5 + Lua 5.1
**아키텍처:** 엔진/게임 분리
**최종 업데이트:** 2025-11-07
