# 🗺️ Map Creation Guide

Tiled 맵 에디터를 사용한 맵 제작 완벽 가이드

---

## 📋 목차

1. [기본 설정](#기본-설정)
2. [필수 레이어](#필수-레이어)
3. [오브젝트 레이어](#오브젝트-레이어)
4. [맵 속성](#맵-속성)
5. [패럴랙스 배경](#패럴랙스-배경-parallax-backgrounds-)
6. [워크플로우](#워크플로우)
7. [예제](#예제)

---

## 기본 설정

### 맵 생성
- **파일 형식**: TMX (Tiled Map Editor)
- **타일 크기**: 32x32 (권장)
- **저장 위치**: `assets/maps/levelX/`
- **명명 규칙**: `areaX.tmx` (예: area1.tmx, area2.tmx)

### 내보내기
Tiled에서 작업 후 반드시 Lua 형식으로 내보내기:
1. File → Export As... → Lua files (*.lua)
2. 같은 폴더에 `.lua` 파일 생성 (예: area1.lua)
3. 게임은 `.lua` 파일을 로드합니다

---

## 필수 레이어

### 1. **Ground** (Tile Layer)
- **타입**: Tile Layer
- **용도**: 바닥 타일 (땅, 잔디, 돌바닥 등)
- **렌더링**: 가장 먼저 그려짐 (배경)

### 2. **Trees** (Tile Layer)
- **타입**: Tile Layer
- **용도**: 나무, 건물 등 엔티티 위에 그려질 장식
- **렌더링**: 엔티티보다 나중에 그려짐 (Y-sorting 후)

### 3. **Walls** (Object Layer)
- **타입**: Object Layer
- **용도**: 충돌 영역 (벽, 장애물)
- **지원 형태**:
  - Rectangle (사각형)
  - Polygon (다각형)
  - Polyline (선)
  - Ellipse (원)

**주의사항**:
- 모든 Walls 오브젝트는 정적 충돌체로 변환됨
- Platformer 모드에서는 friction이 0으로 설정됨

---

## 오브젝트 레이어

### 4. **Portals** (Object Layer)
맵 전환 및 특수 이벤트 영역

#### Portal (일반 맵 전환)
- **Type**: `portal`
- **Properties**:
  - `target_map` (string): 이동할 맵 경로 (예: "assets/maps/level1/area2.lua")
  - `spawn_x` (number): 도착 위치 X
  - `spawn_y` (number): 도착 위치 Y

#### Game Clear
- **Type**: `gameclear`
- **Properties**: 없음
- **효과**: 게임 클리어 화면으로 전환

#### Intro (컷신 전환)
- **Type**: `intro`
- **Properties**:
  - `intro_id` (string): 컷신 ID (예: "level1", "boss_intro")
  - `target_map` (string): 컷신 후 이동할 맵
  - `spawn_x`, `spawn_y`: 컷신 후 스폰 위치

#### Ending (엔딩 컷신)
- **Type**: `ending`
- **Properties**:
  - `intro_id` (string): 엔딩 컷신 ID (예: "ending")

---

### 5. **Enemies** (Object Layer)
적 스폰 위치

#### 기본 설정
- **Object 크기**: 적 종류에 따라 다름 (주로 64x64)
- **Properties**:
  - `type` (string): 적 타입 (예: "green_slime", "humanoid")
  - `patrol_points` (string, optional): 순찰 포인트 (상대 좌표)

#### Patrol Points 형식
```
patrol_points = "0,0;100,0;100,100;0,100"
```
- 세미콜론(`;`)으로 포인트 구분
- 각 포인트는 `x,y` 형식 (오브젝트 기준 상대 좌표)
- 미지정 시: 오브젝트 중심 기준 50픽셀 반경 사각형 순찰

---

### 6. **NPCs** (Object Layer)
NPC 배치

#### 기본 설정
- **Object 크기**: 64x128 (width x height)
- **Properties**:
  - `type` (string): NPC 타입 (예: "villager")
  - `id` (string): 고유 ID (대화 내용 구분용)

#### NPC 타입별 설정
현재 지원: `villager`
- 새 NPC 타입은 `entities/npc/types/` 폴더에 추가

---

### 7. **SavePoints** (Object Layer)
세이브 포인트 배치

#### 기본 설정
- **Object 크기**: 자유 (보통 64x64)
- **Properties**:
  - `type` (string): "savepoint" (필수)
  - `id` (string, optional): 고유 ID

#### 동작
- 플레이어가 F 키 또는 A 버튼으로 상호작용
- 현재 상태를 슬롯에 저장
- 상호작용 범위: 80픽셀

---

### 8. **HealingPoints** (Object Layer)
체력 회복 지점

#### 기본 설정
- **Object 크기**: 영역 크기 (예: 100x100)
- **Properties**:
  - `type` (string): "healing_point" (필수)
  - `heal_amount` (number): 회복량 (기본값: 50)
  - `radius` (number): 효과 반경 (기본값: 오브젝트 크기의 절반)
  - `cooldown` (number): 재사용 대기 시간 초 (기본값: 5.0)

#### 예제
```
heal_amount = 30
radius = 80
cooldown = 10.0
```
- 반경 80픽셀 내에서 30 HP 회복
- 10초 후 다시 사용 가능

자세한 내용: [HEALTH_RECOVERY_README.md](HEALTH_RECOVERY_README.md)

---

### 9. **DeathZones** (Object Layer) ⚠️
즉시 사망 영역

#### 기본 설정
- **Object 크기/형태**: 자유 (Rectangle, Polygon, Ellipse)
- **Properties**: 없음

#### 용도
- 절벽, 구멍, 용암
- 떨어지면 즉시 사망하는 영역
- Topdown 모드: 바닥의 구멍
- Platformer 모드: 낭떠러지

#### 동작
- 플레이어가 닿는 순간 health = 0
- 물리 충돌 없음 (sensor collider)
- Game Over 화면으로 전환

---

### 10. **DamageZones** (Object Layer) 🔥
지속 피해 영역

#### 기본 설정
- **Object 크기/형태**: 자유 (Rectangle, Polygon, Ellipse)
- **Properties**:
  - `damage` (number): 한 번당 피해량 (기본값: 10)
  - `cooldown` (number): 피해 간격 초 (기본값: 1.0)

#### 예제 설정
**가시 함정**:
```
damage = 20
cooldown = 1.0
```
높은 피해, 느린 주기

**불 영역**:
```
damage = 5
cooldown = 0.5
```
중간 피해, 중간 주기

**독가스**:
```
damage = 3
cooldown = 0.3
```
낮은 피해, 빠른 주기

#### 동작
- 플레이어가 영역 안에 있는 동안 주기적 피해
- 각 zone마다 독립적인 쿨다운
- Parry/Dodge로 막을 수 없음
- 물리 충돌 없음 (자유롭게 이동 가능)

---

## 맵 속성

Tiled에서 Map → Map Properties 설정

### 필수 속성

#### 1. **game_mode** (string)
게임 모드 설정 (필수)

**값**:
- `"topdown"`: 탑다운 모드 (중력 없음)
- `"platformer"`: 플랫포머 모드 (중력 있음)

**예제**:
```
game_mode = "topdown"
```

#### 2. **bgm** (string, optional)
배경 음악 지정

**값**: BGM 이름 (`data/sounds.lua`에 정의된 이름)

**예제**:
```
bgm = "boss"
```

**자동 BGM 시스템**:
- 미지정 시: 맵이 위치한 폴더 이름으로 BGM 자동 선택
- `assets/maps/level2/area1.lua` → "level2" BGM 재생
- `assets/maps/level3/area1.lua` → "level3" BGM 재생

자세한 내용: [BGM_GUIDE.md](BGM_GUIDE.md)

---

## 패럴랙스 배경 (Parallax Backgrounds) 🌌

하늘, 구름, 산 등의 배경을 추가하여 깊이감을 줄 수 있습니다.

### 패럴랙스란?
카메라가 움직일 때 배경이 전경보다 천천히 움직여서 깊이감을 만드는 효과입니다.
- **parallax = 0.0**: 배경 고정 (움직이지 않음, 하늘에 적합)
- **parallax = 0.5**: 카메라의 절반 속도로 움직임 (먼 산에 적합)
- **parallax = 1.0**: 카메라와 같은 속도 (일반 레이어, 패럴랙스 없음)

### Tiled에서 패럴랙스 배경 추가

#### 1. Image Layer 추가
1. Tiled에서 Layer → New → Image Layer
2. 레이어 이름 지정 (예: "Sky", "Clouds", "Mountains")
3. 레이어 순서 조정 (배경이 가장 위로, Ground보다 아래)

#### 2. 이미지 선택
1. 생성한 Image Layer 선택
2. Properties 패널에서 "Image" 클릭
3. 배경 이미지 파일 선택 (PNG, JPG 등)

**권장 이미지 크기**:
- 타일맵 크기보다 크거나 같게 (반복 타일링)
- 예: 맵이 1280x720이면 이미지도 1280x720 이상

#### 3. Parallax 속성 설정
Image Layer를 선택하고 Layer Properties에서 Custom Properties 추가:

**필수 속성**:
- **parallax_x** (float): X축 스크롤 비율 (0.0 ~ 1.0)
- **parallax_y** (float): Y축 스크롤 비율 (0.0 ~ 1.0)

**선택 속성**:
- **z_order** (number): 렌더링 순서 (낮을수록 먼저 그려짐, 기본값: 0)

#### 4. 예제 설정

**하늘 배경** (고정):
```
parallax_x = 0.0
parallax_y = 0.0
z_order = -100
```
- 카메라가 움직여도 하늘은 고정
- 가장 먼저 그려짐 (다른 배경보다 뒤)

**먼 산** (느린 스크롤):
```
parallax_x = 0.3
parallax_y = 0.3
z_order = -50
```
- 카메라의 30% 속도로 움직임
- 하늘보다 앞, 구름보다 뒤

**구름** (중간 스크롤):
```
parallax_x = 0.5
parallax_y = 0.2
z_order = -30
```
- X축 50%, Y축 20% 속도
- 산보다 앞, Ground보다 뒤

**가까운 나무/풀** (빠른 스크롤):
```
parallax_x = 0.8
parallax_y = 0.8
z_order = -10
```
- 카메라의 80% 속도로 움직임
- Ground 바로 뒤에 그려짐

### 레이어 순서 예제

올바른 레이어 순서 (Tiled에서 위에서 아래로):
```
레이어 목록:
1. Sky (Image Layer)          parallax_x=0.0, z_order=-100
2. Mountains (Image Layer)    parallax_x=0.3, z_order=-50
3. Clouds (Image Layer)       parallax_x=0.5, z_order=-30
4. Ground (Tile Layer)        (패럴랙스 없음)
5. Trees (Tile Layer)         (패럴랙스 없음)
6. Walls (Object Layer)
7. ... (기타 오브젝트 레이어들)
```

**주의**: Tiled의 레이어 순서와 z_order는 별개입니다. z_order가 실제 렌더링 순서를 결정합니다.

### 하늘섬 맵 예제

**시나리오**: 하늘에 떠있는 섬, 아래는 구름과 하늘

**레이어 구성**:
1. **Sky** (Image Layer)
   - 이미지: 파란 하늘 그라데이션
   - `parallax_x = 0.0, parallax_y = 0.0, z_order = -100`

2. **Clouds_Far** (Image Layer)
   - 이미지: 먼 구름층
   - `parallax_x = 0.2, parallax_y = 0.1, z_order = -50`

3. **Clouds_Near** (Image Layer)
   - 이미지: 가까운 구름
   - `parallax_x = 0.4, parallax_y = 0.2, z_order = -30`

4. **Ground** (Tile Layer)
   - 하늘섬의 땅 타일

5. **Trees** (Tile Layer)
   - 나무, 건물 등

6. **DeathZones** (Object Layer)
   - 섬 가장자리에 배치 (떨어지면 즉사)

**효과**:
- 플레이어가 섬을 이동하면 구름들이 다른 속도로 움직임
- 하늘은 고정되어 안정감 제공
- 깊이감으로 하늘에 떠있는 느낌 강화

### Platformer 하늘섬 예제

**추가 고려사항**:
- 플랫폼 아래에 DeathZone 배치 (떨어지면 사망)
- 배경에 아래로 펼쳐진 구름바다
- Y축 패럴랙스를 X축보다 낮게 설정 (수평 이동이 많으므로)

**레이어 구성**:
1. **Sky** (Image Layer)
   - `parallax_x = 0.0, parallax_y = 0.0`

2. **Cloud_Sea** (Image Layer) - 아래쪽 구름바다
   - `parallax_x = 0.3, parallax_y = 0.15`
   - 맵 아래쪽에 배치

3. **Ground** (Tile Layer) - 플랫폼

4. **DeathZones** (Object Layer)
   - 맵 아래 전체에 긴 사각형 배치

### 팁 & 주의사항

**이미지 준비**:
- 이미지는 타일링 가능하도록 양쪽 끝이 매끄럽게 연결되어야 함
- PNG 포맷 권장 (투명도 지원)
- 파일 크기가 너무 크면 메모리 소모 증가 주의

**성능**:
- Image Layer는 매 프레임 그려지므로 너무 많으면 성능 저하
- 보통 2~4개 패럴랙스 레이어 권장
- z_order로 정렬되므로 순서 중요

**parallax 값 선택**:
- 0.0 (고정) - 하늘, 별
- 0.1 ~ 0.3 (매우 느림) - 매우 먼 산, 먼 구름
- 0.4 ~ 0.6 (느림) - 중간 거리 배경
- 0.7 ~ 0.9 (거의 빠름) - 가까운 배경
- 1.0 (일반) - 패럴랙스 없음 (사용 안 함)

**topdown vs platformer**:
- **Topdown**: X, Y축 패럴랙스 같게 (모든 방향 이동)
- **Platformer**: X축 패럴랙스 > Y축 (주로 좌우 이동)

---

## 워크플로우

### 새 맵 제작 순서

1. **Tiled에서 맵 생성**
   - 적절한 타일 크기 선택 (32x32 권장)
   - 맵 크기 설정 (예: 40x30 타일)

2. **필수 레이어 추가**
   - Ground (Tile Layer)
   - Trees (Tile Layer)
   - Walls (Object Layer)

3. **타일 배치**
   - Ground 레이어에 바닥 타일 배치
   - Trees 레이어에 장식 타일 배치

4. **충돌 영역 설정**
   - Walls 레이어에 벽/장애물 오브젝트 배치
   - 다양한 형태 활용 (사각형, 다각형 등)

5. **게임 오브젝트 배치**
   - 필요에 따라 오브젝트 레이어 추가:
     - Portals (맵 전환)
     - Enemies (적 배치)
     - NPCs (NPC 배치)
     - SavePoints (세이브 포인트)
     - HealingPoints (회복 지점)
     - DeathZones (즉사 영역)
     - DamageZones (피해 영역)

6. **맵 속성 설정**
   - Map Properties에서 `game_mode` 설정 (필수)
   - 필요시 `bgm` 지정

7. **Lua로 내보내기**
   - File → Export As... → Lua files (*.lua)
   - 같은 폴더에 `.lua` 파일 생성 확인

8. **게임에서 테스트**
   - 게임 실행 후 맵 로드 확인
   - 충돌, 전환, 오브젝트 정상 작동 확인

---

## 예제

### Example 1: 간단한 Topdown 맵

**맵 구조**:
```
레이어:
- Ground: 잔디 타일
- Trees: 나무 장식
- Walls: 테두리 벽
- Portals: 다음 맵으로 가는 포탈
- Enemies: 슬라임 3마리
```

**맵 속성**:
```
game_mode = "topdown"
bgm = "level1"
```

**Portal 오브젝트**:
```
type = "portal"
target_map = "assets/maps/level1/area2.lua"
spawn_x = 100
spawn_y = 100
```

---

### Example 2: 함정이 있는 Platformer 맵

**맵 구조**:
```
레이어:
- Ground: 플랫폼 타일
- Trees: 배경 장식
- Walls: 플랫폼 충돌체
- DeathZones: 낭떠러지 (즉사)
- DamageZones: 가시 함정 (지속 피해)
- Enemies: 휴머노이드 적
- SavePoints: 체크포인트
```

**맵 속성**:
```
game_mode = "platformer"
```

**DeathZone 설정**:
- 맵 아래쪽 전체에 긴 사각형 배치
- 속성 없음 (닿으면 즉사)

**DamageZone 설정** (가시 함정):
```
damage = 15
cooldown = 1.5
```

**SavePoint**:
```
type = "savepoint"
id = "checkpoint_1"
```

---

### Example 3: Boss 전투 맵

**맵 구조**:
```
레이어:
- Ground: 아레나 바닥
- Trees: 기둥 장식
- Walls: 아레나 경계
- DamageZones: 용암 웅덩이
- Portals: 승리 후 전환 (gameclear)
- Enemies: Boss 적 1마리
```

**맵 속성**:
```
game_mode = "topdown"
bgm = "boss"
```

**DamageZone** (용암):
```
damage = 8
cooldown = 0.5
```

**Portal** (클리어):
```
type = "gameclear"
```

---

## 팁 & 주의사항

### 일반 팁
- **레이어 순서**: Tiled에서 레이어 순서는 중요하지 않음 (코드에서 지정된 순서로 렌더링)
- **오브젝트 이름**: 오브젝트에 이름을 붙이면 디버깅이 쉬워짐
- **색상 구분**: Tiled에서 레이어별로 색상을 다르게 하면 편리함
- **그리드 활성화**: View → Show Grid로 정렬 쉽게

### 충돌 설정
- **Walls**: 복잡한 형태는 Polygon 사용
- **Zone**: 영역이 정확해야 함 (너무 작거나 크지 않게)
- **Polyline**: 경사로나 곡선 벽에 유용

### 성능 최적화
- 큰 맵은 여러 개의 작은 맵으로 분할
- 불필요한 오브젝트는 최소화
- 타일셋은 적절한 크기로 (너무 크면 메모리 소모)

### 게임 모드별 주의사항

**Topdown**:
- 바닥에 구멍 표현: DeathZone 사용
- 적은 8방향 이동

**Platformer**:
- 플랫폼 간 거리 주의 (점프 가능 거리)
- 낭떠러지: DeathZone 맵 아래에 배치
- 적은 좌우 이동만

---

## 문제 해결

### 맵이 로드되지 않음
1. `.lua` 파일로 내보냈는지 확인
2. 파일 경로가 올바른지 확인
3. 맵 속성에 `game_mode` 설정했는지 확인

### 충돌이 작동하지 않음
1. Walls 레이어가 "Object Layer"인지 확인
2. 오브젝트가 너무 작지는 않은지 확인
3. 복잡한 Polygon은 단순화

### 포탈이 작동하지 않음
1. Portals 레이어의 오브젝트 `type` 속성 확인
2. `target_map` 경로가 정확한지 확인 (`.lua` 파일 경로)
3. `spawn_x`, `spawn_y` 값이 숫자인지 확인

### 적이 스폰되지 않음
1. Enemies 레이어 존재 확인
2. 오브젝트 `type` 속성이 올바른지 확인
3. 적 타입이 `entities/enemy/types/`에 존재하는지 확인

### Zone이 작동하지 않음
1. 레이어 이름이 정확한지 확인 (대소문자 구분)
   - `DeathZones` (복수형)
   - `DamageZones` (복수형)
2. DamageZone의 속성이 숫자(number) 타입인지 확인
3. Zone 오브젝트가 플레이어와 겹치는지 확인

---

## 관련 문서

- **BGM 설정**: [BGM_GUIDE.md](BGM_GUIDE.md)
- **체력 회복**: [HEALTH_RECOVERY_README.md](HEALTH_RECOVERY_README.md)
- **프로젝트 구조**: [MEMO.md](MEMO.md)
- **개발자 가이드**: [../CLAUDE.md](../CLAUDE.md)

---

**Last Updated**: 2025-11-03
