package gameapp

import (
	"context"
	"encoding/json"
	"reflect"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/protocol"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

func TestMakerPreviewEntityLifecycleIsInspectableAndTransient(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	x, y := 500.0, 270.0
	result := callRuntime(
		t,
		runtime,
		protocol.MethodEntitySpawn,
		protocol.SpawnEntityParams{
			ActorID:  "actor.slime",
			EntityID: "preview.slime",
			X:        &x,
			Y:        &y,
		},
	)
	spawned, ok := result.(entityDTO)
	if !ok {
		t.Fatalf("spawn result type = %T", result)
	}
	if spawned.ID != "preview.slime" ||
		spawned.ActorID != "actor.slime" ||
		spawned.X != x || spawned.Y != y ||
		!contains(spawned.Tags, "enemy") {
		t.Fatalf("spawn result = %#v", spawned)
	}
	foundSprite := false
	for _, entity := range runtime.View().Entities {
		if entity.ID == spawned.ID {
			foundSprite = entity.SpriteID == "sprite.slime"
		}
	}
	if !foundSprite {
		t.Fatal("spawned preview is missing renderer metadata")
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 1},
	)
	moved, found := findWorldEntity(
		runtime.worldSnapshotLocked(),
		spawned.ID,
	)
	if !found || moved.X >= spawned.X {
		t.Fatalf("spawned preview did not use chase metadata: %#v", moved)
	}
	if _, err := runtime.Call(
		context.Background(),
		protocol.Call{
			Method: protocol.MethodAppSave,
			Params: protocol.SaveSlotParams{Slot: "preview"},
		},
	); err == nil {
		t.Fatal("temporary preview was accepted by durable save")
	}

	removed := callRuntime(
		t,
		runtime,
		protocol.MethodEntityRemove,
		protocol.RemoveEntityParams{EntityID: spawned.ID},
	).(removeEntityResult)
	if !removed.Queued || removed.EntityID != spawned.ID {
		t.Fatalf("remove result = %#v", removed)
	}
	if _, found := findWorldEntity(
		runtime.worldSnapshotLocked(),
		spawned.ID,
	); !found {
		t.Fatal("queued removal flushed before a simulation step")
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 1},
	)
	after := runtime.worldSnapshotLocked()
	if _, found := findWorldEntity(after, spawned.ID); found {
		t.Fatal("queued preview entity survived its flush tick")
	}
	if !hasEvent(after.RecentEvents, sim.EventEntityRemoved, spawned.ID) {
		t.Fatalf("removal event missing from %#v", after.RecentEvents)
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodAppSave,
		protocol.SaveSlotParams{Slot: "clean"},
	)
}

func TestMakerPreviewDefaultsMatchCameraAndWorldSequence(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	before := runtime.worldSnapshotLocked()
	result := callRuntime(
		t,
		runtime,
		protocol.MethodEntitySpawn,
		protocol.SpawnEntityParams{ActorID: "actor.slime"},
	)
	spawned := result.(entityDTO)
	if spawned.ID != "actor.slime.6" {
		t.Fatalf("generated ID = %q, want actor.slime.6", spawned.ID)
	}
	if spawned.X != before.Camera.CenterX ||
		spawned.Y != before.Camera.CenterY {
		t.Fatalf(
			"default position = (%v,%v), camera center = (%v,%v)",
			spawned.X,
			spawned.Y,
			before.Camera.CenterX,
			before.Camera.CenterY,
		)
	}

	callRuntime(
		t,
		runtime,
		protocol.MethodEntityRemove,
		protocol.RemoveEntityParams{EntityID: spawned.ID},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 1},
	)
	next := callRuntime(
		t,
		runtime,
		protocol.MethodEntitySpawn,
		protocol.SpawnEntityParams{ActorID: "actor.slime"},
	).(entityDTO)
	if next.ID != "actor.slime.7" {
		t.Fatalf("second generated ID = %q, want actor.slime.7", next.ID)
	}

	callRuntime(
		t,
		runtime,
		protocol.MethodAppStartNewGame,
		protocol.EmptyParams{},
	)
	reset := callRuntime(
		t,
		runtime,
		protocol.MethodEntitySpawn,
		protocol.SpawnEntityParams{ActorID: "actor.slime"},
	).(entityDTO)
	if reset.ID != "actor.slime.6" {
		t.Fatalf("new-game generated ID = %q, want actor.slime.6", reset.ID)
	}
}

func TestGeneratedPreviewIDCollisionDoesNotSkipSequence(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	x, y := 500.0, 350.0
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySpawn,
		protocol.SpawnEntityParams{
			ActorID:  "actor.slime",
			EntityID: "actor.slime.7",
			X:        &x,
			Y:        &y,
		},
	)
	if _, err := runtime.Call(
		context.Background(),
		protocol.Call{
			Method: protocol.MethodEntitySpawn,
			Params: protocol.SpawnEntityParams{
				ActorID: "actor.slime",
				X:       &x,
				Y:       &y,
			},
		},
	); err == nil {
		t.Fatal("generated ID collision skipped to a later sequence")
	}
	runtime.mu.RLock()
	sequence := runtime.previewSequence
	runtime.mu.RUnlock()
	if sequence != 6 {
		t.Fatalf("failed spawn advanced sequence to %d", sequence)
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodEntityRemove,
		protocol.RemoveEntityParams{EntityID: "actor.slime.7"},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 1},
	)
	spawned := callRuntime(
		t,
		runtime,
		protocol.MethodEntitySpawn,
		protocol.SpawnEntityParams{
			ActorID: "actor.slime",
			X:       &x,
			Y:       &y,
		},
	).(entityDTO)
	if spawned.ID != "actor.slime.7" {
		t.Fatalf("reused generated ID = %q, want actor.slime.7", spawned.ID)
	}
}

func TestPreviewingPlayerActorDoesNotStealStageControl(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	x, y := 500.0, 400.0
	spawned := callRuntime(
		t,
		runtime,
		protocol.MethodEntitySpawn,
		protocol.SpawnEntityParams{
			ActorID:  "actor.hero",
			EntityID: "preview.hero",
			X:        &x,
			Y:        &y,
		},
	).(entityDTO)
	if spawned.ActorID != "actor.hero" ||
		!contains(spawned.Tags, "player") {
		t.Fatalf("player actor preview = %#v", spawned)
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodInputAction,
		protocol.InputActionParams{
			Action: "move_right",
			Value:  1,
			Frames: 1,
		},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 1},
	)
	world := runtime.worldSnapshotLocked()
	if worldEntity(t, world, "player").X <= 150 {
		t.Fatal("authored player did not retain semantic input ownership")
	}
	if preview := worldEntity(t, world, spawned.ID); preview.X != x {
		t.Fatalf("preview player stole movement input: %#v", preview)
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodEntityRequestAbility,
		protocol.RequestAbilityParams{
			EntityID:  spawned.ID,
			AbilityID: "ability.sword_slash",
		},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 1},
	)
	if preview := worldEntity(
		t,
		runtime.worldSnapshotLocked(),
		spawned.ID,
	); preview.AttackPhase == sim.AttackIdle {
		t.Fatalf("explicit preview ability was not applied: %#v", preview)
	}
}

func TestDialoguePreviewDoesNotApplyChoiceQuest(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	result := callRuntime(
		t,
		runtime,
		protocol.MethodDialogueStart,
		protocol.StartDialogueParams{DialogueID: "dialogue.guide"},
	)
	started, ok := result.(startDialogueResult)
	if !ok {
		t.Fatalf("dialogue result type = %T", result)
	}
	if !started.Applied ||
		started.DialogueID != "dialogue.guide" ||
		started.NodeID != "greeting" {
		t.Fatalf("dialogue result = %#v", started)
	}
	world := runtime.worldSnapshotLocked()
	if !world.Dialogue.Active ||
		world.Dialogue.ID != "dialogue.guide" ||
		world.Dialogue.NPCID != "" {
		t.Fatalf("dialogue snapshot = %#v", world.Dialogue)
	}
	if questStatus(world, "quest.slime_patrol") != sim.QuestInactive {
		t.Fatalf("Dialogue.start applied an unchosen quest: %#v", world.Quests)
	}
	if _, err := runtime.Call(
		context.Background(),
		protocol.Call{
			Method: protocol.MethodDialogueStart,
			Params: protocol.StartDialogueParams{
				DialogueID: "dialogue.guide",
			},
		},
	); err == nil {
		t.Fatal("second active dialogue was accepted")
	}

	callRuntime(
		t,
		runtime,
		protocol.MethodInputAction,
		protocol.InputActionParams{
			Action: "interact",
			Value:  1,
			Frames: 1,
		},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 1},
	)
	if runtime.worldSnapshotLocked().Dialogue.Active {
		t.Fatal("semantic interact did not close direct dialogue")
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodAppSave,
		protocol.SaveSlotParams{Slot: "after-dialogue"},
	)
}

func TestAuthoredGuideInteractionDoesNotAutoAcceptChoiceQuest(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: "player",
			X:        220,
			Y:        240,
		},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodInputAction,
		protocol.InputActionParams{
			Action: "interact",
			Value:  1,
			Frames: 1,
		},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 1},
	)
	world := runtime.worldSnapshotLocked()
	if !world.Dialogue.Active || world.Dialogue.NPCID != "guide" {
		t.Fatalf("authored guide dialogue did not open: %#v", world.Dialogue)
	}
	if questStatus(world, "quest.slime_patrol") != sim.QuestInactive {
		t.Fatalf("opening guide dialogue auto-accepted choice quest: %#v", world.Quests)
	}
}

func TestSpawnedGuideCarriesChoiceDependencyWithoutAutoAccept(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	x, y := 500.0, 400.0
	spawned := callRuntime(
		t,
		runtime,
		protocol.MethodEntitySpawn,
		protocol.SpawnEntityParams{
			ActorID:  "actor.guide",
			EntityID: "preview.guide",
			X:        &x,
			Y:        &y,
		},
	).(entityDTO)
	if spawned.ActorID != "actor.guide" {
		t.Fatalf("spawned guide = %#v", spawned)
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: "player",
			X:        455,
			Y:        400,
		},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodInputAction,
		protocol.InputActionParams{
			Action: "interact",
			Value:  1,
			Frames: 1,
		},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 1},
	)
	world := runtime.worldSnapshotLocked()
	if !world.Dialogue.Active ||
		world.Dialogue.NPCID != spawned.ID {
		t.Fatalf("spawned guide dialogue = %#v", world.Dialogue)
	}
	if questStatus(world, "quest.slime_patrol") != sim.QuestInactive {
		t.Fatalf("spawned guide auto-accepted choice quest: %#v", world.Quests)
	}
}

func TestPlayerLoadRejectsLivePreviewAndLegacySessionTopology(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	callRuntime(
		t,
		runtime,
		protocol.MethodAppSave,
		protocol.SaveSlotParams{Slot: "baseline"},
	)
	x, y := 540.0, 300.0
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySpawn,
		protocol.SpawnEntityParams{
			ActorID:  "actor.slime",
			EntityID: "preview.load",
			X:        &x,
			Y:        &y,
		},
	)
	if _, err := runtime.Call(
		context.Background(),
		protocol.Call{
			Method: protocol.MethodAppLoad,
			Params: protocol.SaveSlotParams{Slot: "baseline"},
		},
	); err == nil {
		t.Fatal("player load replaced a live Maker preview")
	}
	if _, found := findWorldEntity(
		runtime.worldSnapshotLocked(),
		"preview.load",
	); !found {
		t.Fatal("rejected player load mutated the running preview")
	}

	callRuntime(
		t,
		runtime,
		protocol.MethodAppStartNewGame,
		protocol.EmptyParams{},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodAppLoad,
		protocol.SaveSlotParams{Slot: "baseline"},
	)
	if world := runtime.worldSnapshotLocked(); world.Count != 5 {
		t.Fatalf("fresh campaign load entity count = %d", world.Count)
	}

	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySpawn,
		protocol.SpawnEntityParams{
			ActorID:  "actor.slime",
			EntityID: "preview.injected",
			X:        &x,
			Y:        &y,
		},
	)
	runtime.mu.RLock()
	injected := runtime.simulation.SaveSession()
	runtime.mu.RUnlock()
	data, err := json.Marshal(injected)
	if err != nil {
		t.Fatal(err)
	}
	if err := runtime.store.Save("injected", data); err != nil {
		t.Fatal(err)
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodAppStartNewGame,
		protocol.EmptyParams{},
	)
	before := runtime.worldSnapshotLocked()
	if _, err := runtime.Call(
		context.Background(),
		protocol.Call{
			Method: protocol.MethodAppLoad,
			Params: protocol.SaveSlotParams{Slot: "injected"},
		},
	); err == nil {
		t.Fatal("injected preview topology was accepted as a player save")
	}
	if _, found := findWorldEntity(
		runtime.worldSnapshotLocked(),
		"preview.injected",
	); found {
		t.Fatal("legacy session preview leaked into the campaign runtime")
	}
	after := runtime.worldSnapshotLocked()
	if !reflect.DeepEqual(after, before) {
		t.Fatal("rejected legacy session mutated the authored World")
	}
}

func TestPendingRemovalProtectsDialogueSpeaker(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	callRuntime(
		t,
		runtime,
		protocol.MethodEntityRemove,
		protocol.RemoveEntityParams{EntityID: "guide"},
	)
	if _, err := runtime.Call(
		context.Background(),
		protocol.Call{
			Method: protocol.MethodDialogueStart,
			Params: protocol.StartDialogueParams{
				DialogueID: "dialogue.guide",
				SpeakerID:  "guide",
			},
		},
	); err == nil {
		t.Fatal("dialogue accepted a speaker queued for removal")
	}
	if _, err := runtime.Call(
		context.Background(),
		protocol.Call{
			Method: protocol.MethodAppReloadContent,
			Params: protocol.EmptyParams{},
		},
	); err == nil {
		t.Fatal("reload accepted pending preview topology")
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 1},
	)
	if _, found := findWorldEntity(
		runtime.worldSnapshotLocked(),
		"guide",
	); found {
		t.Fatal("authored speaker survived queued removal")
	}
}

func TestRemovedAuthoredEntityCannotQueueAbility(t *testing.T) {
	t.Parallel()
	runtime := newTestRuntime(t)
	callRuntime(
		t,
		runtime,
		protocol.MethodEntityRemove,
		protocol.RemoveEntityParams{EntityID: "quest.slime.1"},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodEmulationStep,
		protocol.StepParams{Frames: 1},
	)
	if _, err := runtime.Call(
		context.Background(),
		protocol.Call{
			Method: protocol.MethodEntityRequestAbility,
			Params: protocol.RequestAbilityParams{
				EntityID:  "quest.slime.1",
				AbilityID: "ability.slime_bump",
			},
		},
	); err == nil {
		t.Fatal("removed authored entity accepted an ability request")
	}
	runtime.mu.RLock()
	queued := runtime.pendingAbilities["quest.slime.1"]
	runtime.mu.RUnlock()
	if queued {
		t.Fatal("removed authored entity left a permanently queued ability")
	}
}

func findWorldEntity(
	world worldSnapshotDTO,
	id string,
) (entityDTO, bool) {
	for _, entity := range world.Entities {
		if entity.ID == id {
			return entity, true
		}
	}
	return entityDTO{}, false
}

func hasEvent(events []sim.Event, kind sim.EventType, entityID string) bool {
	for _, event := range events {
		if event.Type == kind && event.EntityID == entityID {
			return true
		}
	}
	return false
}

func questStatus(world worldSnapshotDTO, id string) sim.QuestStatus {
	for _, quest := range world.Quests {
		if quest.ID == id {
			return quest.Status
		}
	}
	return ""
}
