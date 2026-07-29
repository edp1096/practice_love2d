package gameapp

import (
	"context"
	"reflect"
	"strings"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/protocol"
	"practice_love2d/33_ebitengine_spike/internal/storage"
)

func TestFlowProtocolControlsTheVisibleSemanticMenu(t *testing.T) {
	runtime := newFlowRuntime(t, t.TempDir())
	ctx := context.Background()

	result, err := runtime.Call(ctx, protocol.Call{
		Method: protocol.MethodFlowGetState,
		Params: protocol.EmptyParams{},
	})
	if err != nil {
		t.Fatal(err)
	}
	initial := result.(FlowState)
	if initial.Mode != campaign.ModeTitle ||
		initial.SelectedIndex != 0 ||
		!reflect.DeepEqual(
			flowStateOptionIDs(initial),
			[]string{"new_game", "quit"},
		) {
		t.Fatalf("initial protocol flow = %#v", initial)
	}

	result, err = runtime.Call(ctx, protocol.Call{
		Method: protocol.MethodFlowMove,
		Params: protocol.FlowMoveParams{Delta: 1},
	})
	if err != nil {
		t.Fatal(err)
	}
	moved := result.(FlowState)
	if moved.SelectedIndex != 1 ||
		moved.Revision <= initial.Revision {
		t.Fatalf("moved protocol flow = %#v", moved)
	}

	beforeInvalid := runtime.View()
	if _, err := runtime.Call(ctx, protocol.Call{
		Method: protocol.MethodFlowActivate,
		Params: protocol.FlowActivateParams{OptionID: "continue"},
	}); err == nil || !strings.Contains(err.Error(), "not visible") {
		t.Fatalf("hidden flow option error = %v", err)
	}
	if afterInvalid := runtime.View(); !reflect.DeepEqual(
		afterInvalid,
		beforeInvalid,
	) {
		t.Fatalf(
			"invalid flow activation mutated view:\n got %#v\nwant %#v",
			afterInvalid,
			beforeInvalid,
		)
	}

	result, err = runtime.Call(ctx, protocol.Call{
		Method: protocol.MethodFlowActivate,
		Params: protocol.FlowActivateParams{OptionID: "new_game"},
	})
	if err != nil {
		t.Fatal(err)
	}
	playing := result.(FlowState)
	if playing.Active || playing.Mode != campaign.ModePlaying {
		t.Fatalf("activated protocol flow = %#v", playing)
	}
	stateResult, err := runtime.Call(ctx, protocol.Call{
		Method: protocol.MethodRuntimeGetState,
		Params: protocol.EmptyParams{},
	})
	if err != nil {
		t.Fatal(err)
	}
	if mode := stateResult.(runtimeStateDTO).Mode; mode != string(campaign.ModePlaying) {
		t.Fatalf("Runtime.getState mode = %q", mode)
	}
}

func TestEmulationStepRejectsSemanticFlowAndCannotAdvanceHiddenWorld(
	t *testing.T,
) {
	runtime := newFlowRuntime(t, t.TempDir())
	ctx := context.Background()
	assertRejectedWithoutMutation := func(wantMode campaign.Mode) {
		t.Helper()
		beforeSession := runtime.simulation.SaveSession()
		beforeCampaign := runtime.CampaignState()
		beforeRevision := runtime.View().Revision
		beforeAutomationPause := runtime.automationPaused
		_, err := runtime.Call(ctx, protocol.Call{
			Method: protocol.MethodEmulationStep,
			Params: protocol.StepParams{Frames: 3},
		})
		if err == nil ||
			!strings.Contains(err.Error(), string(wantMode)) {
			t.Fatalf("step in %q error = %v", wantMode, err)
		}
		if got := runtime.simulation.SaveSession(); !reflect.DeepEqual(
			got,
			beforeSession,
		) {
			t.Fatalf("step in %q mutated World", wantMode)
		}
		if got := runtime.CampaignState(); !reflect.DeepEqual(
			got,
			beforeCampaign,
		) {
			t.Fatalf("step in %q mutated Campaign", wantMode)
		}
		if runtime.View().Revision != beforeRevision ||
			runtime.automationPaused != beforeAutomationPause {
			t.Fatalf(
				"step in %q changed revision/pause: %d/%v want %d/%v",
				wantMode,
				runtime.View().Revision,
				runtime.automationPaused,
				beforeRevision,
				beforeAutomationPause,
			)
		}
	}

	assertRejectedWithoutMutation(campaign.ModeTitle)
	if _, err := runtime.ActivateFlowOption("new_game"); err != nil {
		t.Fatal(err)
	}
	if _, err := runtime.Call(ctx, protocol.Call{
		Method: protocol.MethodEmulationStep,
		Params: protocol.StepParams{Frames: 1},
	}); err != nil {
		t.Fatalf("step while playing: %v", err)
	}
	if err := runtime.Tick(ebitapp.Actions{Pause: true}); err != nil {
		t.Fatal(err)
	}
	assertRejectedWithoutMutation(campaign.ModePaused)
}

func TestEmulationStepRollsBackBatchThatEntersSemanticFlowEarly(
	t *testing.T,
) {
	runtime := newFlowRuntime(t, t.TempDir())
	startFlowGame(t, runtime)
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetHealth,
		protocol.SetHealthParams{EntityID: "player", Value: 0},
	)
	beforeSession := runtime.simulation.SaveSession()
	beforeCampaign := runtime.CampaignState()
	beforeRevision := runtime.View().Revision
	beforeAutomationPause := runtime.automationPaused

	_, err := runtime.Call(context.Background(), protocol.Call{
		Method: protocol.MethodEmulationStep,
		Params: protocol.StepParams{Frames: 2},
	})
	if err == nil ||
		!strings.Contains(err.Error(), "before the requested batch completed") {
		t.Fatalf("flow-entering batch error = %v", err)
	}
	if got := runtime.simulation.SaveSession(); !reflect.DeepEqual(
		got,
		beforeSession,
	) {
		t.Fatal("flow-entering batch leaked World changes")
	}
	if got := runtime.CampaignState(); !reflect.DeepEqual(
		got,
		beforeCampaign,
	) {
		t.Fatalf(
			"flow-entering batch leaked Campaign:\n got %#v\nwant %#v",
			got,
			beforeCampaign,
		)
	}
	if runtime.View().Revision != beforeRevision ||
		runtime.automationPaused != beforeAutomationPause {
		t.Fatal("flow-entering batch leaked revision or automation pause")
	}

	// The same transition is valid when it occurs on the requested final
	// frame. Only hidden extra World frames are forbidden.
	if _, err := runtime.Call(context.Background(), protocol.Call{
		Method: protocol.MethodEmulationStep,
		Params: protocol.StepParams{Frames: 1},
	}); err != nil {
		t.Fatal(err)
	}
	if got := runtime.CampaignState().Mode; got != campaign.ModeGameOver {
		t.Fatalf("single final transition mode = %q", got)
	}
}

func TestAuthoredTitleStartsAndFreezesWorldWithoutAutomationPause(
	t *testing.T,
) {
	runtime := newFlowRuntime(t, t.TempDir())
	state := runtime.CampaignState()
	if state.Mode != campaign.ModeTitle ||
		state.Flow.Started ||
		state.CurrentStageID != "" ||
		state.EntrySpawnID != "" {
		t.Fatalf("initial title campaign = %#v", state)
	}
	view := runtime.View()
	if !view.Flow.Active ||
		view.Flow.Mode != string(campaign.ModeTitle) ||
		view.Flow.Heading != "고요한 숲의 수호자" ||
		!reflect.DeepEqual(
			flowOptionIDs(view.Flow),
			[]string{"new_game", "quit"},
		) {
		t.Fatalf("initial title view = %#v", view.Flow)
	}
	before := runtime.simulation.SaveSession()
	if err := runtime.Tick(ebitapp.Actions{
		MoveX:  1,
		Attack: true,
	}); err != nil {
		t.Fatal(err)
	}
	if after := runtime.simulation.SaveSession(); !reflect.DeepEqual(
		after,
		before,
	) {
		t.Fatalf("title advanced World:\n got %#v\nwant %#v", after, before)
	}
	if runtime.automationPaused {
		t.Fatal("title reused the automation pause clock")
	}

	if err := runtime.Tick(ebitapp.Actions{FlowConfirm: true}); err != nil {
		t.Fatal(err)
	}
	state = runtime.CampaignState()
	if state.Mode != campaign.ModePlaying ||
		!state.Flow.Started ||
		state.Flow.Completed ||
		state.CurrentStageID != "stage.village" ||
		state.EntrySpawnID != "default" ||
		runtime.View().Flow.Active {
		t.Fatalf("new-game campaign/view = %#v / %#v", state, runtime.View())
	}
}

func TestEscapePauseIsSemanticAndResumesWithoutFreezingAutomation(
	t *testing.T,
) {
	runtime := newFlowRuntime(t, t.TempDir())
	startFlowGame(t, runtime)
	before := runtime.simulation.SaveSession()

	if err := runtime.Tick(ebitapp.Actions{Pause: true}); err != nil {
		t.Fatal(err)
	}
	state := runtime.CampaignState()
	view := runtime.View()
	if state.Mode != campaign.ModePaused ||
		runtime.automationPaused ||
		!view.Flow.Active ||
		!reflect.DeepEqual(
			flowOptionIDs(view.Flow),
			[]string{"resume", "save", "title"},
		) {
		t.Fatalf(
			"semantic pause state=%#v automation=%v view=%#v",
			state,
			runtime.automationPaused,
			view.Flow,
		)
	}
	if err := runtime.Tick(ebitapp.Actions{
		MoveX:  1,
		Attack: true,
	}); err != nil {
		t.Fatal(err)
	}
	if after := runtime.simulation.SaveSession(); !reflect.DeepEqual(
		after,
		before,
	) {
		t.Fatal("paused flow advanced World")
	}
	if err := runtime.Tick(ebitapp.Actions{FlowCancel: true}); err != nil {
		t.Fatal(err)
	}
	if got := runtime.CampaignState().Mode; got != campaign.ModePlaying {
		t.Fatalf("cancel resumed mode = %q", got)
	}

	// P uses the dedicated Pause action both to enter and leave the menu.
	if err := runtime.Tick(ebitapp.Actions{Pause: true}); err != nil {
		t.Fatal(err)
	}
	if err := runtime.Tick(ebitapp.Actions{Pause: true}); err != nil {
		t.Fatal(err)
	}
	if got := runtime.CampaignState().Mode; got != campaign.ModePlaying {
		t.Fatalf("pause-key resumed mode = %q", got)
	}
}

func TestPauseSaveProvidesValidatedContinueAfterProcessRestart(
	t *testing.T,
) {
	root := t.TempDir()
	processA := newFlowRuntime(t, root)
	startFlowGame(t, processA)
	acceptVillageGuideQuest(t, processA)

	if err := processA.Tick(ebitapp.Actions{Pause: true}); err != nil {
		t.Fatal(err)
	}
	if err := processA.Tick(ebitapp.Actions{FlowDown: true}); err != nil {
		t.Fatal(err)
	}
	if err := processA.Tick(ebitapp.Actions{FlowConfirm: true}); err != nil {
		t.Fatal(err)
	}
	paused := processA.View().Flow
	if processA.CampaignState().Mode != campaign.ModePaused ||
		paused.Message == "" ||
		!processA.continueAvailable {
		t.Fatalf("pause-save result = %#v", paused)
	}

	processB := newFlowRuntime(t, root)
	title := processB.View().Flow
	if !reflect.DeepEqual(
		flowOptionIDs(title),
		[]string{"new_game", "continue", "quit"},
	) || !processB.continueAvailable {
		t.Fatalf("restart title = %#v", title)
	}
	if err := processB.Tick(ebitapp.Actions{FlowDown: true}); err != nil {
		t.Fatal(err)
	}
	if err := processB.Tick(ebitapp.Actions{FlowConfirm: true}); err != nil {
		t.Fatal(err)
	}
	restored := processB.CampaignState()
	if restored.Mode != campaign.ModePlaying ||
		campaignQuest(t, restored, "quest.grove_guardian").Status !=
			campaign.QuestActive ||
		campaignEquipment(t, restored, "weapon").ItemID !=
			"item.training_sword" ||
		restored.Currency != 25 ||
		controlledAttackDamage(t, processB) != 39 {
		t.Fatalf("continued campaign = %#v", restored)
	}
}

func TestCorruptSaveIsNotAdvertisedAsContinue(t *testing.T) {
	root := t.TempDir()
	store, err := storage.NewFileStore(root)
	if err != nil {
		t.Fatal(err)
	}
	if err := store.Save("campaign", []byte(`{"broken":true}`)); err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{
		Store:        store,
		StartAtTitle: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if runtime.continueAvailable ||
		!reflect.DeepEqual(
			flowOptionIDs(runtime.View().Flow),
			[]string{"new_game", "quit"},
		) {
		t.Fatalf("corrupt-save title = %#v", runtime.View().Flow)
	}
}

func TestPlayerDeathOpensGameOverAndRetryBuildsFreshWorld(t *testing.T) {
	runtime := newFlowRuntime(t, t.TempDir())
	startFlowGame(t, runtime)
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetHealth,
		protocol.SetHealthParams{EntityID: "player", Value: 0},
	)
	if err := runtime.Tick(ebitapp.Actions{}); err != nil {
		t.Fatal(err)
	}
	state := runtime.CampaignState()
	view := runtime.View().Flow
	if state.Mode != campaign.ModeGameOver ||
		!view.Active ||
		!reflect.DeepEqual(
			flowOptionIDs(view),
			[]string{"retry", "title"},
		) {
		t.Fatalf("game-over state=%#v view=%#v", state, view)
	}
	deadWorld := runtime.simulation.SaveSession()
	if err := runtime.Tick(ebitapp.Actions{MoveX: 1}); err != nil {
		t.Fatal(err)
	}
	if got := runtime.simulation.SaveSession(); !reflect.DeepEqual(
		got,
		deadWorld,
	) {
		t.Fatal("game-over flow advanced World")
	}
	if err := runtime.Tick(ebitapp.Actions{FlowConfirm: true}); err != nil {
		t.Fatal(err)
	}
	player := entitySnapshot(t, runtime, "player")
	if runtime.CampaignState().Mode != campaign.ModePlaying ||
		player.Dead ||
		player.Health != player.MaxHealth {
		t.Fatalf(
			"retry mode=%q player=%#v",
			runtime.CampaignState().Mode,
			player,
		)
	}
}

func TestCompletedCampaignShowsEndingAndTitleCreatesPristineSession(
	t *testing.T,
) {
	runtime := newFlowRuntime(t, t.TempDir())
	startFlowGame(t, runtime)
	if err := runtime.campaign.Transaction(func(state *campaign.State) error {
		state.Flow.Completed = true
		state.Mode = campaign.ModeEnding
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	view := runtime.View().Flow
	if !view.Active ||
		view.Heading != "숲에 평화가 돌아왔습니다" ||
		!reflect.DeepEqual(
			flowOptionIDs(view),
			[]string{"new_game", "title"},
		) {
		t.Fatalf("ending view = %#v", view)
	}
	if err := runtime.Tick(ebitapp.Actions{FlowDown: true}); err != nil {
		t.Fatal(err)
	}
	if err := runtime.Tick(ebitapp.Actions{FlowConfirm: true}); err != nil {
		t.Fatal(err)
	}
	state := runtime.CampaignState()
	if state.Mode != campaign.ModeTitle ||
		state.Flow.Started ||
		state.Flow.Completed ||
		state.CurrentStageID != "" ||
		state.EntrySpawnID != "" {
		t.Fatalf("returned title campaign = %#v", state)
	}
}

func TestTitleQuitRequestsEbitengineTermination(t *testing.T) {
	runtime := newFlowRuntime(t, t.TempDir())
	if err := runtime.Tick(ebitapp.Actions{FlowDown: true}); err != nil {
		t.Fatal(err)
	}
	if err := runtime.Tick(ebitapp.Actions{FlowConfirm: true}); err != nil {
		t.Fatal(err)
	}
	if !runtime.View().Quit {
		t.Fatal("title quit did not request termination")
	}
}

func newFlowRuntime(t *testing.T, root string) *Runtime {
	t.Helper()
	store, err := storage.NewFileStore(root)
	if err != nil {
		t.Fatal(err)
	}
	runtime, err := New(Options{
		Store:        store,
		StartAtTitle: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	return runtime
}

func startFlowGame(t *testing.T, runtime *Runtime) {
	t.Helper()
	if err := runtime.Tick(ebitapp.Actions{FlowConfirm: true}); err != nil {
		t.Fatal(err)
	}
	if runtime.CampaignState().Mode != campaign.ModePlaying {
		t.Fatalf("new game mode = %q", runtime.CampaignState().Mode)
	}
}

func flowOptionIDs(view ebitapp.FlowView) []string {
	result := make([]string, len(view.Options))
	for index, option := range view.Options {
		result[index] = option.ID
	}
	return result
}

func flowStateOptionIDs(state FlowState) []string {
	result := make([]string, len(state.Options))
	for index, option := range state.Options {
		result[index] = option.ID
	}
	return result
}
