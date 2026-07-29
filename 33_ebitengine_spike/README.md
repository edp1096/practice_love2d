# Recreate Ebitengine Spike

`32_recreate`의 콘텐츠와 액션 RPG 계약을 Ebitengine 기반 순수 Go
런타임으로 옮기는 비교 구현이다. `32_recreate`는 복사 원본이 아니라
기능 기준 명세로 유지한다.

기본 실행은 하드코딩된 시험장이 아니라 `game/game.lua`에서 컴파일한
project manifest의 `stage.village/default`를 사용한다. 플레이어,
실제 안내인·상인 sprite, 벽, 카메라가 보이며 전투 fixture와 Maker
preview에서는 슬라임을 생성할 수 있다. 이동·충돌·공격·피해·경직·
넉백·히트스톱·패링·퍼펙트 패링·회피·대화·퀘스트·상점·인벤토리·
장비·세이브와 게임 흐름이 고정 60 tick 시뮬레이션으로 동작한다.
작성 데이터의 보조 능력, 연속 다중 hit, 연속 충돌 투사체와
중첩·주기 피해·배율·면역 상태이상도 같은 경계를 사용한다.
`movement.platformer` actor는 같은 충돌 경계에서 가속·중력·코요테
타임·점프 버퍼를 사용한다.
stage에 배치한 encounter는 작성된 target tag·지연·웨이브·spawn
override·보스 체력 단계·완료 event를 결정적인 순서로 실행한다.
프로젝트 manifest의 stage music과 전투·퀘스트·UI semantic cue도
동일한 data-driven 경계를 거쳐 WAV BGM/SFX로 재생한다.

## 실행

Ubuntu 22.04 arm64:

```bash
go run ./cmd/recreate
```

조작:

- `WASD`/방향키: 이동
- 플랫포머 actor의 `W`/위 방향키: 점프
- `Space`/`Z`: 공격
- `F`: 특수 능력
- `Q`: 기술
- `C`/`Ctrl`: 패링
- `X`/`Shift`: 회피
- `E`: 대화
- `I`/`Tab`: 인벤토리
- `P`/`Esc`: 일시정지
- `R`: 재시작

대화·상점·인벤토리·흐름 메뉴에서는 `W/S` 또는 방향키로 이동하고
`Enter`/`E`로 결정한다. 상점의 `Q`는 판매, 인벤토리의 `Q`는 장착
해제이며 `Esc`/`Backspace`는 닫기다.

자동 화면 검증:

```bash
go run ./cmd/recreate \
  -no-debug \
  -stage stage.action_room \
  -spawn default \
  -action attack \
  -frames 2 \
  -screenshot /tmp/recreate-ebitengine.png
```

`-stage`, `-spawn`, `-locale`는 개발·인수 테스트에서 project manifest의
특정 조합을 직접 실행하는 override다. stage의 authored background와
tilemap, catalog image manifest, sprite clip/state map, ability visual은
typed `gamebuild`를 거쳐 렌더링된다. actor의 sprite scale/tint override도
같은 경로를 사용하며 누락된 tile GID·sheet 범위를 벗어난 frame·잘못된
image 크기·runtime 경로 이탈은 실행 전에 거부된다.
`-action`은 `-frames` 제한 실행의 첫 tick에 공격·점프 같은 의미 입력
하나를 주입한다. 위 명령은 공격 clip, slash visual, stage BGM,
`attack.started` cue를 같은 제한 실행에서 통과시키고 자동 종료한다.

## 웹 빌드

현재 catalog와 원본 애셋이 포함된 정적 WebAssembly 배포본과 결정적인
ZIP을 만든다.

```bash
go run ./cmd/webbundle
```

기본 출력은 `dist/web`과 `dist/recreate-web.zip`이다. 같은 Go toolchain,
소스와 catalog로 반복하면 파일 순서·시간·build ID가 고정된 동일 ZIP이
생성된다. `recreate-web.json`에는 Go/Ebitengine 버전, catalog 해시,
bundle ID와 각 파일의 크기·SHA-256이 기록된다.

Chromium이 설치된 개발 호스트에서는 실제 WASM, WebGL canvas와 첫 화면을
창 없이 제한 시간 안에 검증할 수 있다.

```bash
go run ./cmd/webaccept \
  -root dist/web \
  -screenshot /tmp/recreate-web.png
```

이 명령은 manifest와 모든 배포 파일의 해시를 먼저 확인하고 임시
loopback 서버와 격리된 headless Chromium을 실행한다. HTML 준비 상태,
Ebitengine의 960×540 canvas와 PNG 크기를 검사한 뒤 브라우저와 서버를
종료한다. 로컬에서 직접 조작할 때만 다음 서버를 사용한다.

```bash
go run ./cmd/webserve -root dist/web
```

개발 서버는 loopback 주소만 허용하고 `.wasm`을
`application/wasm`으로 제공한다. 다른 정적 호스트에 배포할 때도 같은
MIME type이 필요하다. 첫 온라인 로드 뒤 service worker가 런타임을
캐시하며, campaign save는 origin별 `localStorage`에 저장된다. 브라우저
빌드에는 파일 저장소와 TCP debug bridge가 포함되지 않는다. 이는 웹
배포 경로이며 Android/iOS 네이티브 패키징을 대신하지 않는다.

## 화면·상태 자동화

게임을 실행한 채 다른 터미널에서 다음을 사용할 수 있다.

```bash
go run ./cmd/recreatectl state
go run ./cmd/recreatectl world
go run ./cmd/recreatectl pause true
go run ./cmd/recreatectl action move_right --frames 45
go run ./cmd/recreatectl step --frames 45
go run ./cmd/recreatectl screenshot /tmp/controlled.png
go run ./cmd/recreatectl wall north 0 0 960 24
go run ./cmd/recreatectl spawn actor.slime 520 270 preview.slime
go run ./cmd/recreatectl dialogue dialogue.guide guide
go run ./cmd/recreatectl dialogue-state
go run ./cmd/recreatectl dialogue-choose accept
go run ./cmd/recreatectl dialogue-advance
go run ./cmd/recreatectl campaign-state
go run ./cmd/recreatectl flow-state
go run ./cmd/recreatectl flow-move down
go run ./cmd/recreatectl flow-activate new_game
go run ./cmd/recreatectl shop-state
go run ./cmd/recreatectl shop-buy item.potion 2
go run ./cmd/recreatectl shop-sell item.potion
go run ./cmd/recreatectl shop-close
go run ./cmd/recreatectl item-use item.potion
go run ./cmd/recreatectl equip item.training_sword
go run ./cmd/recreatectl unequip weapon
go run ./cmd/recreatectl ability player ability.fire_bolt
go run ./cmd/recreatectl ability preview.slime ability.slime_bump
go run ./cmd/recreatectl encounter-start arena
go run ./cmd/recreatectl remove preview.slime
go run ./cmd/recreatectl position quest.slime.1 190 270
go run ./cmd/recreatectl health quest.slime.1 1
go run ./cmd/recreatectl save test-slot
go run ./cmd/recreatectl load test-slot
go run ./cmd/recreatectl new-game
go run ./cmd/recreatectl new-game stage.action_room default locale.ko
```

`dialogue`는 콘텐츠를 즉시 표시하는 Maker preview 명령이다. 실제 캠페인
대화는 `dialogue-state`로 활성 노드와 가능한 선택지를 조회하고,
`dialogue-choose` 또는 선택지가 없는 노드의 `dialogue-advance`로 진행한다.
`campaign-state`는 장기 진행 상태를, `shop-state`는 현재 열린 상점과
거래 가능 항목을 조회한다. `shop-buy`와 `shop-sell`의 수량은 생략하면
1이며, `item-use`, `equip`, `unequip`으로 inventory와 equipment 동작도
같은 프로토콜을 통해 자동화할 수 있다. `flow-state`, `flow-move`,
`flow-activate`는 title, pause, gameover, ending 화면을 순서나 번역
문자열이 아닌 안정적인 option ID로 제어한다.

`step`은 요청한 프레임을 원자적으로 진행한 뒤 실행 전 pause 상태를
복원한다. 따라서 실행 중인 창에 `step`을 호출해도 멈춘 채 남지 않는다.
title, 게임 pause, gameover, ending 중에는 `step`이 오류로 거부되어
화면 뒤의 World가 진행되지 않는다. 먼저 `flow-activate`로 현재 흐름을
전환해야 한다.
결정적인 화면을 검사할 때만 다음처럼 명시적으로 pause–step–capture–
resume 순서를 사용한다.

```bash
go run ./cmd/recreatectl pause true
go run ./cmd/recreatectl step --frames 45
go run ./cmd/recreatectl screenshot /tmp/controlled.png
go run ./cmd/recreatectl pause false
```

명시적으로 멈춘 동안에는 화면 중앙의 `AUTOMATION PAUSED` 표시가
나타난다.

일반 회귀 테스트는 Ebitengine 창을 만들지 않는
`go test ./...` 경로를 사용한다. 실제 창 검증이 필요할 때만
`-frames`를 지정한 단일 프로세스를 띄우며, 지정한 tick 뒤 자동으로
종료한다.

## Maker에서 편집

기존 32의 브라우저 Maker가 같은 authoring source를 Ebitengine으로
미리 볼 수 있다.

```bash
cd ../32_recreate
go run ./tools/lovectl maker --backend ebitengine
```

종류별 정의 검색·참조 탐색·폼/JSON 편집·새 stage/actor/RPG 콘텐츠
생성은 기존 Maker UI를 그대로 사용한다. 저장은 전체 source를 canonical
catalog로 컴파일한 뒤 현재 stage·spawn·locale을 새 World에서 원자적으로
구축한다. 실패하면 기존 실행 화면을 유지하고 source를 복구한다.
stage 전환, actor 생성, ability/dialogue 실행과 실제 960×540 screenshot도
동일한 semantic protocol을 사용한다. Ebitengine 경로가 프로젝트의
형제 폴더가 아니면 `--ebitengine /path/to/33_ebitengine_spike`를
지정한다.

`step` 묶음은 취소되면 중간 프레임을 남기지 않고 전부 되돌린다.
`screenshot` 출력에는 실제 렌더 tick과 revision이 함께 표시되어 상태
조회와 같은 프레임을 캡처했는지 확인할 수 있다.

`spawn`은 actor 콘텐츠를 현재 World에 즉시 생성한다. 좌표를 생략하면
현재 카메라 중앙, entity ID도 생략하면 32와 같은
`ACTOR_ID.spawn_sequence` 형식을 쓴다. `remove`는 삭제를 예약하고 다음
고정 tick 끝에서 확정하므로 자동화에서는 뒤이어 `step --frames 1`을
호출한다. `dialogue`의 speaker는 생략할 수 있으며 start node의 직접
action만 적용한다. 선택지 안의 quest action은 선택 전에는 실행되지
않는다.

`world`는 ID가 보존된 stage 벽뿐 아니라 모든 entity의 월드 좌표,
논리 화면 좌표, 가시성, 체력, 방향, 정확한 활성 ability와 개별
cooldown, 상태이상, 공격·경직·패링·회피 상태를 반환한다. 살아 있는
투사체도 별도 목록에서 source·ability·이전/현재 월드 좌표·화면 좌표·
관통 hit 수·남은 수명까지 조회할 수 있다. 카메라와 최근 이벤트도
같은 응답에 있으며, 변이는 전체 상태를 검증한 뒤 원자적으로
반영된다. 벽 ID는 렌더 좌표에서 역산하지 않고 simulation까지 직접
보존된다. 플랫포머 actor는 속도, 접지, 코요테/버퍼 남은 tick과 실제
고정틱 이동 수치도 같은 entity 응답에서 조회한다. stage encounter는
placement/definition ID, idle·pending·active·completed·failed 상태,
현재 wave와 남은 지연 tick, 생존 수, 진입한 boss phase를 반환한다.
`encounter-start`는 `auto_start=false`인 배치를 안정적인 placement ID로
시작하며, 이미 시작한 배치에 대한 반복 호출은 상태를 바꾸지 않는다.

`save`/`load`는 stage와 진입 spawn, locale, 게임 진행, flag, inventory,
equipment, quest, 재화를 담은 versioned campaign 저장이다. 체력·위치·
전투·대화·카메라·portal cooldown 같은 현재 World 상태와 가상 입력,
자동화 pause, Maker preview는 저장하지 않는다. `load`는 저장된 stage를
authored content에서 새로 빌드하므로 World는 항상 해당 spawn의 초기
상태로 시작한다. 동적 entity, entity 삭제 예약, 직접 dialogue 같은
Maker preview가 남아 있으면 `save`와 `load`를 모두 명시적으로 거부한다.
자동화는 저장 파일을 simulation checkpoint처럼 재사용하지 말고 setup
명령과 고정 `step`을 다시 실행한다.

디버그 브리지는 loopback만 허용한다. 여러 사용자가 쓰는 호스트에서는
토큰 파일을 `0600`으로 만들고 양쪽에 지정한다.

```bash
go run ./cmd/recreate -token-file /secure/path/debug.token
go run ./cmd/recreatectl --token-file /secure/path/debug.token world
```

`RECREATE_DEBUG_TOKEN` 환경 변수도 지원한다.

## 콘텐츠 변환

Lua는 제작 입력 형식으로만 사용한다. 빌드 시 격리된 순수 Go Lua 5.1
VM이 테이블을 읽고 canonical JSON을 만든다. 배포 게임에는 Lua VM이나
LuaJIT가 필요 없다.

```bash
go run ./cmd/contentc \
  -source ../32_recreate \
  -output game/catalog.json
```

현재 결과는 정의 54개, dependency path 86개다. canonical 파일을 쓰기
전에 7개 stage의 모든 entry spawn과 2개 locale, 총 22개 조합을
simulation까지 구성한다. 동일 입력은 byte-for-byte 같은 catalog를
만든다.

`game/game.lua`의 `audio`는 master/music/SFX volume, semantic event별
cue, stage별 music을 선언한다. `asset_type = "audio"`인 WAV만 패키징하며
누락된 asset, 중복 event/stage, 범위를 벗어난 volume은 컴파일 전에
거부된다. 샘플 음원은 저장소의 `tools/audiofixtures`로 생성한 원본이며
출처와 해시는 `assets/AUDIO_SOURCES.md`에 기록한다.

기본 catalog는 실행 파일에 embed된다. `-catalog path/to/catalog.json`은
개발 중 외부 catalog를 reload할 때만 쓰는 override다.

`Content.validateDefinition`은 세 결과를 구분한다.

- `schema_valid`: 32의 authoring schema에 맞는가
- `fully_applied`: 현재 Ebitengine adapter가 해당 기능을 모두 쓰는가
- `runtime_compatible`: 현재 stage를 실제 preview로 재구축할 수 있는가

스키마상 유효하지만 현재 adapter가 적용하지 못하는 정의는 RPC 오류로
버리지 않고 `fully_applied=false`, `runtime_compatible=false`와 구체적인
warning을 반환한다. action 32종, condition 17종, stage section 7종도
payload와 참조까지 닫힌 규칙으로 검사한다.

## 구조

```text
authored Lua tables ──contentc──▶ canonical JSON catalog
                                      │
Maker / debug client ──protocol v8──▶ gameapp
                                      │
                         deterministic sim
                                      │
                              render snapshot
                                      │
                           Ebitengine adapter
```

- `internal/content`: 제한된 Lua 콘텐츠 컴파일러와 dependency graph
- `internal/gamebuild`: catalog와 image/audio manifest·tilemap·sprite
  clip·ability visual을 검증된 simulation·presentation DTO로 변환
- `internal/projectcheck`: 모든 stage·entry·locale과 Campaign/rule
  topology 사전 검증
- `internal/campaign`: stage와 분리된 장기 진행 및 versioned player save
- `internal/rulesruntime`: 대화·quest·inventory·shop의 원자적 규칙 실행
- `internal/sim`: 렌더러와 분리된 고정소수점 결정적 게임 상태
- `internal/gameapp`: AI, 저장, 화면 DTO, 프로토콜 backend
- `internal/ebitapp`: Ebitengine 입력·스프라이트·화면·WAV 오디오 출력
- `internal/protocol`: 인증 가능한 loopback NDJSON protocol v8
- `internal/storage`: 플랫폼 교체 가능한 세이브 저장소
- `internal/webdist`: 해시가 확인된 WASM 배포본과 loopback HTTP 경계

전환 판정과 남은 기능은 [docs/SPIKE.md](docs/SPIKE.md), 완전한 샘플
게임의 실행 계약과 구현 순서는
[docs/CAMPAIGN_MIGRATION.md](docs/CAMPAIGN_MIGRATION.md)에 정리되어
있다.
