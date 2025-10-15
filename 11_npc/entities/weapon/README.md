# Weapon 리팩토링

## 📂 파일 구조

```
entities/
  weapon/
    init.lua              -- Main weapon class (조율, 메인)
    combat.lua            -- Attack logic, hit detection
    render.lua            -- Drawing, effects, particles
    config/
      hand_anchors.lua    -- HAND_ANCHORS 데이터
      swing_configs.lua   -- SWING_CONFIGS 데이터
      handle_anchors.lua  -- WEAPON_HANDLE_ANCHORS 데이터
    types/
      sword.lua           -- 검 설정
```

## 🔑 모듈 역할

### **init.lua** - 메인 조율 모듈
- `weapon:new(weapon_type)`: 무기 생성
- `weapon:update(dt, owner_x, owner_y, ...)`: 업데이트 조율
- `weapon:getHandPosition(owner_x, owner_y, anim_name, frame_index)`: 손 위치 계산
- `weapon:emitSheathParticles()`: 칼집 파티클 방출
- 외부 인터페이스 제공 (combat/render 호출)

### **combat.lua** - 전투 로직
- `combat.startAttack(weapon)`: 공격 시작
- `combat.endAttack(weapon)`: 공격 종료
- `combat.canDealDamage(weapon)`: 데미지 가능 타이밍 체크
- `combat.getHitbox(weapon)`: 히트박스 반환
- `combat.checkHit(weapon, enemy)`: 적 충돌 체크
- `combat.getDamage(weapon)`: 데미지 반환
- `combat.getKnockback(weapon)`: 넉백 반환

### **render.lua** - 렌더링
- `render.draw(weapon, debug_mode, swing_configs)`: 무기 그리기
- `render.drawDebug(weapon, swing_configs)`: 디버그 시각화
- `render.drawSheathParticles(weapon)`: 칼집 파티클 그리기
- `render.createSheathParticleSystem()`: 파티클 시스템 생성

### **config/hand_anchors.lua** - 손 위치 데이터
- `HAND_ANCHORS`: 각 애니메이션 프레임별 손 위치 (200줄+)
- idle, walk, attack 각 방향별 앵커 포인트

### **config/swing_configs.lua** - 스윙 설정
- `SWING_CONFIGS`: 방향별 스윙 설정
- type (vertical/horizontal), start_angle, end_angle, flip_x

### **config/handle_anchors.lua** - 무기 손잡이 위치
- `WEAPON_HANDLE_ANCHORS`: 무기 스프라이트에서 손잡이 위치

### **types/sword.lua** - 검 설정
- `WEAPON_TYPES.sword`: 스프라이트, 스탯, 타이밍 설정

## ✅ 사용법

### 원본 weapon.lua 교체
```lua
-- 기존 (원본)
local weapon_class = require "entities.weapon"

-- 새로운 것 (리팩토링 후)
local weapon_class = require "entities.weapon.init"
```

### 새 무기 생성
```lua
-- 기존과 동일
local weapon = weapon_class:new("sword")
```

### 외부 인터페이스
원본과 완전히 동일:
- `weapon:update(dt, owner_x, owner_y, owner_angle, direction, anim_name, frame_index, hand_marking_mode)`
- `weapon:draw(debug_mode)`
- `weapon:drawSheathParticles()`
- `weapon:startAttack()`
- `weapon:canDealDamage()`
- `weapon:getHitbox()`
- `weapon:checkHit(enemy)`
- `weapon:getDamage()`
- `weapon:getKnockback()`
- `weapon:emitSheathParticles()`

## 🎯 장점

### 확장성
새로운 무기 추가가 쉬움:
```lua
-- entities/weapon/types/bow.lua
local bow = {}

bow.WEAPON_TYPES = {
    bow = {
        sprite_file = "assets/images/bow.png",
        damage = 15,
        range = 200,
        attack_duration = 0.5,
        -- 활 전용 속성
        arrow_speed = 500,
        charge_time = 1.0
    }
}

return bow
```

### 가독성
- 각 파일이 단일 책임 (SRP)
- 600줄 → 7개 파일로 분산
- 코드 vs 데이터 명확히 분리

### 재사용성
- `combat.lua` 로직을 다른 무기에도 재사용
- `render.lua`의 파티클 시스템 공유
- 설정 데이터만 변경하면 새 무기 추가

### 유지보수
- 손 위치 수정 → `config/hand_anchors.lua`만 수정
- 새 무기 타입 추가 → `types/` 폴더에 파일 추가
- 렌더링 개선 → `render.lua`만 수정

## 🔄 마이그레이션

1. **백업**
   ```bash
   cp entities/weapon.lua entities/weapon_backup.lua
   ```

2. **파일 배치**
   ```
   entities/
     weapon/
       init.lua
       combat.lua
       render.lua
       config/
         hand_anchors.lua
         swing_configs.lua
         handle_anchors.lua
       types/
         sword.lua
   ```

3. **require 경로 변경**
   ```lua
   -- player/combat.lua, player/init.lua 등에서
   local weapon_class = require "entities.weapon.init"
   ```

4. **테스트**
   - 무기 생성 확인
   - 공격 애니메이션 확인
   - 히트 감지 확인
   - 파티클 확인
   - hand marking 모드 확인

## 🚀 향후 확장

### 새 무기 타입 추가
```lua
-- entities/weapon/types/bow.lua
local bow = {}

bow.WEAPON_TYPES = {
    bow = {
        sprite_file = "assets/images/bow.png",
        -- 활 전용 hand_anchors 참조 가능
        custom_hand_anchors = "bow_hand_anchors",
        attack_duration = 0.8,
        damage = 15,
        range = 250,
        projectile = true  -- 투사체 무기
    }
}

return bow
```

### 새 공격 패턴 추가
```lua
-- combat.lua에 추가
function combat.startChargedAttack(weapon, charge_level)
    weapon.is_attacking = true
    weapon.attack_progress = 0
    weapon.charge_level = charge_level
    weapon.damage_multiplier = 1 + charge_level * 0.5
    -- ...
end
```

### 손 위치 추가/수정
```lua
-- config/hand_anchors.lua에 추가
HAND_ANCHORS.special_attack_right = {
    { x = 10, y = -5, angle = -math.pi / 3 },
    { x = 8, y = 0, angle = 0 },
    -- ...
}
```

## 📝 호환성

✅ 순환참조 없음
✅ 원본 외부 인터페이스 100% 호환
✅ player 모듈 수정 최소화
✅ 디버그 기능 모두 보존
✅ hand marking 모드 완전 호환

## 🐛 주의사항

- `require "entities.weapon"` → `require "entities.weapon.init"` 경로 변경 필수
- `player/combat.lua`의 require 경로 수정
- 원본 `weapon.lua` 파일은 삭제하거나 백업 폴더로 이동

## 💡 추가 정보

### 데이터 파일 수정 가이드

**hand_anchors.lua 수정:**
1. hand marking 모드 활성화 (H 키)
2. 각 프레임에서 P 키로 손 위치 마킹
3. 콘솔에 출력되는 좌표를 복사
4. `config/hand_anchors.lua`에 붙여넣기

**새 무기 스윙 패턴:**
1. `swing_configs.lua`에 새 방향 추가
2. start_angle, end_angle 설정
3. flip_x로 좌우 반전 제어

**무기 손잡이 위치:**
1. 무기 스프라이트 16x16 기준
2. 중심점 (8, 8)에서 상대 좌표
3. `handle_anchors.lua`에서 방향별 설정
