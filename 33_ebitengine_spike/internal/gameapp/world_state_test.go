package gameapp

import (
	"image/color"
	"math"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

func TestWorldRegionPageEdgesDriveDurableRulesAndPresentation(
	t *testing.T,
) {
	runtime := newTriggerRuntime(t, "stage.village", "default")
	player := entitySnapshot(t, runtime, "player")
	layerID := ""
	layerWasVisible := false
	if tilemap := runtime.View().Tilemap; tilemap != nil &&
		len(tilemap.Layers) > 0 {
		layerID = tilemap.Layers[0].ID
		layerWasVisible = tilemap.Layers[0].Visible
	}
	if layerID == "" {
		t.Fatal("village stage has no tile layer for world-page test")
	}

	runtime.mu.Lock()
	runtime.built.Stage.Triggers = nil
	runtime.built.Stage.Portals = nil
	runtime.resetTriggerStateLocked()
	exitX := coordPixels(player.Position.X)
	exitY := coordPixels(player.Position.Y)
	for _, spawn := range runtime.built.Stage.SpawnPoints {
		if squaredCoords(
			spawn.Position.X-player.Position.X,
			spawn.Position.Y-player.Position.Y,
		) <= uint64(sim.Pixels(100))*uint64(sim.Pixels(100)) {
			continue
		}
		exitX = coordPixels(spawn.Position.X)
		exitY = coordPixels(spawn.Position.Y)
		break
	}
	if exitX == coordPixels(player.Position.X) &&
		exitY == coordPixels(player.Position.Y) {
		runtime.mu.Unlock()
		t.Fatal("village has no distant valid spawn for region-exit test")
	}
	runtime.built.Stage.Regions = []gamebuild.WorldRegion{{
		ID: "test_square",
		Rect: sim.Rect{
			MinX: player.Position.X - sim.Pixels(24),
			MinY: player.Position.Y - sim.Pixels(24),
			MaxX: player.Position.X + sim.Pixels(24),
			MaxY: player.Position.Y + sim.Pixels(24),
		},
		OnEnter: []gamebuild.RuleAction{{
			Type:     gamebuild.RuleActionAddCurrency,
			Currency: 1,
		}},
		OnExit: []gamebuild.RuleAction{{
			Type:     gamebuild.RuleActionAddCurrency,
			Currency: 2,
		}},
	}}
	runtime.built.Stage.WorldPages = []gamebuild.WorldPage{{
		ID: "inside_square",
		Condition: &gamebuild.RuleCondition{
			Type:     gamebuild.RuleConditionRegionActive,
			RegionID: "test_square",
		},
		Tint:    [4]float64{0.1, 0.2, 0.3, 0.4},
		TintSet: true,
		Layers: []gamebuild.WorldLayerOverride{{
			ID:      layerID,
			Visible: !layerWasVisible,
		}},
		OnEnter: []gamebuild.RuleAction{{
			Type:     gamebuild.RuleActionAddCurrency,
			Currency: 4,
		}},
		OnExit: []gamebuild.RuleAction{{
			Type:     gamebuild.RuleActionAddCurrency,
			Currency: 8,
		}},
	}}
	beforeCurrency := runtime.campaign.Snapshot().Currency
	runtime.mu.Unlock()

	// Page selection runs before region edges, just like 32_recreate. The
	// first tick enters the region; the second selects its dependent page.
	stepProtocol(t, runtime, 1)
	world := runtime.worldSnapshotLocked()
	if got := world.WorldState.ActiveRegions; len(got) != 1 ||
		got[0] != "test_square" ||
		world.WorldState.ActivePage != "" {
		t.Fatalf("first world edge = %#v", world.WorldState)
	}
	if got := runtime.CampaignState().Currency; got != beforeCurrency+1 {
		t.Fatalf("region-enter currency = %d, want %d", got, beforeCurrency+1)
	}

	stepProtocol(t, runtime, 1)
	view := runtime.View()
	world = runtime.worldSnapshotLocked()
	if world.WorldState.ActivePage != "inside_square" {
		t.Fatalf("active world page = %#v", world.WorldState)
	}
	if view.World.Tint != (color.RGBA{R: 26, G: 51, B: 77, A: 102}) {
		t.Fatalf("world tint = %#v", view.World.Tint)
	}
	if got := tileLayerVisibility(t, view, layerID); got == layerWasVisible {
		t.Fatalf(
			"world page layer %q visibility = %t, want override",
			layerID,
			got,
		)
	}
	if got := runtime.CampaignState().Currency; got != beforeCurrency+5 {
		t.Fatalf("page-enter currency = %d, want %d", got, beforeCurrency+5)
	}

	setEntityPosition(t, runtime, "player", exitX, exitY)
	stepProtocol(t, runtime, 1)
	if got := runtime.CampaignState().Currency; got != beforeCurrency+7 {
		t.Fatalf("region-exit currency = %d, want %d", got, beforeCurrency+7)
	}
	stepProtocol(t, runtime, 1)
	view = runtime.View()
	world = runtime.worldSnapshotLocked()
	if world.WorldState.ActivePage != "" ||
		len(world.WorldState.ActiveRegions) != 0 {
		t.Fatalf("cleared world state = %#v", world.WorldState)
	}
	if view.World.Tint.A != 0 {
		t.Fatalf("cleared world tint = %#v", view.World.Tint)
	}
	if got := tileLayerVisibility(t, view, layerID); got != layerWasVisible {
		t.Fatalf(
			"restored layer %q visibility = %t, want %t",
			layerID,
			got,
			layerWasVisible,
		)
	}
	if got := runtime.CampaignState().Currency; got != beforeCurrency+15 {
		t.Fatalf("page-exit currency = %d, want %d", got, beforeCurrency+15)
	}
}

func TestWorldClockSelectsOvernightPageAndAppearsInDebugState(
	t *testing.T,
) {
	runtime := newTriggerRuntime(t, "stage.village", "default")
	runtime.mu.Lock()
	runtime.built.Stage.Triggers = nil
	runtime.resetTriggerStateLocked()
	runtime.built.Stage.WorldPages = []gamebuild.WorldPage{{
		ID: "night",
		Condition: &gamebuild.RuleCondition{
			Type:         gamebuild.RuleConditionTimeBetween,
			StartMinute:  18 * 60,
			FinishMinute: 6 * 60,
		},
		Tint:    [4]float64{0.02, 0.04, 0.1, 0.5},
		TintSet: true,
	}}
	err := runtime.campaign.Transaction(func(state *campaign.State) error {
		state.World.Day = 2
		state.World.Minute = 23*60 + 45
		return nil
	})
	runtime.mu.Unlock()
	if err != nil {
		t.Fatal(err)
	}

	stepProtocol(t, runtime, 1)
	world := runtime.worldSnapshotLocked().WorldState
	if world.Day != 2 || world.Minute != 23*60+45 ||
		world.Clock != "23:45" || world.ActivePage != "night" {
		t.Fatalf("night world state = %#v", world)
	}
}

func TestAutomaticWorldClockUsesFixedTickProjectRate(t *testing.T) {
	runtime := newTriggerRuntime(t, "stage.village", "default")
	runtime.mu.Lock()
	runtime.built.Stage.Triggers = nil
	runtime.built.Stage.Portals = nil
	runtime.resetTriggerStateLocked()
	runtime.campaignConfig.WorldSecondsPerDay = 60
	start := runtime.campaign.Snapshot().World.Minute
	runtime.mu.Unlock()

	stepProtocol(t, runtime, 60)
	world := runtime.worldSnapshotLocked().WorldState
	if math.Abs(world.Minute-(start+24)) > 1e-9 ||
		world.Clock != "08:24" ||
		world.SecondsPerDay != 60 {
		t.Fatalf("automatic world clock = %#v, start=%v", world, start)
	}
}

func tileLayerVisibility(
	t *testing.T,
	view ebitapp.View,
	id string,
) bool {
	t.Helper()
	if view.Tilemap == nil {
		t.Fatal("view has no tilemap")
	}
	for _, layer := range view.Tilemap.Layers {
		if layer.ID == id {
			return layer.Visible
		}
	}
	t.Fatalf("view has no tile layer %q", id)
	return false
}
