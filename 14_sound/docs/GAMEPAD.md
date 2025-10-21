# 게임패드 지원 (DualSense Controller)

Love2D 게임에 DualSense 컨트롤러 지원이 완전히 통합되었습니다.

## 📋 목차
- [버튼 매핑](#버튼-매핑)
- [지원 기능](#지원-기능)
- [화면별 조작](#화면별-조작)
- [고급 설정](#고급-설정)
- [구현 세부사항](#구현-세부사항)

---

## 🎮 버튼 매핑

### DualSense 기본 조작

| 버튼 | 기능 | 비고 |
|------|------|------|
| **왼쪽 스틱** | 이동 (360도) | 아날로그 입력 |
| **오른쪽 스틱** | 조준 방향 | 무기 장착 시 |
| **Cross (✕)** | 공격 / 선택 | 메인 액션 |
| **Square (□)** | 패리 | 방어 액션 |
| **Circle (○)** | 회피 / 뒤로가기 | 닷지 롤 |
| **Triangle (△)** | 상호작용 | NPC 대화, 저장 |
| **L1** | 퀵세이브 슬롯 1 | 빠른 저장 |
| **R1** | 퀵세이브 슬롯 2 | 빠른 저장 |
| **Options** | 일시정지 | 게임 메뉴 |
| **D-Pad** | 메뉴 네비게이션 | UI 조작 |

---

## ✨ 지원 기능

### 1. 아날로그 입력
- **360도 자유 이동**: 왼쪽 스틱으로 모든 방향 이동
- **정밀 조준**: 오른쪽 스틱으로 공격 방향 제어
- **Deadzone 설정**: 스틱 드리프트 방지 (0.05 ~ 0.30)

### 2. 햅틱 피드백 (진동)
- **공격**: 약한 진동 (0.1초)
- **패리**: 중간 진동 (0.15초)
- **퍼펙트 패리**: 강한 진동 (0.3초)
- **피격**: 강한 비대칭 진동 (0.2초)
- **회피**: 짧은 진동 (0.08초)
- **무기 적중**: 중간 진동 (0.15초)

### 3. 방향 유지 시스템
- 우측 스틱을 놓아도 마지막 조준 방향 유지
- 무기를 집어넣으면 방향 리셋
- 무기를 꺼낼 때 현재 바라보는 방향으로 초기화

---

## 🎯 화면별 조작

### 메인 메뉴
```
D-Pad / 왼쪽 스틱  : 메뉴 선택
Cross (✕)          : 선택
Circle (○)         : 종료
```

### 게임플레이
```
왼쪽 스틱          : 이동 (360도)
오른쪽 스틱        : 조준 (무기 장착 시)
Cross (✕)          : 공격
Square (□)         : 패리
Circle (○)         : 회피/닷지 롤
Triangle (△)       : 상호작용 (NPC, 저장)
Options            : 일시정지
L1 / R1            : 퀵세이브 (슬롯 1/2)
```

### 일시정지 메뉴
```
D-Pad              : 메뉴 선택
Cross (✕)          : 선택
Options / Circle   : 재개
```

### 저장 슬롯 선택
```
D-Pad              : 슬롯 선택
Cross (✕)          : 저장
Circle (○)         : 취소
L1 / R1            : 퀵세이브 (슬롯 1/2)
```

### 로드 게임
```
D-Pad              : 슬롯 선택
Cross (✕)          : 로드
Circle (○)         : 뒤로가기
L1 / R1            : 슬롯 1/2 빠른 삭제
```

### 설정 메뉴
```
D-Pad              : 항목 선택
←/→                : 값 변경
Cross (✕)          : 선택/변경
Circle (○)         : 뒤로가기
```

### 게임오버
```
D-Pad              : 선택
Cross (✕)          : 선택
Circle (○)         : 메인 메뉴
```

---

## ⚙️ 고급 설정

Settings 메뉴에서 게임패드 관련 설정을 조정할 수 있습니다.

### Deadzone (데드존)
**범위**: 0.05 ~ 0.30 (기본: 0.15)

**역할**: 스틱의 무감지 영역

| 값 | 특징 | 권장 사용 |
|----|------|-----------|
| **0.05** | 매우 민감 | 새 컨트롤러 |
| **0.15** | 균형잡힌 | 일반적 (기본값) |
| **0.30** | 둔감 | 오래된 컨트롤러 (드리프트 방지) |

**언제 조정하나요?**
- 캐릭터가 저절로 움직임 → **Deadzone 올리기**
- 스틱 반응이 둔함 → **Deadzone 낮추기**

### Vibration (진동)
**ON/OFF**: 진동 기능 전체 활성화/비활성화

**권장**:
- 몰입감을 원하면 → **ON**
- 배터리 절약 → **OFF**

### Vibration Strength (진동 강도)
**범위**: 0% ~ 100% (기본: 100%)

**조정 기준**:
- 진동이 너무 강함 → **50% ~ 75%**
- 진동을 느끼고 싶음 → **100%**
- 약한 피드백만 원함 → **25%**

---

## 🔧 구현 세부사항

### 입력 시스템 아키텍처

```
systems/input.lua
  ↓
액션 매핑 테이블
  ↓
keyboard / mouse / gamepad
  ↓
통합 입력 처리
```

### 주요 모듈

#### `systems/input.lua`
- 통합 입력 관리 시스템
- 액션 매핑 테이블
- Deadzone 처리
- 햅틱 피드백 제어
- 버튼 프롬프트 생성

#### 액션 매핑 예시
```lua
actions = {
    attack = { 
        mouse = 1, 
        gamepad = "a" 
    },
    parry = { 
        mouse = 2, 
        gamepad = "x" 
    },
    dodge = { 
        keyboard = { "space" }, 
        gamepad = "b" 
    }
}
```

### 입력 확인 함수

```lua
-- 현재 눌려있는지 확인
input:isDown("attack")

-- 방금 눌렀는지 확인 (이벤트)
input:wasPressed("attack", "gamepad", button)

-- 이동 벡터 가져오기
local vx, vy = input:getMovement()

-- 조준 각도 가져오기
local angle = input:getAimDirection(player_x, player_y, cam)
```

### 진동 함수

```lua
-- 기본 진동
input:vibrate(duration, left_strength, right_strength)

-- 프리셋 진동
input:vibrateAttack()        -- 공격
input:vibrateParry()          -- 패리
input:vibratePerfectParry()   -- 퍼펙트 패리
input:vibrateHit()            -- 피격
input:vibrateDodge()          -- 회피
input:vibrateWeaponHit()      -- 무기 적중
```

### Deadzone 처리

```lua
function input:applyDeadzone(value)
    if math.abs(value) < self.settings.deadzone then
        return 0
    end
    
    -- Smooth transition
    local sign = value > 0 and 1 or -1
    local adjusted = (math.abs(value) - self.settings.deadzone) / 
                     (1 - self.settings.deadzone)
    return sign * adjusted
end
```

---

## 🎨 UI 통합

### 버튼 프롬프트

게임패드가 연결되면 UI에 자동으로 버튼 아이콘이 표시됩니다:

```lua
-- 버튼 프롬프트 가져오기
local prompt = input:getPrompt("attack")  -- "[✕]"
local prompt = input:getPrompt("pause")   -- "[Options]"

-- 힌트 텍스트에 자동 적용
if input:hasGamepad() then
    hint = input:getPrompt("attack") .. ": Attack"
else
    hint = "Left Click: Attack"
end
```

### DualSense 아이콘 매핑

| 버튼 | 표시 |
|------|------|
| a | [✕] |
| b | [○] |
| x | [□] |
| y | [△] |
| leftshoulder | [L1] |
| rightshoulder | [R1] |
| start | [Options] |
| back | [Share] |

---

## 🐛 문제 해결

### 컨트롤러가 인식되지 않음
1. LÖVE2D conf.lua 확인:
```lua
t.modules.joystick = true
```

2. 컨트롤러 연결 확인:
```lua
print(input.joystick_name)  -- "No Controller"면 미연결
```

### 스틱 드리프트 발생
- Settings → Deadzone 값을 **0.20 ~ 0.30**으로 올리기

### 진동이 작동하지 않음
1. Settings → Vibration이 **ON**인지 확인
2. Vibration Strength가 **0%**가 아닌지 확인
3. Steam 오버레이 진동 설정 확인

### 조준이 부자연스러움
- 우측 스틱 방향 유지 시스템이 작동 중
- 무기를 집어넣으면 리셋됨

---

## 📝 개발자 노트

### 설계 원칙

1. **통합 입력 시스템**
   - 키보드/마우스/게임패드를 하나의 액션 매핑으로 통합
   - 모든 화면에서 일관된 입력 처리

2. **상황별 힌트**
   - 게임패드 연결 시 자동으로 버튼 프롬프트 변경
   - 키보드/마우스와 게임패드 힌트를 모두 표시

3. **햅틱 피드백 설계**
   - 액션의 강도에 따라 차별화된 진동
   - 사용자가 설정으로 제어 가능

4. **방향 유지 시스템**
   - 조작감 향상을 위한 스마트 방향 기억
   - 마우스/게임패드 간 자연스러운 전환

### 테스트 체크리스트

- [ ] 모든 화면에서 게임패드 네비게이션 작동
- [ ] 360도 이동 및 조준 정상 작동
- [ ] 진동 피드백 작동
- [ ] Deadzone 설정 적용
- [ ] 버튼 프롬프트 정상 표시
- [ ] 컨트롤러 연결/해제 처리
- [ ] 키보드/마우스와 동시 사용 가능

---

## 📚 참고 자료

- [LÖVE2D Joystick Documentation](https://love2d.org/wiki/love.joystick)
- [Gamepad API](https://love2d.org/wiki/Joystick:isGamepadDown)
- [DualSense Features](https://www.playstation.com/en-us/accessories/dualsense-wireless-controller/)

---

## 🎉 완료된 기능

✅ 360도 아날로그 이동  
✅ 우측 스틱 조준  
✅ 모든 화면 게임패드 지원  
✅ 햅틱 피드백 (7가지 패턴)  
✅ Deadzone 설정  
✅ 진동 강도 조절  
✅ 버튼 프롬프트 자동 전환  
✅ 방향 유지 시스템  
✅ 퀵세이브/로드 (L1/R1)  
✅ 컨트롤러 핫플러그 지원  

**모든 기능이 DualSense 컨트롤러에 최적화되어 있습니다!** 🎮✨
