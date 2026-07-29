package gamebuild

import (
	"reflect"
	"strings"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/sim"
)

func TestBuildTranslatesAuthoredEncounterWavesBossAndFutureMetadata(
	t *testing.T,
) {
	t.Parallel()
	result, err := Build(loadCatalog(t), Options{
		StageID:  "stage.encounter_room",
		LocaleID: "locale.ko",
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Config.Encounters) != 1 {
		t.Fatalf("encounters = %#v", result.Config.Encounters)
	}
	encounter := result.Config.Encounters[0]
	if encounter.ID != "arena" ||
		encounter.DefinitionID != "encounter.slime_trial" ||
		encounter.TargetEntityID != "player" ||
		!encounter.AutoStart || len(encounter.Waves) != 2 ||
		len(encounter.OnComplete) != 1 ||
		encounter.OnComplete[0].Event !=
			"encounter.slime_trial_completed" {
		t.Fatalf("encounter = %#v", encounter)
	}

	scouts := encounter.Waves[0]
	if scouts.ID != "scouts" ||
		scouts.DelayTicks != secondsToTicks(0.1) ||
		len(scouts.Spawns) != 2 ||
		len(scouts.OnStart) != 1 ||
		scouts.OnStart[0].Event != "encounter.scouts_started" {
		t.Fatalf("scout wave = %#v", scouts)
	}
	wantScouts := []struct {
		spawnID  string
		entityID string
		position sim.Vec
	}{
		{
			"left",
			"encounter.arena.wave.1.left",
			sim.Vec{X: pixels(420), Y: pixels(270)},
		},
		{
			"right",
			"encounter.arena.wave.1.right",
			sim.Vec{X: pixels(560), Y: pixels(270)},
		},
	}
	for index, want := range wantScouts {
		got := scouts.Spawns[index]
		if got.ID != want.spawnID ||
			got.Entity.ID != want.entityID ||
			got.Entity.Position != want.position ||
			got.Entity.Kind != "actor.slime" {
			t.Fatalf("scout %d = %#v, want %#v", index, got, want)
		}
	}

	bossWave := encounter.Waves[1]
	if bossWave.ID != "boss" ||
		bossWave.DelayTicks != secondsToTicks(0.15) ||
		len(bossWave.Spawns) != 1 ||
		len(bossWave.BossPhases) != 1 {
		t.Fatalf("boss wave = %#v", bossWave)
	}
	boss := bossWave.Spawns[0]
	if boss.ID != "champion" ||
		boss.Entity.ID != "encounter.arena.wave.2.champion" ||
		boss.Entity.Position !=
			(sim.Vec{X: pixels(480), Y: pixels(270)}) ||
		boss.Entity.MaxHealth != 120 ||
		boss.Entity.MovePerTick != rateToCoord(86) {
		t.Fatalf("boss = %#v", boss)
	}
	phase := bossWave.BossPhases[0]
	wantPhase := sim.BossPhaseConfig{
		ID:                "enraged",
		SpawnID:           "champion",
		HealthRatioAtMost: sim.UnitsPerPixel / 2,
		Actions: []sim.EncounterActionConfig{{
			Type:     sim.EncounterApplyStatus,
			StatusID: "status.enraged",
		}},
	}
	if !reflect.DeepEqual(phase, wantPhase) {
		t.Fatalf("boss phase = %#v, want %#v", phase, wantPhase)
	}

	for _, id := range []string{
		"encounter.arena.wave.1.left",
		"encounter.arena.wave.1.right",
		"encounter.arena.wave.2.champion",
	} {
		metadata, found := result.Presentation.Instance(id)
		if !found || metadata.ActorID != "actor.slime" ||
			metadata.SpriteID != "sprite.slime" {
			t.Fatalf("future metadata %q = %#v, %v", id, metadata, found)
		}
	}
	champion, _ := result.Presentation.Instance(
		"encounter.arena.wave.2.champion",
	)
	if !containsTag(champion.Tags, "boss") {
		t.Fatalf("boss metadata tags = %q", champion.Tags)
	}
	if _, err := sim.New(result.Config); err != nil {
		t.Fatalf("translated encounter config is not runnable: %v", err)
	}
}

func TestBuildAndCoverageRejectReservedEncounterEmitName(t *testing.T) {
	t.Parallel()
	catalog := mutateCampaignDefinition(
		t,
		loadCatalog(t),
		"encounter.slime_trial",
		func(data map[string]any) {
			onComplete := data["on_complete"].([]any)
			onComplete[0].(map[string]any)["name"] =
				string(sim.EventActorKilled)
		},
	)
	if _, err := Build(catalog, Options{
		StageID: "stage.encounter_room",
	}); err == nil || !strings.Contains(err.Error(), "reserved") {
		t.Fatalf("reserved encounter emit build error = %v", err)
	}
	coverage, err := ValidateDefinition(
		catalog,
		"encounter.slime_trial",
	)
	if err != nil {
		t.Fatal(err)
	}
	if !coverage.SchemaValid || coverage.FullyApplied ||
		!warningsContain(coverage.Warnings, "reserved") {
		t.Fatalf("reserved encounter emit coverage = %#v", coverage)
	}
}
