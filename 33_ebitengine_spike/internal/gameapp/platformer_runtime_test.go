package gameapp

import (
	"math"
	"path/filepath"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/sim"
	"practice_love2d/33_ebitengine_spike/internal/storage"
)

func TestAuthoredPlatformerJumpsAndLandsOnRaisedPlatform(t *testing.T) {
	store, err := storage.NewFileStore(filepath.Join(t.TempDir(), "saves"))
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{
		CatalogPath: filepath.Join("..", "..", "game", "catalog.json"),
		Build: gamebuild.Options{
			StageID:  "stage.platformer_room",
			LocaleID: "locale.ko",
		},
		Store: store,
	})
	if err != nil {
		t.Fatal(err)
	}

	if err := runtime.Tick(ebitapp.Actions{}); err != nil {
		t.Fatal(err)
	}
	start := entitySnapshot(t, runtime, "player")
	if start.Platformer == nil || !start.Grounded ||
		start.Position.Y != sim.Pixels(485) {
		t.Fatalf("platformer did not settle on authored floor: %#v", start)
	}

	if err := runtime.Tick(ebitapp.Actions{MoveX: 1, Jump: true}); err != nil {
		t.Fatal(err)
	}

	jumped := false
	for _, event := range runtime.simulation.Snapshot().Events {
		jumped = jumped || event.Type == sim.EventPlatformerJumped
	}
	landed := false
	apexY := start.Position.Y
	for tick := 0; tick < 120; tick++ {
		actions := ebitapp.Actions{}
		if tick < 24 {
			actions.MoveX = 1
		}
		if err := runtime.Tick(actions); err != nil {
			t.Fatal(err)
		}
		snapshot := runtime.simulation.Snapshot()
		player := entitySnapshot(t, runtime, "player")
		apexY = min(apexY, player.Position.Y)
		for _, event := range snapshot.Events {
			jumped = jumped || event.Type == sim.EventPlatformerJumped
			landed = landed || event.Type == sim.EventPlatformerLanded
		}
		if landed && player.Grounded {
			break
		}
	}
	player := entitySnapshot(t, runtime, "player")
	if !jumped || !landed || !player.Grounded ||
		math.Abs(coordPixels(player.Position.Y)-375) > 0.01 ||
		coordPixels(start.Position.Y-apexY) < 105 ||
		coordPixels(player.Position.X-start.Position.X) < 60 {
		t.Fatalf(
			"authored platformer path failed: jumped=%v landed=%v start=%#v player=%#v apex_y=%f",
			jumped,
			landed,
			start,
			player,
			coordPixels(apexY),
		)
	}

	runtime.mu.RLock()
	world := runtime.worldSnapshotLocked()
	runtime.mu.RUnlock()
	var dto entityDTO
	for _, entity := range world.Entities {
		if entity.ID == "player" {
			dto = entity
			break
		}
	}
	if !dto.Platformer || !dto.Grounded ||
		dto.PlatformerSpeed <= 0 ||
		dto.PlatformerGravity <= 0 ||
		dto.PlatformerJumpSpeed <= 0 {
		t.Fatalf("platformer is not inspectable through world DTO: %#v", dto)
	}

	view := runtime.View()
	shapes := make(map[string]ebitapp.EntityView)
	for _, entity := range view.Entities {
		if entity.ID == "visual.floor" ||
			entity.ID == "visual.raised_platform" {
			shapes[entity.ID] = entity
		}
	}
	if floor := shapes["visual.floor"]; floor.Shape != "rectangle" ||
		floor.Width != 960 || floor.Height != 40 ||
		floor.Tint.A == 0 || floor.Outline.A == 0 {
		t.Fatalf("authored floor render shape = %#v", floor)
	}
	if platform := shapes["visual.raised_platform"]; platform.Shape != "rectangle" ||
		platform.Width != 180 || platform.Height != 24 ||
		platform.Tint.A == 0 || platform.Outline.A == 0 {
		t.Fatalf("authored platform render shape = %#v", platform)
	}
}
