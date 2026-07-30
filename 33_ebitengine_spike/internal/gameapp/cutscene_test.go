package gameapp

import (
	"context"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
)

func TestVillageArrivalCutsceneFreezesWorldAndCompletesNormally(
	t *testing.T,
) {
	runtime := newCampaignRuntime(t)
	before := runtime.simulation.Snapshot().WorldTick
	if err := runtime.Tick(ebitapp.Actions{}); err != nil {
		t.Fatal(err)
	}
	first := runtime.CutsceneState()
	if !first.Active || first.ID != "cutscene.village_arrival" ||
		first.StepID != "threat" || first.StepIndex != 0 ||
		first.StepCount != 2 || first.Text == "" ||
		first.ContinueLabel == "" || first.SkipLabel == "" {
		t.Fatalf("first cutscene step = %#v", first)
	}
	frozenAt := runtime.simulation.Snapshot().WorldTick
	if frozenAt != before+1 {
		t.Fatalf("intro trigger world tick = %d, want %d", frozenAt, before+1)
	}
	if err := runtime.Tick(ebitapp.Actions{}); err != nil {
		t.Fatal(err)
	}
	if got := runtime.simulation.Snapshot().WorldTick; got != frozenAt {
		t.Fatalf("cutscene advanced world tick to %d, want %d", got, frozenAt)
	}
	if _, err := runtime.save(context.Background(), "during-cutscene"); err == nil {
		t.Fatal("save succeeded while cutscene was active")
	}

	if err := runtime.Tick(ebitapp.Actions{MenuConfirm: true}); err != nil {
		t.Fatal(err)
	}
	second := runtime.CutsceneState()
	if !second.Active || second.StepID != "call" ||
		second.StepIndex != 1 || second.Speaker == "" {
		t.Fatalf("second cutscene step = %#v", second)
	}
	if err := runtime.Tick(ebitapp.Actions{MenuConfirm: true}); err != nil {
		t.Fatal(err)
	}
	if runtime.CutsceneState().Active ||
		!campaignFlagValue(
			runtime.CampaignState(),
			"story.village_arrival_seen",
		) ||
		!runtime.View().Notice.Active {
		t.Fatalf(
			"completed cutscene state: cutscene=%#v campaign=%#v notice=%#v",
			runtime.CutsceneState(),
			runtime.CampaignState(),
			runtime.View().Notice,
		)
	}
	if got := runtime.simulation.Snapshot().WorldTick; got != frozenAt {
		t.Fatalf("completion advanced world tick to %d, want %d", got, frozenAt)
	}
	if err := runtime.Tick(ebitapp.Actions{}); err != nil {
		t.Fatal(err)
	}
	if got := runtime.simulation.Snapshot().WorldTick; got != frozenAt+1 {
		t.Fatalf("world did not resume after cutscene: %d", got)
	}
}

func TestVillageArrivalCutsceneSkipPreservesCompletionActions(
	t *testing.T,
) {
	runtime := newCampaignRuntime(t)
	if err := runtime.Tick(ebitapp.Actions{}); err != nil {
		t.Fatal(err)
	}
	frozenAt := runtime.simulation.Snapshot().WorldTick
	if err := runtime.Tick(ebitapp.Actions{MenuCancel: true}); err != nil {
		t.Fatal(err)
	}
	if runtime.CutsceneState().Active ||
		!campaignFlagValue(
			runtime.CampaignState(),
			"story.village_arrival_seen",
		) ||
		!runtime.View().Notice.Active {
		t.Fatalf(
			"skipped cutscene state: cutscene=%#v campaign=%#v notice=%#v",
			runtime.CutsceneState(),
			runtime.CampaignState(),
			runtime.View().Notice,
		)
	}
	if got := runtime.simulation.Snapshot().WorldTick; got != frozenAt {
		t.Fatalf("skip advanced world tick to %d, want %d", got, frozenAt)
	}
}
