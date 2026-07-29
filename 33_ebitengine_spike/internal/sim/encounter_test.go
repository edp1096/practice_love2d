package sim

import (
	"reflect"
	"strings"
	"testing"
)

func TestEncounterManualStartDelayEventsAndSessionRoundTrip(
	t *testing.T,
) {
	config := encounterTestConfig()
	simulation := mustNew(t, config)
	initial := simulation.Snapshot()
	if len(initial.Encounters) != 1 ||
		initial.Encounters[0].Status != EncounterIdle {
		t.Fatalf("initial encounter = %#v", initial.Encounters)
	}

	if err := simulation.StartEncounter("arena"); err != nil {
		t.Fatal(err)
	}
	started := simulation.Snapshot()
	if got := started.Encounters[0]; got.Status != EncounterPending ||
		got.RemainingTicks != 2 {
		t.Fatalf("started encounter = %#v", got)
	}
	assertEventOrder(
		t,
		started.Events,
		EventEncounterStarted,
	)

	simulation.Tick(Input{})
	if got := simulation.Snapshot().Encounters[0]; got.Status != EncounterPending ||
		got.RemainingTicks != 1 {
		t.Fatalf("delayed encounter = %#v", got)
	}
	simulation.Tick(Input{})
	active := simulation.Snapshot()
	if got := active.Encounters[0]; got.Status != EncounterActive ||
		got.WaveID != "scout" || got.WaveIndex != 1 || got.Living != 1 {
		t.Fatalf("active encounter = %#v", got)
	}
	assertEventOrder(
		t,
		active.Events,
		EventType("encounter.wave_opened"),
		EventEntitySpawned,
		EventEncounterWaveStarted,
	)

	saved := simulation.SaveSession()
	restored := mustNew(t, config)
	if err := restored.LoadSession(saved); err != nil {
		t.Fatal(err)
	}
	if got := restored.SaveSession(); !reflect.DeepEqual(got, saved) {
		t.Fatalf("restored session differs:\n got=%#v\nwant=%#v", got, saved)
	}

	corrupt := saved
	corrupt.Encounters = append(
		[]EncounterSessionState(nil),
		saved.Encounters...,
	)
	corrupt.Encounters[0].SpawnEntities = nil
	if err := restored.LoadSession(corrupt); err == nil ||
		!strings.Contains(err.Error(), "wave entity mapping") {
		t.Fatalf("corrupt encounter mapping error = %v", err)
	}

	impossibleCompletion := saved
	impossibleCompletion.Encounters = append(
		[]EncounterSessionState(nil),
		saved.Encounters...,
	)
	impossibleCompletion.Encounters[0].Status = EncounterCompleted
	if err := restored.LoadSession(impossibleCompletion); err == nil ||
		!strings.Contains(err.Error(), "retains living entity") {
		t.Fatalf("living completed encounter error = %v", err)
	}
}

func TestEncounterWaveStartFailureKeepsRestorableTopology(t *testing.T) {
	config := encounterTestConfig()
	config.Entities[0].Status = &StatusReceiverConfig{}
	config.Statuses = []StatusConfig{{
		ID:            "focus",
		DurationTicks: 30,
		Stacking:      StatusRefresh,
		MaxStacks:     1,
		MoveSpeed:     UnitsPerPixel,
		DamageDealt:   UnitsPerPixel,
		DamageTaken:   UnitsPerPixel,
	}}
	config.Encounters[0].Waves[0].DelayTicks = 0
	config.Encounters[0].Waves[0].OnStart = []EncounterActionConfig{
		{
			Type:  EncounterEmit,
			Event: "encounter.before_failed_status",
		},
		{
			Type:     EncounterApplyStatus,
			StatusID: "focus",
		},
	}
	simulation := mustNew(t, config)

	deadHero := simulation.SaveSession()
	for index := range deadHero.Entities {
		if deadHero.Entities[index].ID == "hero" {
			deadHero.Entities[index].Health = 0
			deadHero.Entities[index].Dead = true
		}
	}
	if err := simulation.LoadSession(deadHero); err != nil {
		t.Fatal(err)
	}
	if err := simulation.StartEncounter("arena"); err != nil {
		t.Fatal(err)
	}
	simulation.Tick(Input{})
	failed := simulation.Snapshot().Encounters[0]
	if failed.Status != EncounterFailed || failed.WaveIndex != 0 ||
		failed.Error == "" {
		t.Fatalf("failed encounter = %#v", failed)
	}
	assertEventOrder(
		t,
		simulation.Snapshot().Events,
		EventEncounterActionFailed,
	)
	failure := simulation.Snapshot().Events[0]
	if failure.DefinitionID != "encounter.test" ||
		failure.WaveID != "scout" || failure.WaveIndex != 1 ||
		failure.Scope != "wave_start" ||
		failure.ActionIndex != 2 ||
		failure.ActionType != string(EncounterApplyStatus) {
		t.Fatalf("structured encounter failure = %#v", failure)
	}

	saved := simulation.SaveSession()
	restored := mustNew(t, config)
	if err := restored.LoadSession(saved); err != nil {
		t.Fatalf("restore failed encounter: %v", err)
	}
	if got := restored.SaveSession(); !reflect.DeepEqual(got, saved) {
		t.Fatalf("failed encounter session differs:\n got=%#v\nwant=%#v", got, saved)
	}
}

func TestEncounterRejectsReservedEngineEmitName(t *testing.T) {
	config := encounterTestConfig()
	config.Encounters[0].Waves[0].OnStart[0].Event =
		string(EventActorKilled)
	if _, err := New(config); err == nil ||
		!strings.Contains(err.Error(), "emit action is invalid") {
		t.Fatalf("reserved emit error = %v", err)
	}
}

func encounterTestConfig() Config {
	config := baseConfig()
	spawn := config.Entities[1]
	spawn.ID = "encounter.arena.wave.1.left"
	spawn.Position = Vec{X: Pixels(120), Y: Pixels(50)}
	config.Encounters = []EncounterConfig{{
		ID:             "arena",
		DefinitionID:   "encounter.test",
		TargetEntityID: "hero",
		Waves: []EncounterWaveConfig{{
			ID:         "scout",
			DelayTicks: 2,
			Spawns: []EncounterSpawnConfig{{
				ID:     "left",
				Entity: spawn,
			}},
			OnStart: []EncounterActionConfig{{
				Type:  EncounterEmit,
				Event: "encounter.wave_opened",
			}},
		}},
	}}
	return config
}

func assertEventOrder(
	t *testing.T,
	events []Event,
	wanted ...EventType,
) {
	t.Helper()
	if len(events) != len(wanted) {
		t.Fatalf("event count = %d, want %d: %#v", len(events), len(wanted), events)
	}
	for index, want := range wanted {
		if events[index].Type != want {
			t.Fatalf(
				"event %d = %q, want %q: %#v",
				index,
				events[index].Type,
				want,
				events,
			)
		}
	}
}
