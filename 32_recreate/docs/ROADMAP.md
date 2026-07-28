# 재작성 로드맵

`31_dev_proto`는 비교 가능한 동작 사양으로 유지한다. 새 기능은
`32_recreate`에서 수직 단면 단위로 완성하고 자동화한 뒤 이식한다.

## 1. 액션 기반 — 완료

- 콘텐츠 catalog와 엄격한 참조 검증
- feature/component/system 구조
- 의미 입력과 고정 틱
- 탑다운 이동, 벽 충돌
- 체력, 능력, 피해, 사망
- 공격 windup과 화면 예고
- 공격 활성·후딜과 데이터 기반 이동 잠금
- 시간축 hitbox와 독립 hurtbox
- 피격 경직과 짧은 피격 무적
- 넉백과 히트스톱
- 이동형 무적 회피
- 방향성 패링과 퍼펙트 패링
- 추적 AI
- 기존 애셋 기반 sprite animation
- 원격 의미 검사와 실화면 자동 테스트

완료 조건:

- RPG feature 없이 실행
- 자동 입력으로 실제 플레이어 이동 확인
- 자동 공격으로 선언된 피해량 확인
- 공격 후딜 동안 이동 잠금 확인
- 자동 공격으로 선언된 경직 확인
- 자동 공격의 hitbox, 넉백, 히트스톱 확인
- 적 공격을 회피 무적으로 실제 차단했는지 이벤트로 확인
- 적의 예고 공격에 맞춘 패링으로 피해 차단과 공격자 경직 확인
- 스크린샷과 semantic snapshot 동시 확보

## 2. 월드 제작 — 완료

- canonical stage section과 Go compiler
- 엄격한 Tiled class와 property 규격
- Tiled TMX → 순수 Lua stage content 변환
- rule 기반 trigger, ID 기반 portal과 spawn point
- rectangle·회전 rectangle·polygon 충돌
- tile culling, camera와 큰 맵 렌더링
- 맵 일괄 검증, 원격 stage preview와 실화면 자동화

기존의 레이어 이름 하드코딩을 그대로 이식하지 않는다.

완료 조건:

- 런타임에서 TMX/XML과 레이어 이름을 해석하지 않음
- generated stage가 TMX와 다르면 `check` 실패
- 잘못된 class, property, GID, portal 목적지가 실행 전에 실패
- 큰 맵에서 camera follow와 경계 clamp 확인
- 실제 화면에서 tile, polygon wall, trigger, 양방향 portal 확인

## 3. 액션 확장 — 완료

- 연속 충돌 판정, 관통과 벽 소멸을 갖는 projectile
- 중첩·주기 action·배율·면역을 갖는 status effect
- layer/mask 기반 동적 actor 충돌
- 제한 횟수와 간격이 명시된 연속·다단 hitbox
- 재사용 가능한 encounter, wave, boss health phase
- 가속·중력·코요테 타임·점프 버퍼를 갖는 횡스크롤 이동

탑다운과 플랫포머를 전역 `game_mode` 분기로 연결하지 않는다.

완료 조건:

- 빠른 projectile이 한 프레임 사이 대상을 건너뛰지 않음
- status의 주기 피해, 중첩, 이동·피해 배율과 면역 확인
- 동적 actor가 겹치지 않고 projectile은 의도한 mask로만 막힘
- 한 ability가 선언한 간격과 상한만큼만 재적중
- wave 완료 뒤 다음 wave가 열리고 체력 기준 boss phase가 한 번만 실행
- 같은 공용 충돌 위에서 플랫포머 점프와 착지 확인
- 모든 항목을 실제 LÖVE 프레임, snapshot과 screenshot으로 함께 검증

## 4. RPG 수직 단면 — 완료

- stage 전환과 transactional reload에 유지되는 session과 flags
- stack 제한, 소비 action과 확장 가능한 item section을 갖는 inventory
- 장비 loadout, 제거 guard와 attack·defense·move speed 파생 stats
- 조건부 choice, node action과 입력 gate를 갖는 dialogue graph
- 월드마다 다시 연결되는 quest event subscription과 데이터 보상
- 원자적 buy/sell을 보장하는 shop/economy
- 기본 언어, fallback과 런타임 전환을 갖는 locale
- NPC interactable, RPG HUD와 한글 font asset

완료 조건:

- NPC, 대화, 아이템, 퀘스트와 상점을 데이터 파일만으로 구성
- RPG feature를 끄면 관련 콘텐츠 종류, 시스템과 UI가 로드되지 않음
- action과 함께 켠 hero 장비 공격력이 실제 근접 피해에 반영됨
- `actor.killed` 두 건으로 퀘스트 완료와 보상이 정확히 한 번 발생
- 장착 아이템 판매를 차단하고 거래 잔액·수량을 원자적으로 유지
- stage 전환과 성공·실패 콘텐츠 reload 뒤 session 상태 보존
- 실제 LÖVE 한글 대화·HUD·상점 화면과 semantic snapshot 동시 확보

## 5. 제작 경험 — 완료

- actor, ability, projectile, status, encounter, stage, item, equipment,
  dialogue, quest, shop, locale용 `lovectl new`
- 검증된 참조만 기록하는 순·역방향 dependency graph와 JSON 출력
- 원격 content definition, stage·actor·ability·dialogue preview
- 콘텐츠·TMX·runtime asset 변경 감지와 transactional hot reload
- 파일·필드·참조 경로를 보존하는 오류와 graph edge
- 결정적 runtime-only `.love` compiler와 build manifest
- `assets/source`와 패키지 대상 `assets/runtime` 경계

완료 조건:

- 모든 생성 템플릿을 임시 프로젝트에 적용한 뒤 catalog 검증 통과
- item 하나의 대화·상점 역참조를 정확한 필드 경로로 조회
- 실행 중 새 콘텐츠 감지와 자동 reload를 실제 LÖVE에서 확인
- definition 조회, actor spawn/remove, ability와 dialogue preview 자동화
- 같은 입력으로 만든 두 `.love`의 SHA-256 일치
- 패키지에서 TMX, 도구, 문서, 테스트와 제작 원본 제외
- 생성된 `.love` 자체가 LÖVE 11.5 content check 통과

## 6. 저장과 Linux 배포 — 완료

- feature별 versioned session section과 순수 데이터 serializer
- section 단위 순차 schema migration
- project, stage, spawn과 content ID 호환 계약
- 저장 전 임시 파일과 rename을 사용하는 원자적 쓰기
- 후보 Host·World에서 검증한 뒤 교체하는 transactional load
- inventory, equipment, quest, locale의 현재 콘텐츠 참조 재검증
- save/load debug protocol과 `lovectl` 명령
- 실제 디스크 왕복 뒤 RPG 진행 상태 복원 자동화
- 결정적 runtime-only `.love` 패키징
- Linux LÖVE 11.5 원본 프로젝트와 패키지 부팅 검증

완료 조건:

- 손상·미지원·알 수 없는 section 로드가 현재 World를 바꾸지 않음
- feature v1 상태를 v2로 옮기는 migration 단위 테스트
- 돈·아이템·stage를 저장 후 변경하고 실제 파일 load로 원상 복원
- 퀘스트, flag, inventory, equipment, stats, economy, locale 동시 복원
- 저장 파일에 World 객체, 함수, userdata와 일시 전투 상태가 없음

Windows와 macOS의 실행 파일 패키징, 서명과 파일 교체 동작 검증은 해당
환경을 준비하는 다음 배포 단계로 분리한다.
