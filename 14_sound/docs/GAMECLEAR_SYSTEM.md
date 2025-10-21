# Game Clear 시스템

## 📝 개요

게임 클리어 기능을 추가했습니다. 특정 위치(gameclear 포탈)에 도달하면 승리 화면이 표시됩니다.

## 🎮 구현 내용

### 1. **gameover.lua 수정**
- `is_clear` 플래그 추가
- 승리/패배에 따라 다른 UI 표시

#### Clear 모드 (승리)
- 타이틀: "GAME CLEAR!" (골드색)
- 서브타이틀: "Victory!"
- 옵션: "Main Menu"만 표시
- 골드 플래시 이펙트

#### Game Over 모드 (패배)
- 타이틀: "GAME OVER" (빨간색)
- 서브타이틀: "You Have Fallen"
- 옵션: "Restart", "Main Menu"
- 빨간 플래시 이펙트

### 2. **world.lua 수정**
- `transition_type` 필드 추가
- `"portal"` - 일반 맵 전환
- `"gameclear"` - 게임 클리어
- 디버그 모드에서 golclear 포탈은 골드색으로 표시

### 3. **play.lua 수정**
- gameclear transition 감지
- 감지 시 `gameover` 씬을 clear 모드로 호출
- 일반 portal과 gameclear 분기 처리

## 🗺️ Tiled 맵 설정 방법

### 1. Tiled에서 Portals 레이어에 객체 추가
```
Object 속성:
- type: "gameclear" (문자열)
- (target_map, spawn_x, spawn_y는 불필요)
```

### 2. 예시 (area2.lua에 추가)
```lua
-- Portals 레이어에
{
    name = "game_clear_portal",
    type = "rectangle",
    x = 800,
    y = 200,
    width = 100,
    height = 100,
    properties = {
        type = "gameclear"
    }
}
```

## 📦 파일 구조

```
scenes/
  ├── gameover.lua    (수정) - clear/gameover 분기
  └── play.lua        (수정) - gameclear 감지

systems/
  └── world.lua       (수정) - gameclear 포탈 지원
```

## 🚀 적용 방법

```bash
cp outputs/gameover.lua scenes/
cp outputs/world.lua systems/
cp outputs/play.lua scenes/
```

## 🎯 테스트 방법

1. **디버그 모드 활성화** (F3)
2. **gameclear 포탈 확인** (골드색 사각형)
3. **포탈에 진입**
4. **"GAME CLEAR!" 화면 확인**
5. **"Main Menu" 옵션만 표시 확인**

## 📊 코드 흐름

```
[플레이어 이동]
    ↓
[world:checkTransition()]
    ↓
[transition.transition_type == "gameclear"?]
    ↓ Yes
[scene_control.switch(gameover, true)]
    ↓
[gameover:enter(previous, is_clear=true)]
    ↓
["GAME CLEAR!" UI 표시]
```

## 🔧 커스터마이징

### 클리어 조건 변경
```lua
-- play.lua에서
if transition.transition_type == "gameclear" then
    -- 추가 조건 체크 가능
    if self.player.score >= 1000 then
        scene_control.switch(gameover, true)
    end
end
```

### UI 커스터마이징
```lua
-- gameover.lua에서
if self.is_clear then
    self.titleFont = love.graphics.newFont(64) -- 더 큰 폰트
    self.flash_color = { 1, 0.5, 0 }           -- 다른 색상
end
```

## ✅ 체크리스트

- [x] gameover.lua - clear 모드 추가
- [x] world.lua - gameclear 포탈 타입 지원
- [x] play.lua - gameclear transition 감지
- [x] 디버그 시각화 (골드색 표시)
- [ ] area2.lua 맵에 gameclear 포탈 추가 (Tiled에서 수동 작업)

## 💡 추가 기능 제안

### 1. 스코어/통계 표시
```lua
-- gameover.lua에 추가
if self.is_clear then
    love.graphics.print("Enemies Defeated: " .. stats.kills, ...)
    love.graphics.print("Time: " .. stats.time, ...)
end
```

### 2. 크레딧 화면
```lua
-- gameclear.lua (별도 파일)
function gameclear:enter(previous)
    self.credits = {
        "Game by: Your Name",
        "Music by: ...",
        -- ...
    }
end
```

### 3. 엔딩 애니메이션
```lua
-- gameover.lua에서
if self.is_clear then
    self.ending_timer = 3.0 -- 3초 후 크레딧
    -- 애니메이션 로직...
end
```

## 🐛 주의사항

1. **Tiled 맵 편집 필수**: area2.lua에 직접 gameclear 포탈을 추가해야 합니다
2. **타입 이름 정확히**: `"gameclear"` (소문자, 공백 없음)
3. **transition_type 확인**: world.lua가 제대로 로드하는지 확인

## 📖 관련 문서

- `scenes/gameover.lua` - 승리/패배 화면
- `systems/world.lua` - 포탈 시스템
- `scenes/play.lua` - 게임플레이 로직
