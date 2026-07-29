# Complete campaign 이식 계약

기준일: 2026-07-29

이 문서는 `32_recreate`의 샘플 게임을 Ebitengine 런타임으로 옮길 때
완료 여부를 판단하는 실행 명세다. `32_recreate/game/tests/campaign.json`,
`tools/lovectl/campaign.go`, `docs/SAMPLE_GAME.md`를 감사해 실제 실행
계약을 우선했다.

## 완료 시나리오

1. 저장 파일이 없으면 title에 `new_game`, `quit`가 보인다.
2. 새 게임은 `stage.village/default`에서 시작한다.
3. 안내인 대화의 `accept` 선택은 다음을 한 transaction으로 실행한다.
   - `quest.grove_guardian` 시작
   - `item.training_sword` 1개 지급
   - `weapon` 슬롯에 검 장착
   - currency 25 지급
4. 상점에서 potion을 25에 사면 currency 0, potion 1이 된다.
5. pause menu에서 `campaign` 슬롯을 저장하고 프로세스를 종료한다.
6. 새 프로세스의 title은 `continue`를 제공한다. 불러온 상태는 마을,
   active quest, 장착한 검, potion 1, currency 0을 보존한다.
7. 마을 portal은 `stage.world_hub/village_entry`로 이동시킨다.
8. slime 두 마리를 처치하면 `defeat_slimes=2`지만 quest는 active다.
9. field portal은 `stage.world_grove/west_entry`로 이동시킨다.
10. guardian을 처치하면 `defeat_guardian=1`과 함께 quest가 completed가
    되고 potion 1, currency 75, reward flag를 정확히 한 번 지급한다.
11. grove → field → village로 돌아가 안내인의 completed 선택을 고르면
    `thanks` node의 `finish_game`이 ending을 연다.
12. 별도 새 게임에서 player가 죽으면 gameover가 열린다.

현재 32의 실행 가능한 계약은 **guardian 처치 즉시 보상**이다.
`SAMPLE_GAME.md`의 “보고하고 보상을 받는다”는 문구와 다르므로 parity
구현에서는 기존 acceptance를 따른다. 보상 시점을 바꾸려면 문서,
콘텐츠, acceptance를 한 변경으로 함께 수정해야 한다.

## 상태 경계

```text
CompiledProject (immutable)
 ├─ ProjectManifest
 ├─ typed content index
 └─ StageBlueprint[]

Runtime/App
 ├─ CampaignState       stage 사이에 유지하고 player save에 기록
 ├─ FlowController      title/menu/dialogue/shop 입력
 └─ WorldSimulation     현재 stage 전투·충돌·카메라, 전환 때 재생성
```

`CampaignState`에는 location, locale, flags, quest objective, inventory,
equipment, currency를 둔다. entity 위치, 적 사망 목록, 공격 phase,
hitstop, camera shake, 열린 dialogue, portal cooldown, Maker preview는
player save에 넣지 않는다.

자동화 pause, App/UI tick, World/gameplay tick은 서로 다른 상태다.
`Emulation.step`은 실행 전 자동화 pause 상태를 복원하며, 명시적
automation pause를 게임의 pause menu와 합치지 않는다.

## 구현 순서

- [x] Maker preview protocol 수명주기
- [x] `game/game.lua` canonical project manifest
- [x] 장기 `CampaignState` 자료형과 원자적 transaction
- [x] stage spawn point·portal blueprint 변환
- [x] hub/grove convex polygon collision과 고속 이동 검증
- [x] 전체 stage·entry·locale 조합 사전 검증
- [x] App/Campaign/World 수명주기 및 원자적 stage 전환
- [x] typed condition/action evaluator
- [x] 저장 가능한 Campaign과 저장하지 않는 World를 분리한 process restart
- [x] dialogue graph·조건 재검사·원자적 세션 실행기
- [x] dialogue modal 입력과 화면 연결
- [x] 다중 목표 quest와 commit-after-success 보상 실행기
- [x] simulation kill event와 Campaign quest 연결
- [x] inventory/equipment/economy/shop 도메인 transaction
- [x] stat 반영, item use와 shop/inventory 화면
- [x] title/pause/continue/gameover/ending
- [x] authored tilemap·background·image resource presentation
- [x] 프로세스 재시작을 포함한 headless campaign acceptance
- [x] projectile/status/secondary ability/multi-hit 전투 fixture
- [x] actor-local platformer 이동과 authored shape presentation fixture
- [x] authored encounter wave·boss phase·session fixture
- [x] sprite clip·instance override·ability visual의 data-driven presentation
- [ ] audio cue와 전체 오디오의 data-driven presentation

## 현재 인수 근거

`internal/gameapp/campaign_acceptance_test.go`의
`TestCompleteAuthoredCampaignAcrossProcessRestart`가 위 완료 시나리오
1~11을 하나의 실행 경로로 검증한다.

- 저장 파일이 없는 title의 `new_game`부터 시작한다.
- 실제 안내인·상인 interaction과 dialogue/shop protocol을 사용한다.
- pause의 `save` 뒤 같은 파일 저장소로 새 `Runtime`을 생성한다.
- 새 title의 `continue`로 quest, potion, currency, equipment를 복원한다.
- 장착 검으로 체력 39인 slime을 한 번의 실제 공격으로 처치해 표시용
  stat이 아니라 simulation 피해가 34에서 39로 바뀌었음을 검증한다.
- village → field → grove → field → village portal을 모두 통과한다.
- 두 목표, 즉시 보상, completed 대화와 ending을 확인한다.

시나리오 12의 player death → gameover → retry는
`TestPlayerDeathOpensGameOverAndRetryBuildsFreshWorld`가 별도로 검증한다.
모든 테스트는 Ebitengine 창을 생성하지 않는다.

`stage.world_hub/default`의 authored tilemap, background, image resource는
`gamebuild → gameapp View → Ebitengine renderer` 경계를 그대로 통과한다.
실제 Ubuntu arm64 창을 2 tick만 실행해 960×540 PNG를 캡처하고 자동
종료하는 visual acceptance로 타일 레이어, 카메라 변환, Tiled flip flag와
충돌벽 overlay를 확인했다. 같은 제한 실행에서 grove 보스의 authored
`scale=4`와 보라 tint를 확인했다. sprite sheet geometry, clip FPS/loop,
state map, non-looping 공격 시간과 `ability.sword_slash.visual`은 typed
`gamebuild → View → Ebitengine` 경계를 사용한다. audio는 별도 gate로
남긴다.

`stage.action_room`은 실제 창을 실행한 채 protocol로 player와 slime
좌표를 고정하고 `ability.fire_bolt`를 queue했다. 동일 tick의 화면에서
투사체를, `world` 응답에서 source·ability·이전/현재 위치를 확인했으며
명중 후에는 체력 감소와 `status.burning` 남은 시간·주기 시간을
대조했다. `internal/gameapp/combat_runtime_test.go`는 이 경로와
special/technique 의미 입력, 정확한 ability ID queue, whirlwind 3회
적중을 창 없이 반복 검증한다.

`stage.platformer_room`도 실제 창에서 move/jump 의미 입력으로 구동해
공중 위치·속도·접지 DTO와 화면을 대조하고, 180×24 authored 사각 발판의
중심 Y=375에 착지하는 것을 확인했다.
`internal/gameapp/platformer_runtime_test.go`는 동일한 작성 콘텐츠의
상승 높이·수평 이동·발판 착지와 shape View를 반복 검증하며,
`internal/sim/platformer_test.go`는 코요테 타임·점프 버퍼와 v4에서
도입한 platformer session 상태가 현재 v5에서도 보존되는지 렌더러 없이
검증한다.

`stage.encounter_room`은 작성된 `encounter.slime_trial`을 실제 창에서
실행했다. 정찰 두 마리를 protocol로 처치한 뒤 9 tick 지연과 보스의
정확한 생성 ID·좌표·체력 120을 확인했고, 체력을 60으로 낮춘 다음
`status.enraged`, `boss.phase_entered`, 붉은 tint 화면을 같은 tick에서
대조했다. 마지막 처치는 `encounter.wave_completed`,
`encounter.slime_trial_completed`, `encounter.completed` 순서로 끝난다.
`internal/gameapp/encounter_runtime_test.go`는 전체 작성 데이터 경로와
활성 encounter session v5 복원을 반복 검증하고,
`internal/sim/encounter_test.go`는 수동 시작·지연·event 순서·손상
mapping 거부·첫 wave 실패 topology 복원을 검증한다.

`Flow.getState`, `Flow.move`, `Flow.activate`는 title/pause/gameover/ending
화면을 외부 자동화가 의미 ID로 조회·제어하는 계약이다.
`Emulation.step`은 이 화면들이 활성화된 동안 오류로 거부되므로 화면
뒤의 World를 몰래 진행시킬 수 없다.

## 테스트 불변조건

- 모든 일반·race 테스트는 창을 만들지 않는다.
- stage 전환 실패는 현재 Campaign과 World를 한 바이트도 바꾸지 않는다.
- action 실패는 상태와 event outbox를 모두 rollback한다.
- dialogue choice 조건은 표시할 때와 선택 직전에 다시 평가한다.
- 한 kill event가 일치하는 여러 objective를 결정적인 순서로 갱신한다.
- quest completion과 보상은 같은 transaction이며 보상은 한 번뿐이다.
- player save는 project/content identity와 schema version이 다르면
  현재 runtime을 변경하지 않고 거부한다.
- transition을 일으킨 input edge는 새 World에 다시 전달하지 않는다.
- 손상된 save는 title의 정상 `continue` 항목으로 간주하지 않는다.
