# 개발 가이드

이 가이드는 프로젝트의 개발 워크플로우와 모범 사례를 다룹니다.

---

## 🏗️ 아키텍처 원칙

### 1. 엔진/게임 분리
**목표:** 엔진은 재사용 가능하고, 게임은 콘텐츠입니다.

**규칙:**
- ✅ 엔진 파일은 게임 파일을 임포트하면 안 됩니다
- ✅ 게임 파일은 엔진 파일을 임포트할 수 있습니다
- ✅ 엔진은 범용적이고 설정 가능해야 합니다
- ✅ 게임은 데이터 기반이어야 합니다

**예시:**
```lua
-- ❌ 나쁨: 엔진이 게임 콘텐츠에 의존
-- engine/sound.lua
local game_sounds = require "game.data.sounds"  -- NO!

-- ✅ 좋음: 게임이 엔진에 데이터를 전달
-- game/scenes/menu.lua
local sound = require "engine.sound"
local sounds_config = require "game.data.sounds"
sound:init(sounds_config)  -- 엔진에 설정 전달
```

### 2. 모듈식 아키텍처
**목표:** 각 파일은 단일 책임을 가집니다.

**파일을 분할해야 하는 경우:**
- 파일이 500줄을 초과하는 경우
- 파일이 관련 없는 여러 책임을 가지는 경우
- 파일 탐색이 어려운 경우

**모듈식 씬 패턴:**
```
game/scenes/yourscene/
├── init.lua          - 조정자 (enter, exit, update, draw)
├── input.lua         - 입력 처리만
├── render.lua        - 그리기 로직만
└── logic.lua         - 비즈니스 로직만
```

### 3. 데이터 주도 설계
**목표:** game/ 폴더의 코드를 최소화하고 데이터를 최대화합니다.

**코드보다 데이터를 선호:**
```lua
-- ❌ 나쁨: 씬에 하드코딩
function menu:enter()
    self.options = {"New Game", "Load", "Quit"}
    self.title = "My Game"
end

-- ✅ 좋음: 데이터 주도
-- game/data/menu_config.lua
return {
    title = "My Game",
    options = {"New Game", "Load", "Quit"}
}

-- game/scenes/menu.lua
local menu_config = require "game.data.menu_config"
function menu:enter()
    self.options = menu_config.options
    self.title = menu_config.title
end
```

---

## 🛠️ 개발 워크플로우

### 새로운 엔진 시스템 추가하기

1. **시스템 파일 생성:**
   ```lua
   -- engine/yoursystem.lua
   local yoursystem = {}

   function yoursystem:init(config)
       -- 설정으로 초기화
   end

   function yoursystem:update(dt)
       -- 업데이트 로직
   end

   return yoursystem
   ```

2. **엔진 유틸리티에 추가:**
   - 범용적으로 유지 (게임 특정 코드 없음)
   - 게임 레이어로부터 설정 받기
   - 기존 시스템 패턴 따르기

3. **ENGINE_GUIDE.md에 문서화**

### 새로운 게임 씬 추가하기

1. **씬 구조 생성:**
   ```bash
   mkdir -p game/scenes/yourscene
   touch game/scenes/yourscene/init.lua
   touch game/scenes/yourscene/input.lua
   touch game/scenes/yourscene/render.lua
   ```

2. **씬 라이프사이클 구현:**
   ```lua
   -- game/scenes/yourscene/init.lua
   local yourscene = {}

   function yourscene:enter(previous, ...) end
   function yourscene:exit() end
   function yourscene:update(dt) end
   function yourscene:draw() end
   function yourscene:keypressed(key) end

   return yourscene
   ```

3. **씬 컨트롤에 연결:**
   ```lua
   local scene_control = require "engine.scene_control"
   local yourscene = require "game.scenes.yourscene"
   scene_control.switch(yourscene)
   ```

### 새로운 엔티티 타입 추가하기

1. **엔티티 정의 생성:**
   ```lua
   -- game/entities/enemy/types/yourenemy.lua
   return {
       name = "Your Enemy",
       max_health = 100,
       damage = 20,
       speed = 150,
       sprite_path = "assets/images/enemies/yourenemy.png",
       -- ... 더 많은 속성
   }
   ```

2. **에셋에 스프라이트 추가:**
   ```
   assets/images/enemies/yourenemy.png
   ```

3. **Tiled 맵에 배치:**
   - Enemies 레이어에 오브젝트 생성
   - 속성 설정: `type = "yourenemy"`

### 사운드 이펙트 추가하기

1. **오디오 파일 추가:**
   ```
   assets/sound/category/soundname.wav
   ```

2. **사운드 설정에 등록:**
   ```lua
   -- game/data/sounds.lua
   sfx = {
       category = {
           soundname = {
               path = "assets/sound/category/soundname.wav",
               volume = 0.8,
               pitch_variation = "normal"
           }
       }
   }
   ```

3. **게임에서 재생:**
   ```lua
   local sound = require "engine.sound"
   sound:playSFX("category", "soundname")
   ```

---

## 🎨 코드 스타일

### 네이밍 규칙
```lua
-- 모듈: 언더스코어를 사용한 소문자
local scene_control = require "engine.scene_control"

-- 클래스/객체: PascalCase (Lua에서는 드묾)
local Player = require "game.entities.player"

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
local game_data = require "game.data.something"

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

### 주석
```lua
-- 간단한 설명을 위한 한 줄 주석

--[[
다음을 위한 여러 줄 주석:
- 복잡한 로직 설명
- API 문서
- TODOs
]]

--- 문서 주석 (LDoc 스타일)
--- @param player table 플레이어 엔티티
--- @return boolean 성공 상태
function combat:attack(player)
end
```

---

## 🐛 디버깅

### 디버그 모드 (F1)
- F1 키로 토글 (통합 정보 창 + 히트박스)
- F2: 그리드 시각화 토글
- F3: 가상 마우스 토글
- FPS, 플레이어 상태, 화면 정보 표시
- 히트박스와 충돌 영역 시각화

### Print 디버깅

**조건부 디버그 Print (dprint):**
```lua
-- 디버그 메시지는 dprint() 사용 (F1 디버그 모드가 켜져있을 때만 출력)
dprint("Player HP:", player.health)
dprint("Enemy spawned at:", x, y)

-- 중요한 에러/경고는 print() 사용 (항상 출력)
print("ERROR: Failed to load map")
print("Warning: Missing texture")
```

**각각 언제 사용할까:**
- `dprint()`: 디버그 정보, 상태 변화, 상세 로깅
- `print()`: 에러, 경고, 중요한 메시지

**복잡한 테이블 포맷:**
```lua
local inspect = require "vendor.inspect"  -- (사용 가능한 경우)
dprint(inspect(player))
```

### 에러 처리
```lua
-- 위험한 작업에 pcall 사용
local success, result = pcall(function()
    return require "game.optional.module"
end)

if not success then
    print("Warning: Optional module not found")
    result = nil
end
```

### 일반적인 문제들

**문제: 파일을 찾을 수 없음**
```
해결책: require 경로가 슬래시가 아닌 점을 사용하는지 확인
✅ require "game.scenes.menu"
❌ require "game/scenes/menu"
```

**문제: Nil 값 에러**
```
해결책: 사용하기 전에 모듈이 존재하는지 확인
local module = require "engine.something"
if not module then return end
module:doSomething()
```

**문제: 물리가 이상하게 동작함**
```
해결책: 맵 속성의 game_mode 확인
Topdown: 중력 없음
Platformer: 중력 활성화
```

---

## 🧪 테스팅

### 수동 테스트 체크리스트
- [ ] 게임이 오류 없이 시작됨
- [ ] 모든 씬 접근 가능 (menu, play, settings 등)
- [ ] 키보드 컨트롤 작동
- [ ] 게임패드 컨트롤 작동 (사용 가능한 경우)
- [ ] 터치 컨트롤 작동 (모바일/가상 게임패드)
- [ ] 사운드 정상 재생 (BGM, SFX)
- [ ] 저장/로드 작동
- [ ] 인벤토리 시스템 작동
- [ ] 전투 시스템 작동 (공격, 패리, 회피)
- [ ] 맵 전환 작동
- [ ] NPC와 대화 작동
- [ ] 게임 모드 작동 (topdown, platformer)

### 성능 테스트
```lua
-- 디버그 모드(F1)에서 FPS 확인
-- 메모리 사용량 모니터링
-- 필요시 LuaJIT 프로파일러 사용
```

---

## 📦 빌드 및 배포

### .love 파일 생성
```bash
# 불필요한 파일 제외
zip -9 -r game.love . -x "*.git*" "*.md" "docs/*" ".vscode/*"
```

### Windows
```bash
# LÖVE와 게임 연결
cat love.exe game.love > mygame.exe
```

### macOS
```bash
# love.app 내용 교체
cp -r game.love MyGame.app/Contents/Resources/
```

### Linux
```bash
# AppImage 또는 .love 파일 패키징
# 사용자가 실행: love game.love
```

### Mobile (Android)
```bash
# love-android-sdl2 사용
# .love를 APK로 패키징
```

---

## 🔄 버전 관리

### Git 워크플로우
```bash
# 불필요한 파일 무시
echo "config.ini" >> .gitignore
echo "*.log" >> .gitignore
echo ".DS_Store" >> .gitignore

# 구조 변경 커밋
git add engine/ game/
git commit -m "Refactor: Separate engine and game folders"

# 콘텐츠 변경 커밋
git add game/entities/enemy/types/newenemy.lua
git commit -m "Add new enemy: Dragon"
```

### 브랜치 전략
```
main          - 안정 릴리스
develop       - 개발 브랜치
feature/X     - 새로운 기능
bugfix/X      - 버그 수정
```

---

## 📝 문서화

### 문서 업데이트 유지
- 엔진 시스템 추가 시 **ENGINE_GUIDE.md** 업데이트
- 콘텐츠 워크플로우 추가 시 **GAME_GUIDE.md** 업데이트
- 재구성 시 **PROJECT_STRUCTURE.md** 업데이트

### 복잡한 코드에 주석 달기
```lua
-- WHAT이 아닌 WHY를 설명
-- ❌ 나쁨: "플레이어 속도를 200으로 설정"
player.speed = 200

-- ✅ 좋음: "반응형 컨트롤을 위해 플랫포머 모드에서 더 빠른 속도"
player.speed = (game_mode == "platformer") and 200 or 150
```

---

## 🚀 성능 팁

### 핫 패스에서 피해야 할 것
```lua
-- ❌ 나쁨: 매 프레임마다 테이블 생성
function update(dt)
    local pos = {x = player.x, y = player.y}  -- 가비지 생성
end

-- ✅ 좋음: 테이블 재사용
local temp_pos = {x = 0, y = 0}
function update(dt)
    temp_pos.x = player.x
    temp_pos.y = player.y
end
```

### 지연 로딩
```lua
-- 시작 시 모두 로드하지 않고 필요할 때 리소스 로드
-- 엔진이 이미 사운드에 대해 이렇게 처리함
```

### 프로파일링
```lua
-- 비용이 많이 드는 작업 측정
local start = love.timer.getTime()
expensiveOperation()
print("Took:", love.timer.getTime() - start)
```

---

## 🎯 다음 단계

1. `engine/`과 `game/`의 기존 코드 읽기
2. 간단한 것들 수정 시도 (적 스탯, 사운드)
3. 새로운 씬이나 엔티티 생성
4. 엔진 개선에 기여
5. 이 엔진으로 자신만의 게임 만들기!

---

**참고:**
- [ENGINE_GUIDE.md](ENGINE_GUIDE.md) - 엔진 API 레퍼런스
- [GAME_GUIDE.md](GAME_GUIDE.md) - 콘텐츠 생성
- [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) - 전체 구조
