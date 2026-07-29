# Sample audio provenance

`runtime/audio`의 WAV 파일은 외부 음원을 복사한 것이 아니다.
[`tools/audiofixtures`](../tools/audiofixtures)가 표준 Go 라이브러리만으로
합성한 이 프로젝트의 원본 fixture다. 같은 명령으로 byte-for-byte
재생성할 수 있다.

```bash
go run ./tools/audiofixtures -output assets/runtime
```

게임 제작자는 동일한 ID와 `game/game.lua` routing을 유지한 채 자기
WAV로 교체하거나, asset 정의와 cue/stage mapping을 함께 수정하면 된다.
