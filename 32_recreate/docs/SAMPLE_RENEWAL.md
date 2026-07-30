# 30·31 샘플 복원과 리뉴얼 계획

기준일: 2026-07-30

## 목적

`30_misc`는 실제로 돌아가는 작은 게임의 형태를 만들었고,
`31_dev_proto`는 그 게임에 화면·상태 제어와 자동화를 붙였다.
`32_recreate`는 로직을 제작 데이터 중심으로 다시 설계했지만, 재작성
초기에 마을의 공간감과 집·상점 같은 플레이 동선이 줄어들었다.

이 문서의 원칙은 다음과 같다.

- 제작 원본과 게임 규칙의 기준은 `32_recreate`다.
- `33_ebitengine_spike`는 같은 canonical 콘텐츠를 실행하는 두 번째
  런타임이지 별도 게임 원본이 아니다.
- `30_misc`의 맵·애셋·게임 흐름과 `31_dev_proto`의 자동화 계약은
  회귀 기준으로 사용한다.
- 과거 코드 구조나 하드코딩 좌표는 복사하지 않고 현재 stage, rule,
  protocol schema로 옮긴다.

## 기준 프로젝트에서 가져올 것

| 기준 | 보존할 내용 | 옮기는 형식 |
| --- | --- | --- |
| `30_misc` | 타일 기반 마을, 집·상점 실내, NPC와 출입 동선 | TMX → generated stage |
| `30_misc` | 플레이어·안내인·상인·슬라임·타일 애셋 | 검증된 runtime asset ID |
| `30_misc` | 타이틀부터 결말까지 이어지는 작은 게임 형태 | campaign content와 portal |
| `31_dev_proto` | 의미 입력, 월드 검사, 좌표·체력 제어, 화면 캡처 | 안정적인 debug protocol |
| `31_dev_proto` | 실제 화면과 semantic state를 함께 보는 검사 | `lovectl campaign` |

가져오지 않는 것은 맵 이름 의존 로직, 숫자 좌표를 박아 둔 자동화,
런타임에서 TMX를 해석하는 코드, 한 게임의 ID를 엔진에 직접 넣는
코드다.

## 30·31 실제 구성 감사

`30_misc`와 `31_dev_proto`는 게임 데이터와 맵이 사실상 같다.
`31_dev_proto`에서 추가된 핵심은 debug bridge·inspector, 안전한 save
codec, Go `lovectl`과 자동 테스트이며 별도 캠페인 콘텐츠는 아니다.
따라서 샘플의 형태는 30을, 외부 제어 계약은 31을 기준으로 판단한다.

30의 플레이 공간은 다음 일곱 맵으로 구성된다.

| 공간 | 실제 구성 |
| --- | --- |
| `level1/area1` | 낮의 시작 지역, 슬라임 4, 집·상점·area2·area4 분기, 저장점, 계단, 피해·사망 구역, 월드 아이템, 탈것 |
| `level1/area2` | 밤 배경과 4중 parallax, bandit 1, area1·area3·area4 연결, 저장점 |
| `level1/area3` | 횡스크롤 구간, 슬라임 2, 경사면, 회복점, NPC, level2 도입 컷신 |
| `level1/area4` | 마을형 공간, 슬라임 2, 주민·탈것 상인, 탈것, 피해 구역, 저장점 |
| `level1/home1` | 실내, 퀘스트 NPC, 회복점 2, 이동·파괴 가능한 장식 |
| `level1/shop1` | 실내, 상인과 상점, 이동·파괴 가능한 장식 |
| `level2/area1` | 짧은 후속 공간과 ending portal |

데이터 카탈로그는 퀘스트 16개, 대화 7개, 아이템 12개, 상점 1개,
컷신 6개, 적 타입 9개와 탈것 7개를 선언한다. 그러나 이 전체가 한
캠페인에서 모두 배치·완결된 것은 아니다. 존재하지 않는 level3
배경을 참조하는 미래 컷신, 맵에 없는 giver NPC를 요구하는 퀘스트,
테스트용 적·탈것 정의도 함께 들어 있다. “파일이 있다”와 “완전한
샘플에서 실제 사용한다”를 구분해야 한다.

이 감사에 따른 이식 분류는 다음과 같다.

- 루트 샘플에 반드시 유지: 타이틀·새 게임·이어하기, 연결된 야외와
  실내, 실제 NPC, 대화·의뢰·상점·회복, 실시간 전투와 보스, 귀환
  보고, 저장·게임오버·엔딩, 다국어와 장소별 음악.
- 엔진 fixture와 생성 profile로 증명: 플랫포머, projectile/status,
  encounter phase, 턴제 전투처럼 한 캠페인에 억지로 섞지 않아도 되는
  장르 기능.
- 다음 리뉴얼에서 일반화한 뒤 샘플에 선택적으로 사용: 여러 적 AI와
  보스 패턴, 월드 아이템·loot, 피해 구역, 이동·파괴 prop, 계단·
  parallax 같은 환경 기믹, kill 외의 퀘스트 목표.
- 그대로 복원하지 않음: 맵 이름에 묶인 날씨 전역 로직, 미완성
  level3, 배치되지 않은 16개 퀘스트 전체, 샘플 완주에 필요하지 않은
  탈것을 우선순위 없이 한꺼번에 옮기는 일.

현재 `32_recreate` 루트 샘플은 30보다 기능 전시 수는 적지만,
`village → home/shop → field → grove → return → ending`이라는 한
게임의 목표와 결말은 더 명확하다. 이후 확장은 이 완주 경로를
흐트러뜨리지 않고 위의 세 번째 분류를 하나씩 데이터화하는 방식으로
진행한다.

## 목표 캠페인

```text
title
  │
  ▼
village ◀──────────── return/report ───────────┐
  ├── village_home: rest trigger              │
  ├── village_shop: merchant/shop             │
  └── world_hub: field combat ── world_grove ─┘
                                      │
                                      └── guardian/quest reward
```

이 경로의 모든 이동은 portal ID와 target spawn ID로 연결한다.
자동화는 화면 좌표를 기억하지 않고 runtime inspector가 내보낸 portal
shape의 중심을 사용한다.

## 진행 상태

### R1. 공간과 동선 복원 — 완료

- [x] `30_misc`의 마을 3개 타일 레이어를 canonical `stage.village`로
  이식
- [x] 집과 잡화점 TMX, 실내 타일셋, 출입 portal과 spawn point 이식
- [x] 안내인은 마을, 상인은 잡화점 실내에 실제 sprite actor로 배치
- [x] 집에 data-authored 회복 trigger 배치
- [x] tilemap stage에서 semantic collision wall을 화면 도형으로
  중복 렌더링하지 않도록 LÖVE/Ebitengine 표현 정리
- [x] 좁은 실내 viewport에서 HUD를 적응형으로 배치
- [x] navigation inspector에 정렬된 spawn/trigger/portal geometry 공개
- [x] LÖVE 자동화가 title부터 도입 컷신·집·상점·저장·전투·귀환·
  접근성·엔딩·게임오버까지 22개 화면, 집의 실제 50→80 회복과 semantic
  상태를 검증
- [x] Ebitengine이 같은 65개 정의, 9개 stage와 집의 heal/숲의 emit
  trigger를 typed runtime으로 실행

### R2. 샘플 연출 강화 — 완료

- [x] 저장과 분리된 범용 `show_notice` action, 다국어 문장, 세 tone,
  modal pause와 semantic inspector 구현
- [x] 새 게임 도입, 들판 조작, 집 회복을 짧은 데이터 알림으로 안내
- [x] 실제 적 AI의 공격을 퍼펙트 패링하고 체력 무손실·적 경직·
  카메라 흔들림을 캠페인 안에서 검증
- [x] 마을, 들판, 숲에 서로 다른 원본 생성형 loop 음악 배치
- [x] 보스 진입 경고와 처치 보상, 퀘스트 수락·완료 알림
- [x] 완료 상태 전용 귀환 보고 대화와 다국어 전용 엔딩 화면 연결
- [x] 장비·보상 획득 알림, 상점 구매 메시지와 UI/quest 효과음을 실제
  화면·semantic 상태로 함께 검증

### R3. 제작자 입력 단순화 — 완료

- [x] 대화 node/choice와 quest objective·완료 보상을 카드 폼에서 연결
- [x] interaction과 일반 `actions` 배열에서 종류를 고르는 명령 builder
- [x] stage의 actor·spawn·trigger 수와 portal 목적지를 맵 카드로 검사
- [x] `lovectl init --profile`로 샘플 구조를 복제하는 project/template
  흐름
- [x] 목적별 필드를 먼저 보이고 전체 스키마·JSON을 접어 두는 단계별 UI
- [x] TMX actor·spawn 좌표와 trigger 조건·명령, portal 목적지를 Maker에서
  수정하고 전체 맵 compile·runtime reload 실패 시 원복

### R4. RPG·액션 제작 범위 확장 — 진행 중

- [x] 순수 RPG profile의 데이터 기반 턴제 전투와 의뢰 수락 → 전투 →
  보상 → 보고 → 엔딩 완주 예제
- [x] 순수 액션 profile의 자동 시작 encounter → 실시간 전투 → 엔딩 예제
- [x] 액션 RPG profile의 의뢰 수락 → 실시간 전투 → 보상 → 보고 →
  엔딩 예제
- [x] NPC interaction과 TMX trigger의 조건부 이벤트 page, Maker 편집,
  LÖVE/Ebitengine 공통 실행
- [x] 배경·다국어 step·자동 진행·안전한 건너뛰기·후속 action을 갖는
  컷신과 LÖVE/Ebitengine 공통 실행
- [x] 저장 가능한 시각·일자, 자정 횡단 시간 조건, 지역 진입·이탈,
  마지막 일치 page의 tint·tile layer·후속 action을 갖는 월드 변화와
  Maker/TMX/LÖVE/Ebitengine 공통 실행
- [x] 체력 단계·거리대·공전·스킬 순환을 갖는 데이터 기반 적 AI와
  보스 패턴을 LÖVE/Ebitengine 공통 콘텐츠로 실행
- [x] 30의 독병 애셋을 사용한 1회성 월드 아이템 event page와 재진입
  피해 구역을 범용 action/trigger 조합으로 실행
- [x] 실제 게임패드 버튼 이름으로 전체 플레이, 카메라 움직임·피격
  flash·알림 시간 접근성 설정과 새 게임/재시작 보존 검증
- [ ] Linux 완성 뒤 Windows·macOS·대상 콘솔별 배포 검증

## R1 인수 명령

```bash
cd 32_recreate
go run ./tools/lovectl check
go run ./tools/lovectl campaign

cd ../33_ebitengine_spike
go test -count=1 ./...
go run ./cmd/recreate \
  -no-debug -stage stage.village_home -spawn entry \
  -frames 2 -screenshot /tmp/recreate-home.png
```

R1 완료는 전체 Maker가 완성됐다는 뜻이 아니다. 현재는 재작성 과정에서
잃었던 “작지만 연결된 한 게임의 공간과 동선”을 복원하고, 두 런타임이
같은 데이터와 자동화 계약을 사용하게 만든 상태다. R2 자동 캠페인은
도입 컷신과 접근성 설정을 포함한 22개 화면과 실제 게임패드 입력
264 fixed tick으로 이 동선, 월드 아이템·피해 구역과 실제 패링
연출까지 검사한다.
다음 판단은 항상 R2~R4의 미완료 항목과
[SAMPLE_GAME.md](SAMPLE_GAME.md)의 완전한 게임 판정을 함께 본다.
