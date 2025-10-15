# Effects 시스템

## 📂 파일 위치
```
systems/
  effects.lua          -- 중앙 이펙트 매니저
```

## 🎨 포함된 이펙트

### 1. **Blood** 🩸
- 빨간색 피 파티클
- 사방으로 튀는 효과
- 용도: 플레이어/적 피격

### 2. **Spark** ⚡
- 노란색/흰색 불꽃
- 좁은 원뿔 형태
- 용도: 패링, 무기 막기

### 3. **Dust** 💨
- 회색/갈색 먼지
- 위로 퍼지는 효과
- 용도: 땅 타격, 충격

### 4. **Slash** ✨
- 청록색 검기 잔상
- 좁은 퍼짐
- 용도: 무기 궤적

## ✅ 초기화

effects는 자동으로 초기화됩니다:
```lua
local effects = require "systems.effects"
-- 바로 사용 가능!
```

## 🎯 기본 사용법

### 간단한 이펙트 생성
```lua
local effects = require "systems.effects"

-- 위치에 이펙트 생성
effects:spawn("blood", x, y)

-- 방향 지정
effects:spawn("spark", x, y, angle)

-- 파티클 개수 지정
effects:spawn("dust", x, y, nil, 30)
```

### 방향성 이펙트
```lua
-- 방향 벡터로 생성
local dir_x = enemy_x - player_x
local dir_y = enemy_y - player_y
effects:spawnDirectional("blood", x, y, dir_x, dir_y, 25)
```

### 프리셋 조합
```lua
-- 적/플레이어 피격
effects:spawnHitEffect(x, y, "enemy", weapon_angle)

-- 패링 성공
effects:spawnParryEffect(x, y, angle, is_perfect)

-- 무기 궤적
effects:spawnWeaponTrail(x, y, weapon_angle)
```

## 📋 실제 적용 예시

### 1. world.lua - 무기 히트
```lua
-- systems/world.lua
local effects = require "systems.effects"

function world:applyWeaponHit(hit_result)
    local enemy = hit_result.enemy
    local damage = hit_result.damage
    
    -- 데미지 적용
    enemy:takeDamage(damage)
    
    -- 피격 이펙트 생성
    local hit_x = enemy.x + enemy.collider_offset_x
    local hit_y = enemy.y + enemy.collider_offset_y
    
    -- 무기 방향으로 피 튀김
    effects:spawnHitEffect(hit_x, hit_y, "enemy", self.player.weapon.angle)
end

function world:update(dt)
    -- 이펙트 업데이트
    effects:update(dt)
    
    -- ... 기존 코드
end
```

### 2. player/combat.lua - 플레이어 피격
```lua
-- entities/player/combat.lua
local effects = require "systems.effects"

function combat.takeDamage(player, damage, shake_callback)
    local parried, is_perfect = combat.checkParry(player, damage)
    if parried then
        -- 패링 성공 이펙트
        effects:spawnParryEffect(player.x, player.y, player.facing_angle, is_perfect)
        
        if shake_callback then
            shake_callback(4, 0.1)
        end
        return false, true, is_perfect
    end

    -- 회피 체크
    if player.dodge_invincible_timer > 0 then
        print("Dodged attack!")
        return false, false, false
    end

    if player.invincible_timer > 0 then
        return false, false, false
    end

    -- 데미지 적용
    player.health = math.max(0, player.health - damage)
    
    -- 피격 이펙트
    effects:spawnHitEffect(player.x, player.y, "player", nil)
    
    player.hit_flash_timer = 0.2
    player.invincible_timer = player.invincible_duration

    if shake_callback then
        shake_callback(12, 0.3)
    end

    if player.health <= 0 then
        print("Player died!")
    end

    return true, false, false
end
```

### 3. weapon/combat.lua - 공격 궤적
```lua
-- entities/weapon/combat.lua
local effects = require "systems.effects"

function combat.startAttack(weapon)
    if weapon.is_attacking then
        return false
    end

    weapon.is_attacking = true
    weapon.attack_progress = 0
    weapon.has_hit = false
    weapon.hit_enemies = {}

    -- 검기 이펙트
    local dir_x = math.cos(weapon.angle)
    local dir_y = math.sin(weapon.angle)
    local trail_x = weapon.owner_x + dir_x * 40
    local trail_y = weapon.owner_y + dir_y * 40
    effects:spawnWeaponTrail(trail_x, trail_y, weapon.angle)

    -- Create slash animation
    local anim8 = require "vendor.anim8"
    weapon.slash_active = true
    weapon.slash_anim = anim8.newAnimation(
        weapon.slash_grid('1-2', 1),
        0.06,
        function() weapon.slash_active = false end
    )

    -- ... 기존 코드
    
    return true
end
```

### 4. scenes/play.lua - 렌더링
```lua
-- scenes/play.lua
local effects = require "systems.effects"

function play:update(dt)
    -- ... 기존 코드
    
    -- 이펙트 업데이트
    effects:update(dt)
end

function play:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.clear(0, 0, 0, 1)

    self.cam:attach()

    self.world:drawLayer("Ground")
    self.world:drawEnemies()
    self.player:drawAll()

    if debug.debug_mode then
        self.player:drawDebug()
    end

    self.world:drawLayer("Trees")
    
    -- 이펙트 그리기 (적과 나무 사이)
    effects:draw()

    if debug.debug_mode then
        self.world:drawDebug()
    end

    self.cam:detach()

    -- HUD
    -- ...
end
```

## 🔧 API 레퍼런스

### effects:spawn(effect_type, x, y, [angle], [particle_count])
기본 이펙트 생성
- `effect_type`: "blood", "spark", "dust", "slash"
- `x, y`: 생성 위치
- `angle` (optional): 방향 (라디안)
- `particle_count` (optional): 파티클 개수 (기본 20)

### effects:spawnDirectional(effect_type, x, y, direction_x, direction_y, [particle_count])
방향 벡터로 이펙트 생성
- `direction_x, direction_y`: 방향 벡터 (정규화 불필요)

### effects:spawnHitEffect(x, y, target_type, angle)
피격 프리셋
- `target_type`: "enemy", "player", "wall"
- 자동으로 적절한 이펙트 조합

### effects:spawnParryEffect(x, y, angle, is_perfect)
패링 프리셋
- `is_perfect`: true면 더 많은 파티클

### effects:spawnWeaponTrail(x, y, angle)
무기 궤적 프리셋

### effects:update(dt)
모든 이펙트 업데이트 (매 프레임 호출)

### effects:draw()
모든 이펙트 그리기

### effects:clear()
모든 활성 이펙트 제거

### effects:getCount()
현재 활성 이펙트 개수 반환 (디버그용)

## 🎨 커스터마이징

### 새 이펙트 타입 추가
```lua
-- systems/effects.lua에 추가

function effects:createFireSystem()
    local particle_img = createParticleImage(10)
    local ps = love.graphics.newParticleSystem(particle_img, 60)
    
    ps:setParticleLifetime(0.5, 1.0)
    ps:setEmissionRate(0)
    ps:setSizes(2, 3, 2, 1, 0)
    
    -- Orange/red fire
    ps:setColors(
        1, 0.9, 0.3, 1,      -- Yellow
        1, 0.5, 0.1, 0.9,    -- Orange
        0.8, 0.2, 0.0, 0.6,  -- Red
        0.5, 0.1, 0.0, 0.3,
        0.2, 0.0, 0.0, 0
    )
    
    ps:setLinearDamping(0.5, 1.5)
    ps:setSpeed(20, 60)
    ps:setSpread(math.pi / 6)
    
    return ps
end

-- init 함수에 추가
function effects:init()
    self.particle_systems = {
        blood = self:createBloodSystem(),
        spark = self:createSparkSystem(),
        dust = self:createDustSystem(),
        slash = self:createSlashSystem(),
        fire = self:createFireSystem()  -- 추가
    }
end
```

### 색상 변경
각 `create___System()` 함수에서 `ps:setColors()` 수정

### 속도/수명 조정
- `ps:setParticleLifetime()`: 파티클 수명
- `ps:setSpeed()`: 초기 속도
- `ps:setLinearDamping()`: 감속
- `ps:setSpread()`: 퍼짐 각도

## 💡 팁

### 성능 최적화
- 이펙트는 자동으로 정리됨 (수명 2초 또는 파티클 0개)
- 한 화면에 너무 많은 이펙트는 피하기
- `effects:getCount()`로 모니터링

### 레이어링
```lua
-- 배경 이펙트 (땅 위)
effects:draw()

-- 전경 이펙트 (나무 위)
-- 별도 이펤트 시스템 사용하거나 Z-order 구현
```

### 디버깅
```lua
if debug.debug_mode then
    love.graphics.print("Active effects: " .. effects:getCount(), 10, 100)
end
```

## 🎯 적용 체크리스트

- [ ] `systems/effects.lua` 파일 추가
- [ ] `world.lua`에서 effects:update(dt) 호출
- [ ] `play.lua`에서 effects:draw() 호출
- [ ] `world:applyWeaponHit()`에서 피격 이펙트
- [ ] `player:takeDamage()`에서 피격/패링 이펙트
- [ ] (선택) `weapon:startAttack()`에서 궤적 이펙트

## 🚀 향후 확장

- 다양한 속성 이펙트 (불, 얼음, 번개)
- 폭발 이펙트
- 치유 이펙트
- 레벨업 이펙트
- 버프/디버프 이펙트
- 텍스트 데미지 숫자

## ⚠️ 주의사항

- effects:update(dt)와 effects:draw()를 **반드시** 호출해야 작동
- 카메라 좌표계 안에서 draw() 호출 (cam:attach() 후)
- 파티클은 자동으로 사라지므로 수동 정리 불필요
