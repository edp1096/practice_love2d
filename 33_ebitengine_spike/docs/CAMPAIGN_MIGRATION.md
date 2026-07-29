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
- [ ] dialogue modal 입력과 화면 연결
- [x] 다중 목표 quest와 commit-after-success 보상 실행기
- [ ] simulation kill event와 Campaign quest 연결
- [x] inventory/equipment/economy/shop 도메인 transaction
- [ ] stat 반영, item use와 shop/inventory 화면
- [ ] title/pause/continue/gameover/ending
- [ ] tilemap과 data-driven presentation
- [ ] 프로세스 재시작을 포함한 headless campaign acceptance
- [ ] projectile/status/secondary ability 및 나머지 fixture

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
