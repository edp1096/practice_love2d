# 저장 규격

저장은 실행 중인 `World`, 엔티티, 시스템 객체를 통째로 덤프하지 않는다.
App은 현재 stage identity를 기록하고, 각 feature는 자신이 소유한
session section만 등록한다.

```text
save schema v1
├─ project
├─ stage
│  ├─ id
│  └─ spawn (선택)
└─ sections
   ├─ game.flow       v1
   ├─ rpg.flags       v1
   ├─ rpg.inventory   v1
   ├─ rpg.equipment   v1
   ├─ rpg.quests      v1
   ├─ rpg.economy     v1
   └─ rpg.locale      v1
```

현재 위치는 stage와 선택된 spawn point로 표현한다. 물리 접촉, 투사체,
공격 중간 phase, AI 내부 타이머 같은 일시 상태는 저장하지 않고 새
World에서 다시 만든다. `game.flow`는 새 게임 시작 여부와 완료 여부를
보존해 이어하기와 엔딩 상태를 복원한다.

## 사용

디버그 런타임을 실행한다.

```bash
go run ./tools/lovectl run
```

다른 터미널에서 슬롯을 저장하고 불러온다.

```bash
go run ./tools/lovectl save slot_1
go run ./tools/lovectl load slot_1
```

슬롯 이름은 소문자, 숫자, `_`, `-`만 사용하며 최대 64자다. 현재
프로젝트 identity는 `practice_love2d_recreate`이므로 Linux에서는 LÖVE
save directory 아래 `saves/slot_1.lua`에 기록된다. 게임 코드에서는
`App:save("slot_1")`, `App:loadSave("slot_1")`을 호출할 수 있다.

저장은 먼저 `saves/slot_1.lua.tmp`에 완전히 쓴 뒤 운영체제 rename으로
교체한다. 쓰기 실패 시 기존 슬롯은 유지된다.

## 로드 보장

로드는 다음 순서로 후보 상태에서만 수행한다.

1. 순수 데이터 형식과 save schema, project ID를 검사한다.
2. section별 저장 버전을 확인하고 필요한 migration을 순서대로 실행한다.
3. 선택된 feature가 모든 section을 인식하는지 검사한다.
4. inventory item, equipment item/slot, quest/objective, locale 같은 현재
   콘텐츠 참조를 다시 검증한다.
5. 저장된 stage와 spawn으로 새 Host와 World를 완전히 만든다.
6. 모든 단계가 성공한 경우에만 실행 중인 Host, World, session을 한 번에
   교체한다.

따라서 손상된 저장, 더 최신 버전의 저장, 다른 프로젝트의 저장,
삭제된 콘텐츠 ID 또는 존재하지 않는 stage는 현재 플레이 상태를
훼손하지 않고 오류로 끝난다.

## feature section 추가

stage보다 오래 유지할 상태가 있는 feature만 section을 등록한다.

```lua
local session = host.services.session
local state = session:registerSection("rpg.reputation", {
    version = 2,
    defaults = {
        factions = {},
    },
    migrations = {
        [1] = function(previous)
            return {
                factions = previous.values or {},
            }
        end,
    },
    validate = function(value)
        if type(value.factions) ~= "table" then
            return nil, "factions must be a table"
        end
        return true
    end,
})
```

`migrations[1]`은 v1 데이터를 받아 v2 테이블을 반환한다. 버전을 두 단계
올리면 각 중간 버전 migration을 모두 제공해야 한다. migration과
validation은 복사된 후보에 적용되므로 실패해도 기존 session은 바뀌지
않는다.

section 안에는 문자열, boolean, 유한한 number와 순수 table만 넣는다.
함수, userdata, metatable, cycle, 문자열 key와 배열 index의 혼합은
저장할 수 없다.

## ID 변경 규칙

다음 ID는 저장 호환 계약이다.

- project ID
- stage ID와 spawn point ID
- item, quest, locale 등 section에 기록되는 content ID
- quest objective ID
- equipment loadout과 slot 이름

출시된 ID는 표시 이름을 바꿀 때 함께 바꾸지 않는다. ID를 정말
변경해야 하면 해당 feature section 버전을 올리고 migration에서 기존
key를 새 ID로 옮긴다. stage ID나 spawn ID 변경은 feature section
migration으로 처리할 수 없으므로 save schema migration을 함께
설계해야 한다.

## 현재 의도적으로 저장하지 않는 것

- 진행 중인 공격, 경직, 패링, 회피와 hitstop
- 살아 있는 projectile과 status 남은 시간
- encounter wave의 순간 전투 상태
- NPC와 적의 현재 위치·체력·AI 타이머
- 대화·상점 창의 열린 메뉴 위치

이 값들은 일시적인 World 상태다. 게임 기획상 체크포인트보다 더 세밀한
복원이 필요해질 때 해당 feature가 안정적인 ID와 명시적인 section
schema를 추가한다.
