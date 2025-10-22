# Love2D 게임 사운드 시스템 완전 통합 가이드

## 📁 파일 구조

```
14_sound/
├── systems/
│   └── sound.lua                  ⭐ 새 파일 - 중앙 사운드 관리
├── entities/
│   ├── player/
│   │   ├── sound.lua              ⭐ 새 파일 - 플레이어 사운드
│   │   └── combat.lua             🔧 수정 - 사운드 통합
│   └── enemy/
│       ├── sound.lua              ⭐ 새 파일 - 적 사운드
│       ├── init.lua               🔧 수정 - 사운드 통합
│       └── ai.lua                 🔧 수정 - 사운드 통합
├── scenes/
│   ├── menu.lua                   🔧 수정 - 메뉴 사운드 추가
│   ├── pause.lua                  🔧 수정 - 일시정지 사운드 추가
│   ├── play.lua                   🔧 수정 - BGM 및 사운드 통합
│   └── settings.lua               🔧 수정 - 볼륨 제어 추가
└── assets/
    ├── bgm/
    │   ├── menu.ogg
    │   ├── level1.ogg
    │   ├── level2.ogg
    │   └── boss.ogg
    └── sound/
        ├── menu/
        │   ├── navigate.wav
        │   ├── select.wav
        │   ├── back.wav
        │   └── error.wav
        ├── ui/
        │   ├── save.wav
        │   ├── pause.wav
        │   └── unpause.wav
        ├── player/
        │   ├── footstep.wav
        │   ├── sword_swing.wav
        │   ├── sword_hit.wav
        │   ├── dodge.wav
        │   ├── hurt.wav
        │   ├── weapon_draw.wav
        │   └── weapon_sheath.wav
        ├── enemy/
        │   ├── slime_move.wav
        │   ├── slime_attack.wav
        │   ├── slime_hurt.wav
        │   ├── slime_death.wav
        │   ├── slime_stunned.wav
        │   └── detect.wav
        └── combat/
            ├── hit_flesh.wav
            ├── hit_metal.wav
            ├── parry.wav
            ├── parry_perfect.wav
            └── death.wav
```

## 🎵 주요 기능

### 1. 중앙 사운드 관리 시스템 (systems/sound.lua)
- ✅ BGM 자동 루핑 및 스트리밍
- ✅ SFX 정적 로딩
- ✅ 사운드 풀링 (자주 사용되는 사운드용)
- ✅ 독립적인 볼륨 제어 (마스터, BGM, SFX)
- ✅ 음소거 기능
- ✅ 페이드인/아웃

### 2. 플레이어 사운드 (entities/player/sound.lua)
- 🚶 발소리: 걷기 중 자동 재생 (타이밍 조절)
- ⚔️ 전투: 공격, 히트, 패링(일반/퍼펙트), 회피
- 💔 피격 사운드
- 🗡️ 무기: 장착/해제 사운드

### 3. 적 사운드 (entities/enemy/sound.lua)
- 👾 이동: 슬라임 타입별 이동 사운드
- 👊 전투: 공격, 피격, 죽음
- ⚡ 특수: 기절, 플레이어 감지

### 4. UI/메뉴 사운드
- 🎮 메뉴: 네비게이션, 선택, 뒤로가기, 에러
- 💾 UI: 저장, 일시정지/재개

## 📥 설치 방법

### 1단계: 사운드 시스템 파일 추가

```lua
-- 14_sound/systems/sound.lua 생성
-- (제공된 sound_system.lua 내용 복사)

-- 14_sound/entities/player/sound.lua 생성
-- (제공된 player_sound.lua 내용 복사)

-- 14_sound/entities/enemy/sound.lua 생성
-- (제공된 enemy_sound.lua 내용 복사)
```

### 2단계: 기존 파일 업데이트

```lua
-- entities/player/combat.lua 교체
-- (제공된 player_combat_with_sound.lua로 교체)

-- entities/enemy/init.lua 교체
-- (제공된 enemy_init_with_sound.lua로 교체)

-- entities/enemy/ai.lua 교체
-- (제공된 enemy_ai_with_sound.lua로 교체)

-- scenes/play.lua 교체
-- (제공된 play_with_sound.lua로 교체)

-- scenes/menu.lua 교체
-- (제공된 menu_with_sound.lua로 교체)

-- scenes/pause.lua 교체
-- (제공된 pause_with_sound.lua로 교체)

-- scenes/settings.lua 교체
-- (제공된 settings_with_sound.lua로 교체)
```

### 3단계: 사운드 파일 준비

사운드 파일이 없어도 시스템은 작동합니다 (경고만 출력). 실제 사운드를 추가하려면:

#### 무료 사운드 리소스
- 🌐 https://freesound.org (다양한 효과음)
- 🎮 https://opengameart.org (게임 사운드)
- 🎹 https://incompetech.com (무료 BGM)

#### 사운드 생성 도구
- 🔊 BFXR: https://www.bfxr.net (레트로 스타일 효과음)
- 🎛️ Audacity: https://www.audacityteam.org (무료 편집)

#### 파일 포맷 가이드
- **BGM**: `.ogg` 또는 `.mp3` (스트리밍용, 파일 크기가 큼)
- **SFX**: `.wav` 또는 `.ogg` (빠른 재생용, 파일 크기가 작음)

## 🎮 사용법

### BGM 제어

```lua
local sound = require "systems.sound"

-- BGM 재생
sound:playBGM("menu")
sound:playBGM("level1")

-- BGM 제어
sound:stopBGM()
sound:pauseBGM()
sound:resumeBGM()
```

### SFX 재생

```lua
-- 일반 재생
sound:playSFX("menu", "select")

-- 피치 변경 (0.5 ~ 2.0)
sound:playSFX("combat", "sword_swing", 1.2)

-- 볼륨 조절
sound:playSFX("combat", "sword_swing", 1.0, 0.5) -- 피치, 볼륨

-- 풀링된 사운드 (자주 사용, 성능 향상)
sound:playPooled("player", "footstep", 0.9, 0.3)
```

### 볼륨 제어

```lua
-- 마스터 볼륨 (0.0 ~ 1.0)
sound:setMasterVolume(0.8)

-- BGM 볼륨
sound:setBGMVolume(0.6)

-- SFX 볼륨
sound:setSFXVolume(0.7)

-- 음소거 토글
sound:toggleMute()

-- 상태 확인
print(sound.settings.muted)
print(sound.settings.master_volume)
```

### 플레이어 사운드

```lua
local player_sound = require "entities.player.sound"

-- 전투 사운드
player_sound.playAttack()
player_sound.playWeaponHit()
player_sound.playDodge()
player_sound.playHurt()

-- 패링 (일반/퍼펙트 자동 선택)
player_sound.playParry(is_perfect)

-- 무기
player_sound.playWeaponDraw()
player_sound.playWeaponSheath()

-- 발소리 (자동으로 재생되지만 수동 호출 가능)
player_sound.playFootstep()
```

### 적 사운드

```lua
local enemy_sound = require "entities.enemy.sound"

-- 이동 (슬라임 타입 지정)
enemy_sound.playMove("red_slime")
enemy_sound.playMove("green_slime")

-- 전투
enemy_sound.playAttack("red_slime")
enemy_sound.playHurt("blue_slime")
enemy_sound.playDeath("purple_slime")

-- 특수
enemy_sound.playStunned("red_slime")
enemy_sound.playDetect() -- 플레이어 발견
```

## 🔧 통합 포인트

### entities/player/combat.lua
```lua
-- 초기화
combat.initialize(player)
  └─> player_sound.initialize()

-- 업데이트
combat.updateTimers(player, dt)
  └─> player_sound.update(dt, player) -- 발소리 타이밍

-- 공격
combat.attack(player)
  ├─> player_sound.playWeaponDraw() (무기 장착)
  └─> player_sound.playAttack()

-- 패링
combat.checkParry(player, damage)
  └─> player_sound.playParry(is_perfect)

-- 회피
combat.startDodge(player)
  └─> player_sound.playDodge()

-- 피격
combat.takeDamage(player, damage, shake_callback)
  └─> player_sound.playHurt()
```

### entities/enemy/init.lua
```lua
-- 초기화 (1회만)
enemy:new(x, y, enemy_type)
  └─> enemy_sound.initialize()

-- 업데이트
enemy:update(dt, player_x, player_y)
  └─> enemy_sound.playMove(self.type) -- 이동 사운드 타이밍

-- 피격
enemy:takeDamage(damage)
  ├─> enemy_sound.playHurt(self.type)
  └─> enemy_sound.playDeath(self.type) (사망 시)

-- 기절
enemy:stun(duration, is_perfect)
  └─> enemy_sound.playStunned(self.type)
```

### entities/enemy/ai.lua
```lua
-- 플레이어 감지
ai.updateIdle(enemy, dt, player_x, player_y)
ai.updatePatrol(enemy, dt, player_x, player_y)
  └─> enemy_sound.playDetect() (시야 확보 시)

-- 공격
ai.updateAttack(enemy, dt, player_x, player_y)
  └─> enemy_sound.playAttack(enemy.type)
```

### scenes/play.lua
```lua
-- 씬 진입
play:enter(previous, mapPath, spawn_x, spawn_y, save_slot)
  └─> sound:playBGM("level1") -- 맵 기반 BGM

-- 씬 종료
play:exit()
  └─> sound:stopBGM()

-- 저장
play:saveGame(slot)
  └─> sound:playSFX("ui", "save")

-- 일시정지
play:keypressed(key) [ESC]
  ├─> sound:playSFX("ui", "pause")
  └─> sound:pauseBGM()

-- 무기 히트
player.weapon.is_attacking == true
  └─> player_sound.playWeaponHit()
```

### scenes/menu.lua
```lua
-- 씬 진입
menu:enter(previous, ...)
  └─> sound:playBGM("menu")

-- 네비게이션
menu:keypressed(key) [↑/↓]
  └─> sound:playSFX("menu", "navigate")

-- 선택
menu:keypressed(key) [Enter]
  └─> sound:playSFX("menu", "select")

-- 에러
menu:executeOption(option_index)
  └─> sound:playSFX("menu", "error") (실패 시)
```

### scenes/pause.lua
```lua
-- 네비게이션
pause:keypressed(key) [↑/↓]
  └─> sound:playSFX("menu", "navigate")

-- 선택
pause:keypressed(key) [Enter]
  └─> sound:playSFX("menu", "select")

-- 재개
pause:executeOption(1) [Resume]
  ├─> sound:playSFX("ui", "unpause")
  └─> sound:resumeBGM()

-- 메뉴로
pause:executeOption(4) [Quit to Menu]
  └─> sound:playSFX("menu", "back")
```

### scenes/settings.lua
```lua
-- 새 옵션 추가:
  - Master Volume (마스터 볼륨)
  - BGM Volume (배경음악 볼륨)
  - SFX Volume (효과음 볼륨)
  - Mute (음소거)

-- 볼륨 변경
settings:changeOption(direction) [Master/BGM/SFX Volume]
  ├─> sound:setMasterVolume(volume)
  ├─> sound:setBGMVolume(volume)
  ├─> sound:setSFXVolume(volume)
  └─> sound:playSFX("menu", "navigate") -- 테스트 사운드

-- 음소거
settings:changeOption(direction) [Mute]
  └─> sound:toggleMute()
```

## ⚙️ 고급 기능

### 사운드 풀링 시스템

자주 재생되는 사운드는 풀링하여 성능 향상:

```lua
-- systems/sound.lua에서
sound:createPool("player", "footstep", "assets/sound/player/footstep.wav", 4)

-- 사용 시
sound:playPooled("player", "footstep", pitch, volume)
```

### 피치 변조로 다양성 추가

```lua
-- 랜덤 피치로 자연스러운 사운드
local pitch = 0.9 + math.random() * 0.2 -- 0.9 ~ 1.1
player_sound.playFootstep(pitch)
```

### 사운드 타이밍 제어

```lua
-- player/sound.lua 참고
player_sound.footstep_timer = 0
player_sound.footstep_interval = 0.4 -- 0.4초마다 발소리

function player_sound.update(dt, player)
    if player.state == "walking" then
        player_sound.footstep_timer = player_sound.footstep_timer + dt
        
        if player_sound.footstep_timer >= player_sound.footstep_interval then
            player_sound.playFootstep()
            player_sound.footstep_timer = 0
        end
    end
end
```

## 🎨 사운드 생성 가이드

### BFXR로 효과음 만들기

1. https://www.bfxr.net 접속
2. 프리셋 선택:
   - **Pickup/Coin**: 아이템 획득
   - **Laser/Shoot**: 공격 사운드
   - **Explosion**: 파괴, 죽음
   - **PowerUp**: 레벨업, 버프
   - **Hit/Hurt**: 피격
   - **Jump**: 점프, 회피
   - **Blip/Select**: 메뉴 선택

3. 파라미터 조정:
   - **Attack Time**: 빠를수록 날카로움
   - **Sustain Time**: 지속 시간
   - **Frequency**: 높을수록 높은 음

4. Export → `.wav` 저장

### Audacity로 편집하기

1. 사운드 파일 열기
2. 효과 적용:
   - **Normalize**: 볼륨 균일화
   - **Fade In/Out**: 부드러운 시작/끝
   - **Change Pitch**: 피치 조정
   - **Noise Reduction**: 노이즈 제거

3. Export → `.wav` 또는 `.ogg` 저장

## 📊 성능 최적화

### 1. 사운드 포맷 선택

| 용도 | 포맷 | 이유 |
|------|------|------|
| BGM (장시간) | `.ogg` | 압축률 좋음, 스트리밍 |
| SFX (짧고 빈번) | `.wav` | 빠른 로딩, 저지연 |

### 2. 풀링 사용

```lua
-- 자주 재생되는 사운드 (초당 여러 번)
sound:createPool("player", "footstep", path, 4)

-- 가끔 재생되는 사운드 (초당 1-2번)
sound:loadSFX("combat", "sword_swing", path)
```

### 3. 볼륨 밸런싱

```lua
-- 기본 볼륨 설정 (systems/sound.lua)
sound.settings = {
    master_volume = 1.0,  -- 100%
    bgm_volume = 0.7,     -- 70% (BGM은 배경)
    sfx_volume = 0.8      -- 80% (SFX는 강조)
}

-- 개별 사운드 볼륨 조정
sound:playSFX("player", "footstep", 1.0, 0.3) -- 30%로 재생
sound:playSFX("combat", "hit", 1.0, 0.8)      -- 80%로 재생
```

## 🐛 문제 해결

### 사운드가 재생되지 않음

1. **파일 경로 확인**:
   ```lua
   print(love.filesystem.getInfo("assets/sound/player/footstep.wav"))
   -- nil이면 파일이 없음
   ```

2. **사운드 시스템 초기화 확인**:
   ```lua
   -- systems/sound.lua의 init()가 자동 호출됨
   sound:printStatus() -- 로딩된 사운드 확인
   ```

3. **볼륨 확인**:
   ```lua
   print(sound.settings.master_volume) -- 0이면 안 들림
   print(sound.settings.muted)          -- true면 음소거
   ```

### BGM이 끊김

```lua
-- 스트리밍 타입으로 로딩했는지 확인
source = love.audio.newSource(path, "stream") -- ✅ 좋음
source = love.audio.newSource(path, "static") -- ❌ 메모리 많이 사용
```

### SFX가 겹쳐서 재생됨

```lua
-- 풀링 시스템 사용
sound:createPool("player", "footstep", path, 3) -- 3개 인스턴스
sound:playPooled("player", "footstep")
```

## 📚 추가 확장 아이디어

### 1. 사운드 믹싱
```lua
-- 전투 중 BGM 볼륨 낮추기
if player.state == "attacking" or enemy_nearby then
    sound:setBGMVolume(0.3) -- 30%
else
    sound:setBGMVolume(0.7) -- 70%
end
```

### 2. 3D 사운드 (거리 기반)
```lua
function sound:playPositional(category, name, x, y, listener_x, listener_y)
    local dx = x - listener_x
    local dy = y - listener_y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    local volume = math.max(0, 1 - distance / 500) -- 500픽셀까지 들림
    self:playSFX(category, name, 1.0, volume)
end
```

### 3. 환경음 (Ambience)
```lua
-- 특정 맵에서 자동 재생
if map_type == "forest" then
    sound:playBGM("forest_ambience")
elseif map_type == "cave" then
    sound:playBGM("cave_ambience")
end
```

## 📖 참고 자료

- Love2D 오디오 문서: https://love2d.org/wiki/love.audio
- LÖVE 사운드 튜토리얼: https://simplegametutorials.github.io/love/audio/
- 오디오 파일 포맷: https://love2d.org/wiki/SoundData

## ✅ 체크리스트

- [ ] `systems/sound.lua` 생성 완료
- [ ] `entities/player/sound.lua` 생성 완료
- [ ] `entities/enemy/sound.lua` 생성 완료
- [ ] `entities/player/combat.lua` 업데이트 완료
- [ ] `entities/enemy/init.lua` 업데이트 완료
- [ ] `entities/enemy/ai.lua` 업데이트 완료
- [ ] `scenes/play.lua` 업데이트 완료
- [ ] `scenes/menu.lua` 업데이트 완료
- [ ] `scenes/pause.lua` 업데이트 완료
- [ ] `scenes/settings.lua` 업데이트 완료
- [ ] 사운드 파일 준비 (선택사항)
- [ ] 게임 실행 및 테스트

---

## 🎉 완성!

이제 게임에 완전한 사운드 시스템이 통합되었습니다!

사운드 파일 없이도 시스템이 작동하므로, 나중에 천천히 사운드를 추가할 수 있습니다.
