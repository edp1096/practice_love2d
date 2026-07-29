package gameapp

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	gamecatalog "practice_love2d/33_ebitengine_spike/game"
	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/protocol"
	"practice_love2d/33_ebitengine_spike/internal/sim"
	"practice_love2d/33_ebitengine_spike/internal/storage"
)

func newCampaignRuntime(t *testing.T) *Runtime {
	t.Helper()
	store, err := storage.NewFileStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{Store: store})
	if err != nil {
		t.Fatal(err)
	}
	return runtime
}

func TestRuntimeStartsCampaignAndWorldAtManifestLocation(t *testing.T) {
	t.Parallel()
	runtime := newCampaignRuntime(t)
	state := runtime.campaign.Snapshot()
	if state.CurrentStageID != "stage.village" ||
		state.EntrySpawnID != "default" ||
		state.Locale != "locale.ko" {
		t.Fatalf("campaign location = %#v", state)
	}
	if runtime.built.Stage.ID != state.CurrentStageID ||
		runtime.buildOptions.StageID != state.CurrentStageID ||
		runtime.buildOptions.SpawnID != state.EntrySpawnID {
		t.Fatalf(
			"world/campaign mismatch: stage=%q options=%#v state=%#v",
			runtime.built.Stage.ID,
			runtime.buildOptions,
			state,
		)
	}
}

func TestCampaignReloadTopologyGuardsEveryDurableAxis(t *testing.T) {
	t.Parallel()
	runtime := newCampaignRuntime(t)
	base := runtime.campaignConfig

	compatible := base.Clone()
	compatible.ContentID = "sha256:edited-presentation"
	compatible.DefaultLocale = "locale.en"
	if err := validateCampaignReloadTopology(base, compatible); err != nil {
		t.Fatalf("compatible presentation reload rejected: %v", err)
	}
	state := runtime.campaign.Snapshot()
	state.Currency = 37
	restored, err := restoreReloadedCampaign(
		compatible,
		state,
		"locale.en",
	)
	if err != nil {
		t.Fatal(err)
	}
	got := restored.Snapshot()
	if got.ContentID != compatible.ContentID ||
		got.Locale != "locale.en" ||
		got.Currency != 37 {
		t.Fatalf("restored hot-reload campaign = %#v", got)
	}

	tests := []struct {
		name   string
		mutate func(*campaign.Config)
	}{
		{
			name: "project identity",
			mutate: func(config *campaign.Config) {
				config.ProjectID = "other.project"
			},
		},
		{
			name: "config version",
			mutate: func(config *campaign.Config) {
				config.Version++
			},
		},
		{
			name: "initial location",
			mutate: func(config *campaign.Config) {
				config.InitialStageID = "stage.world_hub"
				config.InitialEntrySpawnID = "village_entry"
			},
		},
		{
			name: "locale IDs",
			mutate: func(config *campaign.Config) {
				config.Locales = append(config.Locales, "locale.extra")
			},
		},
		{
			name: "stage entries",
			mutate: func(config *campaign.Config) {
				config.Stages[0].EntrySpawns[0] = "changed"
			},
		},
		{
			name: "flag IDs",
			mutate: func(config *campaign.Config) {
				config.Flags = append(config.Flags, "flag.extra")
			},
		},
		{
			name: "item definitions",
			mutate: func(config *campaign.Config) {
				config.Items[0].MaxQuantity++
			},
		},
		{
			name: "equipment slots",
			mutate: func(config *campaign.Config) {
				config.EquipmentSlots = append(
					config.EquipmentSlots,
					"accessory",
				)
			},
		},
		{
			name: "quest objectives",
			mutate: func(config *campaign.Config) {
				config.Quests[0].Objectives[0].Required++
			},
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			edited := base.Clone()
			edited.ContentID = "sha256:" + test.name
			test.mutate(&edited)
			if err := validateCampaignReloadTopology(base, edited); err == nil {
				t.Fatal("incompatible campaign topology was accepted")
			}
		})
	}
}

func TestReloadAfterPortalPreservesCurrentWorldAndCampaign(t *testing.T) {
	runtime := newCampaignRuntime(t)
	moveEntityToPortal(t, runtime, "player", "to_field")
	stepProtocol(t, runtime, 1)
	if err := runtime.campaign.Transaction(func(state *campaign.State) error {
		state.Currency = 23
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetHealth,
		protocol.SetHealthParams{
			EntityID: "enemy.slime.1",
			Value:    1,
		},
	)
	beforeSession := runtime.simulation.SaveSession()
	callRuntime(
		t,
		runtime,
		protocol.MethodAppReloadContent,
		protocol.EmptyParams{},
	)
	assertLocation(t, runtime, "stage.world_hub", "village_entry")
	if got := runtime.campaign.Snapshot().Currency; got != 23 {
		t.Fatalf("reload reset campaign currency to %d", got)
	}
	assertDeepEqual(
		t,
		"current field session",
		runtime.simulation.SaveSession(),
		beforeSession,
	)
}

func TestReloadRejectsChangedProjectIdentityAtomically(t *testing.T) {
	t.Parallel()
	catalogPath := filepath.Join(t.TempDir(), "catalog.json")
	if err := os.WriteFile(catalogPath, gamecatalog.Bytes(), 0o600); err != nil {
		t.Fatal(err)
	}
	store, err := storage.NewFileStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{CatalogPath: catalogPath, Store: store})
	if err != nil {
		t.Fatal(err)
	}
	beforeCampaign := runtime.campaign
	beforeState := runtime.campaign.Snapshot()
	beforeSession := runtime.simulation.SaveSession()
	beforeBuilt := runtime.built
	beforeRevision := runtime.revision

	data, err := os.ReadFile(catalogPath)
	if err != nil {
		t.Fatal(err)
	}
	var document map[string]any
	if err := json.Unmarshal(data, &document); err != nil {
		t.Fatal(err)
	}
	document["project"].(map[string]any)["id"] = "other.project"
	edited, err := json.Marshal(document)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(catalogPath, edited, 0o600); err != nil {
		t.Fatal(err)
	}
	err = runtime.reloadContent(context.Background())
	if err == nil || !strings.Contains(err.Error(), "project identity") {
		t.Fatalf("changed project reload error = %v", err)
	}
	if runtime.campaign != beforeCampaign ||
		runtime.built != beforeBuilt ||
		runtime.revision != beforeRevision {
		t.Fatal("changed project reload changed runtime identity")
	}
	assertDeepEqual(t, "campaign", runtime.campaign.Snapshot(), beforeState)
	assertDeepEqual(t, "session", runtime.simulation.SaveSession(), beforeSession)
}

func TestExplicitBuildOverrideHasMatchingCampaignLocation(t *testing.T) {
	t.Parallel()
	store, err := storage.NewFileStore(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{
		Build: gamebuild.Options{
			StageID:  "stage.world_grove",
			LocaleID: "locale.en",
		},
		Store: store,
	})
	if err != nil {
		t.Fatal(err)
	}
	state := runtime.campaign.Snapshot()
	if state.CurrentStageID != "stage.world_grove" ||
		state.EntrySpawnID != "west_entry" ||
		state.Locale != "locale.en" {
		t.Fatalf("explicit campaign location = %#v", state)
	}
	if runtime.buildOptions.SpawnID != "" {
		t.Fatalf(
			"authored-position override unexpectedly resolved spawn %q",
			runtime.buildOptions.SpawnID,
		)
	}
}

func TestPortalRoundTripRebuildsWorldAndPreservesCampaign(t *testing.T) {
	runtime := newCampaignRuntime(t)
	if err := runtime.campaign.Transaction(func(state *campaign.State) error {
		state.Currency = 17
		return nil
	}); err != nil {
		t.Fatal(err)
	}

	// Dialogue, camera shake, and the current input edge all belong to the old
	// World. Open authored dialogue first so its reset is observable.
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: "player",
			X:        350,
			Y:        240,
		},
	)
	scheduleProtocolAction(t, runtime, "interact")
	stepProtocol(t, runtime, 1)
	if !runtime.simulation.Snapshot().Dialogue.Active {
		t.Fatal("authored village dialogue did not open before transition")
	}
	// Also mutate an NPC position so returning to the stage proves the whole
	// stage-local entity set is reconstructed.
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: "guide",
			X:        880,
			Y:        270,
		},
	)
	moveEntityToPortal(t, runtime, "player", "to_field")
	session := runtime.simulation.SaveSession()
	session.Camera.ShakeMagnitude = sim.Pixels(5)
	session.Camera.ShakeDuration = 10
	session.Camera.ShakeRemaining = 10
	if err := runtime.simulation.LoadSession(session); err != nil {
		t.Fatal(err)
	}
	beforeRevision := runtime.revision
	stepProtocol(t, runtime, 1)
	if runtime.revision != beforeRevision+1 {
		t.Fatalf(
			"successful transition revision = %d, want %d",
			runtime.revision,
			beforeRevision+1,
		)
	}
	assertLocation(t, runtime, "stage.world_hub", "village_entry")
	assertFreshWorld(t, runtime, 80, 288)
	if runtime.simulation.Snapshot().Dialogue.Active {
		t.Fatal("village dialogue crossed into field World")
	}
	if runtime.simulation.Snapshot().Camera.ShakeTicks != 0 {
		t.Fatal("village camera shake crossed into field World")
	}
	if got := runtime.campaign.Snapshot().Currency; got != 17 {
		t.Fatalf("campaign currency after village portal = %d", got)
	}

	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetHealth,
		protocol.SetHealthParams{
			EntityID: "enemy.slime.1",
			Value:    1,
		},
	)
	moveEntityToPortal(t, runtime, "player", "to_grove")
	beforeRevision = runtime.revision
	scheduleProtocolAction(t, runtime, "attack")
	stepProtocol(t, runtime, 1)
	if runtime.revision != beforeRevision+1 {
		t.Fatalf(
			"attack transition revision = %d, want %d",
			runtime.revision,
			beforeRevision+1,
		)
	}
	assertLocation(t, runtime, "stage.world_grove", "west_entry")
	assertFreshWorld(t, runtime, 96, 288)
	if got := entitySnapshot(t, runtime, "player").Attack.Phase; got != sim.AttackIdle {
		t.Fatalf("transition input edge replayed attack phase %q", got)
	}
	if hasEntity(runtime.simulation.Snapshot(), "enemy.slime.1") {
		t.Fatal("field enemy crossed into grove World")
	}
	if !hasEntity(runtime.simulation.Snapshot(), "boss.grove_guardian") {
		t.Fatal("fresh grove boss is missing")
	}

	// Entering during cooldown latches the portal. Expiry while still inside
	// must not bounce back; leaving and entering again must transition.
	moveEntityToPortal(t, runtime, "player", "to_hub")
	stepProtocol(t, runtime, 15)
	if runtime.portalCooldownTicks != 0 {
		t.Fatalf("portal cooldown = %d", runtime.portalCooldownTicks)
	}
	if got := runtime.built.Stage.ID; got != "stage.world_grove" {
		t.Fatalf("inside latch bounced to %q", got)
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: "player",
			X:        96,
			Y:        288,
		},
	)
	stepProtocol(t, runtime, 1)
	moveEntityToPortal(t, runtime, "player", "to_hub")
	stepProtocol(t, runtime, 1)
	assertLocation(t, runtime, "stage.world_hub", "grove_return")
	assertFreshWorld(t, runtime, 980, 288)
	if got := entitySnapshot(t, runtime, "enemy.slime.1").Health; got <= 1 {
		t.Fatalf("field enemy transient health was retained: %d", got)
	}

	if runtime.portalCooldownTicks > 0 {
		stepProtocol(t, runtime, runtime.portalCooldownTicks)
	}
	moveEntityToPortal(t, runtime, "player", "to_village")
	stepProtocol(t, runtime, 1)
	assertLocation(t, runtime, "stage.village", "field_return")
	assertFreshWorld(t, runtime, 850, 270)
	guide := entitySnapshot(t, runtime, "guide")
	if guide.Position != (sim.Vec{X: sim.Pixels(310), Y: sim.Pixels(240)}) {
		t.Fatalf("village guide transient position = %#v", guide.Position)
	}
	if got := runtime.campaign.Snapshot().Currency; got != 17 {
		t.Fatalf("campaign currency after round trip = %d", got)
	}
}

func TestPortalOverlapUsesExactPolygonAndStrictEdges(t *testing.T) {
	t.Parallel()
	runtime := newCampaignRuntime(t)
	built := *runtime.built
	built.Config.StageBounds.MaxX = sim.Pixels(1000)
	built.Stage.Portals = []gamebuild.Portal{{
		ID: "diamond",
		Rect: sim.Rect{
			MinX: sim.Pixels(860),
			MinY: sim.Pixels(230),
			MaxX: sim.Pixels(940),
			MaxY: sim.Pixels(310),
		},
		Points: []sim.Vec{
			{X: sim.Pixels(860), Y: sim.Pixels(270)},
			{X: sim.Pixels(900), Y: sim.Pixels(230)},
			{X: sim.Pixels(940), Y: sim.Pixels(270)},
			{X: sim.Pixels(900), Y: sim.Pixels(310)},
		},
		TargetStageID: "stage.world_hub",
		TargetSpawnID: "village_entry",
	}}
	simulation, err := sim.New(built.Config)
	if err != nil {
		t.Fatal(err)
	}
	tests := []struct {
		name     string
		position sim.Vec
		want     bool
	}{
		{
			name: "inside exact polygon",
			position: sim.Vec{
				X: sim.Pixels(900),
				Y: sim.Pixels(270),
			},
			want: true,
		},
		{
			name: "inside bounds outside polygon",
			position: sim.Vec{
				X: sim.Pixels(864),
				Y: sim.Pixels(234),
			},
			want: false,
		},
		{
			name: "body edge touches polygon vertex",
			position: sim.Vec{
				X: sim.Pixels(955),
				Y: sim.Pixels(270),
			},
			want: false,
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			state := simulation.SaveSession()
			for index := range state.Entities {
				if state.Entities[index].ID == "player" {
					state.Entities[index].Position = test.position
				}
			}
			center := clampCameraTarget(
				test.position,
				built.Config.StageBounds,
				built.Config.Camera,
			)
			state.Camera = sim.CameraSessionState{
				BaseCenter: center,
				Center:     center,
			}
			if err := simulation.LoadSession(state); err != nil {
				t.Fatal(err)
			}
			overlaps, err := portalOverlaps(&built, simulation)
			if err != nil {
				t.Fatal(err)
			}
			if got := overlaps["diamond"]; got != test.want {
				t.Fatalf("polygon portal overlap = %t, want %t", got, test.want)
			}
		})
	}
}

func TestPortalTransitionDelaysMakerPreview(t *testing.T) {
	runtime := newCampaignRuntime(t)
	result, err := runtime.spawnEntity(protocol.SpawnEntityParams{
		ActorID:  "actor.slime",
		EntityID: "preview.slime",
		X:        floatPointer(500),
		Y:        floatPointer(400),
	})
	if err != nil {
		t.Fatal(err)
	}
	if result == nil {
		t.Fatal("spawn preview returned nil")
	}
	moveEntityToPortal(t, runtime, "player", "to_field")
	stepProtocol(t, runtime, 1)
	if got := runtime.built.Stage.ID; got != "stage.village" {
		t.Fatalf("preview leaked through portal to %q", got)
	}
	if runtime.portalInside["to_field"] {
		t.Fatal("preview-blocked portal consumed the entry latch")
	}

	if _, err := runtime.queueEntityRemoval(protocol.RemoveEntityParams{
		EntityID: "preview.slime",
	}); err != nil {
		t.Fatal(err)
	}
	stepProtocol(t, runtime, 1)
	assertLocation(t, runtime, "stage.world_hub", "village_entry")
	if runtime.simulation.HasTemporaryPreview() {
		t.Fatal("Maker preview topology crossed the stage boundary")
	}
}

func TestInvalidPortalTargetRollsBackWholeTick(t *testing.T) {
	runtime := newCampaignRuntime(t)
	moveEntityToPortal(t, runtime, "player", "to_field")
	runtime.built.Stage.Portals[0].TargetStageID = "stage.missing"
	runtime.pendingAbilities["player"] = true
	runtime.virtual["attack"] = virtualAction{
		value:     1,
		remaining: 2,
		fresh:     true,
	}
	runtime.moving["player"] = true

	beforeBuilt := runtime.built
	beforeCampaign := runtime.campaign
	beforeCampaignState := runtime.campaign.Snapshot()
	beforeSession := runtime.simulation.SaveSession()
	beforeOptions := runtime.buildOptions
	beforeVirtual := cloneVirtualActions(runtime.virtual)
	beforePendingAbilities := cloneBoolMap(runtime.pendingAbilities)
	beforePendingRemovals := cloneBoolMap(runtime.pendingRemovals)
	beforeMoving := cloneBoolMap(runtime.moving)
	beforePreview := clonePreviewEntities(runtime.previewEntities)
	beforeSequence := runtime.previewSequence
	beforeCooldown := runtime.portalCooldownTicks
	beforeInside := cloneBoolMap(runtime.portalInside)
	beforeRevision := runtime.revision

	if _, err := runtime.Call(
		context.Background(),
		protocol.Call{
			Method: protocol.MethodEmulationStep,
			Params: protocol.StepParams{Frames: 1},
		},
	); err == nil {
		t.Fatal("invalid portal target was accepted")
	}
	if runtime.built != beforeBuilt ||
		runtime.campaign != beforeCampaign ||
		runtime.revision != beforeRevision ||
		runtime.previewSequence != beforeSequence ||
		runtime.portalCooldownTicks != beforeCooldown {
		t.Fatal("invalid transition changed runtime identity or counters")
	}
	assertDeepEqual(t, "campaign", runtime.campaign.Snapshot(), beforeCampaignState)
	assertDeepEqual(t, "session", runtime.simulation.SaveSession(), beforeSession)
	assertDeepEqual(t, "build options", runtime.buildOptions, beforeOptions)
	assertDeepEqual(t, "virtual input", runtime.virtual, beforeVirtual)
	assertDeepEqual(
		t,
		"pending abilities",
		runtime.pendingAbilities,
		beforePendingAbilities,
	)
	assertDeepEqual(
		t,
		"pending removals",
		runtime.pendingRemovals,
		beforePendingRemovals,
	)
	assertDeepEqual(t, "moving", runtime.moving, beforeMoving)
	assertDeepEqual(t, "preview metadata", runtime.previewEntities, beforePreview)
	assertDeepEqual(t, "portal latch", runtime.portalInside, beforeInside)
}

func TestStartNewGameResetsCampaignAndWorld(t *testing.T) {
	runtime := newCampaignRuntime(t)
	moveEntityToPortal(t, runtime, "player", "to_field")
	stepProtocol(t, runtime, 1)
	if err := runtime.campaign.Transaction(func(state *campaign.State) error {
		state.Currency = 99
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	previous := runtime.campaign
	callRuntime(
		t,
		runtime,
		protocol.MethodAppStartNewGame,
		protocol.EmptyParams{},
	)
	if runtime.campaign == previous {
		t.Fatal("start new game retained the previous campaign instance")
	}
	state := runtime.campaign.Snapshot()
	if state.Currency != 0 {
		t.Fatalf("new campaign currency = %d", state.Currency)
	}
	assertLocation(t, runtime, "stage.village", "default")
	if got := runtime.simulation.Snapshot().Tick; got != 0 {
		t.Fatalf("new world tick = %d", got)
	}
}

func moveEntityToPortal(
	t *testing.T,
	runtime *Runtime,
	entityID string,
	portalID string,
) {
	t.Helper()
	portal := findPortal(t, runtime, portalID)
	x := coordPixels((portal.Rect.MinX + portal.Rect.MaxX) / 2)
	y := coordPixels((portal.Rect.MinY + portal.Rect.MaxY) / 2)
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: entityID,
			X:        x,
			Y:        y,
		},
	)
}

func scheduleProtocolAction(
	t *testing.T,
	runtime *Runtime,
	action string,
) {
	t.Helper()
	callRuntime(
		t,
		runtime,
		protocol.MethodInputAction,
		protocol.InputActionParams{
			Action: action,
			Value:  1,
			Frames: 1,
		},
	)
}

func stepProtocol(t *testing.T, runtime *Runtime, frames int) {
	t.Helper()
	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: frames},
	)
}

func findPortal(
	t *testing.T,
	runtime *Runtime,
	id string,
) gamebuild.Portal {
	t.Helper()
	for _, portal := range runtime.built.Stage.Portals {
		if portal.ID == id {
			return portal
		}
	}
	t.Fatalf("portal %q missing from %q", id, runtime.built.Stage.ID)
	return gamebuild.Portal{}
}

func assertLocation(
	t *testing.T,
	runtime *Runtime,
	stageID string,
	spawnID string,
) {
	t.Helper()
	state := runtime.campaign.Snapshot()
	if runtime.built.Stage.ID != stageID ||
		runtime.buildOptions.StageID != stageID ||
		runtime.buildOptions.SpawnID != spawnID ||
		state.CurrentStageID != stageID ||
		state.EntrySpawnID != spawnID {
		t.Fatalf(
			"location = world %q, options %#v, campaign %s/%s; want %s/%s",
			runtime.built.Stage.ID,
			runtime.buildOptions,
			state.CurrentStageID,
			state.EntrySpawnID,
			stageID,
			spawnID,
		)
	}
}

func assertFreshWorld(
	t *testing.T,
	runtime *Runtime,
	playerX int64,
	playerY int64,
) {
	t.Helper()
	snapshot := runtime.simulation.Snapshot()
	if snapshot.Tick != 0 || snapshot.WorldTick != 0 ||
		snapshot.HitstopTicks != 0 ||
		snapshot.Dialogue.Active ||
		snapshot.Camera.ShakeTicks != 0 {
		t.Fatalf("new World retained transient state: %#v", snapshot)
	}
	player := entitySnapshot(t, runtime, "player")
	wantPosition := sim.Vec{
		X: sim.Pixels(playerX),
		Y: sim.Pixels(playerY),
	}
	if player.Position != wantPosition {
		t.Fatalf(
			"player entry position = %#v, want %#v",
			player.Position,
			wantPosition,
		)
	}
	wantCamera := clampCameraTarget(
		wantPosition,
		runtime.built.Config.StageBounds,
		runtime.built.Config.Camera,
	)
	if snapshot.Camera.BaseCenter != wantCamera ||
		snapshot.Camera.Center != wantCamera {
		t.Fatalf(
			"fresh camera = base %#v center %#v, want %#v",
			snapshot.Camera.BaseCenter,
			snapshot.Camera.Center,
			wantCamera,
		)
	}
}

func entitySnapshot(
	t *testing.T,
	runtime *Runtime,
	id string,
) sim.EntitySnapshot {
	t.Helper()
	for _, entity := range runtime.simulation.Snapshot().Entities {
		if entity.ID == id {
			return entity
		}
	}
	t.Fatalf("entity %q missing from %q", id, runtime.built.Stage.ID)
	return sim.EntitySnapshot{}
}

func hasEntity(snapshot sim.Snapshot, id string) bool {
	for _, entity := range snapshot.Entities {
		if entity.ID == id {
			return true
		}
	}
	return false
}

func assertDeepEqual(t *testing.T, label string, got, want any) {
	t.Helper()
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("%s changed:\n got %#v\nwant %#v", label, got, want)
	}
}

func floatPointer(value float64) *float64 {
	return &value
}

var _ = sim.TicksPerSecond
