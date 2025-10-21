# Love2D Sound System Integration Guide

## 파일 구조

```
14_sound/
├── systems/
│   └── sound.lua (새 파일)
├── entities/
│   ├── player/
│   │   ├── sound.lua (새 파일)
│   │   └── combat.lua (수정됨)
│   └── enemy/
│       ├── sound.lua (새 파일)
│       ├── init.lua (수정됨)
│       └── ai.lua (수정됨)
├── scenes/
│   ├── menu.lua (수정됨)
│   ├── pause.lua (수정됨)
│   └── play.lua (수정됨)
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

## 주요 기능

### 1. 중앙 사운드 관리 (systems/sound.lua)
- BGM 자동 루핑
- SFX 풀링 시스템 (자주 사용되는 사운드용)
- 볼륨 제어 (마스터, BGM, SFX 별도)
- 음소거 기능
- 자동 페이드인/아웃

### 2. 플레이어 사운드 (entities/player/sound.lua)
- 발소리 자동 재생 (걷기 중)
- 공격 사운드
- 무기 히트 사운드
- 패링 사운드 (일반/퍼펙트 분리)
- 회피 사운드
- 피격 사운드
- 무기 장착/해제 사운드

### 3. 적 사운드 (entities/enemy/sound.lua)
- 이동 사운드 (슬라임)
- 공격 사운드
- 피격 사운드
- 죽음 사운드
- 기절 사운드
- 플레이어 감지 사운드

### 4. 메뉴 사운드
- 네비게이션 사운드
- 선택 사운드
- 뒤로가기 사운드
- 에러 사운드

### 5. UI 사운드
- 저장 사운드
- 일시정지/재개 사운드

## 사용법

### BGM 재생
```lua
local sound = require "systems.sound"
sound:playBGM("menu")
sound:playBGM("level1")
sound:stopBGM()
sound:pauseBGM()
sound:resumeBGM()
```

### SFX 재생
```lua
-- 일반 재생
sound:playSFX("menu", "select")
sound:playSFX("combat", "sword_swing", 1.2) -- 피치 변경

-- 풀링된 사운드 재생 (자주 사용)
sound:playPooled("player", "footstep", 0.9, 0.5) -- 피치, 볼륨
```

### 볼륨 제어
```lua
sound:setMasterVolume(0.8)
sound:setBGMVolume(0.6)
sound:setSFXVolume(0.7)
sound:toggleMute()
```

### 플레이어 사운드
```lua
local player_sound = require "entities.player.sound"

player_sound.playAttack()
player_sound.playWeaponHit()
player_sound.playParry(is_perfect)
player_sound.playDodge()
player_sound.playHurt()
```

### 적 사운드
```lua
local enemy_sound = require "entities.enemy.sound"

enemy_sound.playMove("red_slime")
enemy_sound.playAttack("green_slime")
enemy_sound.playHurt("blue_slime")
enemy_sound.playDeath("purple_slime")
enemy_sound.playStunned("red_slime")
enemy_sound.playDetect()
```

## 통합 포인트

### 1. entities/player/combat.lua
- `combat.initialize()`: player_sound 초기화
- `combat.updateTimers()`: player_sound.update() 호출
- `combat.attack()`: 무기 장착/공격 사운드
- `combat.startParry()`: 무기 장착 사운드
- `combat.startDodge()`: 회피 사운드
- `combat.checkParry()`: 패링 사운드
- `combat.takeDamage()`: 피격 사운드

### 2. entities/enemy/init.lua
- `enemy:new()`: enemy_sound 초기화
- `enemy:update()`: 이동 사운드 타이머
- `enemy:takeDamage()`: 피격/죽음 사운드
- `enemy:stun()`: 기절 사운드

### 3. entities/enemy/ai.lua
- `ai.updateIdle()`: 플레이어 감지 시 감지 사운드
- `ai.updatePatrol()`: 플레이어 감지 시 감지 사운드
- `ai.updateAttack()`: 공격 사운드

### 4. scenes/play.lua
- `play:enter()`: 레벨 BGM 시작
- `play:exit()`: BGM 정지
- `play:saveGame()`: 저장 사운드
- `play:keypressed()`: 일시정지 사운드, BGM 일시정지
- 무기 히트 시: 히트 사운드 재생

### 5. scenes/menu.lua
- `menu:enter()`: 메뉴 BGM 시작
- `menu:update()`: 마우스 호버 네비게이션 사운드
- `menu:keypressed()`: 네비게이션/선택 사운드
- `menu:executeOption()`: 에러 사운드 (실패 시)

### 6. scenes/pause.lua
- `pause:update()`: 마우스 호버 네비게이션 사운드
- `pause:keypressed()`: 네비게이션/선택/재개 사운드
- `pause:executeOption()`: 재개 시 unpause 사운드, BGM 재개

## 주의사항

1. **사운드 파일 필요**: assets/ 폴더에 모든 사운드 파일이 있어야 합니다
2. **파일 포맷**: 
   - BGM: .ogg (스트리밍용)
   - SFX: .wav (빠른 재생용)
3. **메모리 관리**: 자주 사용되는 사운드는 풀링 시스템 사용
4. **볼륨 밸런싱**: 각 사운드의 기본 볼륨을 조정하여 균형 맞추기

## 테스트

사운드 파일 없이 테스트하려면 systems/sound.lua의 `loadBGM()`, `loadSFX()`, `createPool()` 함수에서 파일이 없을 때 경고만 출력하도록 되어 있습니다.

실제 사운드를 추가하려면:
1. 무료 사운드: freesound.org, opengameart.org
2. 생성 도구: BFXR, SFXR (레트로 사운드)
3. DAW: Audacity (무료 편집)

## 확장

추가 사운드를 넣으려면:

```lua
-- systems/sound.lua의 init() 함수에 추가
sound:loadSFX("category", "sound_name", "assets/sound/path.wav")

-- 또는 풀 생성
sound:createPool("category", "sound_name", "assets/sound/path.wav", 5)
```
