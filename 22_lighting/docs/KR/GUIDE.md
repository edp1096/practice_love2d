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

## 애플리케이션 생명주기

### `engine/lifecycle.lua`
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
lifecycle.screen = screen
lifecycle.input = input
lifecycle.scene_control = scene_control
-- ... (기타 의존성)

-- 애플리케이션 초기화
lifecycle:initialize(menu)
```

**목적:**
- main.lua의 복잡한 초기화 로직을 캡슐화
- 여러 엔진 시스템 조정 (input, screen, fonts, sound)
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
coords:virtualToPhysical(vx, vy, screen)
coords:physicalToVirtual(px, py, screen)
coords:worldToVirtual(wx, wy, camera, screen)
coords:virtualToWorld(vx, vy, camera, screen)

-- 유틸리티 함수
coords:debugPoint(x, y, camera, screen, label)
coords:isVisibleInCamera(wx, wy, camera, margin)
coords:isVisibleInVirtual(vx, vy, screen)
coords:distanceWorld(x1, y1, x2, y2)
coords:distanceCamera(x1, y1, x2, y2, camera)
```

**일반적인 사용 사례:**

1. **마우스 클릭 → 월드 위치:**
```lua
local mx, my = love.mouse.getPosition()  -- Physical
local vx, vy = coords:physicalToVirtual(mx, my, screen)
local wx, wy = coords:virtualToWorld(vx, vy, cam, screen)
-- 이제 (wx, wy)가 월드 위치
```

2. **월드 오브젝트에 UI 오버레이:**
```lua
-- 적 위에 체력바 표시
local cx, cy = coords:worldToCamera(enemy.x, enemy.y, cam)
local vx, vy = coords:physicalToVirtual(cx, cy, screen)
-- 가상 좌표 (vx, vy)에 그리기
```

3. **좌표 디버깅:**
```lua
coords:debugPoint(player.x, player.y, cam, screen, "Player")
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
- ❌ **절대** `screen:ToVirtualCoords()` 또는 `screen:ToScreenCoords()` 직접 사용 금지
- coords 모듈은 통합 인터페이스를 제공하며 자동으로 nil 체크를 처리합니다

---

## 카메라 시스템

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

## 사운드 시스템

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
우선순위 시스템으로 LÖVE 입력 이벤트를 적절한 핸들러로 라우팅합니다.

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

### `engine/dialogue.lua`
NPC 대화 시스템 (Talkies 라이브러리 래퍼).

**주요 함수:**
```lua
dialogue:show(messages, avatar, on_complete)  -- 대화 표시
dialogue:isActive()                           -- 대화가 활성화되어 있는지 확인
dialogue:update(dt)                           -- 대화 시스템 업데이트
dialogue:draw()                               -- 대화 상자 그리기
```

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
디버그 오버레이 및 시각화 (F1 토글).

**주요 기능:**
- 통합 정보 창 (FPS, 플레이어 상태, 화면 정보)
- 히트박스 시각화 (F1)
- 그리드 시각화 (F2)
- 가상 마우스 커서 (F3)

---

## 게임 모드 시스템

### `engine/game_mode.lua`
Topdown vs Platformer 모드 관리.

**모드:**
- **topdown:** 자유로운 2D 이동, 중력 없음
- **platformer:** 수평 이동 + 점프, 중력 활성화

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

```lua
-- 스포트라이트 (미구현)
-- TODO: 이미지 또는 셰이더를 사용하여 스포트라이트 구현
```

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
            radius = 350,
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
-- game/entities/enemy/types/goblin.lua
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
-- game/entities/item/types/potion.lua
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
2. 타입: `game/entities/enemy/types/dragon.lua`
3. Tiled 맵에 배치: `type = "dragon"`

### 새 아이템 추가
1. 아이콘: `assets/images/items/sword.png`
2. 타입: `game/entities/item/types/sword.lua`
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
local scene_control = require "engine.scene_control"

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
