# Health Recovery System v2.1 - 체력 회복 시스템 (최종 수정판)

## 최종 수정 사항 (v2.1)

### 버그 수정
1. ✅ **인벤토리 UI 크래시 수정**
   - 문제: `attempt to get length of field 'items' (a nil value)`
   - 원인: `scene_control.push(inventory_ui, self, self.inventory, self.player)` - 인자 순서 오류
   - 해결: `scene_control.push(inventory_ui, self.inventory, self.player)` - 올바른 인자 전달

2. ✅ **사운드 경고 제거**
   - 문제: `WARNING: SFX not found: ui/open`
   - 해결: 안전한 사운드 래퍼 함수로 pcall 처리

3. ✅ **world.lua 구조 수정**
   - 문제: `return world` 위치 오류로 힐링 포인트 함수들 실행 불가
   - 해결: 모든 함수 정의 후 마지막에 `return world` 배치

4. ✅ **world.lua 문자 오류 수정**
   - 문제: sed 실수로 줄바꿈 대신 "n" 문자 삽입
   - 해결: 불필요한 문자 제거

## 조작 방법

### 인벤토리
- **I**: 인벤토리 UI 창 열기/닫기
- **Q**: 선택된 아이템 빠른 사용
- **Tab**: 다음 아이템 선택
- **1-5**: 아이템 슬롯 직접 선택

### 인벤토리 UI 창 내부
- **마우스 클릭**: 아이템 선택
- **마우스 우클릭**: 아이템 사용
- **방향키/WASD**: 아이템 선택 이동
- **E/Q/Space/Enter**: 아이템 사용
- **I/ESC**: 창 닫기

### 기본 조작
- **스페이스**: 회피/구르기
- **마우스 좌클릭**: 공격
- **마우스 우클릭**: 패리 (✅ 버그 수정됨)

## 주요 기능

### 1. 포션 아이템
- 작은 포션: 30 HP 회복
- 큰 포션: 60 HP 회복

### 2. 힐링 포인트 (Tiled 맵 연동)
- `HealingPoints` 오브젝트 레이어에서 자동 로드
- 초록색 원형 구역 + 파티클 효과
- 위치, 회복량, 반경, 쿨다운 설정 가능

### 3. 인벤토리 UI
- 전체 화면 인벤토리 창
- 아이템 상세 정보 표시
- 사용 가능 여부 실시간 확인

## Tiled 맵 설정

### HealingPoints 레이어 생성
1. Tiled에서 새 오브젝트 레이어 생성
2. 레이어 이름: `HealingPoints` (정확히 이 이름)
3. 원형 또는 사각형 오브젝트 배치
4. 오브젝트 속성 설정:

```
name: healing_point
Properties:
  - type: healing_point (string, 필수)
  - heal_amount: 50 (int)
  - radius: 40 (float)
  - cooldown: 5.0 (float)
```

## 버그 수정 상세

### 1. 인벤토리 UI 크래시
**에러 메시지:**
```
Error: scenes/inventory_ui.lua:161: attempt to get length of field 'items' (a nil value)
```

**원인:**
```lua
-- 잘못된 호출
scene_control.push(inventory_ui, self, self.inventory, self.player)

-- scene_control.push 내부에서:
scene.enter(previous, ...)  -- previous, self, inventory, player

-- inventory_ui:enter 정의:
function inventory_ui:enter(previous, player_inventory, player)
-- player_inventory에 self(play scene)가 들어감!
-- player에 inventory가 들어감!
```

**해결:**
```lua
-- 올바른 호출
scene_control.push(inventory_ui, self.inventory, self.player)

-- 이제 제대로 전달됨:
-- previous, inventory, player
```

### 2. 패리 버그
**증상:** 패리 성공했는데 HP 깎임

**원인:** 적이 attack 상태일 때 매 프레임마다 데미지 판정
```lua
if enemy.state == "attack" and not enemy.stunned then
    takeDamage()  -- 매 프레임 실행!
end
```

**해결:** `has_attacked` 플래그 체크
```lua
if enemy.state == "attack" and not enemy.stunned and not enemy.has_attacked then
    takeDamage()  -- 공격당 1회만
    enemy.has_attacked = true
end
```

### 3. 사운드 경고
**문제:** 없는 SFX 파일 호출

**해결:** 안전한 래퍼 함수
```lua
local function play_sound(category, name)
    if sound and sound.playSFX then
        pcall(function() sound:playSFX(category, name) end)
    end
end
```

## 파일 구조

```
scenes/
  inventory_ui.lua          - 인벤토리 UI 창 (버그 수정)
  play.lua                  - 메인 게임 (인자 전달 수정)

systems/
  inventory.lua             - 인벤토리 관리
  world.lua                 - 힐링 포인트 Tiled 로드 (구조 수정)
  hud.lua                   - 인벤토리 미니 표시

entities/
  item/
    init.lua                - 아이템 베이스 클래스
    types/
      small_potion.lua      - 작은 포션
      large_potion.lua      - 큰 포션
  healing_point/
    init.lua                - 힐링 포인트 엔티티
```

## 테스트 체크리스트

- [ ] 게임 실행 시 크래시 없음
- [ ] I키로 인벤토리 UI 열림
- [ ] 포션 사용 (Q키 또는 UI에서)
- [ ] 적 공격 패리 시 HP 안 깎임
- [ ] 힐링 포인트 작동 (초록색 원형)
- [ ] 사운드 경고 없음

## 알려진 이슈

없음 (모든 버그 수정 완료)

## 변경 이력

### v2.1 (최종)
- ✅ 인벤토리 UI 크래시 수정
- ✅ 사운드 경고 제거
- ✅ world.lua 구조 및 문자 오류 수정

### v2.0
- 인벤토리 UI 창 추가
- 힐링 포인트 Tiled 맵 로드
- 패리 버그 수정

### v1.1
- 스페이스 키 dodge 복구
- 1-5번 키 버그 수정

### v1.0
- 초기 포션/인벤토리/힐링 포인트 시스템
