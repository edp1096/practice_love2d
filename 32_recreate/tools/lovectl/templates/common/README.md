# {{PROJECT_TITLE}}

Recreate Maker 1.0의 `{{PROFILE}}` 프로필로 만든 독립 프로젝트다.
첫 실행은 타이틀에서 시작하며 기본 `campaign` 슬롯의 이어하기,
일시정지 저장, 게임오버와 엔딩 흐름을 공통 골격으로 사용한다.

```bash
go run ./tools/lovectl check
go run ./tools/lovectl smoke
go run ./tools/lovectl run
go run ./tools/lovectl package --output dist/game.love
```

주로 수정할 곳은 다음과 같다.

- `game/game.lua`: feature와 입력 조합
- `game/content`: 배우, 능력, 아이템, 대화, 퀘스트 등 데이터
- `game/maps`: Tiled TMX 원본
- `game/tests/smoke.json`: 프로젝트의 필수 수직 단면

콘텐츠 파일은 `go run ./tools/lovectl new`로 만들 수 있다. 엔진 동작을
바꾸지 않고 콘텐츠와 feature 조합부터 수정하는 것을 기본 작업 흐름으로
삼는다.
