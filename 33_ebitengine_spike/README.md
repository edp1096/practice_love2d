# Recreate Ebitengine Spike

`32_recreate`의 콘텐츠와 액션 RPG 계약을 Ebitengine 기반 순수 Go
런타임으로 옮기는 비교 구현이다. `32_recreate`는 복사 원본이 아니라
기능 기준 명세로 유지한다.

현재 vertical slice에는 기존 애셋과 `stage.rpg_village` 콘텐츠를
그대로 사용한 플레이어, 가이드, 상인, 슬라임 2마리, 벽, 카메라가
있다. 이동·충돌·공격·피해·경직·넉백·히트스톱·패링·퍼펙트 패링·
회피·대화·퀘스트·세이브가 고정 60 tick 시뮬레이션으로 동작한다.

## 실행

Ubuntu 22.04 arm64:

```bash
go run ./cmd/recreate
```

조작:

- `WASD`/방향키: 이동
- `Space`/`Z`: 공격
- `C`/`Ctrl`: 패링
- `X`/`Shift`: 회피
- `E`: 대화
- `P`/`Esc`: 일시정지
- `R`: 재시작

자동 화면 검증:

```bash
go run ./cmd/recreate \
  -no-debug \
  -frames 180 \
  -screenshot /tmp/recreate-ebitengine.png
```

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
go run ./cmd/recreatectl position quest.slime.1 190 270
go run ./cmd/recreatectl health quest.slime.1 1
go run ./cmd/recreatectl save test-slot
go run ./cmd/recreatectl load test-slot
go run ./cmd/recreatectl new-game
```

`step`은 결정적인 화면 검사를 위해 요청한 프레임을 진행한 뒤 게임을
**일시정지 상태로 유지한다.** 창이 멎은 것이 아니며 화면 중앙의
`AUTOMATION PAUSED` 표시로 구분된다. 다시 실시간으로 실행하려면 다음을
호출한다.

```bash
go run ./cmd/recreatectl pause false
```

일반 회귀 테스트는 Ebitengine 창을 만들지 않는
`go test ./...` 경로를 사용한다. 실제 창 검증이 필요할 때만
`-frames`를 지정한 단일 프로세스를 띄우며, 지정한 tick 뒤 자동으로
종료한다.

`step` 묶음은 취소되면 중간 프레임을 남기지 않고 전부 되돌린다.
`screenshot` 출력에는 실제 렌더 tick과 revision이 함께 표시되어 상태
조회와 같은 프레임을 캡처했는지 확인할 수 있다.

`world`는 ID가 보존된 stage 벽뿐 아니라 모든 entity의 월드 좌표,
논리 화면
좌표, 가시성, 체력, 방향, 공격·경직·패링·회피 상태, 카메라와 최근
이벤트를 반환한다. 변이는 전체 상태를 검증한 뒤 원자적으로 반영된다.
벽 ID는 렌더 좌표에서 역산하지 않고 simulation까지 직접 보존된다.

`save`/`load`는 실제 플레이 세션용이다. 체력·위치·전투·퀘스트·대화·
카메라 상태를 저장하지만, 테스트가 주입한 가상 입력과 대기 명령,
일시적인 벽 preview는 의도적으로 저장하지 않는다. 자동화는 저장 파일을
checkpoint처럼 재사용하지 말고 setup 명령과 고정 `step`을 다시 실행한다.

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

현재 결과는 정의 44개, dependency path 86개이며 동일 입력은
byte-for-byte 같은 catalog를 만든다.

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
- `internal/gamebuild`: catalog를 검증된 게임 설정으로 변환
- `internal/sim`: 렌더러와 분리된 고정소수점 결정적 게임 상태
- `internal/gameapp`: AI, 저장, 화면 DTO, 프로토콜 backend
- `internal/ebitapp`: Ebitengine 입력·스프라이트·화면 출력
- `internal/protocol`: 인증 가능한 loopback NDJSON protocol v8
- `internal/storage`: 플랫폼 교체 가능한 세이브 저장소

전환 판정과 남은 기능은 [docs/SPIKE.md](docs/SPIKE.md)에 정리되어 있다.
