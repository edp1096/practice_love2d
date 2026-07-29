# Third-party notices

This spike does not copy Ebitengine or GopherLua source code into the
repository. Their packages are resolved by the Go module system.

| Component | Use | License |
| --- | --- | --- |
| [Ebitengine](https://github.com/hajimehoshi/ebiten) | Runtime graphics, input, audio and platform adapter | Apache-2.0 |
| [GopherLua](https://github.com/yuin/gopher-lua) | Build-time import of pure Lua content tables | MIT |

Ebitengine's transitive notices remain available from its module
`NOTICE.md`. A release packager must copy the applicable license and notice
files into the shipped product.

The sample bitmap and font assets are copied unchanged from
`32_recreate/assets/runtime`. Their provenance remains documented in
`32_recreate/assets/SOURCES.md`; this spike does not grant additional rights.

Nintendo Switch, Xbox and PlayStation platform SDKs are not included. Their
availability and redistribution terms are controlled by the corresponding
platform-holder agreements.
