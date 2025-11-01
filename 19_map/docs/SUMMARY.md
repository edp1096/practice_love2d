# 인간형 몬스터 추가 완료

## 요약
기존 슬라임 몬스터 시스템에 인간형 몬스터(8방향 이동, player/npc와 동일한 이동 시스템)를 추가했습니다.

## 추가된 인간형 몬스터 타입

### 1. Bandit (도적)
- 체력: 120
- 속도: 120
- 공격력: 15
- 균형잡힌 기본 적

### 2. Rogue (자객)
- 체력: 100
- 속도: 150 (가장 빠름)
- 공격력: 12
- 특징: 빠르지만 약함, 검은색 외형

### 3. Warrior (전사)
- 체력: 150 (가장 높음)
- 속도: 100 (가장 느림)
- 공격력: 20 (가장 높음)
- 특징: 탱커형, 붉은색 외형

### 4. Guard (경비병)
- 체력: 140
- 속도: 110
- 공격력: 18
- 특징: 균형잡힌 방어형

## 핵심 기능

### 이동 시스템
- **8방향 자유 이동**: player를 향해 대각선 포함 모든 방향으로 이동
- **4방향 애니메이션**: 실제 표시는 상하좌우 4방향
- player, npc와 동일한 이동 메커니즘

### 공격 시스템
- player와 유사한 공격 방식
- 공격 범위 내 진입 시 자동 공격
- 4방향 공격 애니메이션 (up, down, left, right)
- 각 타입별 고유 공격 쿨다운

## 사용 방법

### 방법 1: 맵 파일에 추가
맵의 Enemies 레이어에 오브젝트 추가 (예시는 `test_humanoid_enemies.lua` 참조)

### 방법 2: 프로그래밍 방식으로 생성
```lua
-- play.lua에서
local enemy_spawner = require "utils.enemy_spawner"

-- 개별 생성
enemy_spawner:spawnEnemy(self.world, "bandit", 800, 400)

-- 그룹 생성 (4마리가 진형을 이루어 생성)
enemy_spawner:spawnHumanoidGroup(self.world, 1000, 800)
```

## 주요 파일

### 새로 추가된 파일
1. `entities/enemy/types/humanoid.lua` - 인간형 적 타입 정의
2. `utils/enemy_spawner.lua` - 프로그래밍 방식 생성 유틸리티
3. `test_humanoid_enemies.lua` - 맵 추가 예제
4. `EXAMPLE_SPAWN_HUMANOID.lua` - 코드 사용 예제
5. `README_HUMANOID.md` - 상세 문서
6. `CHANGELOG_HUMANOID.md` - 변경 내역

### 수정된 파일
1. `entities/enemy/init.lua` - 인간형 적 지원 추가
2. `entities/enemy/ai.lua` - 8방향 이동 로직 추가

## 호환성
- ✅ 기존 슬라임 적 완벽 호환
- ✅ 기존 맵 수정 불필요
- ✅ 기존 코드 영향 없음

## 테스트 방법
1. 게임 실행
2. `EXAMPLE_SPAWN_HUMANOID.lua`의 코드를 `scenes/play.lua`에 추가
3. 또는 `test_humanoid_enemies.lua`를 참고하여 맵 파일에 적 추가

## 특징
- 8방향 자유 이동 (player/npc와 동일)
- 4방향 애니메이션 자동 전환
- 순찰, 추적, 공격 AI 완비
- 컬러 스왑 지원 (rogue, warrior)
- 타입별 차별화된 스탯

모든 인간형 적은 player-sheet.png 또는 passerby_01-sheet.png 스프라이트를 사용합니다.
