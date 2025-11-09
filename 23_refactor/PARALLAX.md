# 패럴랙스 배경 시스템 설계

## 개요

무한 스크롤 패럴랙스 배경을 Engine/Game 분리 아키텍처에 맞게 구현하기 위한 설계 문서입니다.

---

## 핵심 개념

### 패럴랙스란?
- 여러 배경 레이어가 카메라 이동에 따라 서로 다른 속도로 움직임
- 2D 게임에서 깊이감을 표현
- 느린 움직임 = 먼 배경, 빠른 움직임 = 가까운 배경

### 무한 스크롤
- 배경 이미지가 카메라 이동에 따라 끊김 없이 반복됨
- 텍스처 래핑(`setWrap("repeat")`)과 modulo 연산 사용
- 오픈 월드나 큰 맵에 필수적

---

## 아키텍처 결정

### 어디에 무엇을 두는가?

| 컴포넌트 | 위치 | 역할 |
|----------|------|------|
| **무한 스크롤 배경** | 코드 (`engine/systems/background.lua`) | 렌더링 로직, 래핑, 자동 스크롤 |
| **배경 테마 설정** | 데이터 (`game/data/backgrounds.lua`) | 이미지 경로, 패럴랙스 값, 스크롤 속도 |
| **맵별 배경 선택** | Tiled (맵 프로퍼티) | 어떤 테마 사용할지 (`background = "forest"`) |
| **정적 패럴랙스 요소** | Tiled (타일 레이어) | 위치 고정된 랜드마크 (성, 특정 산) |
| **동적 효과 영역** | Tiled (오브젝트 레이어) | 날씨 구역, 안개 지역, 구름 생성기 |

---

## 왜 Tiled로 무한 스크롤을 할 수 없는가?

### Tiled 타일 레이어의 한계:
1. **고정된 맵 크기** - 레이어에 경계가 있음 (예: 100x100 타일)
2. **텍스처 래핑 없음** - 타일이 무한히 반복되지 않음
3. **정적 배치** - 타일은 월드 좌표에 고정, 카메라 상대적이지 않음
4. **자동 스크롤 없음** - 구름이 자동으로 흐르게 할 수 없음

### Tiled 레이어를 언제 사용하는가:
- ✅ 위치가 정해진 배경 요소 (특정 언덕 위의 성)
- ✅ 반복되지 않는 랜드마크 (고유한 산 형태)
- ✅ 정확한 타일 배치가 필요한 요소
- ❌ 무한 스크롤 구름/하늘/먼 산

---

## 구현 전략

### 1. Tiled 설정

#### 맵 프로퍼티 (맵의 커스텀 프로퍼티):
```
background = "forest_day"    // game/data/backgrounds.lua 참조
ambient = "day"              // 기존 조명 시스템
bgm = "forest_theme"         // 기존 사운드 시스템
```

#### 정적 패럴랙스 레이어 (선택사항):
```
레이어: "BG_Castle"
  타입: Tile Layer
  커스텀 프로퍼티:
    parallax = 0.4  (숫자)

내용: 먼 성의 타일들 (반복되지 않음)
```

#### 동적 효과 영역 (선택사항):
```
레이어: "Effects"
  타입: Object Layer

오브젝트: "fog_zone_1"
  타입: "fog_zone"
  커스텀 프로퍼티:
    density = 0.7
    color = "white"

오브젝트: "cloud_spawner_1"
  타입: "cloud_spawner"
  커스텀 프로퍼티:
    spawn_rate = 2.0
    direction = "left"
```

### 2. 데이터 설정

**파일: `game/data/backgrounds.lua`**
```lua
return {
    forest_day = {
        {
            image = "assets/images/backgrounds/sky_day.png",
            parallax_x = 0.1,
            parallax_y = 0.05,
            auto_scroll_x = 5,    -- 초당 픽셀 (선택사항)
            auto_scroll_y = 0,
        },
        {
            image = "assets/images/backgrounds/clouds.png",
            parallax_x = 0.3,
            parallax_y = 0.2,
            auto_scroll_x = 20,
            auto_scroll_y = 0,
        },
        {
            image = "assets/images/backgrounds/mountains.png",
            parallax_x = 0.5,
            parallax_y = 0.4,
            auto_scroll_x = 0,    -- 고정
            auto_scroll_y = 0,
        },
    },

    cave = {
        {
            image = "assets/images/backgrounds/cave_wall.png",
            parallax_x = 0.3,
            parallax_y = 0.3,
            auto_scroll_x = 0,
            auto_scroll_y = 0,
        },
    },

    desert = {
        -- 사막 배경 레이어들...
    },
}
```

### 3. 엔진 시스템

**파일: `engine/systems/background.lua`** (새 파일)

**책임:**
- 래핑이 활성화된 배경 이미지 로드
- 자동 스크롤 오프셋 업데이트
- 패럴랙스가 적용된 무한 타일 배경 렌더링
- 카메라 기반 오프셋 계산 처리

**주요 함수:**
```lua
background:new()
background:addLayer(image_path, parallax_x, parallax_y, auto_scroll_x, auto_scroll_y)
background:update(dt)  -- 자동 스크롤 업데이트
background:draw(camera)  -- 패럴랙스 + 래핑으로 렌더링
```

**알고리즘:**
```
각 레이어마다:
  1. 오프셋 계산 = camera.pos * parallax + auto_scroll
  2. 무한 래핑을 위해 modulo 적용: offset % image_size
  3. 화면을 덮도록 이미지 타일 그리기 + 오버랩
```

### 4. 통합 지점

#### `engine/scenes/gameplay.lua`
```lua
function gameplay:init(map_path, spawn_x, spawn_y)
    -- 맵 로드
    local map = sti(map_path)

    -- Tiled 맵 프로퍼티에서 배경 테마 읽기
    local bg_theme = map.properties.background or "default"

    -- 배경 설정 로드 (game/에서 주입됨)
    if self.background_configs and self.background_configs[bg_theme] then
        self.background = background:new()
        for _, layer_cfg in ipairs(self.background_configs[bg_theme]) do
            self.background:addLayer(
                layer_cfg.image,
                layer_cfg.parallax_x,
                layer_cfg.parallax_y,
                layer_cfg.auto_scroll_x,
                layer_cfg.auto_scroll_y
            )
        end
    end

    -- 기존 초기화...
end

function gameplay:update(dt)
    if self.background then
        self.background:update(dt)
    end
    -- 기존 업데이트...
end

function gameplay:draw()
    -- 1. 무한 스크롤 배경 그리기 (가장 뒤)
    if self.background then
        self.background:draw(camera)
    end

    -- 2. Tiled 정적 패럴랙스 레이어 그리기
    for _, layer in ipairs(map.layers) do
        if layer.type == "tilelayer" and layer.properties.parallax then
            local p = layer.properties.parallax
            -- 패럴랙스 오프셋으로 렌더링...
        end
    end

    -- 3. 월드 그리기 (엔티티, 충돌)
    world:render(camera)

    -- 4. 동적 효과 그리기 (날씨, 안개)
    -- ...

    -- 5. HUD 그리기
    hud:draw()
end
```

#### `main.lua` (의존성 주입)
```lua
local bg_configs = require "game.data.backgrounds"
local gameplay_scene = require "engine.scenes.gameplay"

-- 엔진에 배경 설정 주입
gameplay_scene.background_configs = bg_configs
```

---

## 렌더링 순서 (뒤에서 앞으로)

```
1. 무한 스크롤 배경 (engine/systems/background.lua)
   ├─ 하늘 레이어 (parallax=0.1, 자동 스크롤)
   ├─ 구름 (parallax=0.3, 자동 스크롤)
   └─ 먼 산 (parallax=0.5)

2. Tiled 정적 패럴랙스 레이어 (engine/systems/world/rendering.lua)
   ├─ BG_Castle (parallax=0.4, 위치 고정)
   └─ BG_Trees (parallax=0.6, 위치 고정)

3. Tiled 지면 레이어 (parallax=1.0)

4. 엔티티 (플레이어, 적, NPC)

5. 동적 효과 (안개, 날씨 파티클)

6. HUD
```

---

## 탑다운 게임 고려사항

### 탑다운용 패럴랙스 값:
- **미세한 값** 사용 (0.6 ~ 0.9) - 방향 감각 상실 방지
- 수평(X) 패럴랙스가 수직(Y)보다 자연스러움
- 강한 패럴랙스는 탑다운 뷰에서 잘못된 원근감 생성

### 권장 설정:
```lua
-- 탑다운 친화적 패럴랙스
{
    parallax_x = 0.7,  -- 미묘한 수평 이동
    parallax_y = 0.9,  -- 최소한의 수직 이동
}

-- 탑다운에서 피할 것:
{
    parallax_x = 0.3,  -- 너무 강함, 이상해 보임
    parallax_y = 0.3,  -- 잘못된 깊이감 생성
}
```

### 탑다운에 좋은 사용 사례:
- ✅ 대기 요소 (구름, 안개)
- ✅ 먼 랜드마크 (지평선의 산)
- ✅ 물결 효과
- ❌ 강한 깊이 레이어 (부자연스러움)

---

## 에셋 준비

### 배경 이미지 요구사항:
1. **끊김 없는 타일링** - 왼쪽 끝이 오른쪽 끝과 일치, 위가 아래와 일치
2. **2의 제곱수 크기** - 512x512, 1024x512, 2048x1024 (GPU 친화적)
3. **압축 저항성** - 밴딩을 일으키는 그라디언트 피하기
4. **일관된 아트 스타일** - 게임의 비주얼 테마와 일치

### 끊김 없는 텍스처 제작 도구:
- GIMP: Filters → Map → Make Seamless
- Photoshop: Filter → Other → Offset (수동 체크)
- Krita: Wrap-around 모드 (W 키)

---

## 예시 워크플로우

### 시나리오: 숲 맵 추가하기

#### 1단계: 에셋 준비
```
assets/images/backgrounds/
  ├─ forest_sky.png      (1024x512, 끊김 없음)
  ├─ forest_clouds.png   (512x256, 끊김 없음)
  └─ forest_hills.png    (1024x512, 끊김 없음)
```

#### 2단계: `game/data/backgrounds.lua`에 설정
```lua
forest_day = {
    { image = "assets/images/backgrounds/forest_sky.png", parallax_x = 0.1, auto_scroll_x = 3 },
    { image = "assets/images/backgrounds/forest_clouds.png", parallax_x = 0.3, auto_scroll_x = 15 },
    { image = "assets/images/backgrounds/forest_hills.png", parallax_x = 0.5, auto_scroll_x = 0 },
}
```

#### 3단계: Tiled에서 설정
```
Map → Map Properties → Add Property:
  Name: background
  Type: string
  Value: forest_day
```

#### 4단계: (선택사항) Tiled에 정적 요소 추가
```
레이어: BG_Castle
  프로퍼티: parallax = 0.4
  내용: x=2000, y=500에 성 타일 배치
```

#### 5단계: 테스트
```bash
love .
```

카메라 이동 시 다음이 보여야 함:
- 하늘은 거의 안 움직임 (parallax=0.1)
- 구름은 흐름 + 패럴랙스 (auto_scroll + camera)
- 언덕은 절반 속도로 움직임 (parallax=0.5)
- Tiled 성은 올바른 위치에 있음

---

## 향후 개선사항

### 가능한 추가 기능:
- **시간대 전환** - 낮/밤 배경 블렌딩
- **날씨 통합** - 비 파티클 + 어두운 구름
- **셰이더 효과** - 열기 왜곡, 수중 왜곡
- **수직 패럴랙스** - 플랫포머 모드용 (탑다운과 다름)
- **배경 이벤트** - 새 날아다님, 먼 번개

### 성능 최적화:
- 배치 드로잉 (반복 타일에 SpriteBatch 사용)
- 지연 로딩 (맵 전환 시 배경 로드)
- 캔버스 캐싱 (정적 패럴랙스 레이어 사전 렌더링)

---

## 테스트 체크리스트

- [ ] Tiled 맵 프로퍼티에서 배경이 올바르게 로드됨
- [ ] 무한 스크롤 작동 (이음새/간격 없음)
- [ ] 카메라 이동 시 패럴랙스 효과 보임
- [ ] 자동 스크롤 작동 (구름 흐름)
- [ ] 성능 저하 없음 (60 FPS 유지)
- [ ] 정적 Tiled 레이어가 올바른 깊이 순서로 렌더링됨
- [ ] 맵 전환 시 배경 변경됨
- [ ] 탑다운/플랫포머 모드 모두 작동
- [ ] 엣지 케이스: 월드 경계의 카메라, 맵 모서리

---

## 아키텍처 준수

### Engine/Game 분리:
- ✅ `engine/systems/background.lua` - 범용 시스템 (게임 콘텐츠 없음)
- ✅ `game/data/backgrounds.lua` - 게임 특화 설정
- ✅ `main.lua` - 의존성 주입 지점
- ✅ Tiled 맵 - 레벨별 배경 선택

### 재사용성:
- ✅ `engine/` 복사해서 새 프로젝트로
- ✅ 새 `game/data/backgrounds.lua` 생성
- ✅ Tiled 맵에 `background` 프로퍼티 설정
- ✅ 완료! 엔진 코드 변경 불필요

---

## 구현 우선순위

### 1단계: 핵심 시스템 (최소)
1. `engine/systems/background.lua` 생성 (기본 무한 스크롤)
2. `game/data/backgrounds.lua` 생성 (테스트 테마 하나)
3. `engine/scenes/gameplay.lua` 수정 (로드 + 렌더링)
4. 맵 하나로 테스트

### 2단계: Tiled 통합
1. Tiled 맵에서 `background` 프로퍼티 읽기
2. 정적 패럴랙스 레이어 지원 (Tiled 타일 레이어)
3. 여러 배경 테마 추가

### 3단계: 다듬기
1. 자동 스크롤 애니메이션
2. 동적 효과 영역 (안개, 날씨)
3. 시간대 전환
4. 성능 최적화

---

## 구현 전 답해야 할 질문들

1. **어떤 맵에 배경이 필요한가?**
   - 모든 야외 맵? 특정 맵만?

2. **아트 스타일은?**
   - 픽셀 아트 또는 HD? (끊김 없는 타일링 난이도에 영향)

3. **성능 목표는?**
   - 모바일 (최적화) 또는 데스크톱만?

4. **동적 기능은?**
   - 단순 정적 스크롤만, 또는 날씨/시간 변화?

5. **기존 에셋은?**
   - 현재 타일셋 이미지 재사용 가능, 또는 새 아트 필요?

---

**마지막 업데이트:** 2025-11-10
**상태:** 설계 단계 (미구현)
**의존성:** `engine/core/camera.lua`, `engine/core/display/`, `engine/scenes/gameplay.lua`
