# Love2D 게임 프레임워크 가이드

## 📋 목차
1. [프로젝트 구조](#프로젝트-구조)
2. [핵심 시스템](#핵심-시스템)
3. [게임 만들기](#게임-만들기)
4. [주요 API](#주요-api)

---

## 프로젝트 구조

```
14_sound/
├── conf.lua                    # Love2D 설정 (해상도, 모듈)
├── main.lua                    # 엔트리 포인트
├── data/                       # 게임 데이터 정의
│   ├── input_config.lua        # 입력 매핑 (키보드/게임패드)
│   └── sounds.lua              # 사운드 정의 및 설정
├── systems/                    # 핵심 시스템
│   ├── scene_control.lua       # 씬 전환 관리
│   ├── input.lua               # 통합 입력 처리
│   ├── sound.lua               # 사운드 시스템
│   ├── world.lua               # 맵/물리/충돌
│   ├── camera.lua              # 카메라 효과
│   ├── effects.lua             # 파티클 효과
│   ├── dialogue.lua            # 대화 시스템
│   ├── save.lua                # 세이브/로드
│   ├── hud.lua                 # UI 표시
│   └── debug.lua               # 디버그 도구
├── scenes/                     # 게임 씬
│   ├── menu.lua                # 메인 메뉴
│   ├── play.lua                # 게임플레이
│   ├── pause.lua               # 일시정지
│   ├── settings.lua            # 설정
│   ├── gameover.lua            # 게임 오버
│   └── ...
├── entities/                   # 게임 엔티티
│   ├── player/                 # 플레이어
│   ├── enemy/                  # 적
│   ├── npc/                    # NPC
│   └── weapon/                 # 무기
└── lib/                        # 유틸리티 라이브러리
    ├── screen/                 # 해상도/스케일링
    ├── ini/                    # INI 파일 파서
    └── text/                   # 텍스트 유틸
```

---

## 핵심 시스템

### 🎮 입력 시스템 (systems/input.lua)

키보드, 마우스, 게임패드를 통합 처리합니다.

```lua
-- 사용 예시
local input = require "systems.input"

-- 이동 입력 (키보드 또는 게임패드)
local vx, vy = input:getMovement()

-- 조준 방향 (마우스 또는 우측 스틱)
local angle = input:getAimDirection(player.x, player.y, cam)

-- 액션 확인
if input:wasPressed("attack", "keyboard", key) then
    player:attack()
end

-- 진동 피드백
input:vibrateAttack()  -- 공격
input:vibratePerfectParry()  -- 완벽한 패리
```

**설정 파일**: `data/input_config.lua`에서 키 매핑 변경 가능

---

### 🔊 사운드 시스템 (systems/sound.lua)

BGM과 효과음을 관리합니다.

```lua
local sound = require "systems.sound"

-- BGM 재생
sound:playBGM("level1")  -- data/sounds.lua에 정의된 이름

-- 효과음 재생 (자동 pitch variation)
sound:playSFX("combat", "sword_swing")

-- 풀링된 사운드 (빈번한 재생용)
sound:playPooled("player", "footstep")

-- 볼륨 조절
sound:setMasterVolume(0.8)
sound:setBGMVolume(0.7)
sound:setSFXVolume(0.9)
```

**설정 파일**: `data/sounds.lua`에서 사운드 추가/설정

---

### 🎬 씬 시스템 (systems/scene_control.lua)

게임 씬 전환을 관리합니다.

```lua
local scene_control = require "systems.scene_control"

-- 씬 전환 (이전 씬 종료)
local menu = require "scenes.menu"
scene_control.switch(menu)

-- 씬 푸시 (이전 씬 유지, 일시정지용)
local pause = require "scenes.pause"
scene_control.push(pause)

-- 이전 씬으로 복귀
scene_control.pop()
```

**씬 구조**:
```lua
local my_scene = {}

function my_scene:enter(previous, ...)
    -- 씬 진입 시 초기화
end

function my_scene:update(dt)
    -- 매 프레임 업데이트
end

function my_scene:draw()
    -- 렌더링
end

function my_scene:keypressed(key)
    -- 키 입력 처리
end

return my_scene
```

---

### 🗺️ 월드 시스템 (systems/world.lua)

맵, 물리, 충돌을 처리합니다.

```lua
local world = require "systems.world"

-- 월드 생성 (Tiled 맵 로드)
self.world = world:new("assets/maps/level1/area1.lua")

-- 엔티티 추가
self.world:addEntity(player)

-- 적 추가
local enemy = require "entities.enemy"
local slime = enemy:new(200, 200, "green_slime")
self.world:addEnemy(slime)

-- 무기 충돌 체크
local hits = self.world:checkWeaponCollisions(player.weapon)
for _, hit in ipairs(hits) do
    self.world:applyWeaponHit(hit)
end
```

---

### 💾 세이브 시스템 (systems/save.lua)

3개 슬롯 세이브/로드 지원

```lua
local save_sys = require "systems.save"

-- 저장
local save_data = {
    hp = player.health,
    max_hp = player.max_health,
    map = current_map_path,
    x = player.x,
    y = player.y
}
save_sys:saveGame(1, save_data)  -- 슬롯 1에 저장

-- 불러오기
local data = save_sys:loadGame(1)
if data then
    player.health = data.hp
    player.x = data.x
end

-- 최근 슬롯 찾기 (Continue 기능)
local recent_slot = save_sys:getMostRecentSlot()
```

---

### 🎨 효과 시스템 (systems/effects.lua)

파티클 효과 생성

```lua
local effects = require "systems.effects"

-- 개별 효과
effects:spawn("blood", x, y, angle, 40)  -- 피 효과
effects:spawn("spark", x, y, angle, 30)  -- 불꽃
effects:spawn("dust", x, y, nil, 20)     -- 먼지

-- 프리셋 효과
effects:spawnHitEffect(x, y, "enemy", angle)
effects:spawnParryEffect(x, y, angle, is_perfect)
effects:spawnWeaponTrail(x, y, angle)
```

---

## 게임 만들기

### 1️⃣ 새 씬 만들기

```lua
-- scenes/my_level.lua
local my_level = {}

local player = require "entities.player"
local world = require "systems.world"
local scene_control = require "systems.scene_control"
local sound = require "systems.sound"

function my_level:enter(previous, ...)
    -- 플레이어 생성
    self.player = player:new("assets/images/player-sheet.png", 400, 300)
    
    -- 월드 로드
    self.world = world:new("assets/maps/my_map.lua")
    self.world:addEntity(self.player)
    
    -- BGM 재생
    sound:playBGM("level1")
end

function my_level:update(dt)
    -- 플레이어 업데이트
    local vx, vy = self.player:update(dt, self.cam)
    self.world:moveEntity(self.player, vx, vy, dt)
    
    -- 적 업데이트
    self.world:updateEnemies(dt, self.player.x, self.player.y)
    
    -- 월드 업데이트
    self.world:update(dt)
end

function my_level:draw()
    -- 맵 레이어 그리기
    self.world:drawLayer("Ground")
    
    -- 엔티티 Y-정렬 그리기
    self.world:drawEntitiesYSorted(self.player)
    
    -- 상단 레이어
    self.world:drawLayer("Trees")
end

function my_level:keypressed(key)
    if key == "escape" then
        local pause = require "scenes.pause"
        scene_control.push(pause)
    end
end

return my_level
```

---

### 2️⃣ 적 추가하기

```lua
-- entities/enemy/types/slime.lua에 타입 정의
slime.ENEMY_TYPES.my_slime = {
    sprite_sheet = "assets/images/my-slime.png",
    health = 100,
    damage = 15,
    speed = 80,
    detection_range = 200,
    attack_range = 50,
    -- ... 기타 설정
}

-- Tiled 맵의 "Enemies" 레이어에 오브젝트 추가
-- Properties에 type = "my_slime" 설정
```

---

### 3️⃣ 사운드 추가하기

```lua
-- data/sounds.lua
return {
    bgm = {
        my_level = { 
            path = "assets/bgm/my_level.ogg", 
            volume = 0.7, 
            loop = true 
        }
    },
    
    sfx = {
        my_category = {
            my_sound = { 
                path = "assets/sound/my_sound.wav", 
                volume = 0.8,
                pitch_variation = "normal"  -- 자동 pitch 변조
            }
        }
    }
}

-- 재생
sound:playBGM("my_level")
sound:playSFX("my_category", "my_sound")
```

---

### 4️⃣ 입력 추가하기

```lua
-- data/input_config.lua
return {
    my_actions = {
        special_move = {
            keyboard = { "q" },
            gamepad = "y",  -- Triangle (DualSense)
            mouse = 3       -- Middle click
        }
    }
}

-- 사용
if input:wasPressed("special_move", "keyboard", key) then
    player:doSpecialMove()
end
```

---

## 주요 API

### Screen (lib/screen/)
```lua
local screen = require "lib.screen"

-- 가상 해상도 (960x540 고정)
local vw, vh = screen:GetVirtualDimensions()

-- 마우스 좌표 변환
local vmx, vmy = screen:GetVirtualMousePosition()

-- 렌더링 (씬 draw 함수에서)
screen:Attach()
-- ... 게임 렌더링
screen:Detach()
```

### Camera (systems/camera.lua)
```lua
local camera_sys = require "systems.camera"

-- 화면 흔들림
camera_sys:shake(10, 0.3)  -- (강도, 지속시간)

-- 슬로우 모션
camera_sys:activate_slow_motion(0.5, 0.3)  -- (지속시간, 시간배율)

-- 업데이트 (play.lua)
local scaled_dt = camera_sys:get_scaled_dt(dt)
local shake_x, shake_y = camera_sys:get_shake_offset()
```

### HUD (systems/hud.lua)
```lua
local hud = require "systems.hud"

-- 체력바
hud:draw_health_bar(x, y, width, height, current_hp, max_hp)

-- 쿨다운 표시
hud:draw_cooldown(x, y, width, current_cd, max_cd, "Dodge", "[Space]")

-- 패리 성공 표시
hud:draw_parry_success(player, screen_width, screen_height)

-- 슬로우 모션 비네트 효과
hud:draw_slow_motion_vignette(time_scale, screen_width, screen_height)
```

### Dialogue (systems/dialogue.lua)
```lua
local dialogue = require "systems.dialogue"

-- 초기화 (씬 enter에서)
dialogue:initialize()

-- 대화 표시
dialogue:showMultiple("NPC Name", {"Hello!", "How are you?"})

-- 대화창 열려있는지 확인
if dialogue:isOpen() then
    -- 입력 처리 차단
end

-- 업데이트/그리기
dialogue:update(dt)
dialogue:draw()
```

### Debug (systems/debug.lua)
```lua
local debug = require "systems.debug"

-- 디버그 모드 확인
if debug.enabled then
    -- 디버그 정보 표시
end

-- 특정 레이어 확인
if debug.show_colliders then
    -- 충돌 박스 그리기
end

-- 키 입력 처리 (씬 keypressed에서)
debug:handleInput(key, {
    player = self.player,
    world = self.world,
    camera = self.cam
})
```

---

## 🚀 빠른 시작

### 최소 게임 구조

```lua
-- main.lua
local scene_control = require "systems.scene_control"
local input = require "systems.input"
local screen = require "lib.screen"

function love.load()
    screen:Initialize(GameConfig)
    input:init()
    
    local menu = require "scenes.menu"
    scene_control.switch(menu)
end

function love.update(dt)
    input:update(dt)
    scene_control.update(dt)
end

function love.draw()
    scene_control.draw()
end

function love.keypressed(key)
    scene_control.keypressed(key)
end

function love.resize(w, h)
    screen:Resize(w, h)
    scene_control.resize(w, h)
end
```

### 필수 파일
1. `conf.lua` - Love2D 설정
2. `main.lua` - 엔트리 포인트
3. `data/sounds.lua` - 사운드 정의
4. `data/input_config.lua` - 입력 매핑
5. `scenes/menu.lua` - 시작 씬

---

## 💡 팁

### 성능 최적화
- 빈번한 사운드는 **풀(pool)** 사용: `sound:playPooled()`
- 파티클 효과는 `effects:spawn()` 호출 최소화
- 충돌 체크는 필요할 때만
- Y-정렬은 `world:drawEntitiesYSorted()` 사용

### 디버그
- **F3**: 전체 디버그 토글
- **F1**: 화면 정보 표시
- **F2**: 가상 마우스 커서 표시
- **F4**: 효과 디버그
- **F5**: 마우스 위치에 테스트 효과 생성
- **F6**: AI 상태 표시
- **F7**: NPC 디버그 정보
- **F12**: 레거시 디버그 (호환성)

### 멀티플랫폼
- 키보드/마우스/게임패드 자동 지원
- `input:hasGamepad()` 로 UI 프롬프트 변경
- `input:getPrompt("action")` 로 버튼 표시

### 화면 관리
- 가상 해상도: 960x540 (16:9)
- 실제 창 크기는 자동 스케일링
- `screen:Attach()` / `screen:Detach()` 로 렌더링
- 레터박스/필러박스 자동 처리

---

## 📚 엔티티 시스템

### Player (entities/player/)

```lua
local player = require "entities.player"

-- 생성
local p = player:new("assets/images/player-sheet.png", x, y)

-- 업데이트
local vx, vy = p:update(dt, camera, dialogue_open)

-- 전투
p:attack()                -- 공격
p:startParry()            -- 패리 시작
p:startDodge()            -- 회피
p:takeDamage(damage)      -- 데미지 받기

-- 상태 확인
if p:isAlive() then end
if p:isInvincible() then end
if p:isParrying() then end
if p:isDodging() then end

-- 렌더링
p:drawAll()  -- 플레이어 + 무기
p:draw()     -- 플레이어만
p:drawWeapon()  -- 무기만
```

### Enemy (entities/enemy/)

```lua
local enemy = require "entities.enemy"

-- 생성
local e = enemy:new(x, y, "green_slime")

-- 패트롤 설정
e:setPatrolPoints({
    {x = 100, y = 100},
    {x = 200, y = 100},
    {x = 200, y = 200}
})

-- 업데이트
local vx, vy = e:update(dt, player_x, player_y)

-- 전투
e:takeDamage(damage)
e:stun(duration, is_perfect)

-- 렌더링
e:draw()
```

### NPC (entities/npc/)

```lua
local npc = require "entities.npc"

-- 생성
local n = npc:new(x, y, "merchant", "shop_keeper_1")

-- 상호작용 확인
if n.can_interact then
    local dialogue = n:interact()
    -- 대화 시스템에 전달
end

-- 렌더링
n:draw()
n:drawDebug()
```

### Weapon (entities/weapon/)

```lua
local weapon = require "entities.weapon"

-- 생성
local w = weapon:new("sword")

-- 공격
if w:startAttack() then
    -- 공격 시작됨
end

-- 충돌 체크
if w:canDealDamage() then
    local hitbox = w:getHitbox()
    if w:checkHit(enemy) then
        local damage = w:getDamage()
        enemy:takeDamage(damage)
    end
end

-- 업데이트
w:update(dt, owner_x, owner_y, angle, direction, anim_name, frame_index)

-- 렌더링
w:draw(debug_mode)
w:drawSheathParticles()
```

---

## 🎨 이펙트 가이드

### 파티클 효과 종류

```lua
local effects = require "systems.effects"

-- Blood (피) - 빨간색, 튀김
effects:spawn("blood", x, y, angle, 35)

-- Spark (불꽃) - 노란색/흰색, 금속 충돌
effects:spawn("spark", x, y, angle, 40)

-- Dust (먼지) - 회갈색, 지면 충돌
effects:spawn("dust", x, y, nil, 30)

-- Slash (참격) - 청록색, 무기 궤적
effects:spawn("slash", x, y, angle, 20)
```

### 프리셋 효과

```lua
-- 타격 효과 (자동으로 적절한 파티클 선택)
effects:spawnHitEffect(x, y, "enemy", angle)    -- 적 타격
effects:spawnHitEffect(x, y, "player", angle)   -- 플레이어 피격
effects:spawnHitEffect(x, y, "wall", angle)     -- 벽 충돌

-- 패리 효과
effects:spawnParryEffect(x, y, angle, false)    -- 일반 패리
effects:spawnParryEffect(x, y, angle, true)     -- 완벽한 패리

-- 무기 궤적
effects:spawnWeaponTrail(x, y, angle)
```

### 커스텀 파티클 시스템

```lua
-- systems/effects.lua에 새 시스템 추가
function effects:createMyEffect()
    local particle_img = createParticleImage(12)
    local ps = love.graphics.newParticleSystem(particle_img, 60)
    
    ps:setParticleLifetime(0.5, 1.0)
    ps:setEmissionRate(0)
    ps:setSizes(2, 3, 2, 1, 0)
    ps:setColors(r1, g1, b1, a1, r2, g2, b2, a2, ...)
    ps:setSpeed(100, 180)
    ps:setSpread(math.pi * 2)
    
    return ps
end

-- 초기화에서 등록
effects.particle_systems.my_effect = effects:createMyEffect()

-- 사용
effects:spawn("my_effect", x, y, angle, 30)
```

---

## 🗺️ 맵 제작 가이드 (Tiled)

### 레이어 구조

```
Ground      (Tile Layer)      - 바닥 타일
Walls       (Object Layer)    - 충돌 벽 (polygon/rectangle)
Portals     (Object Layer)    - 씬 전환 포털
SavePoints  (Object Layer)    - 세이브 포인트
Enemies     (Object Layer)    - 적 스폰 위치
NPCs        (Object Layer)    - NPC 위치
Trees       (Tile Layer)      - 상단 장식 (플레이어 뒤)
```

### 오브젝트 Properties

**Walls (충돌)**
- 타입: Rectangle, Polygon, Polyline, Ellipse

**Portals (전환)**
```
type = "portal"
target_map = "assets/maps/level1/area2.lua"
spawn_x = 400
spawn_y = 250
```

**Game Clear (게임 클리어)**
```
type = "gameclear"
```

**Save Points (세이브)**
```
type = "savepoint"
id = "checkpoint_1"
```

**Enemies (적)**
```
type = "green_slime"   (또는 red_slime, blue_slime, purple_slime)
patrol_points = "50,0;-50,0;0,50;0,-50"  (선택사항)
```

**NPCs**
```
type = "merchant"      (또는 guard, villager, elder)
id = "shop_keeper_1"
```

---

## 🔧 설정 파일

### conf.lua (Love2D 설정)

```lua
GameConfig = {
    title = "My Game",
    author = "Your Name",
    version = "1.0.0",
    
    width = 1280,
    height = 720,
    resizable = true,
    fullscreen = false,
    vsync = true,
    scale_mode = "fit",  -- "fit", "fill", "stretch"
    
    min_width = 640,
    min_height = 360
}

function love.conf(t)
    t.title = GameConfig.title
    t.window.width = GameConfig.width
    t.window.height = GameConfig.height
    t.window.resizable = GameConfig.resizable
    t.window.vsync = GameConfig.vsync
    
    -- 사용할 모듈 설정
    t.modules.joystick = true
    t.modules.physics = true
    t.modules.touch = false
end
```

### config.ini (런타임 설정)

```ini
Title = My Game
Author = Your Name

[Window]
Width = 1280
Height = 720
FullScreen = false
Monitor = 1
```

---

## 📝 체크리스트

### 새 프로젝트 시작

- [ ] `conf.lua` 설정 (타이틀, 해상도)
- [ ] `data/sounds.lua` 사운드 정의
- [ ] `data/input_config.lua` 입력 매핑 확인
- [ ] `scenes/menu.lua` 메인 메뉴 작성
- [ ] `scenes/play.lua` 게임플레이 씬 작성
- [ ] Tiled로 맵 제작 및 레이어 설정
- [ ] 플레이어 스프라이트 준비 (48x48 프레임)
- [ ] 적 타입 정의 (`entities/enemy/types/`)
- [ ] BGM 및 효과음 준비

### 테스트

- [ ] 키보드 입력 동작 확인
- [ ] 게임패드 입력 동작 확인 (연결된 경우)
- [ ] 화면 크기 조절 테스트
- [ ] 전체화면 전환 테스트
- [ ] 세이브/로드 기능 확인
- [ ] 씬 전환 테스트
- [ ] 사운드 재생 확인
- [ ] 충돌 검사 확인 (F3로 디버그 모드)

### 최적화

- [ ] 자주 재생되는 사운드는 pool 사용
- [ ] 파티클 효과 개수 제한
- [ ] 화면 밖 엔티티 업데이트 스킵
- [ ] 불필요한 draw 호출 제거
- [ ] 충돌 체크 최적화

---

## 🎯 고급 기능

### 카메라 효과

```lua
local camera_sys = require "systems.camera"

-- 슬로우 모션 + 화면 흔들림 조합
camera_sys:activate_slow_motion(0.3, 0.2)  -- 0.3초간 20% 속도
camera_sys:shake(15, 0.2)                  -- 강한 진동

-- 업데이트
camera_sys:update(dt)
local scaled_dt = camera_sys:get_scaled_dt(dt)  -- 슬로우 모션 적용된 dt

-- 카메라 오프셋 적용
local shake_x, shake_y = camera_sys:get_shake_offset()
camera:lookAt(player.x + shake_x, player.y + shake_y)

-- 슬로우 모션 확인
if camera_sys:is_slow_motion() then
    -- 특수 연출
end
```

### 진동(Haptic) 피드백

```lua
local input = require "systems.input"

-- 기본 진동 (지속시간, 좌강도, 우강도)
input:vibrate(0.2, 0.8, 0.5)

-- 프리셋
input:vibrateAttack()         -- 약한 진동
input:vibrateHit()            -- 중간 진동
input:vibrateParry()          -- 강한 진동
input:vibratePerfectParry()   -- 매우 강한 진동
input:vibrateDodge()          -- 짧은 진동
input:vibrateWeaponHit()      -- 무기 타격

-- 설정
input:setVibrationEnabled(true)
input:setVibrationStrength(0.75)  -- 75%
input:setDeadzone(0.15)           -- 조이스틱 데드존
```

### 대화 시스템

```lua
local dialogue = require "systems.dialogue"

-- 단일 메시지
dialogue:showSimple("NPC Name", "Hello!")

-- 다중 메시지 (순차 표시)
dialogue:showMultiple("Merchant", {
    "Welcome to my shop!",
    "What would you like to buy?",
    "Thank you for visiting!"
})

-- 게임플레이에서
if dialogue:isOpen() then
    -- 입력 차단
    if input:wasPressed("interact", "keyboard", key) then
        dialogue:onAction()  -- 다음 메시지
    end
    return  -- 다른 입력 무시
end
```

### 세이브 시스템 심화

```lua
local save_sys = require "systems.save"

-- 슬롯 정보 가져오기
local slot_info = save_sys:getSlotInfo(1)
if slot_info.exists then
    print("HP: " .. slot_info.hp .. "/" .. slot_info.max_hp)
    print("Map: " .. slot_info.map_display)
    print("Time: " .. slot_info.time_string)
end

-- 모든 슬롯 정보
local all_slots = save_sys:getAllSlotsInfo()

-- 슬롯 삭제
save_sys:deleteSlot(2)

-- 모든 세이브 삭제
save_sys:deleteAllSlots()

-- 세이브 디렉토리 열기 (OS 탐색기)
save_sys:openSaveFolder()

-- 상태 출력
save_sys:printStatus()
```

---

## 🐛 디버깅 가이드

### 일반적인 문제

**문제**: 사운드가 재생되지 않음
- `data/sounds.lua`에 정의되어 있는지 확인
- 파일 경로가 정확한지 확인
- 볼륨 설정 확인 (`sound:printStatus()`)
- Mute 상태 확인

**문제**: 입력이 동작하지 않음
- `data/input_config.lua`에 액션이 정의되어 있는지 확인
- `input:wasPressed(action, source, value)` 파라미터 확인
- 게임패드 연결 확인 (`input:hasGamepad()`)

**문제**: 충돌이 작동하지 않음
- Tiled 맵의 Walls 레이어 확인
- 충돌 클래스 설정 확인
- F3 디버그 모드로 충돌 박스 표시

**문제**: 화면이 이상하게 표시됨
- `screen:Attach()` / `screen:Detach()` 쌍 확인
- 스케일 모드 확인 (`GameConfig.scale_mode`)
- F1으로 화면 정보 확인

**문제**: 적이 플레이어를 감지하지 못함
- `detection_range` 설정 확인
- Line of Sight 체크 (`world:checkLineOfSight`)
- F6으로 AI 상태 확인

### 디버그 명령어

```lua
-- 콘솔에 출력
print("Debug message")

-- 디버그 시스템
local debug = require "systems.debug"
debug:toggle()  -- F3 키와 동일

-- 특정 레이어만 표시
debug.show_colliders = true
debug.show_fps = true
debug.show_ai_state = true

-- 시스템 상태 출력
sound:printStatus()
save_sys:printStatus()
input:getDebugInfo()
```

---

## 📚 참고 자료

### 공식 문서
- **Love2D**: https://love2d.org/wiki/
- **Lua 5.1**: https://www.lua.org/manual/5.1/

### 라이브러리
- **Windfield** (물리): https://github.com/a327ex/windfield
- **STI** (타일맵): https://github.com/karai17/Simple-Tiled-Implementation
- **anim8** (애니메이션): https://github.com/kikito/anim8
- **HUMP** (카메라): https://github.com/vrld/hump

### 외부 도구
- **Tiled** (맵 에디터): https://www.mapeditor.org/
- **Aseprite** (스프라이트): https://www.aseprite.org/
- **Audacity** (사운드): https://www.audacityteam.org/

### 커뮤니티
- **Love2D Forums**: https://love2d.org/forums/
- **Discord**: Love2D 공식 디스코드
- **Reddit**: r/love2d
