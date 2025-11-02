# Health Recovery System - 체력 회복 시스템 (수정됨)

게임에 포션과 힐링 포인트를 추가했습니다.

## 새로운 기능

### 1. 포션 아이템 (Potion Items)
- **작은 포션 (Small Potion)**: 30 HP 회복
- **큰 포션 (Large Potion)**: 60 HP 회복

### 2. 힐링 포인트 (Healing Point)
- 맵에 배치된 초록색 원형 구역
- 플레이어가 들어가면 자동으로 50 HP 회복
- 5초 쿨다운 후 재사용 가능
- 초록색 파티클 이펙트

## 조작 방법 (Controls)

### 인벤토리 (Inventory)
- **Q**: 선택된 아이템 사용
- **Tab**: 다음 아이템 선택
- **1-5**: 아이템 슬롯 직접 선택 (인벤토리만 변경)

### 기존 조작
- **스페이스**: 회피/구르기 (Dodge/Roll) ⭐ 정상 작동
- **마우스 왼쪽 클릭**: 공격
- **마우스 오른쪽 클릭**: 패리
- **ESC**: 일시정지

## 수정 사항 (v1.1)
- ✅ 스페이스 키 dodge 기능 복구
- ✅ 1-5번 키로 인벤토리 슬롯 선택 시 dodge가 실행되던 버그 수정
- ✅ 코드 정리

## 구조 (Structure)

### 새로 추가된 파일들:
```
entities/
  item/
    init.lua              # Base item class
    types/
      small_potion.lua    # Small potion configuration
      large_potion.lua    # Large potion configuration
  healing_point/
    init.lua              # Healing point entity

systems/
  inventory.lua           # Inventory management system

systems/hud.lua           # Updated with inventory display
scenes/play.lua           # Updated with item and healing systems
```

## 주요 기능

### 인벤토리 시스템 (Inventory System)
- 최대 10개 슬롯
- 아이템 스택 가능 (포션별 최대 수량 제한)
- 선택된 아이템 하이라이트 표시
- 자동 저장/로드

### 힐링 포인트 (Healing Points)
- entities에서 관리되는 독립 객체
- 충돌 감지를 통한 자동 회복
- 비주얼 피드백 (파티클, 펄스 애니메이션)
- 쿨다운 시스템

## 테스트용 초기 아이템 (Starting Items for Testing)
게임 시작 시 자동으로 지급:
- 작은 포션 x3
- 큰 포션 x1

테스트용 힐링 포인트 위치:
- (300, 300)
- (600, 400)

## 저장/로드 (Save/Load)
인벤토리 데이터가 자동으로 저장됩니다:
- 아이템 종류와 수량
- 선택된 슬롯 정보

## 확장 가능성 (Extensibility)

### 새 아이템 타입 추가:
1. `entities/item/types/` 에 새 파일 생성
2. 아래 구조로 설정:
```lua
local new_item = {
    name = "Item Name",
    description = "Item Description",
    max_stack = 99,
}

function new_item.use(player)
    -- Use logic here
    return true -- success
end

function new_item.canUse(player)
    -- Check if item can be used
    return true
end

return new_item
```

### 힐링 포인트 추가:
`scenes/play.lua`의 `enter` 함수에서:
```lua
table.insert(self.healing_points, healing_point_class:new(x, y, heal_amount, radius))
```

## 향후 개선사항 (Future Improvements)
- 포션 아이템 스프라이트 이미지
- 사운드 이펙트
- 다양한 아이템 타입 (마나 포션, 버프 등)
- 맵 에디터를 통한 힐링 포인트 배치
- 아이템 드롭 시스템
- 상점 시스템
