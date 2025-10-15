# Enemy 리팩토링

## 📂 파일 구조

```
entities/
  enemy/
    init.lua           -- Base enemy class (조율, 공통 로직)
    ai.lua             -- AI state machine
    render.lua         -- 렌더링 (색상 swap, 이펙트)
    types/
      slime.lua        -- 슬라임 타입 설정
```

## 🔑 모듈 역할

### **init.lua** - 메인 조율 모듈
- `enemy:new(x, y, enemy_type)`: 적 생성
- `enemy:update(dt, player_x, player_y)`: 타이머 업데이트 및 AI 호출
- `enemy:takeDamage(damage)`: 데미지 처리
- `enemy:stun(duration, is_perfect)`: 스턴 처리
- `enemy:getDistanceToPoint(x, y)`: 거리 계산
- `enemy:setPatrolPoints(points)`: 순찰 경로 설정
- `enemy:getColliderBounds()`: 충돌체 영역 반환

### **ai.lua** - AI 상태 머신
- `ai.update(enemy, dt, player_x, player_y)`: AI 업데이트 및 이동 계산
- `ai.updateIdle(enemy, dt, player_x, player_y)`: 대기 상태
- `ai.updatePatrol(enemy, dt, player_x, player_y)`: 순찰 상태
- `ai.updateChase(enemy, dt, player_x, player_y)`: 추격 상태
- `ai.updateAttack(enemy, dt, player_x, player_y)`: 공격 상태
- `ai.updateHit(enemy, dt)`: 피격 상태
- `ai.setState(enemy, new_state)`: 상태 전환

### **render.lua** - 렌더링
- `render.draw(enemy)`: 적 그리기
- `render.initialize_shader()`: 색상 swap shader 초기화
- Shadow, 체력바, 스턴 별, 피격 이펙트 처리
- 디버그 시각화 (탐지/공격 범위, 충돌체, AI 상태)

### **types/slime.lua** - 슬라임 설정
- `slime.ENEMY_TYPES`: 4종 슬라임 설정 (red, green, blue, purple)
- 스탯, 스프라이트, 충돌체, 색상 swap 설정

## ✅ 사용법

### 원본 enemy.lua 교체
```lua
-- 기존 (원본)
local enemy = require "entities.enemy"

-- 새로운 것 (리팩토링 후)
local enemy = require "entities.enemy.init"
```

### 새 적 생성
```lua
-- 기존과 동일
local slime = enemy:new(100, 200, "green_slime")
```

### 외부 인터페이스
원본과 완전히 동일:
- `enemy:update(dt, player_x, player_y)`
- `enemy:draw()`
- `enemy:takeDamage(damage)`
- `enemy:stun(duration, is_perfect)`
- `enemy:setPatrolPoints(points)`
- `enemy:getColliderBounds()`
- `enemy:getDistanceToPoint(x, y)`

## 🎯 장점

### 확장성
새로운 적 추가가 쉬움:
```lua
-- entities/enemy/types/humanoid.lua
local humanoid = {}

humanoid.ENEMY_TYPES = {
    knight = {
        sprite_sheet = "assets/images/knight.png",
        health = 200,
        weapon = "sword",
        -- ...
    }
}

return humanoid
```

### 가독성
- 각 파일이 단일 책임 (SRP)
- 600줄 → 4개 파일로 분산 (각 100-200줄)

### 재사용성
- `ai.lua`를 다른 적에게도 재사용 가능
- `render.lua`의 shader 시스템 공유

### 테스트
- 각 모듈을 독립적으로 테스트 가능
- AI 로직만 수정하려면 `ai.lua`만 수정

## 🔄 마이그레이션

1. **백업**
   ```bash
   cp entities/enemy.lua entities/enemy_backup.lua
   ```

2. **파일 배치**
   ```
   entities/
     enemy/
       init.lua
       ai.lua
       render.lua
       types/
         slime.lua
   ```

3. **require 경로 변경**
   ```lua
   -- world.lua, play.lua 등에서
   local enemy = require "entities.enemy.init"
   ```

4. **테스트**
   - 적 생성 확인
   - AI 동작 확인
   - 패링/스턴 확인
   - 색상 swap 확인

## 🚀 향후 확장

### 새 몬스터 타입 추가
```lua
-- entities/enemy/types/boss.lua
local boss = {}

boss.ENEMY_TYPES = {
    dragon_boss = {
        health = 5000,
        phases = {...},
        special_attacks = {...}
    }
}

return boss
```

### 새 AI 패턴 추가
```lua
-- ai.lua에 추가
function ai.updatePhase1(enemy, dt, player_x, player_y)
    -- 보스 페이즈 1 로직
end

function ai.updatePhase2(enemy, dt, player_x, player_y)
    -- 보스 페이즈 2 로직
end
```

## 📝 호환성

✅ 순환참조 없음
✅ 원본 외부 인터페이스 100% 호환
✅ world.lua, play.lua 수정 최소화
✅ 디버그 기능 모두 보존

## 🐛 주의사항

- `require "entities.enemy"` → `require "entities.enemy.init"` 경로 변경 필수
- `world.lua`의 `loadEnemies()` 함수 require 경로만 수정
- 원본 `enemy.lua` 파일은 삭제하거나 백업 폴더로 이동

## 🔧 버그 수정 (추가 파일)

### **systems/debug.lua** 수정
- `current_anim_name`이 nil일 때 발생하는 에러 수정
- `next_frame()`, `prev_frame()`, `mark_hand_position()`, `toggle_hand_marking()` 함수에 nil 체크 추가
- 디버그 모드에서 PgUp/PgDn 사용 시 안전하게 작동

### **entities/player/animation.lua** 수정  
- `current_anim_name`이 항상 설정되도록 보장
- 모든 분기에서 fallback 값 제공 (`"idle_" .. player.direction`)
- hand marking 모드에서도 안전하게 작동
