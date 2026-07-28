# Tiled 맵 제작 규격

## 경계

Tiled TMX는 사람이 편집하는 입력이다. LÖVE 런타임은 XML, 레이어 이름,
파일 경로를 해석하지 않고 컴파일된 순수 Lua `stage`만 읽는다.

```text
game/maps/*.tmx
       │ lovectl map compile
       ▼
game/content/stages/generated/*.lua
       │ catalog의 일반 stage 검증
       ▼
geometry + tilemap + navigation + camera feature
```

따라서 `Walls`, `Enemies`, `Portals` 같은 영문 레이어 이름은 계약이
아니다. 오브젝트의 Tiled `class`가 의미를 정하며 레이어 이름과 폴더는
작업자가 자유롭게 정리할 수 있다.

## 지원하는 TMX 범위

- finite orthogonal map
- inline tileset
- CSV tile layer
- rectangle, 회전 rectangle, polygon stage object
- horizontal, vertical, diagonal tile flip bit
- layer visibility, opacity, offset

현재 의도적으로 받지 않는 입력:

- infinite map과 chunk
- external TSX
- base64/compressed layer
- nested group과 image layer
- ellipse, tile object, template object

지원하지 않는 입력은 조용히 무시하지 않고 컴파일 오류가 된다.

## Map property

| 이름 | 필수 | 예 | 의미 |
|---|---:|---|---|
| `stage_id` | 예 | `stage.world_hub` | 콘텐츠 전체에서 쓰는 stage ID |
| `display_name` | 아니오 | `World Hub` | HUD 표시명 |
| `mode` | 아니오 | `topdown` | 제작 메타데이터. `topdown`, `platformer` |
| `camera_width` | 아니오 | `800` | 논리 viewport 폭 |
| `camera_height` | 아니오 | `450` | 논리 viewport 높이 |
| `background` | 아니오 | `#101a22` | `#RRGGBB` 또는 `#AARRGGBB` |

알 수 없는 property는 오타로 간주한다.

## Tileset

tileset은 TMX 안에 inline하고 다음 custom property로 등록된 image
콘텐츠를 연결한다.

```xml
<tileset firstgid="1" name="world_tileset"
         tilewidth="32" tileheight="32" tilecount="486" columns="27">
  <properties>
    <property name="asset" value="image.world_tileset"/>
  </properties>
  <image source="../../assets/runtime/images/tilesets/tileset.png"
         width="864" height="576"/>
</tileset>
```

`image.source`는 Tiled 편집기가 쓰는 상대 경로이고 런타임은 `asset`
ID를 쓴다. asset 파일 존재 여부와 선언 크기는 일반 콘텐츠 검증에서
다시 확인한다. 각 tileset의 `first_gid .. first_gid + tile_count - 1`
범위는 겹칠 수 없으며 수동 canonical stage도 같은 검증을 받는다.

## Object class

모든 semantic object는 class가 필요하다. `type`은 구버전 Tiled 입력을
위한 fallback일 뿐 새 맵에서는 `class`를 쓴다.

### `spawn`

actor 인스턴스를 배치한다.

| property | 필수 | 의미 |
|---|---:|---|
| `actor` | 예 | `actor.hero` 같은 actor ID |
| `id` | 아니오 | 인스턴스 ID. 없으면 object name 사용 |
| `tags` | 아니오 | 쉼표로 구분한 추가 tag |

point object의 좌표를 그대로 사용한다. rectangle이면 중심을 사용한다.

### `spawn_point`

portal의 도착 위치다. `id` property 또는 object name이 ID가 된다.
portal은 좌표를 복사하지 않고 이 ID를 참조한다.

### `wall`

정적 충돌 영역이다. 축 정렬 rectangle은 rectangle으로, 회전 rectangle과
polygon은 절대 좌표 polygon으로 컴파일된다. 별도 wall actor 콘텐츠는
필요하지 않다.

### `portal`

| property | 필수 | 의미 |
|---|---:|---|
| `target_stage` | 예 | 목적지 stage ID |
| `target_spawn` | 예 | 목적지 stage의 spawn point ID |
| `actor_tag` | 아니오 | 진입 actor tag. 기본 `player` |
| `cooldown` | 아니오 | 재진입 대기 시간. 기본 `0.25` |

컴파일된 맵끼리는 목적지 spawn을 Go 단계에서 확인하고, 수동 Lua stage를
가리키는 경우 catalog가 전체 콘텐츠를 읽은 뒤 다시 확인한다.

### `trigger`

| property | 필수 | 의미 |
|---|---:|---|
| `actions` | 예 | 비어 있지 않은 JSON action 배열 |
| `condition` | 아니오 | JSON condition 하나 |
| `actor_tag` | 아니오 | 진입 actor tag. 기본 `player` |
| `once` | 아니오 | stage 인스턴스에서 한 번만 실행 |
| `cooldown` | 아니오 | actor별 재실행 대기 시간 |

예를 들어 회복 영역은 다음 property를 쓴다.

```json
[{"type":"heal","amount":15}]
```

새 이벤트만 발행할 수도 있다.

```json
[{
  "type":"emit",
  "name":"world.grove_discovered",
  "data":{"region":"grove"}
}]
```

JSON은 Lua 코드를 실행하는 통로가 아니다. 컴파일 뒤에도 등록된
action/condition 스키마로 다시 검증된다.

## 현재 encounter 배치

wave와 boss phase는 구현되어 있지만 TMX semantic object로는 아직
컴파일하지 않는다. 현재는 `game/content/encounters`에 encounter를
정의하고 수동 Lua stage의 `encounters` section에서 배치한다. Tiled
지원 전까지 encounter object를 임의 class로 넣으면 지원하지 않는
입력으로 실패하게 두며, 런타임이 레이어 이름을 추측하게 만들지 않는다.

## 작업 순서

```bash
# 모든 game/maps/**/*.tmx 생성
go run ./tools/lovectl map compile

# TMX와 generated Lua가 정확히 일치하는지 확인
go run ./tools/lovectl map check

# Lua, 콘텐츠 교차 참조와 실제 파일까지 전체 확인
go run ./tools/lovectl check
```

실행 중에는 원격으로 원하는 stage와 spawn point를 열 수 있다.

```bash
go run ./tools/lovectl run
go run ./tools/lovectl stage stage.world_hub default
go run ./tools/lovectl overlay true
go run ./tools/lovectl screenshot artifacts/world_hub.png
```

현재 기준 예제는 `game/maps/world_hub.tmx`와
`game/maps/world_grove.tmx`다.
