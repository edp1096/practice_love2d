# 기존 애셋 이식 기록

현재 수직 단면에서 실제 사용하는 파일만 `31_dev_proto`에서 복사했다.
원본 프로젝트 파일은 변경하지 않았다.

| 새 asset ID | 기존 경로 | 새 경로 | SHA-256 |
|---|---|---|---|
| `image.player_sheet` | `31_dev_proto/assets/images/player/player-sheet.png` | `assets/runtime/images/player/player-sheet.png` | `a2087be8417968d612a06e0fa3e24db2efb614bb8bad6c0dd544b986ad23881f` |
| `image.slime_red_sheet` | `31_dev_proto/assets/images/sprites/enemies/enemy-sheet-slime-red.png` | `assets/runtime/images/enemies/slime-red-sheet.png` | `b1f88d57845caef6105ebcba227c5f1f9897e77a7997cd96f4b903aa430b017f` |
| `image.slash` | `31_dev_proto/assets/images/sprites/effects/effect-slash.png` | `assets/runtime/images/effects/slash.png` | `b085d707f6934344c43f20a9ac50ec4fadcdee7df82d84bce85da297fb787c86` |
| `image.world_tileset` | `31_dev_proto/assets/maps/level1/tileset_area1.png` | `assets/runtime/images/tilesets/tileset_area1.png` | `75334f5b575e7960b3ec51903626e46c17082f39d36a43814dd3cbacf53c0532` |
| `image.interior_tileset` | `31_dev_proto/assets/maps/level1/tileset_interior1.png` | `assets/runtime/images/tilesets/tileset_interior1.png` | `aafb346da6511222b6cc110f7ce67e698d786a02bda16c91e1c34c60c507a525` |
| `image.guide_sheet` | `31_dev_proto/assets/images/sprites/npcs/guide-sheet.png` | `assets/runtime/images/npcs/guide-sheet.png` | `c7c4291a60ff32e101b615d1964d672db514eca4a9a0ffffe7b7c712ecebc5d9` |
| `image.merchant_sheet` | `31_dev_proto/assets/images/sprites/npcs/merchant-sheet.png` | `assets/runtime/images/npcs/merchant-sheet.png` | `453267ed90602fe338fec27a7dfdff6a2598180dd00079246e1a9dc9d623b4f8` |
| `image.poison_jar_sheet` | `30_misc/assets/maps/level1/poison_jar.png` | `assets/runtime/images/items/poison-jar.png` | `832dd469dce60e97f293d74a297180cc4aecc14a7f9fd295b363b75dd659340a` |
| `font.ui` | `31_dev_proto/assets/fonts/Hakgyoansim_ChaekgalpiR.ttf` | `assets/runtime/fonts/Hakgyoansim_ChaekgalpiR.ttf` | `a9a24de881bc3e26da0186a953f78c6f750e0ecb8eda52b051fa013cd1453587` |

다음 오디오는 외부 음원을 가져온 것이 아니라
`33_ebitengine_spike/tools/audiofixtures`가 생성한 프로젝트 원본이다.

| asset ID | 경로 | SHA-256 |
|---|---|---|
| `audio.forest_theme` | `assets/runtime/audio/music/forest-theme.wav` | `96457c52293a384fa1e39f67366014d60303efda5aed2206b3d2bdcf3e6f35aa` |
| `audio.road_theme` | `assets/runtime/audio/music/road-theme.wav` | `6e60c4fd8951b3107b1b05f86dde3745987a5793c9e75ea2ddd81f406d9b51c9` |
| `audio.village_theme` | `assets/runtime/audio/music/village-theme.wav` | `1e92ef7ba897c4bfabee14c46bdec8b102a353d995130d4abe975490ed23437a` |
| `audio.attack` | `assets/runtime/audio/sfx/attack.wav` | `9a76f7aba36fc2617d31717e197a3e46f380c120053c197a1f07559ab65b7d53` |
| `audio.hit` | `assets/runtime/audio/sfx/hit.wav` | `de0b25792b09326b702e7c26a55e59349d96ac996a7f42fbf5ae0b0183923ddd` |
| `audio.jump` | `assets/runtime/audio/sfx/jump.wav` | `1995ca22020b48fd91c77f24ae908b1b1ad2a7cf6b422ef873a90664b1b41f91` |
| `audio.kill` | `assets/runtime/audio/sfx/kill.wav` | `1016bb8538c6e63357abedbc84f3097c2c5662c0b22c745283918ddd9feaec87` |
| `audio.parry` | `assets/runtime/audio/sfx/parry.wav` | `7cf9f17b900f4e6a9595bd279d1c0698d12f0fb467ad61fe2da8c35845f3f20b` |
| `audio.projectile` | `assets/runtime/audio/sfx/projectile.wav` | `022b41778afdbf22a10664aa3ca9eb349711be0845fc6504cde9bb65336f57dd` |
| `audio.quest` | `assets/runtime/audio/sfx/quest.wav` | `07c262b9b2d88c8b89f24527049c609f2f37f8cf865ae4a7e96844173e15effd` |
| `audio.ui_cancel` | `assets/runtime/audio/sfx/ui-cancel.wav` | `1dcacd029776aea0047b953f71b924dd4a43163c0876339b0b272230a0d6c8bb` |
| `audio.ui_confirm` | `assets/runtime/audio/sfx/ui-confirm.wav` | `de408767d84dcbd7107ecb680d94e782208806378099bce0c7196d22887f6c87` |

기존 `assets` 디렉터리에서는 별도 라이선스 파일을 찾지 못했다. 외부
배포 전 각 원본 애셋의 라이선스와 크레딧 요구사항을 별도로 확인해야
한다.

`assets/runtime`은 게임과 `.love`에 들어갈 파일만 둔다. PSD, Aseprite,
고해상도 원본과 변환 프로젝트는 필요할 때 `assets/source` 아래에 두며
asset 콘텐츠에서 직접 참조하지 않는다.
