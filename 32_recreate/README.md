# 32_recreate

`32_recreate`는 RPG, 액션 RPG, 순수 액션을 같은 기반에서 만들기 위한
LÖVE 11.5용 2D 제작 런타임이다.

`31_dev_proto`의 코드를 복사해 정리하지 않는다. 기존 프로젝트는 동작
참조로 보존하고, 검증된 애셋과 동작만 새 콘텐츠 규격으로 옮긴다.

## 현재 상태

탑다운 액션, 플랫포머 액션, 월드 제작, RPG 수직 단면이 실행된다.

- 순수 데이터 콘텐츠 자동 탐색
- feature 의존성 조합
- actor + component 엔티티 구성
- 의미 기반 키보드·게임패드·자동화 입력
- 고정 60Hz 시뮬레이션
- 서로 독립적인 탑다운·플랫포머 이동
- 정적 geometry와 collision layer/mask 기반 동적 actor 충돌
- 체력, 적대 팀, 스킬 효과, 추적 AI
- 시간축 hitbox와 독립 hurtbox, 단발·제한 다단 적중
- 공격 예고·활성·후딜과 선택 가능한 이동 잠금
- 피격 경직·무적, 넉백, 히트스톱
- 방향성 패링·퍼펙트 패링, 이동형 무적 회피
- 발사체의 연속 충돌 판정·관통·벽 소멸
- 중첩·주기 효과·능력치 배율·면역을 갖는 상태 효과
- 데이터 기반 encounter·wave·boss phase
- 중력·가속·코요테 타임·점프 버퍼를 갖는 플랫포머 이동
- 기존 플레이어·슬라임·베기 애셋의 ID 기반 애니메이션
- TMX를 런타임 순수 Lua stage로 바꾸는 Go compiler
- Tiled class 기반 actor, 벽, trigger, portal, spawn point 배치
- 회전 사각형·polygon 정적 충돌
- ID 기반 양방향 stage 전환과 목적지 spawn point
- 큰 맵 tile culling과 플레이어 추적·경계 clamp camera
- stage 전환과 안전한 콘텐츠 reload를 통과해 유지되는 런타임 session
- feature별 버전·migration과 원자적 파일 교체를 갖는 transactional save
- 플래그, 인벤토리, 소비 아이템, 장비와 파생 스탯
- 조건·액션을 공유하는 NPC 상호작용과 다국어 대화 graph
- 전투 이벤트를 구독하는 퀘스트 목표와 데이터 기반 보상
- 원자적 구매·판매, 소지금과 장착 아이템 판매 방지
- 기본 언어와 fallback을 갖는 locale, 한글 TTF 표시
- 검증된 순·역방향 콘텐츠 dependency graph와 필드 경로 조회
- actor·ability·dialogue·stage의 실행 중 preview 제어
- 콘텐츠·TMX·runtime asset 변경 감지와 안전한 자동 reload
- authoring 원본을 제외하는 결정적 runtime-only `.love` 패키지
- 실행 전 스키마·파일·교차 참조 검증
- 원격 월드 검사, 엔티티 제어, 프레임 스텝, 화면 캡처
- Go 기반 검사·콘텐츠 생성·실화면 테스트

RPG 기능은 action/condition/event 계약 위의 독립 feature다. 순수 액션
프로젝트에서는 RPG feature를 선택하지 않으면 콘텐츠 종류, 상태와 UI가
로드되지 않는다. 같은 actor에 action과 RPG component를 함께 붙이면
별도의 장르 분기 없이 액션 RPG가 된다.

## 실행

```bash
cd 32_recreate
love .
```

조작:

- 이동: `WASD` 또는 방향키
- 공격: `Space` 또는 `Z`
- 발사체: `F` 또는 `V`
- 다단 회전 공격: `Q`
- 회피: `Shift` 또는 `X`
- 패링: `C` 또는 `Ctrl`
- 점프: 플랫포머 stage에서 `W` 또는 `↑`
- NPC 상호작용: `E`
- 대화·상점 선택: 방향키 또는 `WASD`
- 대화·상점 확인: `Enter` 또는 `Space`
- 대화·상점 닫기: `Esc` 또는 `Backspace`
- 스테이지 재시작: `R`
- 시맨틱 디버그 오버레이: `F1`

## 검사와 자동화

Go 1.26과 LÖVE 11.5가 설치된 환경에서 실행한다.

```bash
go run ./tools/lovectl check
go run ./tools/lovectl test
```

`check`는 Lua 문법, Lua 단위 테스트, 콘텐츠 참조와 Go 테스트를
수행하며 모든 TMX와 생성된 stage의 일치 여부도 검사한다. `test`는
실제 LÖVE 창에서 이동, 공격 시간축, 피해·경직·넉백·히트스톱,
퍼펙트 패링과 무적 회피를 결정적인 프레임 단위로 검증한다. 발사체,
상태 효과, 동적 충돌, 다단 공격, encounter·boss phase, 플랫포머
점프·착지도 같은 방식으로 검사한다. 이어서 타일 렌더링, 큰 맵
카메라, stage 벽 충돌, trigger와 양방향 portal을 검증하고 각 화면을
캡처한다. 마지막으로 한글 대화에서 퀘스트를 수락하고 장비 보정이
실제 공격 피해에 반영되는지, 적 처치 이벤트로 목표와 보상이
완료되는지, 상점 거래와 stage 전환 뒤 session 보존까지 검증한다.
이어 실제 save 파일을 쓴 뒤 돈·아이템·stage를 변경하고, 퀘스트·장비·
능력치·재화·인벤토리·locale이 디스크 load로 복원되는지 확인한다.

디버그 가능한 게임을 직접 실행하려면:

```bash
go run ./tools/lovectl run
```

다른 터미널에서:

```bash
go run ./tools/lovectl world
go run ./tools/lovectl action move_right --frames 30
go run ./tools/lovectl pause true
go run ./tools/lovectl step --frames 30
go run ./tools/lovectl position enemy.slime.1 320 270
go run ./tools/lovectl health enemy.slime.1 10
go run ./tools/lovectl give item.potion 2
go run ./tools/lovectl money 100
go run ./tools/lovectl save slot_1
go run ./tools/lovectl load slot_1
go run ./tools/lovectl stage stage.world_hub default
go run ./tools/lovectl screenshot artifacts/manual.png
go run ./tools/lovectl reload
```

`reload`은 모든 콘텐츠를 다시 읽어 검증한 다음 월드를 교체한다.
검증에 실패하면 실행 중인 정상 월드는 유지된다.

콘텐츠를 저장할 때마다 자동 반영하려면 또 다른 터미널에서 실행한다.

```bash
go run ./tools/lovectl watch
```

TMX가 바뀌면 canonical stage를 먼저 다시 컴파일한다. Lua 콘텐츠나
애셋이 잘못되면 오류를 표시하되 실행 중인 정상 게임과 session은
유지한다. engine 코드와 `game/game.lua` 변경은 프로세스를 재시작해야
한다.

## Tiled 맵 제작

TMX는 편집 원본이고 게임은 생성된 canonical stage만 읽는다.

```bash
go run ./tools/lovectl map compile
go run ./tools/lovectl map check
go run ./tools/lovectl check
```

`game/maps/*.tmx`를 수정한 뒤 `map compile`을 실행한다.
`game/content/stages/generated`는 생성물이므로 직접 수정하지 않는다.
실행 중인 맵을 미리 보려면 `lovectl stage`와 `screenshot`을 사용한다.

```bash
go run ./tools/lovectl stage stage.world_hub default
go run ./tools/lovectl overlay true
go run ./tools/lovectl screenshot artifacts/world_hub.png
```

Tiled map property, object class와 JSON action 규격은
[docs/MAPS.md](docs/MAPS.md)에 있다.

## 콘텐츠 생성

등록 파일을 따로 수정할 필요가 없다.

```bash
go run ./tools/lovectl new actor training_dummy
go run ./tools/lovectl new ability heavy_slash
go run ./tools/lovectl new item potion_large
go run ./tools/lovectl new equipment iron_sword
go run ./tools/lovectl new dialogue blacksmith
go run ./tools/lovectl new quest find_ore
go run ./tools/lovectl new shop blacksmith item.training_sword
go run ./tools/lovectl new stage dungeon_01
go run ./tools/lovectl check
```

콘텐츠를 바꾸기 전에 순·역방향 참조를 확인할 수 있다.

```bash
go run ./tools/lovectl graph item.training_sword
go run ./tools/lovectl graph --json dialogue.guide
```

Linux용 runtime `.love`는 다음처럼 만든다.

```bash
go run ./tools/lovectl package
```

패키지는 `assets/runtime`의 등록 애셋만 포함한다. Tiled TMX, 문서,
테스트, Go 도구와 향후 `assets/source`의 제작 원본은 제외한다.

액션 게임을 조립하는 가장 짧은 흐름은
[docs/ACTION.md](docs/ACTION.md), RPG·액션 RPG 콘텐츠를 만드는 흐름은
[docs/RPG.md](docs/RPG.md), 전체 작성 규격은
[docs/CONTENT.md](docs/CONTENT.md), 내부 경계는
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), 기능을 독립적으로 추가하는
방법은 [docs/EXTENDING.md](docs/EXTENDING.md), 다음 구현 순서는
[docs/ROADMAP.md](docs/ROADMAP.md), 생성·감시·미리보기·패키징 명령은
[docs/TOOLS.md](docs/TOOLS.md), 저장 형식과 migration은
[docs/SAVES.md](docs/SAVES.md)에 정리되어 있다.
