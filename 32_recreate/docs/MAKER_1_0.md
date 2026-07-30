# Maker 1.0 진단과 완성 계획

## 목표

`32_recreate`를 샘플 게임 하나가 동작하는 코드가 아니라, 제작자가
애셋과 콘텐츠를 정리해 넣으면 RPG, 액션 RPG, 순수 액션 프로젝트를
반복해서 만들 수 있는 2D 제작 엔진으로 완성한다.

Maker 1.0의 제작 방식은 다음과 같다.

- Tiled에서 맵과 배치를 편집한다.
- `game/content`의 작은 데이터 파일에서 배우, 능력, 아이템, 대화,
  퀘스트와 인카운터를 편집한다.
- `lovectl`이 프로젝트 생성, 템플릿 생성, 참조 탐색, 전체 검증,
  실행 중 미리보기, 회귀 테스트와 패키징을 담당한다.
- 게임 코드는 장르별 분기를 직접 추가하지 않고 feature와 actor
  component를 조합한다.
- 엔진 오류와 콘텐츠 오류를 분리해 보고하며 콘텐츠 오류는 원본 파일,
  필드 경로와 관련 ID를 함께 표시한다.

Maker 1.0은 RPG Maker의 UI를 그대로 복제하는 목표가 아니다. Tiled와
텍스트 기반 콘텐츠를 공식 제작 화면으로 사용하되, 게임별 Lua 로직을
작성하지 않고도 아래 수직 단면을 완성할 수 있어야 한다.

1. 대화, 퀘스트, 인벤토리, 장비, 상점과 저장이 있는 RPG
2. 이동, 공격, 피격, 경직, 회피, 패링, 투사체와 보스전이 있는 액션
3. 위 두 기능을 같은 actor와 session에 조합한 액션 RPG

## 기준선 진단

2026-07-29의 `2669a91`을 기준으로 Lua 문법, 63개 Lua 테스트, 35개
콘텐츠 정의, 2개 TMX, Go 테스트, race 검사와 `go vet`은 통과했다.
하지만 다음 문제는 기존 검사가 다루지 않았다.

### P0: 게임 상태의 정확성

- 여러 action 중 뒤 action이 실패하면 앞 action의 변경이 남는다.
  trigger, 소비 아이템, 상호작용, 대화, 퀘스트, encounter와 전투
  effect가 서로 다른 실패 정책을 사용한다.
- 퀘스트와 encounter 일부 경로는 action 실패를 무시하고 완료 상태와
  성공 이벤트를 먼저 확정한다.
- status의 callback이 같은 status를 제거하거나 다시 적용하면 오래된
  실행 프레임이 새 상태를 덮어쓴다.
- 사망한 actor가 진행 중인 공격을 계속 적중시키며, 직접 체력 변경은
  사망 타이머와 도메인 이벤트를 우회한다.

### P0: 액션 게임 판정

- projectile이 한 tick에서 벽과 대상을 모두 통과하면 벽을 먼저
  처리한다. 여러 대상을 통과하면 실제로 가까운 대상이 아니라 entity
  생성 순서에 따라 적중한다.
- body schema는 이동하는 rectangle과 polygon을 허용하지만 motion은
  동적 circle 충돌만 해결한다.
- trigger와 portal의 위치 판정은 hurtbox offset과 비원형 body의
  실제 크기를 반영하지 않는다.

### P0: 장시간 실행

- 제거된 entity ID가 `entity_order`에 남아서 spawn/remove가 반복될수록
  모든 query와 snapshot 비용이 증가한다.
- 여러 entity를 같은 tick에 제거할 때 이벤트 순서가 결정적이지 않다.

### P1: 제작 입력과 생성물

- strict schema가 알 수 없는 숫자 key와 일부 condition/action의 오타를
  허용한다.
- asset 검사는 선언한 크기만 검사하고 실제 이미지 크기는 첫 렌더에서
  확인한다.
- TMX compile은 삭제하거나 이름을 바꾼 맵의 예전 generated stage를
  제거하지 않으며 여러 출력 파일을 직접 순차 교체한다.
- 단일 TMX `map check`가 선택하지 않은 정상 generated stage를 orphan으로
  오인할 수 있다.

### P1: 자동화 격리와 재사용성

- visual test가 고정된 데모 콘텐츠 ID에 결합되어 새 프로젝트의 엔진
  회귀 테스트로 재사용되지 않는다.
- test가 실제 LÖVE identity 아래 `visual_regression` save를 쓰고 남긴다.
- debug `Test.step --dt`가 고정 tick과 다른 의미를 가지며 큰 `dt`에서
  simulation 시간을 버린다.
- Go visual test 핵심 경로의 단위 테스트가 부족하다.

### P2: 제작자 경험

- 기존 프로젝트 안의 콘텐츠 파일은 생성할 수 있지만 RPG, 액션 RPG,
  액션용 새 프로젝트 전체를 만드는 명령이 없다.
- 장르별 최소 manifest, 입력, 필수 actor와 stage 예제가 공식 template로
  분리되어 있지 않다.
- 데모 검증 시나리오와 엔진 자체 회귀 시나리오의 경계가 없다.
- 문서의 “완료” 표시는 기능 존재 여부 중심이며 실패 원자성, 장시간
  실행과 샘플 독립성까지 증명하지 않는다.

## 설계 결정

### 1. action batch

모든 action 목록은 `World:executeActions` 하나를 사용한다.

- 기본 정책은 `atomic`이다.
- action이나 event listener가 실패하면 session, entity, feature state,
  spawn/remove queue와 request를 실행 전 상태로 복구한다.
- transaction 중 발생한 event는 commit 전까지 listener와 history에
  공개하지 않는다.
- 연출처럼 부분 성공이 의도된 경우에만 명시적으로 `best_effort`를
  사용한다.
- 실패 이벤트는 transaction 밖에서 한 번만 발행한다.

### 2. actor 생명주기

- `alive`, `dying`, `removed`의 의미를 체력 feature가 소유한다.
- 사망 시 공격, 회피, 패링, 경직과 넉백의 일시 상태를 취소한다.
- 부활은 별도 `revive` action으로만 가능하다.
- debug 명령도 동일한 `damage`, `heal`, `revive` service를 사용한다.

### 3. 충돌 결과

연속 이동 판정은 충돌 여부뿐 아니라 `fraction`, 충돌 위치, normal과
대상을 반환한다. projectile은 wall과 actor 후보를 한 목록에서 비교해
가장 작은 fraction을 먼저 처리한다. fraction이 같으면 안정적인 ID
순서를 사용한다.

Maker 1.0에서는 동적 solid body를 circle로 제한한다. rectangle과
polygon은 정적 geometry에서 지원한다. 범용 convex dynamic solver를
구현한 것처럼 schema가 오해하게 두지 않는다.

### 4. canonical 생성물

TMX compile은 모든 source를 메모리와 임시 디렉터리에서 먼저 완성한
후 generated 디렉터리를 교체한다. 전체 compile은 orphan을 제거하며,
선택 compile은 선택한 출력만 원자적으로 갱신하고 다른 출력은
보존한다.

### 5. 테스트 경계

- engine smoke scenario는 엔진과 함께 제공되는 최소 fixture만 사용한다.
- sample game scenario는 프로젝트가 선언한 scenario manifest를 읽는다.
- 테스트 프로세스는 매 실행마다 임시 LÖVE identity와 임시 save
  directory를 사용하고 종료 시 제거한다.
- visual test는 고정 ID가 없을 때 해당 기능을 무조건 실패시키지 않고,
  manifest가 요구한 capability만 검사한다.

### 6. 프로젝트 profile

공식 profile은 `rpg`, `action-rpg`, `action` 세 가지다. 각 profile은
필요한 feature, 입력 action, 최소 콘텐츠와 검증 capability를 선언한다.
`lovectl init`은 독립 실행과 재현 가능한 검사를 위해 현재 버전의
`engine`, `tools/lovectl`, `tests`를 새 프로젝트에 함께 복사한다. 게임
고유 composition과 콘텐츠는 이 번들과 분리되며, 프로젝트 manifest가
선택한 profile과 추가 feature를 명시한다. 엔진 갱신은 생성 당시 버전을
모호하게 추적하는 대신 검증된 새 번들로 명시적으로 승격한다.

## 구현 단계와 완료 조건

### M1. 정확성 기반

- [x] 공통 atomic action batch와 transactional event 구현
- [x] trigger, item, interaction, dialogue, quest, encounter, combat,
  projectile와 status를 공통 batch로 이전
- [x] 실패·중첩·재진입 회귀 테스트
- [x] entity order 정리와 결정적 removal 테스트
- [x] 사망·회복·부활 계약과 debug mutation 통일

완료 조건: 중간 action 실패 뒤 session/world/event snapshot이 실행
전과 같고, 보상과 완료 이벤트를 재시도로 중복 획득할 수 없다.

### M2. 액션 판정

- [x] projectile wall/actor 통합 time-of-impact 정렬
- [x] 가까운 대상, 벽 앞 대상, 관통과 동률 판정 테스트
- [x] 동적 body 지원 범위 schema와 runtime 일치
- [x] trigger/portal에서 hurtbox offset과 body extents 반영
- [x] status callback 재진입 안전성 테스트

완료 조건: 동일 입력과 fixed tick에서 충돌 및 event 순서가 반복 실행마다
동일하며 지원하지 않는 body 조합은 실행 전에 정확한 필드에서 실패한다.

### M3. 제작 파이프라인

- [x] 모든 object schema의 알 수 없는 key 거부
- [x] 실제 runtime asset metadata 검사
- [x] TMX generated output의 원자적 교체와 orphan 정리
- [x] 전체 compile과 선택 compile/check의 의미 분리
- [x] 오류 출력에 source와 field path 유지

완료 조건: 오타, 잘못된 애셋 크기, 삭제된 맵과 깨진 참조가 게임 실행
전에 `lovectl check`에서 발견되고 compile 실패 시 기존 generated
디렉터리가 한 파일도 바뀌지 않는다.

### M4. 자동화

- [x] test identity/save 완전 격리
- [x] engine fixture와 sample scenario 분리
- [x] fixed tick과 `step` 계약 통일
- [x] debug client disconnect, 입력 크기와 screenshot 요청 정리
- [x] Go 단위·통합 테스트 보강

완료 조건: 실제 사용자 save가 있는 상태에서도 test 전후 파일 목록과
내용이 같고, 샘플 콘텐츠 ID를 바꿔도 engine fixture 검사가 통과한다.

### M5. Maker 프로젝트

- [x] `lovectl init --profile rpg|action-rpg|action`
- [x] profile별 최소 실행 프로젝트와 콘텐츠 template
- [x] project capability와 scenario manifest 검증
- [x] actor/ability/RPG 콘텐츠 scaffold 개선
- [x] NPC interaction과 TMX trigger의 조건부 event page 카드 편집
- [x] 처음부터 실행·검사·패키지하는 제작자 안내서

완료 조건: 빈 임시 디렉터리에서 각 profile을 생성한 뒤 추가 엔진 코드
없이 `check`, smoke test와 deterministic package가 통과한다.

### M6. 전체 인수

- [x] Lua unit와 syntax
- [x] Go unit, integration, race와 vet
- [x] RPG 실제 화면 수직 단면
- [x] 액션 실제 화면 수직 단면
- [x] 액션 RPG save/load 수직 단면
- [x] 장시간 spawn/remove와 반복 action stress
- [x] 문서의 완료 표시와 실제 검사 결과 일치

2026-07-30 인수에서는 `lovectl check`의 Lua 114개 테스트와 콘텐츠
65개 정의, Go race/vet를 다시 통과했다. 빈 임시 디렉터리에서 세
profile을 각각 생성해 `check`, 격리된 실제 화면 `smoke`, 동일 SHA의
두 `.love` 패키지를 확인했다. 세 smoke는 새 프로젝트가 즉시 gameplay로
건너뛰지 않고 `new_game`, `accessibility`, `quit`가 있는 title에서
시작하는 화면까지 캡처한다. 같은 생성 프로젝트를 Ebitengine canonical catalog로도
컴파일해 세 profile 모두 title과 gameplay 제한 실행을 확인했다.
루트 `lovectl test`는 액션·패링·회피·
투사체·status·다단 히트·보스 phase·플랫포머·RPG·저장 화면 15개와
370 fixed tick을, `lovectl campaign`은 타이틀부터 프로세스 재시작
이어하기·집·잡화점·월드 아이템·피해 구역·엔딩·게임오버 및 실제
퍼펙트 패링과 접근성 설정 보존까지 화면 22개와 실제 게임패드 입력
264 fixed tick을 통과했다.
같은 캠페인은 보스 처치 후 18:30 시각과 저녁 마을 page도 검사한다.
두 명령이 만든 런타임은 종료 뒤 남지 않았으며 사용자 save 경로를
사용하지 않았다.

## 범위 경계

Maker 1.0은 Linux와 LÖVE 11.5를 기준으로 완료한다. Windows와 macOS
실행 파일, 코드 서명과 플랫폼별 installer는 다음 배포 단계다.

Tiled를 대체하는 자체 타일맵 GUI, 애니메이션 타임라인 GUI와 대화
노드 GUI는 Maker 1.0 런타임 정확성의 선행 조건이 아니다. 콘텐츠 규격과
CLI가 안정된 뒤 같은 schema를 사용하는 별도 편집기에서 추가할 수
있으며, 그때도 게임 런타임을 다시 작성하지 않는다.
