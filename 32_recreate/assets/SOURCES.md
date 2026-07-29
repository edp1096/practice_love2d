# 기존 애셋 이식 기록

현재 수직 단면에서 실제 사용하는 파일만 `31_dev_proto`에서 복사했다.
원본 프로젝트 파일은 변경하지 않았다.

| 새 asset ID | 기존 경로 | 새 경로 | SHA-256 |
|---|---|---|---|
| `image.player_sheet` | `31_dev_proto/assets/images/player/player-sheet.png` | `assets/runtime/images/player/player-sheet.png` | `a2087be8417968d612a06e0fa3e24db2efb614bb8bad6c0dd544b986ad23881f` |
| `image.slime_red_sheet` | `31_dev_proto/assets/images/sprites/enemies/enemy-sheet-slime-red.png` | `assets/runtime/images/enemies/slime-red-sheet.png` | `b1f88d57845caef6105ebcba227c5f1f9897e77a7997cd96f4b903aa430b017f` |
| `image.slash` | `31_dev_proto/assets/images/sprites/effects/effect-slash.png` | `assets/runtime/images/effects/slash.png` | `b085d707f6934344c43f20a9ac50ec4fadcdee7df82d84bce85da297fb787c86` |
| `image.world_tileset` | `31_dev_proto/assets/maps/level1/tileset_area1.png` | `assets/runtime/images/tilesets/tileset_area1.png` | `75334f5b575e7960b3ec51903626e46c17082f39d36a43814dd3cbacf53c0532` |
| `image.guide_sheet` | `31_dev_proto/assets/images/sprites/npcs/guide-sheet.png` | `assets/runtime/images/npcs/guide-sheet.png` | `c7c4291a60ff32e101b615d1964d672db514eca4a9a0ffffe7b7c712ecebc5d9` |
| `image.merchant_sheet` | `31_dev_proto/assets/images/sprites/npcs/merchant-sheet.png` | `assets/runtime/images/npcs/merchant-sheet.png` | `453267ed90602fe338fec27a7dfdff6a2598180dd00079246e1a9dc9d623b4f8` |
| `font.ui` | `31_dev_proto/assets/fonts/Hakgyoansim_ChaekgalpiR.ttf` | `assets/runtime/fonts/Hakgyoansim_ChaekgalpiR.ttf` | `a9a24de881bc3e26da0186a953f78c6f750e0ecb8eda52b051fa013cd1453587` |

기존 `assets` 디렉터리에서는 별도 라이선스 파일을 찾지 못했다. 외부
배포 전 각 원본 애셋의 라이선스와 크레딧 요구사항을 별도로 확인해야
한다.

`assets/runtime`은 게임과 `.love`에 들어갈 파일만 둔다. PSD, Aseprite,
고해상도 원본과 변환 프로젝트는 필요할 때 `assets/source` 아래에 두며
asset 콘텐츠에서 직접 참조하지 않는다.
