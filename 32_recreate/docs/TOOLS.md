# 제작 도구

`lovectl`은 게임 규칙을 다시 구현하지 않는다. 엔진의 validator,
semantic debug protocol과 transactional reload를 사용해 콘텐츠 제작을
돕는다.

## 독립 프로젝트 생성

```bash
go run ./tools/lovectl init --profile rpg ../my-rpg
go run ./tools/lovectl init --profile action-rpg ../my-action-rpg
go run ./tools/lovectl init --profile action ../my-action
```

대상 경로는 존재하지 않아야 하며 실패 시 반쪽짜리 디렉터리를 남기지
않는다. 생성물에는 version을 고정한 `engine`, `tools/lovectl`, `tests`
번들과 profile별 composition·최소 콘텐츠·smoke manifest가 들어간다.
첫 부팅은 title이며 smoke도 `new_game`, `quit`와 title screenshot을
먼저 검증한 뒤 gameplay capability를 검사한다. 공식 profile의
`smoke.json`은 `journey.steps`로 목표 actor에 접근해 입력을 실행하고
순수 RPG의 battle·quest, 액션의 encounter, 액션 RPG의 quest와 최종
ending까지 확인한 `smoke-complete.png`도 남긴다.

세 profile은 LÖVE의 `check`·실화면 smoke·결정적 package뿐 아니라
Ebitengine의 canonical catalog, title 제한 실행과 gameplay 제한
실행으로도 교차 검증한다. 순수 action에는 locale/font가 없어도 되고,
RPG profile의 단일 locale은 자기 자신을 fallback으로 사용한다.

## 로컬 Maker 화면

```bash
go run ./tools/lovectl maker
go run ./tools/lovectl maker --no-open --listen 127.0.0.1:0
go run ./tools/lovectl maker --backend ebitengine
```

`maker`는 실제 프로젝트를 읽는 격리된 LÖVE 미리보기와 loopback 전용
Go HTTP 서버를 시작한다. 브라우저에서는 다음 작업을 할 수 있다.

- 종류별 콘텐츠 검색과 순·역방향 참조 탐색
- dialogue 노드·선택지, quest 목표·완료 보상, NPC 상호작용의 조건부
  event page, 컷신 step과 턴제 스킬·적 편성의 간편 카드 편집
- `actions` 배열에서 명령 종류를 고르면 필수 필드가 채워지는 명령
  builder와 콘텐츠 ID 선택 목록
- stage의 actor·spawn 좌표, trigger 조건·명령·조건부 event page와
  portal 목적지, region의 조건·진입·이탈 명령을 편집하는 TMX 맵 카드
- 간편 화면에 없는 객체·배열 구조 편집과 전체 JSON 고급 편집
- 현재 엔진의 Catalog/Validator를 이용한 draft 검증
- actor, ability, dialogue와 stage 미리보기
- 게임 화면 자동 캡처와 의미 입력
- 검증된 scaffold를 이용한 새 콘텐츠 생성

브라우저가 Lua 파일을 직접 쓰거나 임의 debug RPC를 호출하지 않는다.
서버는 `game/content` 아래의 실제 Catalog source만 수정하며 generated
stage는 읽기 전용이다. 저장 요청은 읽을 때 받은 SHA-256 revision을
반드시 제시해야 한다. 전체 draft 검증과 transactional runtime reload가
성공한 경우에만 새 파일을 유지하며, 외부 수정과 충돌하면 덮어쓰지
않는다.

Maker 미리보기의 save identity와 XDG 디렉터리는 실제 플레이 데이터와
분리된다. 타일맵 편집은 [MAPS.md](MAPS.md)의 Tiled 작업 흐름을 사용한다.
특정 콘텐츠로 바로 열려면 Maker URL에
`?content=dialogue.village_guide`처럼 content ID를 붙인다.

dialogue·quest·actor·stage·cutscene·turn_skill·turn_battle은 허용된 목적별
필드를 먼저 보여주고 전체 스키마는 접힌 고급 영역에 둔다. 명령과
조건의 `type`, item·quest·shop·battle 등의 참조 필드는 자유 문자열
대신 현재 Catalog 선택 목록을 사용한다.
월드 제작 명령 builder는 `set_world_time`, `advance_world_time`,
`time_between`, `region_active`의 목적별 필드를 제공한다. map-level
`world_pages`의 전체 배열은 현재 고급 JSON property로 편집하며, Tiled
원본과 같은 strict validator를 통과해야 저장된다.
변경 후 검증·저장 경계는 기존과 동일하므로 간편 화면도 validator를
우회하지 않는다. generated stage Lua 본문은 계속 읽기 전용이지만 맵
카드는 `game/maps/*.tmx` 원본만 수정한다. 수정 시 SHA-256 revision을
확인하고 전체 TMX 교차 연결을 검증한 뒤 generated stage를 원자적으로
다시 만들고 런타임을 reload한다. 컴파일이나 reload가 실패하면 TMX와
generated stage를 이전 상태로 복구한다.

기본 backend는 `love`다. `--backend ebitengine`은 프로젝트와 나란히
있는 `33_ebitengine_spike`를 빌드하고 같은 Maker UI와 protocol v8
계약에 연결한다. 다른 위치에 있으면
`--ebitengine /path/to/33_ebitengine_spike`를 함께 지정한다.
저장할 때 전체 Lua authoring source를 임시 canonical catalog로 먼저
컴파일한 뒤, 현재 stage·spawn·locale을 새 Ebitengine World에서
구축한다. 컴파일이나 구축이 실패하면 실행 중 화면을 바꾸지 않고 Maker가
원본 source를 복구한다. stage, actor, ability, dialogue preview와 화면
캡처는 두 backend에서 같은 HTTP API를 사용한다.

## 콘텐츠 생성

```bash
go run ./tools/lovectl new TYPE NAME [REFERENCE_ID]
```

| TYPE | 생성 ID | 추가 인자 |
|---|---|---|
| `actor` | `actor.NAME` | 없음 |
| `ability` | `ability.NAME` | 없음 |
| `projectile` | `projectile.NAME` | 사용할 `actor.*` |
| `status` | `status.NAME` | 없음 |
| `encounter` | `encounter.NAME` | 배치할 `actor.*` |
| `stage` | `stage.NAME` | 없음 |
| `item` | `item.NAME` | 없음 |
| `equipment` | `item.NAME` | 없음 |
| `dialogue` | `dialogue.NAME` | 없음 |
| `quest` | `quest.NAME` | 없음 |
| `shop` | `shop.NAME` | 첫 offer의 `item.*` |
| `locale` | `locale.NAME` | 없음; NAME을 초기 code로 사용 |
| `turn-skill` | `turn_skill.NAME` | 없음 |
| `turn-battle` | `turn_battle.NAME` | 첫 적의 `actor.*` |
| `cutscene` | `cutscene.NAME` | 없음 |

예:

```bash
go run ./tools/lovectl new equipment iron_sword
go run ./tools/lovectl new dialogue blacksmith
go run ./tools/lovectl new shop blacksmith item.iron_sword
go run ./tools/lovectl new turn-skill heavy_strike
go run ./tools/lovectl new turn-battle forest_slime actor.turn_slime
go run ./tools/lovectl new cutscene village_arrival
```

기존 파일은 덮어쓰지 않는다. 템플릿은 그 자체로 현재 schema를
통과하지만, 실제 수치·문장·참조는 게임에 맞게 바꾼다.

## 참조 확인

전체 graph:

```bash
go run ./tools/lovectl graph
```

한 콘텐츠의 직접 참조와 역참조:

```bash
go run ./tools/lovectl graph item.training_sword
```

출력 예:

```text
item.training_sword [item]
source: game/content/items/training_sword.lua
depends on:
  (none)
used by:
  dialogue.guide via nodes.greeting.choices[1].actions[2].item
  shop.village via offers[2].item
```

도구에서 읽을 때는 `--json`을 사용한다. graph edge는 문자열 검색
결과가 아니라 각 feature validator가 실제로 확인한 참조와 필드
경로다.

## 실행 중 편집

첫 터미널:

```bash
go run ./tools/lovectl run
```

두 번째 터미널:

```bash
go run ./tools/lovectl watch
```

watch 대상:

- `game/content`
- `game/maps`
- `assets`

변경이 잠시 멈추면 한 묶음으로 처리한다. TMX가 포함되면 먼저 모든
맵을 컴파일하고, 그다음 새 Host와 World를 session 복사본 위에서
검증한다. 성공했을 때만 실행 중 상태를 교체한다. 실패하면 오류를
출력하고 마지막 정상 화면을 유지한 채 다음 저장을 기다린다.

engine 코드와 `game/game.lua`는 Lua module 및 composition root이므로
프로세스를 재시작해야 한다.

## 검사와 Preview

```bash
go run ./tools/lovectl definition actor.hero
go run ./tools/lovectl world
go run ./tools/lovectl preview stage stage.rpg_village
go run ./tools/lovectl preview actor actor.slime 600 270 debug.slime
go run ./tools/lovectl preview ability player ability.sword_slash
go run ./tools/lovectl preview dialogue dialogue.guide guide
go run ./tools/lovectl screenshot artifacts/preview.png
```

- `definition`은 검증된 원문 테이블과 실제 source 파일을 보여 준다.
- `world`의 `navigation`은 count뿐 아니라 ID로 정렬된 spawn point,
  trigger와 portal의 authored geometry, 대상 stage/spawn을 반환한다.
  자동화는 이 값을 사용해 TMX 좌표를 코드에 다시 적지 않는다.
- actor preview 좌표를 생략하면 현재 camera 중앙에 생성한다.
- ability preview는 해당 entity의 loadout에 든 ability만 허용한다.
- dialogue preview의 speaker entity는 생략할 수 있다.
- preview mutation은 실행 중 World에만 적용된다. stage restart로
  되돌릴 수 있다.

임의 Lua 실행은 지원하지 않는다. 실제 콘텐츠 ID, entity ID와 의미
명령만 다룬다.

## 진행 상태와 저장

```bash
go run ./tools/lovectl give item.potion 2
go run ./tools/lovectl money 100
go run ./tools/lovectl save slot_1
go run ./tools/lovectl load slot_1
```

`give`와 `money`는 각각 실제 inventory/economy service를 거치므로
존재하지 않는 아이템, stack limit과 잘못된 금액 검사를 우회하지 않는다.
`save`는 feature별 버전 section을 원자적으로 쓰고, `load`는 새
Host·World에서 schema, migration, 콘텐츠 참조와 stage를 전부 검증한
뒤 성공할 때만 현재 실행 상태를 교체한다.

저장 형식, ID 호환 규칙과 feature migration 작성법은
[SAVES.md](SAVES.md)에 있다.

## Runtime 패키지

```bash
go run ./tools/lovectl package
go run ./tools/lovectl package --output dist/my_game.love
```

패키징 전에 TMX compile과 실제 LÖVE catalog validation을 수행한다.
asset 콘텐츠의 `path`는 `assets/runtime` 아래여야 한다. PSD, Aseprite,
고해상도 원본과 변환 프로젝트는 `assets/source`에 두며 package에
포함되지 않는다.

`.love` 안의 `recreate-build.json`에는 콘텐츠·참조 수와 각 runtime
파일의 SHA-256이 기록된다. timestamp를 입력으로 쓰지 않으므로 같은
소스에서 같은 SHA-256 패키지가 생성된다.
