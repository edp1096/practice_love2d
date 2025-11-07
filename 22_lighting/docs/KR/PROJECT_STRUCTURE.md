# 프로젝트 구조

## 📁 루트 디렉토리

```
22_lighting/
├── main.lua              - 진입점 (LÖVE 콜백, 에러 핸들러, 입력 라우팅)
├── conf.lua              - LÖVE 설정 (윈도우, 모듈, 버전)
├── locker.lua            - 프로세스 잠금 (데스크톱 전용, 다중 인스턴스 방지)
├── config.ini            - 사용자 설정 (윈도우, 사운드, 입력, IsDebug)
│
├── engine/               - 재사용 가능한 게임 엔진 (ENGINE_GUIDE.md 참조)
├── game/                 - 게임 전용 콘텐츠 (GAME_GUIDE.md 참조)
├── lib/                  - 서드파티 라이브러리 래퍼
├── vendor/               - 외부 라이브러리 (STI, Windfield, anim8, hump, Talkies)
├── assets/               - 게임 리소스 (맵, 이미지, 사운드, 폰트)
└── docs/                 - 문서 (이 폴더)
```

---

## 🎮 엔진 폴더 (`engine/`)

**목적:** 모든 LÖVE2D 게임에서 재사용 가능한 시스템.

```
engine/
├── lifecycle.lua         - 애플리케이션 생명주기 (초기화, 업데이트, 렌더링, 리사이즈, 종료)
├── scene_control.lua     - 씬 스택 관리 (switch, push, pop)
├── camera.lua            - 카메라 효과 (흔들림, 슬로우 모션)
├── coords.lua            - **통합 좌표계 시스템** (월드, 카메라, 가상, 물리)
├── game_mode.lua         - 게임 모드 관리 (topdown/platformer)
├── sound.lua             - 오디오 시스템 (BGM, SFX, 볼륨 제어)
├── save.lua              - 저장/로드 시스템 (슬롯 기반)
├── inventory.lua         - 인벤토리 시스템 (아이템, 사용)
├── debug.lua             - 디버그 오버레이 (F1 토글)
├── constants.lua         - 엔진 상수
│
├── display/              - 가상 화면 시스템
│   └── init.lua          - 스케일링, 레터박싱, 좌표 변환
│
├── input/                - 입력 시스템
│   ├── init.lua                        - 입력 퍼사드 (API 진입점)
│   ├── dispatcher.lua                  - 입력 이벤트 디스패처
│   ├── virtual_gamepad.lua             - 가상 온스크린 게임패드 (모바일)
│   └── sources/
│       ├── base_input.lua              - 베이스 클래스
│       ├── keyboard_input.lua          - 키보드 처리
│       ├── mouse_input.lua             - 마우스/조준 처리
│       ├── gamepad.lua                 - 물리 컨트롤러
│       └── virtual_pad.lua             - 가상 게임패드 어댑터
│
├── world/                - 물리 & 월드 시스템
│   ├── init.lua          - 월드 코디네이터 (Windfield 래퍼)
│   ├── loaders.lua       - 맵 로딩 (Tiled TMX)
│   ├── entities.lua      - 엔티티 관리 (추가, 제거, 업데이트)
│   └── rendering.lua     - Y 정렬 렌더링
│
├── effects/              - 시각 효과 시스템
│   ├── init.lua          - 효과 코디네이터
│   ├── particles/        - 파티클 효과 (피, 불꽃 등)
│   └── screen/           - 스크린 효과 (플래시, 비네트, 오버레이)
│
├── lighting/             - 라이팅 시스템 (이미지 기반)
│   ├── init.lua          - 라이팅 매니저 (주변광, 포인트 라이트)
│   └── light.lua         - 개별 광원 객체
│
├── hud/                  - 인게임 HUD 시스템
│   ├── status.lua        - 체력바, 쿨다운, 상태 표시
│   └── minimap.lua       - 미니맵 렌더링
│
├── ui/                   - 메뉴 UI 시스템
│   ├── menu.lua          - 메뉴 UI 헬퍼 (레이아웃, 네비게이션, 다이얼로그)
│   └── dialogue.lua      - NPC 대화 시스템 (Talkies 래퍼)
│
└── utils/                - 엔진 유틸리티
    ├── util.lua          - 일반 유틸리티
    ├── restart.lua       - 게임 재시작 로직
    ├── fonts.lua         - 폰트 관리
    └── ini.lua           - INI 파일 파서
```

---

## 🕹️ 게임 폴더 (`game/`)

**목적:** 게임 전용 콘텐츠 (데이터 중심 게임 개발).

```
game/
├── scenes/               - 게임 화면 (메뉴, 게임플레이)
│   ├── menu.lua
│   ├── gameover.lua
│   ├── intro.lua
│   ├── pause.lua
│   ├── newgame.lua
│   ├── saveslot.lua
│   ├── play/             - 메인 게임플레이 씬 (모듈형)
│   │   ├── init.lua      - 씬 코디네이터
│   │   ├── update.lua    - 게임 루프
│   │   ├── render.lua    - 그리기
│   │   └── input.lua     - 입력 처리
│   ├── settings/         - 설정 메뉴 (모듈형)
│   │   ├── init.lua
│   │   ├── options.lua
│   │   ├── render.lua
│   │   └── input.lua
│   ├── load/             - 게임 로드 씬 (모듈형)
│   │   ├── init.lua
│   │   ├── slot_renderer.lua
│   │   └── input.lua
│   └── inventory/        - 인벤토리 오버레이 (모듈형)
│       ├── init.lua
│       ├── slot_renderer.lua
│       └── input.lua
│
├── entities/             - 게임 캐릭터 & 오브젝트
│   ├── player/
│   │   ├── init.lua      - 메인 코디네이터
│   │   ├── animation.lua - 애니메이션 상태 머신
│   │   ├── combat.lua    - 체력, 공격, 패리, 회피
│   │   ├── render.lua    - 그리기 로직
│   │   └── sound.lua     - 플레이어 사운드 효과
│   ├── enemy/
│   │   ├── init.lua
│   │   ├── ai.lua        - AI 상태 머신
│   │   ├── render.lua
│   │   ├── sound.lua
│   │   ├── spawner.lua   - 적 생성 로직
│   │   └── types/
│   │       ├── slime.lua
│   │       └── humanoid.lua
│   ├── weapon/
│   │   ├── init.lua
│   │   ├── combat.lua
│   │   ├── render.lua
│   │   ├── config/       - 무기 설정
│   │   └── types/
│   │       └── sword.lua
│   ├── npc/
│   │   ├── init.lua
│   │   └── types/
│   │       └── villager.lua
│   ├── item/
│   │   ├── init.lua
│   │   └── types/
│   │       ├── small_potion.lua
│   │       └── large_potion.lua
│   └── healing_point/
│       └── init.lua
│
└── data/                 - 게임 설정 데이터
    ├── input_config.lua  - 키 매핑 & 컨트롤러 설정
    ├── sounds.lua        - 사운드 에셋 정의 (BGM, SFX)
    └── intro_configs.lua - 인트로/컷신 설정
```

---

## 🔧 벤더 폴더 (`vendor/`)

**목적:** 외부 라이브러리 (수정되지 않음).

```
vendor/
├── anim8/                - 스프라이트 애니메이션 라이브러리
├── hump/                 - 유틸리티 컬렉션 (카메라, 타이머, 벡터)
├── sti/                  - Simple Tiled Implementation (TMX 로더)
├── windfield/            - Box2D 물리 래퍼
└── talkies/              - 대화/텍스트 박스 시스템
```

---

## 🎨 에셋 폴더 (`assets/`)

**목적:** 게임 리소스.

```
assets/
├── maps/                 - Tiled 맵 (.tmx + .lua)
│   ├── level1/
│   │   ├── area1.lua/tmx
│   │   ├── area2.lua/tmx
│   │   └── area3.lua/tmx
│   └── level2/
│       └── area1.lua/tmx
├── images/               - 스프라이트, 타일셋, UI 그래픽
├── bgm/                  - 배경 음악 (.ogg, .mp3)
├── sound/                - 사운드 효과 (.wav)
└── fonts/                - 커스텀 폰트
```

---

## 📊 파일 개수 요약

| 카테고리 | 파일 수 | 라인 수 |
|----------|-------|-------|
| **Engine** | ~30 파일 | ~4,500 라인 |
| **Game Content** | ~50 파일 | ~7,000 라인 |
| **Total** | ~80 파일 | ~11,500 라인 |

---

## 🎯 설계 원칙

### 1. Engine/Game 분리
- **Engine:** "어떻게 작동하는가?" (시스템, 메커니즘)
- **Game:** "무엇을 보여주는가?" (콘텐츠, 데이터)

### 2. 모듈형 아키텍처
- 복잡한 시스템을 집중된 파일로 분할
- 모듈당 단일 책임
- 찾고 수정하기 쉬움

### 3. 콘텐츠 중심 철학
- 엔진은 프로젝트 간 재사용 가능
- game 폴더는 콘텐츠 전용
- game/에 최소한의 코드 (주로 데이터)

---

**참고:**
- [ENGINE_GUIDE.md](ENGINE_GUIDE.md) - 엔진 시스템 레퍼런스
- [GAME_GUIDE.md](GAME_GUIDE.md) - 콘텐츠 제작 가이드
