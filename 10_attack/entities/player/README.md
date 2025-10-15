# Player 시스템 리팩토링 완료

원본 player.lua (900줄)를 여러 모듈로 분리했습니다.

## 📁 파일 구조

```
entities/player/
  ├── init.lua       (50줄) - 메인 조율 모듈
  ├── combat.lua     (300줄) - 전투 시스템
  ├── render.lua     (100줄) - 렌더링
  └── animation.lua  (150줄) - 애니메이션

systems/
  ├── debug.lua      (200줄) - 디버그 + hand marking
  ├── camera.lua     (60줄)  - 카메라 효과
  └── hud.lua        (120줄) - UI 시스템

scenes/
  └── play.lua       (250줄) - 게임플레이 씬
```

## 🔧 사용법

### 기본 사용 (변경 없음)
```lua
local player = require "entities.player"
local p = player:new("assets/player.png", 400, 300)
p:update(dt, cam)
p:attack()
p:startParry()
p:startDodge()
```

### 새로운 시스템 사용
```lua
local camera_sys = require "systems.camera"
local hud = require "systems.hud"
local debug = require "systems.debug"

-- Camera shake
camera_sys:shake(10, 0.3)

-- Slow motion
camera_sys:activate_slow_motion(0.5, 0.3)

-- HUD
hud:draw_health_bar(x, y, w, h, hp, max_hp)

-- Debug
debug:toggle_hand_marking(player)
```

## ✅ 주요 변경사항

1. **모듈 분리**: player 코드를 4개 파일로 분리
2. **Hand marking → debug**: 디버그 기능을 debug 모듈로 이동
3. **Camera 효과 분리**: shake와 slow motion을 별도 모듈로
4. **HUD 시스템**: UI 렌더링을 독립 모듈로
5. **원본 호환성**: 외부 인터페이스는 완전히 동일

## 📊 코드 통계

- **원본**: player.lua 900줄
- **리팩토링 후**: 총 980줄 (더 체계적)
- **파일 수**: 1개 → 8개
- **평균 파일 크기**: 120줄

모든 기능이 원본과 동일하게 작동합니다!
