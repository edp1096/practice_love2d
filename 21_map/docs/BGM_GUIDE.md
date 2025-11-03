# BGM System Guide

## 🎵 배경음악(BGM) 시스템 사용법

---

## 📁 기본 구조

```
assets/bgm/           - BGM 오디오 파일
data/sounds.lua       - BGM 등록 (필수)
Tiled Map Properties  - 맵별 BGM 지정 (선택)
```

---

## 🎮 사용 방법

### 1️⃣ **자동 BGM (권장 방법)**

폴더 이름을 기준으로 자동 재생됩니다.

#### 예시:
```
assets/maps/level1/area1.lua  → BGM: "level1"
assets/maps/level1/area2.lua  → BGM: "level1"
assets/maps/level2/area1.lua  → BGM: "level2"
assets/maps/level3/area1.lua  → BGM: "level3"
```

#### 설정 단계:
1. **BGM 파일 추가:**
   ```
   assets/bgm/level3.ogg
   ```

2. **data/sounds.lua에 등록:**
   ```lua
   bgm = {
       level1 = { path = "assets/bgm/level1.ogg", volume = 0.7, loop = true },
       level2 = { path = "assets/bgm/level2.mp3", volume = 0.7, loop = true },
       level3 = { path = "assets/bgm/level3.ogg", volume = 0.7, loop = true },
   }
   ```

3. **맵 제작:**
   ```
   assets/maps/level3/area1.tmx
   ```

4. **완료!** level3 폴더의 모든 맵은 자동으로 level3 BGM 재생 ✅

---

### 2️⃣ **맵별 커스텀 BGM (수동 지정)**

특정 맵만 다른 BGM을 재생하고 싶을 때 사용합니다.

#### 예시: 보스방에서 보스 BGM 재생

1. **Tiled에서 맵 열기:**
   ```
   assets/maps/level1/boss_room.tmx
   ```

2. **Map → Map Properties 설정:**
   ```
   Property Name: bgm
   Type: string
   Value: boss
   ```

3. **data/sounds.lua에 boss BGM 등록:**
   ```lua
   bgm = {
       level1 = { path = "assets/bgm/level1.ogg", volume = 0.7, loop = true },
       boss = { path = "assets/bgm/boss.ogg", volume = 0.8, loop = true },
   }
   ```

4. **결과:**
   - `level1/area1` → level1 BGM 재생
   - `level1/boss_room` → boss BGM 재생 (맵 속성 우선)
   - `level1/area2` → level1 BGM 재생

---

## 🎬 특수 BGM: Intro & Ending

**Intro와 Ending은 별도 시스템을 사용합니다** (맵 속성과 무관)

### Intro/Cutscene BGM

Intro는 `data/intro_configs.lua`에서 설정합니다:

```lua
-- data/intro_configs.lua
return {
    level1 = {
        background = "assets/maps/level1/scene_intro.png",
        bgm = "intro_level1",  -- Intro 전용 BGM
        messages = { "Welcome to the adventure!", ... }
    },

    level2 = {
        background = "assets/maps/level2/scene_intro.jpg",
        bgm = "intro_level2",  -- Level2 Intro BGM
        messages = { "Good bye level 1!", ... }
    }
}
```

**Portal에서 Intro 호출:**
```
Tiled Portal Properties:
  - type: "intro"
  - intro_id: "level2"
  - target_map: "assets/maps/level2/area1.lua"
  - spawn_x: 400
  - spawn_y: 250
```

### Ending BGM

Ending도 `data/intro_configs.lua`에서 설정:

```lua
-- data/intro_configs.lua
ending = {
    background = "assets/maps/ending.jpg",
    bgm = "ending",  -- Ending BGM (loop=false 권장)
    messages = { "Congratulations!", ... },
    is_ending = true  -- 엔딩 플래그
}
```

**Portal에서 Ending 호출:**
```
Tiled Portal Properties:
  - type: "ending"
  - intro_id: "ending"
```

**Ending BGM은 한 번만 재생:**
```lua
-- data/sounds.lua
bgm = {
    ending = { path = "assets/bgm/ending.mp3", volume = 0.8, loop = false },
}
```

---

## 🔄 BGM 전환 동작

### ✅ 같은 BGM → 끊김 없이 계속 재생

```
level1/area1 (BGM: level1)
    ↓ Portal
level1/area2 (BGM: level1)
    ↓
Result: BGM이 끊기지 않고 계속 재생됨 ✅
```

### ✅ 다른 BGM → 자연스럽게 전환

```
level1/area1 (BGM: level1)
    ↓ Portal
level1/boss_room (BGM: boss)
    ↓
Result: level1 BGM 정지 → boss BGM 시작 ✅
```

### ✅ 보스방에서 일반 area로 복귀

```
level1/boss_room (BGM: boss)
    ↓ Portal
level1/area2 (BGM: level1)
    ↓
Result: boss BGM 정지 → level1 BGM 처음부터 재생 ✅
```

---

## 📋 실전 예제

### 예제 1: 새 레벨 추가

```bash
# 1. BGM 파일 추가
assets/bgm/level4.ogg

# 2. data/sounds.lua 수정
bgm = {
    level4 = { path = "assets/bgm/level4.ogg", volume = 0.7, loop = true },
}

# 3. 맵 제작
assets/maps/level4/area1.tmx

# 4. 기존 맵에 Portal 추가 (level3 → level4 연결)
Portals 레이어에 rectangle 추가:
  - type: "portal"
  - target_map: "assets/maps/level4/area1.lua"
  - spawn_x: 400
  - spawn_y: 250
```

**결과:** level4 폴더의 모든 area는 자동으로 level4 BGM 재생!

---

### 예제 2: 특정 area만 다른 BGM

```bash
# 시나리오: level2의 area3만 숨겨진 던전 BGM 재생

# 1. BGM 파일 추가
assets/bgm/dungeon.ogg

# 2. data/sounds.lua 수정
bgm = {
    level2 = { path = "assets/bgm/level2.mp3", volume = 0.7, loop = true },
    dungeon = { path = "assets/bgm/dungeon.ogg", volume = 0.6, loop = true },
}

# 3. Tiled에서 area3.tmx 열기
# 4. Map Properties 설정:
  - bgm: "dungeon"

# 5. 완료!
```

**결과:**
- level2/area1 → level2 BGM
- level2/area2 → level2 BGM
- level2/area3 → dungeon BGM (맵 속성 우선)
- level2/area4 → level2 BGM

---

### 예제 3: 엔딩 크레딧 BGM (반복 안함)

```lua
-- data/sounds.lua
bgm = {
    ending = { path = "assets/bgm/ending.mp3", volume = 0.8, loop = false },
}
```

**Tiled 맵 속성:**
```
Map: assets/maps/ending/credits.tmx
Property: bgm = "ending"
```

**결과:** 크레딧 맵 진입 시 ending BGM이 한 번만 재생됨 (loop=false)

---

## 🎛️ 고급 설정

### BGM 볼륨 조절

```lua
bgm = {
    menu = { path = "assets/bgm/menu.ogg", volume = 0.7, loop = true },
    boss = { path = "assets/bgm/boss.ogg", volume = 0.9, loop = true },  -- 더 크게
}
```

### 지원 파일 형식

- ✅ `.ogg` (권장 - 용량 작고 품질 좋음)
- ✅ `.mp3`
- ✅ `.wav` (용량 큼, 비권장)

---

## ⚠️ 주의사항

### 1. BGM 이름 오타
```lua
# ❌ 잘못된 예:
맵 속성: bgm = "bos"  (오타)
data/sounds.lua: boss = { ... }

# 결과: BGM 재생 안됨, 콘솔에 경고 출력
# WARNING: BGM not found: bos
```

### 2. 파일 경로 오류
```lua
# ❌ 잘못된 예:
bgm = {
    level3 = { path = "assets/bgm/level_3.ogg", ... }  # 파일명 틀림
}

# 실제 파일: assets/bgm/level3.ogg

# 결과: BGM 로딩 실패
# WARNING: BGM not found: assets/bgm/level_3.ogg
```

### 3. 맵 속성 타입 오류
```
# ❌ Tiled에서 잘못 설정:
Property Name: bgm
Type: int (틀림!)
Value: 1

# ✅ 올바른 설정:
Property Name: bgm
Type: string
Value: boss
```

---

## 🔍 디버깅

### BGM이 재생 안될 때 체크리스트:

1. **콘솔 확인:**
   ```
   Playing BGM: level1 (rewound)
   ```
   이 메시지가 안 보이면 BGM이 시작 안된 것

2. **data/sounds.lua 확인:**
   ```lua
   bgm = {
       your_bgm_name = { path = "correct/path.ogg", volume = 0.7, loop = true },
   }
   ```

3. **파일 존재 확인:**
   ```bash
   ls assets/bgm/
   # level1.ogg, level2.mp3, boss.ogg 등이 보여야 함
   ```

4. **맵 속성 확인 (커스텀 BGM 사용 시):**
   - Tiled → Map → Map Properties
   - bgm 속성이 string 타입이고 값이 정확한지 확인

5. **볼륨 설정 확인:**
   - 게임 내 Settings → BGM Volume이 0이 아닌지 확인
   - Mute가 켜져있지 않은지 확인

---

## 📚 관련 파일

- **data/sounds.lua** - BGM 등록
- **systems/sound.lua** - BGM 재생 시스템
- **scenes/play/init.lua** (96-100줄) - 게임 시작 시 BGM
- **scenes/play/init.lua** (185-197줄) - Portal 전환 시 BGM

---

**Last Updated:** 2025-11-03
