package gameapp

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"sync"
	"testing"

	gamecatalog "practice_love2d/33_ebitengine_spike/game"
	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/protocol"
	"practice_love2d/33_ebitengine_spike/internal/sim"
	"practice_love2d/33_ebitengine_spike/internal/storage"
)

func verticalSliceBuildOptions() gamebuild.Options {
	return gamebuild.Options{
		StageID:  "stage.rpg_village",
		SpawnID:  "default",
		LocaleID: "locale.ko",
	}
}

func newTestRuntime(t *testing.T) *Runtime {
	t.Helper()
	store, err := storage.NewFileStore(filepath.Join(t.TempDir(), "saves"))
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{
		CatalogPath: filepath.Join("..", "..", "game", "catalog.json"),
		Build:       verticalSliceBuildOptions(),
		Store:       store,
	})
	if err != nil {
		t.Fatal(err)
	}
	return runtime
}

func TestRuntimeUsesEmbeddedCatalogWithoutWorkingDirectoryDependency(
	t *testing.T,
) {
	t.Parallel()
	store, err := storage.NewFileStore(filepath.Join(t.TempDir(), "saves"))
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{Store: store})
	if err != nil {
		t.Fatal(err)
	}
	view := runtime.View()
	if got := view.World.Stage; got != "stage.village" {
		t.Fatalf("embedded stage = %q, want stage.village", got)
	}
	if got, want := len(view.Entities), 2; got != want {
		t.Fatalf("embedded entities = %d, want %d", got, want)
	}
	entityIDs := make([]string, 0, len(view.Entities))
	for _, entity := range view.Entities {
		entityIDs = append(entityIDs, entity.ID)
	}
	if got, want := entityIDs, []string{"guide", "player"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("embedded entity IDs = %v, want %v", got, want)
	}
	if got := runtime.buildOptions; got.StageID != "stage.village" ||
		got.SpawnID != "default" || got.LocaleID != "locale.ko" {
		t.Fatalf("resolved embedded build options = %#v", got)
	}
}

func TestResolveBuildOptionsUsesManifestOnlyForEmptyFields(t *testing.T) {
	t.Parallel()
	catalog, err := loadCatalog("")
	if err != nil {
		t.Fatal(err)
	}
	impact := gamebuild.ImpactOptions{
		DamageShakePixels:  9,
		DamageShakeSeconds: 0.2,
	}
	got := resolveBuildOptions(catalog, gamebuild.Options{
		StageID:  "stage.rpg_village",
		LocaleID: "locale.en",
		Impact:   impact,
	})
	want := gamebuild.Options{
		StageID:  "stage.rpg_village",
		LocaleID: "locale.en",
		Impact:   impact,
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("resolved build options = %#v, want %#v", got, want)
	}
}

func TestExplicitStageDoesNotInheritManifestStartSpawn(t *testing.T) {
	t.Parallel()
	store, err := storage.NewFileStore(filepath.Join(t.TempDir(), "saves"))
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{
		Build: gamebuild.Options{StageID: "stage.world_grove"},
		Store: store,
	})
	if err != nil {
		t.Fatal(err)
	}
	if got := runtime.View().World.Stage; got != "stage.world_grove" {
		t.Fatalf("explicit stage = %q", got)
	}
	if got := runtime.buildOptions; got.SpawnID != "" ||
		got.LocaleID != "locale.ko" {
		t.Fatalf("resolved explicit-stage options = %#v", got)
	}
	player := worldEntity(t, runtime.worldSnapshotLocked(), "player")
	if player.X != 96 || player.Y != 288 {
		t.Fatalf("authored grove player position = (%v, %v)", player.X, player.Y)
	}
}

func TestMakerNewGameSelectsStageSpawnAndLocaleAtomically(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	callRuntime(
		t,
		runtime,
		protocol.MethodAppStartNewGame,
		protocol.StartNewGameParams{
			StageID:  "stage.world_hub",
			SpawnID:  "village_entry",
			LocaleID: "locale.en",
		},
	)
	world := runtime.worldSnapshotLocked()
	player := worldEntity(t, world, "player")
	if world.Stage.ID != "stage.world_hub" ||
		player.X != 80 ||
		player.Y != 288 ||
		runtime.buildOptions.LocaleID != "locale.en" {
		t.Fatalf(
			"Maker stage preview = world %#v player %#v options %#v",
			world.Stage,
			player,
			runtime.buildOptions,
		)
	}

	beforeView := runtime.View()
	beforeCampaign := runtime.CampaignState()
	beforeOptions := runtime.buildOptions
	beforeCatalog := runtime.catalog
	_, err := runtime.Call(context.Background(), protocol.Call{
		Method: protocol.MethodAppStartNewGame,
		Params: protocol.StartNewGameParams{
			StageID: "stage.missing",
		},
	})
	if err == nil {
		t.Fatal("Maker stage preview accepted a missing stage")
	}
	if !reflect.DeepEqual(runtime.View(), beforeView) ||
		!reflect.DeepEqual(runtime.CampaignState(), beforeCampaign) ||
		!reflect.DeepEqual(runtime.buildOptions, beforeOptions) ||
		runtime.catalog != beforeCatalog {
		t.Fatal("failed Maker stage preview mutated the active runtime")
	}
}

func TestMakerNewGameAppliesAnEditedCanonicalDefinition(t *testing.T) {
	t.Parallel()
	catalogPath := filepath.Join(t.TempDir(), "catalog.json")
	if err := os.WriteFile(catalogPath, gamecatalog.Bytes(), 0o600); err != nil {
		t.Fatal(err)
	}
	store, err := storage.NewFileStore(filepath.Join(t.TempDir(), "saves"))
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{
		CatalogPath: catalogPath,
		Store:       store,
	})
	if err != nil {
		t.Fatal(err)
	}
	if got := worldEntity(
		t,
		runtime.worldSnapshotLocked(),
		"player",
	).MaxHealth; got != 100 {
		t.Fatalf("initial player max health = %d", got)
	}

	writeCatalogActorMaxHealth(t, catalogPath, "actor.hero", 137)
	callRuntime(
		t,
		runtime,
		protocol.MethodAppStartNewGame,
		protocol.StartNewGameParams{},
	)
	player := worldEntity(t, runtime.worldSnapshotLocked(), "player")
	if player.MaxHealth != 137 || player.Health != 137 {
		t.Fatalf("edited actor definition was not applied: %#v", player)
	}
}

func TestNewGameAndReloadResolveCurrentManifestDefaults(t *testing.T) {
	t.Parallel()
	catalogPath := filepath.Join(t.TempDir(), "catalog.json")
	if err := os.WriteFile(catalogPath, gamecatalog.Bytes(), 0o600); err != nil {
		t.Fatal(err)
	}
	store, err := storage.NewFileStore(filepath.Join(t.TempDir(), "saves"))
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{
		CatalogPath: catalogPath,
		Store:       store,
	})
	if err != nil {
		t.Fatal(err)
	}
	if got := runtime.View().HUD.Title; got != "버드나무 마을" {
		t.Fatalf("initial manifest locale title = %q", got)
	}

	writeCatalogDefaultLocale(t, catalogPath, "locale.en")
	callRuntime(
		t,
		runtime,
		protocol.MethodAppStartNewGame,
		protocol.EmptyParams{},
	)
	if got := runtime.View().HUD.Title; got != "Willow Village" {
		t.Fatalf("new-game manifest locale title = %q", got)
	}
	if got := runtime.buildOptions.LocaleID; got != "locale.en" {
		t.Fatalf("new-game resolved locale = %q", got)
	}

	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: "player",
			X:        430,
			Y:        300,
		},
	)
	writeCatalogDefaultLocale(t, catalogPath, "locale.ko")
	callRuntime(
		t,
		runtime,
		protocol.MethodAppReloadContent,
		protocol.EmptyParams{},
	)
	view := runtime.View()
	if got := view.HUD.Title; got != "버드나무 마을" {
		t.Fatalf("reload manifest locale title = %q", got)
	}
	if got := runtime.buildOptions.LocaleID; got != "locale.ko" {
		t.Fatalf("reload resolved locale = %q", got)
	}
	if got := worldEntity(t, runtime.worldSnapshotLocked(), "player").X; got != 430 {
		t.Fatalf("reload did not preserve active session position: %v", got)
	}
}

func TestFailedNewGameKeepsResolvedRuntimeAtomic(t *testing.T) {
	t.Parallel()
	catalogPath := filepath.Join(t.TempDir(), "catalog.json")
	if err := os.WriteFile(catalogPath, gamecatalog.Bytes(), 0o600); err != nil {
		t.Fatal(err)
	}
	store, err := storage.NewFileStore(filepath.Join(t.TempDir(), "saves"))
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{
		CatalogPath: catalogPath,
		Store:       store,
	})
	if err != nil {
		t.Fatal(err)
	}
	beforeView := runtime.View()
	beforeOptions := runtime.buildOptions
	beforeProject := runtime.catalog.Project()

	writeCatalogDefaultLocale(t, catalogPath, "locale.missing")
	if err := runtime.startNewGame(context.Background()); err == nil {
		t.Fatal("new game accepted a missing manifest locale")
	}
	if got := runtime.View(); !reflect.DeepEqual(got, beforeView) {
		t.Fatalf("failed new game changed view:\n got %#v\nwant %#v", got, beforeView)
	}
	if got := runtime.buildOptions; !reflect.DeepEqual(got, beforeOptions) {
		t.Fatalf("failed new game changed build options: %#v", got)
	}
	if got := runtime.catalog.Project(); !reflect.DeepEqual(got, beforeProject) {
		t.Fatalf("failed new game changed active catalog: %#v", got)
	}
}

func writeCatalogDefaultLocale(
	t *testing.T,
	path string,
	localeID string,
) {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var document map[string]any
	if err := json.Unmarshal(data, &document); err != nil {
		t.Fatal(err)
	}
	project, ok := document["project"].(map[string]any)
	if !ok {
		t.Fatal("catalog project manifest is missing")
	}
	locale, ok := project["locale"].(map[string]any)
	if !ok {
		t.Fatal("catalog project locale is missing")
	}
	locale["default"] = localeID
	encoded, err := json.Marshal(document)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, encoded, 0o600); err != nil {
		t.Fatal(err)
	}
}

func writeCatalogActorMaxHealth(
	t *testing.T,
	path string,
	actorID string,
	maxHealth float64,
) {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var document map[string]any
	if err := json.Unmarshal(data, &document); err != nil {
		t.Fatal(err)
	}
	definitions, ok := document["definitions"].([]any)
	if !ok {
		t.Fatal("catalog definitions are missing")
	}
	found := false
	for _, raw := range definitions {
		definition, _ := raw.(map[string]any)
		value, _ := definition["data"].(map[string]any)
		if value["id"] != actorID {
			continue
		}
		components, _ := value["components"].(map[string]any)
		health, _ := components["action.health"].(map[string]any)
		if health == nil {
			t.Fatalf("%s has no action.health component", actorID)
		}
		health["max"] = maxHealth
		found = true
		break
	}
	if !found {
		t.Fatalf("catalog actor %q is missing", actorID)
	}
	encoded, err := json.MarshalIndent(document, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	encoded = append(encoded, '\n')
	if err := os.WriteFile(path, encoded, 0o600); err != nil {
		t.Fatal(err)
	}
}

func callRuntime(
	t *testing.T,
	runtime *Runtime,
	method string,
	params any,
) any {
	t.Helper()
	result, err := runtime.Call(
		context.Background(),
		protocol.Call{Method: method, Params: params},
	)
	if err != nil {
		t.Fatalf("%s: %v", method, err)
	}
	return result
}

func TestRuntimeBuildsCompleteInspectableView(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)

	view := runtime.View()
	if view.World.Stage != "stage.rpg_village" ||
		view.World.Width != 960 ||
		view.World.Height != 540 {
		t.Fatalf("world view = %#v", view.World)
	}
	if got, want := len(view.Entities), 5; got != want {
		t.Fatalf("visible entities = %d, want %d", got, want)
	}
	if got, want := len(view.Walls), 5; got != want {
		t.Fatalf("walls = %d, want %d", got, want)
	}
	if view.Camera.Zoom != 1.2 {
		t.Fatalf("camera zoom = %v, want 1.2", view.Camera.Zoom)
	}

	result := callRuntime(
		t,
		runtime,
		protocol.MethodWorldGetSnapshot,
		protocol.EmptyParams{},
	)
	world, ok := result.(worldSnapshotDTO)
	if !ok {
		t.Fatalf("world result type = %T", result)
	}
	if !world.Available || world.Count != 5 ||
		len(world.Entities) != 5 || len(world.Walls) != 5 {
		t.Fatalf("incomplete world snapshot = %#v", world)
	}
	if world.Stage.ID != "stage.rpg_village" ||
		world.Camera.ViewportWidth != 800 ||
		world.Camera.ViewportHeight != 450 {
		t.Fatalf("world geometry = %#v / %#v", world.Stage, world.Camera)
	}
	if wall := worldWall(t, world, "north"); wall.Height != 32 {
		t.Fatalf("north wall = %#v", wall)
	}
	player := worldEntity(t, world, "player")
	if player.ActorID != "actor.hero" ||
		player.Health != 100 ||
		!player.Visible ||
		player.ScreenX < 0 ||
		player.ScreenY < 0 {
		t.Fatalf("player inspection = %#v", player)
	}
}

func TestWallMutationIsIdentifiedValidatedAndTransactional(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	callRuntime(
		t,
		runtime,
		protocol.MethodWorldSetWall,
		protocol.SetWallParams{
			WallID: "north",
			X:      0,
			Y:      0,
			Width:  960,
			Height: 24,
		},
	)
	changed := runtime.worldSnapshotLocked()
	if wall := worldWall(t, changed, "north"); wall.Height != 24 || wall.Width != 960 {
		t.Fatalf("changed north wall = %#v", wall)
	}

	_, err := runtime.Call(
		context.Background(),
		protocol.Call{
			Method: protocol.MethodWorldSetWall,
			Params: protocol.SetWallParams{
				WallID: "west",
				X:      140,
				Y:      0,
				Width:  32,
				Height: 540,
			},
		},
	)
	if err == nil {
		t.Fatal("wall mutation overlapping the player was accepted")
	}
	afterRejected := runtime.worldSnapshotLocked()
	if wall := worldWall(t, afterRejected, "west"); wall.X != 0 {
		t.Fatalf("rejected mutation changed west wall: %#v", wall)
	}

	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: "player",
			X:        430,
			Y:        300,
		},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodWorldSetWall,
		protocol.SetWallParams{
			WallID: "west",
			X:      140,
			Y:      0,
			Width:  20,
			Height: 540,
		},
	)
	if wall := worldWall(t, runtime.worldSnapshotLocked(), "west"); wall.X != 140 {
		t.Fatalf("wall over vacated authored spawn was not applied: %#v", wall)
	}
}

func TestCampaignSaveLoadRebuildsFreshDeterministicWorld(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	initial := runtime.worldSnapshotLocked()
	initialPlayer := worldEntity(t, initial, "player")

	callRuntime(
		t,
		runtime,
		protocol.MethodInputAction,
		protocol.InputActionParams{
			Action: "move_right",
			Value:  1,
			Frames: 30,
		},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 30},
	)
	moved := runtime.worldSnapshotLocked()
	movedPlayer := worldEntity(t, moved, "player")
	if moved.Tick != 30 || movedPlayer.X <= initialPlayer.X+90 {
		t.Fatalf(
			"movement did not advance deterministically: tick=%d x=%v -> %v",
			moved.Tick,
			initialPlayer.X,
			movedPlayer.X,
		)
	}

	callRuntime(
		t,
		runtime,
		protocol.MethodAppSave,
		protocol.SaveSlotParams{Slot: "automation"},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: "player",
			X:        430,
			Y:        300,
		},
	)
	mutated := runtime.worldSnapshotLocked()
	if got := worldEntity(t, mutated, "player").X; got != 430 {
		t.Fatalf("mutated player x = %v", got)
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodAppLoad,
		protocol.SaveSlotParams{Slot: "automation"},
	)
	restored := runtime.worldSnapshotLocked()
	if got := worldEntity(t, restored, "player").X; got != initialPlayer.X {
		t.Fatalf("fresh player x = %v, want %v", got, initialPlayer.X)
	}
	if restored.Tick != 0 || restored.WorldTick != 0 {
		t.Fatalf(
			"fresh World clocks = tick %d, world tick %d",
			restored.Tick,
			restored.WorldTick,
		)
	}

	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 1},
	)
	afterExpiredInput := runtime.worldSnapshotLocked()
	if got := worldEntity(t, afterExpiredInput, "player").X; got != initialPlayer.X {
		t.Fatalf("expired virtual input moved player to %v", got)
	}
}

type cancelAfterContext struct {
	context.Context
	checks int
}

func (ctx *cancelAfterContext) Err() error {
	ctx.checks--
	if ctx.checks < 0 {
		return context.Canceled
	}
	return nil
}

func TestCancelledStepRollsBackPartialBatch(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	callRuntime(
		t,
		runtime,
		protocol.MethodInputAction,
		protocol.InputActionParams{
			Action: "move_right",
			Value:  1,
			Frames: 20,
		},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodInputAction,
		protocol.InputActionParams{
			Action: "attack",
			Value:  1,
			Frames: 1,
		},
	)
	before := runtime.worldSnapshotLocked()
	runtime.mu.RLock()
	beforeVirtual := cloneVirtualActions(runtime.virtual)
	beforeAudioSequence := runtime.audioSequence
	beforeAudioCues := append([]queuedAudioCue(nil), runtime.audioCues...)
	beforeRevision := runtime.revision
	beforePaused := runtime.automationPaused
	runtime.mu.RUnlock()

	ctx := &cancelAfterContext{
		Context: context.Background(),
		checks:  3,
	}
	if _, err := runtime.step(ctx, 10); err == nil {
		t.Fatal("partially cancelled step unexpectedly succeeded")
	}
	after := runtime.worldSnapshotLocked()
	runtime.mu.RLock()
	afterVirtual := cloneVirtualActions(runtime.virtual)
	afterAudioSequence := runtime.audioSequence
	afterAudioCues := append([]queuedAudioCue(nil), runtime.audioCues...)
	afterRevision := runtime.revision
	afterPaused := runtime.automationPaused
	runtime.mu.RUnlock()
	if !reflect.DeepEqual(after, before) ||
		!reflect.DeepEqual(afterVirtual, beforeVirtual) ||
		afterAudioSequence != beforeAudioSequence ||
		!reflect.DeepEqual(afterAudioCues, beforeAudioCues) ||
		afterRevision != beforeRevision ||
		afterPaused != beforePaused {
		t.Fatalf(
			"cancelled step leaked partial state: before=%#v after=%#v",
			before,
			after,
		)
	}
}

func TestSuccessfulStepPreservesAutomationPauseState(t *testing.T) {
	t.Parallel()

	for _, paused := range []bool{false, true} {
		paused := paused
		t.Run(fmt.Sprintf("paused=%t", paused), func(t *testing.T) {
			t.Parallel()
			runtime := newTestRuntime(t)
			runtime.automationPaused = paused

			result, err := runtime.step(context.Background(), 1)
			if err != nil {
				t.Fatal(err)
			}

			runtime.mu.RLock()
			after := runtime.automationPaused
			runtime.mu.RUnlock()
			if after != paused {
				t.Fatalf(
					"step changed automation pause from %t to %t",
					paused,
					after,
				)
			}

			wire, err := json.Marshal(result)
			if err != nil {
				t.Fatal(err)
			}
			var response struct {
				Paused bool `json:"paused"`
				Tick   int  `json:"tick"`
			}
			if err := json.Unmarshal(wire, &response); err != nil {
				t.Fatal(err)
			}
			if response.Paused != paused || response.Tick != 1 {
				t.Fatalf("step response = %s", wire)
			}
		})
	}
}

func TestDebugMutationRejectsWallsAndPreservesState(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	before := runtime.worldSnapshotLocked()

	_, err := runtime.Call(
		context.Background(),
		protocol.Call{
			Method: protocol.MethodEntitySetPosition,
			Params: protocol.SetPositionParams{
				EntityID: "player",
				X:        16,
				Y:        270,
			},
		},
	)
	if err == nil {
		t.Fatal("wall-overlapping debug position was accepted")
	}
	after := runtime.worldSnapshotLocked()
	if got, want := worldEntity(t, after, "player").X,
		worldEntity(t, before, "player").X; got != want {
		t.Fatalf("rejected mutation changed player x: %v != %v", got, want)
	}

	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetHealth,
		protocol.SetHealthParams{EntityID: "quest.slime.1", Value: 0},
	)
	killed := runtime.worldSnapshotLocked()
	if enemy := worldEntity(t, killed, "quest.slime.1"); !enemy.Dead || enemy.Health != 0 ||
		enemy.Visible || !enemy.InViewport {
		t.Fatalf("health mutation = %#v", enemy)
	}
}

func TestAuthoredEnemyAIProducesPerfectParry(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: "quest.slime.1",
			X:        174,
			Y:        270,
		},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 15},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodInputAction,
		protocol.InputActionParams{Action: "parry", Value: 1, Frames: 1},
	)
	foundParryEffect := false
	for range 13 {
		callRuntime(
			t,
			runtime,
			protocol.MethodEmulationStep,
			protocol.StepParams{Frames: 1},
		)
		for _, effect := range runtime.View().Effects {
			if effect.Kind == "parry" {
				foundParryEffect = true
			}
		}
	}
	world := runtime.worldSnapshotLocked()
	player := worldEntity(t, world, "player")
	enemy := worldEntity(t, world, "quest.slime.1")
	if player.Health != 100 {
		t.Fatalf("perfect parry lost health: %#v", player)
	}
	if enemy.StaggerRemaining == 0 {
		t.Fatalf("perfect parry did not stagger enemy: %#v", enemy)
	}
	if !player.ParryPerfect {
		t.Fatalf("perfect parry flag was not exposed: %#v", player)
	}
	if !foundParryEffect {
		t.Fatal("perfect parry did not produce a presentation effect")
	}
}

func TestGuardianBehaviorAIChangesPhaseAndAimsAuthoredAbility(
	t *testing.T,
) {
	t.Parallel()
	store, err := storage.NewFileStore(filepath.Join(t.TempDir(), "saves"))
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{
		CatalogPath: filepath.Join("..", "..", "game", "catalog.json"),
		Build: gamebuild.Options{
			StageID:  "stage.world_grove",
			SpawnID:  "west_entry",
			LocaleID: "locale.ko",
		},
		Store: store,
	})
	if err != nil {
		t.Fatal(err)
	}
	before := worldEntity(
		t,
		runtime.worldSnapshotLocked(),
		"boss.grove_guardian",
	)
	if before.AIPattern != "sentinel" ||
		before.AINextAbility != "ability.slime_bump" ||
		before.AIAttackIndex != 1 {
		t.Fatalf("initial guardian AI = %#v", before)
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetHealth,
		protocol.SetHealthParams{
			EntityID: "boss.grove_guardian",
			Value:    120,
		},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: "boss.grove_guardian",
			X:        300,
			Y:        350,
		},
	)
	awakened := worldEntity(
		t,
		runtime.worldSnapshotLocked(),
		"boss.grove_guardian",
	)
	if awakened.AIPattern != "awakened" ||
		awakened.AINextAbility != "ability.fire_bolt" ||
		awakened.AITargetTag != "player" {
		t.Fatalf("health phase was not selected: %#v", awakened)
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 1},
	)
	attacking := worldEntity(
		t,
		runtime.worldSnapshotLocked(),
		"boss.grove_guardian",
	)
	if attacking.AbilityID != "ability.fire_bolt" ||
		attacking.AttackPhase == sim.AttackIdle ||
		attacking.AIAttackIndex != 2 ||
		attacking.AINextAbility != "ability.whirlwind" {
		t.Fatalf("authored attack cycle was not advanced: %#v", attacking)
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 10},
	)
	world := runtime.worldSnapshotLocked()
	if len(world.Projectiles) == 0 {
		t.Fatalf("fire bolt was not spawned: %#v", world.RecentEvents)
	}
	projectile := world.Projectiles[0]
	if projectile.DirectionX >= 0 || projectile.DirectionY >= 0 {
		t.Fatalf(
			"orbiting guardian did not aim toward the player: %#v",
			projectile,
		)
	}
}

func TestDefinitionValidationIsNonMutating(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	runtime.mu.RLock()
	raw, ok := runtime.catalog.Definition("ability.sword_slash")
	runtime.mu.RUnlock()
	if !ok {
		t.Fatal("ability definition missing")
	}
	var draft map[string]any
	if err := json.Unmarshal(raw, &draft); err != nil {
		t.Fatal(err)
	}
	effects := draft["effects"].([]any)
	effects[0].(map[string]any)["amount"] = float64(41)
	encoded, err := json.Marshal(draft)
	if err != nil {
		t.Fatal(err)
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodContentValidateDefinition,
		protocol.ValidateDefinitionParams{
			ContentID:  "ability.sword_slash",
			Definition: encoded,
		},
	)
	runtime.mu.RLock()
	var unchanged struct {
		Effects []struct {
			Type   string `json:"type"`
			Amount int    `json:"amount"`
		} `json:"effects"`
	}
	err = runtime.catalog.Decode("ability.sword_slash", &unchanged)
	runtime.mu.RUnlock()
	if err != nil {
		t.Fatal(err)
	}
	if unchanged.Effects[0].Amount != 34 {
		t.Fatalf("validation mutated live content: %#v", unchanged.Effects)
	}

	runtime.mu.RLock()
	fireBoltRaw, found := runtime.catalog.Definition("ability.fire_bolt")
	runtime.mu.RUnlock()
	if !found {
		t.Fatal("fire bolt definition missing")
	}
	var invalid map[string]any
	if err := json.Unmarshal(fireBoltRaw, &invalid); err != nil {
		t.Fatal(err)
	}
	invalid["duration"] = float64(-999)
	invalidRaw, err := json.Marshal(invalid)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := runtime.Call(
		context.Background(),
		protocol.Call{
			Method: protocol.MethodContentValidateDefinition,
			Params: protocol.ValidateDefinitionParams{
				ContentID:  "ability.fire_bolt",
				Definition: invalidRaw,
			},
		},
	); err == nil {
		t.Fatal("validation accepted an invalid unused ability")
	}
}

func TestDefinitionValidationReportsRuntimeGapWithoutLosingSchemaResult(
	t *testing.T,
) {
	t.Parallel()
	runtime := newTestRuntime(t)
	runtime.mu.RLock()
	raw, ok := runtime.catalog.Definition("actor.hero")
	runtime.mu.RUnlock()
	if !ok {
		t.Fatal("actor definition missing")
	}
	var draft map[string]any
	if err := json.Unmarshal(raw, &draft); err != nil {
		t.Fatal(err)
	}
	components := draft["components"].(map[string]any)
	delete(components, "body")
	encoded, err := json.Marshal(draft)
	if err != nil {
		t.Fatal(err)
	}

	result, err := runtime.Call(
		context.Background(),
		protocol.Call{
			Method: protocol.MethodContentValidateDefinition,
			Params: protocol.ValidateDefinitionParams{
				ContentID:  "actor.hero",
				Definition: encoded,
			},
		},
	)
	if err != nil {
		t.Fatalf("schema-valid runtime gap became an RPC error: %v", err)
	}
	validation, ok := result.(definitionValidationResult)
	if !ok {
		t.Fatalf("validation result type = %T", result)
	}
	if !validation.SchemaValid ||
		validation.FullyApplied ||
		validation.RuntimeCompatible ||
		validation.RuntimeError == "" ||
		len(validation.Warnings) == 0 {
		t.Fatalf("runtime gap result = %#v", validation)
	}
}

func TestRequestedAbilityRemainsQueuedUntilSimulationAcceptsIt(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	request := protocol.RequestAbilityParams{
		EntityID:  "player",
		AbilityID: "ability.sword_slash",
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodEntityRequestAbility,
		request,
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 1},
	)
	runtime.mu.RLock()
	_, pendingAfterStart := runtime.pendingAbilities["player"]
	runtime.mu.RUnlock()
	if pendingAfterStart {
		t.Fatal("accepted ability request remained queued")
	}

	callRuntime(
		t,
		runtime,
		protocol.MethodEntityRequestAbility,
		request,
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 1},
	)
	runtime.mu.RLock()
	_, pendingDuringAttack := runtime.pendingAbilities["player"]
	runtime.mu.RUnlock()
	if !pendingDuringAttack {
		t.Fatal("busy simulation silently discarded queued ability")
	}

	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 60},
	)
	runtime.mu.RLock()
	_, pendingAfterRetry := runtime.pendingAbilities["player"]
	runtime.mu.RUnlock()
	if pendingAfterRetry {
		t.Fatal("queued ability was not retried after cooldown")
	}
}

func TestQueuedControlledAbilityMergesWithPlayerInput(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	runtime.mu.Lock()
	config := runtime.built.Config
	config.Entities = append(config.Entities[:0:0], config.Entities...)
	for index := range config.Entities {
		if !config.Entities[index].Controlled {
			continue
		}
		combat := *config.Entities[index].Combat
		combat.Abilities = append(
			[]sim.AbilityConfig(nil),
			config.Entities[index].Combat.Abilities...,
		)
		combat.Bindings = append(
			[]sim.AbilityBinding(nil),
			config.Entities[index].Combat.Bindings...,
		)
		config.Entities[index].Combat = &combat
		config.Entities[index].PrimaryAbility().LockMovement = false
	}
	built := *runtime.built
	built.Config = config
	runtime.built = &built
	if err := runtime.resetLocked(); err != nil {
		runtime.mu.Unlock()
		t.Fatal(err)
	}
	runtime.pendingAbilities["player"] = "ability.sword_slash"
	before := runtime.worldSnapshotLocked()
	runtime.mu.Unlock()

	if err := runtime.Tick(ebitapp.Actions{MoveX: 1}); err != nil {
		t.Fatal(err)
	}
	after := runtime.worldSnapshotLocked()
	if worldEntity(t, after, "player").X <= worldEntity(t, before, "player").X {
		t.Fatal("queued player ability replaced simultaneous movement input")
	}
}

func TestStartNewGameReloadsContentWithoutRequiringSessionCompatibility(
	t *testing.T,
) {
	t.Parallel()
	runtime := newTestRuntime(t)
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: "player",
			X:        430,
			Y:        300,
		},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodAppStartNewGame,
		protocol.EmptyParams{},
	)
	world := runtime.worldSnapshotLocked()
	player := worldEntity(t, world, "player")
	if player.X != 150 || player.Y != 270 || world.Tick != 0 {
		t.Fatalf("new game did not reset authored spawn: %#v", player)
	}
}

func TestQuitWaitsForProtocolResponseAcknowledgement(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	callRuntime(
		t,
		runtime,
		protocol.MethodAppQuit,
		protocol.EmptyParams{},
	)
	runtime.mu.RLock()
	pending, quit := runtime.quitPending, runtime.quit
	runtime.mu.RUnlock()
	if !pending || quit {
		t.Fatalf("quit before acknowledgement: pending=%v quit=%v", pending, quit)
	}
	runtime.ProtocolResponseWritten(protocol.MethodAppQuit)
	if view := runtime.View(); !view.Quit {
		t.Fatal("acknowledged quit did not stop the runtime")
	}
}

func TestRuntimeConcurrentInspectionAndTicks(t *testing.T) {
	runtime := newTestRuntime(t)
	var wait sync.WaitGroup
	for worker := 0; worker < 4; worker++ {
		wait.Add(1)
		go func(worker int) {
			defer wait.Done()
			for index := 0; index < 100; index++ {
				if worker&1 == 0 {
					if err := runtime.Tick(ebitapp.Actions{
						MoveX: float64((index % 3) - 1),
					}); err != nil {
						t.Errorf("Tick: %v", err)
						return
					}
					continue
				}
				if _, err := runtime.Call(
					context.Background(),
					protocol.Call{
						Method: protocol.MethodWorldGetSnapshot,
						Params: protocol.EmptyParams{},
					},
				); err != nil {
					t.Errorf("World.getSnapshot: %v", err)
					return
				}
			}
		}(worker)
	}
	wait.Wait()
}

func TestScreenshotRejectsPresentationOlderThanRequestedRevision(
	t *testing.T,
) {
	t.Parallel()
	runtime := newTestRuntime(t)
	runtime.SetCapture(func(context.Context) (ebitapp.Capture, error) {
		return ebitapp.Capture{
			PNG:      []byte("old"),
			Tick:     0,
			Revision: 0,
		}, nil
	})
	if _, err := runtime.Call(
		context.Background(),
		protocol.Call{
			Method: protocol.MethodPageCaptureScreenshot,
			Params: protocol.EmptyParams{},
		},
	); err == nil {
		t.Fatal("stale screenshot was accepted")
	}

	revision := runtime.View().Revision
	runtime.SetCapture(func(context.Context) (ebitapp.Capture, error) {
		return ebitapp.Capture{
			PNG:      []byte("current"),
			Tick:     0,
			Revision: revision,
		}, nil
	})
	callRuntime(
		t,
		runtime,
		protocol.MethodPageCaptureScreenshot,
		protocol.EmptyParams{},
	)
}

func worldEntity(
	t *testing.T,
	world worldSnapshotDTO,
	id string,
) entityDTO {
	t.Helper()
	for _, entity := range world.Entities {
		if entity.ID == id {
			return entity
		}
	}
	t.Fatalf("entity %q missing from %#v", id, world.Entities)
	return entityDTO{}
}

func worldWall(t *testing.T, world worldSnapshotDTO, id string) wallDTO {
	t.Helper()
	for _, wall := range world.Walls {
		if wall.ID == id {
			return wall
		}
	}
	t.Fatalf("wall %q missing from %#v", id, world.Walls)
	return wallDTO{}
}
