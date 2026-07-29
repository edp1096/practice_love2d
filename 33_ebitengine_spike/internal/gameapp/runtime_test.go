package gameapp

import (
	"context"
	"encoding/json"
	"path/filepath"
	"reflect"
	"sync"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/protocol"
	"practice_love2d/33_ebitengine_spike/internal/storage"
)

func newTestRuntime(t *testing.T) *Runtime {
	t.Helper()
	store, err := storage.NewFileStore(filepath.Join(t.TempDir(), "saves"))
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{
		CatalogPath: filepath.Join("..", "..", "game", "catalog.json"),
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
	if got := runtime.View().World.Stage; got != "stage.rpg_village" {
		t.Fatalf("embedded stage = %q", got)
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

func TestVirtualInputStepAndSaveLoadAreDeterministic(t *testing.T) {
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
	if got := worldEntity(t, restored, "player").X; got != movedPlayer.X {
		t.Fatalf("restored x = %v, want %v", got, movedPlayer.X)
	}

	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 1},
	)
	afterExpiredInput := runtime.worldSnapshotLocked()
	if got := worldEntity(t, afterExpiredInput, "player").X; got != movedPlayer.X {
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
	before := runtime.worldSnapshotLocked()
	runtime.mu.RLock()
	beforeVirtual := cloneVirtualActions(runtime.virtual)
	beforeRevision := runtime.revision
	beforePaused := runtime.paused
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
	afterRevision := runtime.revision
	afterPaused := runtime.paused
	runtime.mu.RUnlock()
	if !reflect.DeepEqual(after, before) ||
		!reflect.DeepEqual(afterVirtual, beforeVirtual) ||
		afterRevision != beforeRevision ||
		afterPaused != beforePaused {
		t.Fatalf(
			"cancelled step leaked partial state: before=%#v after=%#v",
			before,
			after,
		)
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
		ability := *config.Entities[index].Ability
		ability.LockMovement = false
		config.Entities[index].Ability = &ability
	}
	built := *runtime.built
	built.Config = config
	runtime.built = &built
	if err := runtime.resetLocked(); err != nil {
		runtime.mu.Unlock()
		t.Fatal(err)
	}
	runtime.pendingAbilities["player"] = true
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
