# LÖVE2D 게임 엔진

깔끔한 **엔진/게임 분리 아키텍처**를 가진 LÖVE2D 게임 프로젝트.

---

## 🎯 프로젝트 철학

이 프로젝트는 **모듈형 아키텍처**를 따릅니다:

### **엔진 (100% 재사용 가능)** ⭐
`engine/` 폴더는 **모든** 게임 시스템과 엔티티를 포함합니다:
- **핵심 시스템:** lifecycle, input, display, sound, save, camera, debug
- **서브시스템:** world (물리), effects, lighting, HUD
- **엔티티:** player, enemy, weapon, NPC, item, healing_point (**모두 engine에!**)
- **UI:** menu system, screens, dialogue, widgets
- **씬 빌더:** 데이터 기반 씬 팩토리, cutscene, gameplay

### **게임 (데이터 + 최소 코드)**
`game/` 폴더는 **오직** 게임 특화 콘텐츠만 포함합니다:
- **씬:** 4개의 데이터 기반 메뉴 (각 6줄!), 복잡한 씬들 (play, settings, inventory, load)
- **데이터 설정:** player stats, enemy types, menu configs, sounds, input mappings
- **엔티티 폴더 없음!** (engine으로 이동)

### **장점**
- **새 게임 만들기 쉬움**: `engine/` 폴더 복사하고 새 `game/` 콘텐츠 생성
- **깔끔한 분리**: 엔진 코드 vs 게임 콘텐츠
- **유지보수 용이**: 명확한 구조로 파일 빠르게 찾기
- **콘텐츠 중심 워크플로우**: 엔진 코드가 아닌 게임 콘텐츠에 집중

---

## 🚀 빠른 시작

### 게임 실행하기

**데스크톱:**
```bash
love .
```

**배포용 빌드:**
```bash
# Windows
zip -9 -r game.love .
cat love.exe game.love > mygame.exe

# macOS / Linux
zip -9 -r game.love .
```

### 조작법

**데스크톱:**
- **WASD / 방향키** - 이동 (탑다운) / 좌우 이동 + 점프 (플랫포머)
- **마우스** - 조준
- **좌클릭 / Z** - 공격
- **우클릭 / X** - 패리
- **Shift / C** - 회피
- **F** - 상호작용 (NPC, 세이브 포인트)
- **I** - 인벤토리 열기
- **Q** - 선택한 아이템 사용
- **Tab** - 아이템 순환
- **1-5** - 인벤토리 슬롯 빠른 선택
- **Escape** - 일시정지
- **F11** - 전체화면 전환
- **F1** - 디버그 모드 전환 (config.ini에서 IsDebug=true 필요)
- **F2** - 그리드 시각화 전환
- **F3** - 가상 마우스 전환
- **F4** - 가상 게임패드 전환 (PC 전용, 테스트용)
- **F5** - 효과 디버그 전환
- **F6** - 마우스 위치에서 효과 테스트

**게임패드 (Xbox / DualSense):**
- **왼쪽 스틱 / D-Pad** - 이동 / 조준
- **오른쪽 스틱** - 조준
- **A / Cross (✕)** - 공격 / 상호작용
- **B / Circle (○)** - 점프 (플랫포머는 물리, 탑다운은 시각 효과) / 대화 스킵 (0.5초 홀드)
- **X / Square (□)** - 패리
- **Y / Triangle (△)** - NPC/세이브 포인트 상호작용
- **LB / L1** - 아이템 사용
- **LT / L2** - 다음 아이템
- **RB / R1** - 회피
- **RT / R2** - 인벤토리 열기/닫기
- **Start / Options** - 일시정지

**모바일 (터치):**
- **가상 게임패드** - 화면 컨트롤
- **아무 곳이나 터치** - 메뉴 탐색 / 대화 진행

---

## 📁 프로젝트 구조

```
23_refactor/
├── engine/       - 재사용 가능한 게임 엔진 (시스템)
├── game/         - 게임 콘텐츠 (씬, 엔티티, 데이터)
├── assets/       - 리소스 (맵, 이미지, 사운드)
├── vendor/       - 외부 라이브러리
└── docs/         - 문서
```

**핵심 개념:**
- **engine/** = "어떻게 작동하는가" (재사용 가능)
- **game/** = "무엇을 보여주는가" (콘텐츠)

---

## 🎮 첫 단계

### 1. 게임 탐험하기
- `love .`로 게임 시작
- 새 게임 → 세이브 슬롯 생성
- WASD로 이동
- 좌클릭으로 적 공격
- NPC를 찾고 F를 눌러 대화
- 세이브 포인트(빛나는 원)를 찾고 F를 눌러 저장

### 2. 다양한 게임 모드 체험하기
- **탑다운 모드** (level1/area1-3): 자유로운 2D 이동
- **플랫포머 모드** (level2/area1): 수평 이동 + 점프

### 3. 전투 테스트하기
- 공격: 좌클릭 / A 버튼
- 패리: 우클릭 / X 버튼 (적이 공격할 때 정확히 누르면 슬로우 모션)
- 회피: Shift / R1 버튼 (무적 프레임)

### 4. 인벤토리 시스템
- I를 눌러 인벤토리 열기
- Q / L1로 아이템 사용
- Tab / L2로 아이템 순환
- 1-5 키로 빠른 선택

---

## 🛠️ 콘텐츠 만들기

### 새 적 추가하기
1. 스프라이트 생성: `assets/images/enemies/yourenemy.png`
2. 타입 생성: `engine/entities/enemy/types/yourenemy.lua` (`slime.lua`에서 복사)
3. Tiled에서 맵 열기, `type = "yourenemy"`로 적 오브젝트 추가

### 새 아이템 추가하기
1. 아이콘 생성: `assets/images/items/youritem.png`
2. 타입 생성: `engine/entities/item/types/youritem.lua` (`small_potion.lua`에서 복사)
3. 코드에서 인벤토리에 추가: `inventory:addItem("youritem", 1)`

### 새 맵 추가하기
1. Tiled에서 `.tmx` 생성: `assets/maps/level1/newarea.tmx`
2. 맵 속성 설정: `game_mode = "topdown"` (또는 "platformer")
3. Lua로 내보내기: `assets/maps/level1/newarea.lua`
4. 이전 맵에 포털 오브젝트 생성: `target_map = "assets/maps/level1/newarea.lua"`

### 배경 음악 추가하기
1. 파일 배치: `assets/bgm/yourmusic.ogg`
2. `game/data/sounds.lua`에 등록:
   ```lua
   bgm = {
       yourmusic = { path = "assets/bgm/yourmusic.ogg", volume = 0.7, loop = true }
   }
   ```
3. Tiled 맵 속성에 설정: `bgm = "yourmusic"`

---

## 📚 문서

- **[GUIDE.md](GUIDE.md)** - 완전한 가이드 (엔진 + 게임 + 개발 + 효과)
- **[PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md)** - 전체 프로젝트 구조

---

## 🐛 문제 해결

### 게임이 시작되지 않음
- `love --version` 확인 (LÖVE 11.5 필요)
- `lua -v` 확인 (Lua 5.1 호환 필요)
- 콘솔에서 오류 확인

### 파일을 찾을 수 없음 오류
- 모든 `require` 경로가 점을 사용하는지 확인: `require "engine.sound"`
- 파일 경로가 슬래시를 사용하는지 확인: `"assets/maps/level1/area1.lua"`

### 소리가 나지 않음
- `config.ini`에 0이 아닌 볼륨이 설정되어 있는지 확인
- `assets/bgm/` 및 `assets/sound/`에 사운드 파일이 있는지 확인
- `game/data/sounds.lua`에서 사운드 정의 확인

### 맵이 로드되지 않음
- Tiled 맵이 Lua 형식(`.lua` 파일)으로 내보내졌는지 확인
- 맵에 필수 레이어(Ground, Walls 등)가 있는지 확인
- 맵 속성 `game_mode`가 설정되어 있는지 확인

---

**프레임워크:** LÖVE 11.5 + Lua 5.1
**아키텍처:** 엔진/게임 분리
**최종 업데이트:** 2025-11-07
