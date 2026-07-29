package gameapp

import (
	"context"
	"path/filepath"
	"reflect"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/protocol"
	"practice_love2d/33_ebitengine_spike/internal/sim"
	"practice_love2d/33_ebitengine_spike/internal/storage"
)

func TestProtocolStartsAuthoredEncounterIdempotently(t *testing.T) {
	store, err := storage.NewFileStore(filepath.Join(t.TempDir(), "saves"))
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{
		CatalogPath: filepath.Join("..", "..", "game", "catalog.json"),
		Build: gamebuild.Options{
			StageID:  "stage.encounter_room",
			LocaleID: "locale.ko",
		},
		Store: store,
	})
	if err != nil {
		t.Fatal(err)
	}
	session := runtime.simulation.SaveSession()
	if len(session.Encounters) != 1 ||
		session.Encounters[0].Status != sim.EncounterPending {
		t.Fatalf("authored auto-start session = %#v", session.Encounters)
	}
	session.Encounters[0] = sim.EncounterSessionState{
		ID:        "arena",
		Status:    sim.EncounterIdle,
		WaveIndex: -1,
	}
	if err := runtime.simulation.LoadSession(session); err != nil {
		t.Fatalf("prepare manual protocol start: %v", err)
	}
	before := runtime.revision
	result := callRuntime(
		t,
		runtime,
		protocol.MethodEncounterStart,
		protocol.StartEncounterParams{EncounterID: "arena"},
	).(encounterStartResult)
	if !result.Applied || result.EncounterID != "arena" ||
		result.DefinitionID != "encounter.slime_trial" ||
		result.Status != sim.EncounterPending ||
		runtime.revision != before+1 {
		t.Fatalf("first encounter start = %#v revision=%d", result, runtime.revision)
	}
	again := callRuntime(
		t,
		runtime,
		protocol.MethodEncounterStart,
		protocol.StartEncounterParams{EncounterID: "arena"},
	).(encounterStartResult)
	if again.Applied || again.Status != sim.EncounterPending ||
		runtime.revision != before+1 {
		t.Fatalf("repeated encounter start = %#v revision=%d", again, runtime.revision)
	}
	runtime.equipmentRebuildPending = true
	if _, err := runtime.Call(
		context.Background(),
		protocol.Call{
			Method: protocol.MethodEncounterStart,
			Params: protocol.StartEncounterParams{
				EncounterID: "arena",
			},
		},
	); err == nil {
		t.Fatal("encounter start during pending equipment rebuild was accepted")
	}
	runtime.equipmentRebuildPending = false
	if _, err := runtime.Call(
		context.Background(),
		protocol.Call{
			Method: protocol.MethodEncounterStart,
			Params: protocol.StartEncounterParams{
				EncounterID: "missing",
			},
		},
	); err == nil {
		t.Fatal("unknown encounter start was accepted")
	}

	title, err := campaign.NewTitle(runtime.campaign.Config())
	if err != nil {
		t.Fatal(err)
	}
	runtime.campaign = title
	if _, err := runtime.Call(
		context.Background(),
		protocol.Call{
			Method: protocol.MethodEncounterStart,
			Params: protocol.StartEncounterParams{
				EncounterID: "arena",
			},
		},
	); err == nil {
		t.Fatal("encounter start outside playing mode was accepted")
	}
}

func TestAuthoredEncounterAdvancesWavesBossPhaseAndCompletion(
	t *testing.T,
) {
	store, err := storage.NewFileStore(filepath.Join(t.TempDir(), "saves"))
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{
		CatalogPath: filepath.Join("..", "..", "game", "catalog.json"),
		Build: gamebuild.Options{
			StageID:  "stage.encounter_room",
			LocaleID: "locale.ko",
		},
		Store: store,
	})
	if err != nil {
		t.Fatal(err)
	}

	initial := encounterSnapshot(t, runtime, "arena")
	if initial.Status != sim.EncounterPending ||
		initial.RemainingTicks != 6 || initial.WaveIndex != 0 {
		t.Fatalf("authored auto-start encounter = %#v", initial)
	}
	firstWave := waitForEncounter(
		t,
		runtime,
		sim.EncounterActive,
		"scouts",
		20,
	)
	if firstWave.Living != 2 {
		t.Fatalf("first wave = %#v", firstWave)
	}
	scoutIDs := []string{
		"encounter.arena.wave.1.left",
		"encounter.arena.wave.1.right",
	}
	for _, id := range scoutIDs {
		scout := entitySnapshot(t, runtime, id)
		metadata, exists := runtime.metadata(id)
		if !exists || scout.Dead || scout.Kind != "actor.slime" ||
			!contains(metadata.Tags, "enemy") ||
			metadata.SpriteID != "sprite.slime" {
			t.Fatalf(
				"authored scout %q is incomplete: entity=%#v metadata=%#v",
				id,
				scout,
				metadata,
			)
		}
		setEntityHealth(t, runtime, id, 0)
	}
	if err := runtime.Tick(ebitapp.Actions{}); err != nil {
		t.Fatal(err)
	}

	bossWave := waitForEncounter(
		t,
		runtime,
		sim.EncounterActive,
		"boss",
		24,
	)
	if bossWave.Living != 1 {
		t.Fatalf("boss wave = %#v", bossWave)
	}
	const bossID = "encounter.arena.wave.2.champion"
	boss := entitySnapshot(t, runtime, bossID)
	metadata, exists := runtime.metadata(bossID)
	if !exists || boss.MaxHealth != 120 ||
		!contains(metadata.Tags, "boss") ||
		metadata.SpriteID != "sprite.slime" {
		t.Fatalf("authored boss = %#v metadata=%#v", boss, metadata)
	}

	setEntityHealth(t, runtime, bossID, 60)
	if err := runtime.Tick(ebitapp.Actions{}); err != nil {
		t.Fatal(err)
	}
	boss = entitySnapshot(t, runtime, bossID)
	state := encounterSnapshot(t, runtime, "arena")
	if len(state.EnteredPhases) != 1 ||
		state.EnteredPhases[0] != "enraged" ||
		len(boss.Statuses) != 1 ||
		boss.Statuses[0].ID != "status.enraged" {
		t.Fatalf("boss phase state=%#v boss=%#v", state, boss)
	}
	if err := runtime.Tick(ebitapp.Actions{}); err != nil {
		t.Fatal(err)
	}
	if phases := encounterSnapshot(
		t,
		runtime,
		"arena",
	).EnteredPhases; len(phases) != 1 {
		t.Fatalf("boss phase ran more than once: %v", phases)
	}

	saved := runtime.simulation.SaveSession()
	restored, err := sim.New(runtime.built.Config)
	if err != nil {
		t.Fatal(err)
	}
	if err := restored.LoadSession(saved); err != nil {
		t.Fatalf("restore active encounter: %v", err)
	}
	if got := restored.SaveSession(); !reflect.DeepEqual(got, saved) {
		t.Fatalf(
			"encounter session differs:\n got=%#v\nwant=%#v",
			got,
			saved,
		)
	}

	setEntityHealth(t, runtime, bossID, 0)
	if err := runtime.Tick(ebitapp.Actions{}); err != nil {
		t.Fatal(err)
	}
	completed := encounterSnapshot(t, runtime, "arena")
	if completed.Status != sim.EncounterCompleted ||
		completed.Living != 0 {
		t.Fatalf("completed encounter = %#v", completed)
	}
	snapshot := runtime.simulation.Snapshot()
	if !eventTypesContain(
		snapshot.Events,
		sim.EventEncounterCompleted,
		sim.EventType("encounter.slime_trial_completed"),
	) {
		t.Fatalf("completion events = %#v", snapshot.Events)
	}

	runtime.mu.RLock()
	world := runtime.worldSnapshotLocked()
	runtime.mu.RUnlock()
	if world.EncounterCount != 1 ||
		len(world.Encounters) != 1 ||
		world.Encounters[0].Status != sim.EncounterCompleted {
		t.Fatalf("encounter world DTO = %#v", world.Encounters)
	}
}

func waitForEncounter(
	t *testing.T,
	runtime *Runtime,
	status sim.EncounterStatus,
	waveID string,
	limit int,
) sim.EncounterSnapshot {
	t.Helper()
	for range limit {
		state := encounterSnapshot(t, runtime, "arena")
		if state.Status == status && state.WaveID == waveID {
			return state
		}
		if err := runtime.Tick(ebitapp.Actions{}); err != nil {
			t.Fatal(err)
		}
	}
	state := encounterSnapshot(t, runtime, "arena")
	t.Fatalf(
		"encounter did not reach status=%q wave=%q: %#v",
		status,
		waveID,
		state,
	)
	return sim.EncounterSnapshot{}
}

func encounterSnapshot(
	t *testing.T,
	runtime *Runtime,
	id string,
) sim.EncounterSnapshot {
	t.Helper()
	for _, state := range runtime.simulation.Snapshot().Encounters {
		if state.ID == id {
			return state
		}
	}
	t.Fatalf("encounter %q is missing", id)
	return sim.EncounterSnapshot{}
}

func setEntityHealth(
	t *testing.T,
	runtime *Runtime,
	id string,
	health int,
) {
	t.Helper()
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetHealth,
		protocol.SetHealthParams{
			EntityID: id,
			Value:    float64(health),
		},
	)
}

func eventTypesContain(
	events []sim.Event,
	wanted ...sim.EventType,
) bool {
	found := make(map[sim.EventType]bool, len(wanted))
	for _, event := range events {
		found[event.Type] = true
	}
	for _, eventType := range wanted {
		if !found[eventType] {
			return false
		}
	}
	return true
}
