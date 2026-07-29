package gameapp

import (
	"reflect"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/protocol"
)

// TestCompleteAuthoredCampaignAcrossProcessRestart is the executable release
// gate for docs/CAMPAIGN_MIGRATION.md. It intentionally uses only the same
// semantic input and protocol boundaries available to an external controller.
func TestCompleteAuthoredCampaignAcrossProcessRestart(t *testing.T) {
	saveRoot := t.TempDir()

	// Process A: title -> authored village interactions -> pause save.
	processA := newFlowRuntime(t, saveRoot)
	if got := flowOptionIDs(processA.View().Flow); !reflect.DeepEqual(
		got,
		[]string{"new_game", "quit"},
	) {
		t.Fatalf("fresh title options = %q", got)
	}
	activateFlow(t, processA, "new_game")
	assertLocation(t, processA, "stage.village", "default")

	acceptVillageGuideQuest(t, processA)
	accepted := processA.CampaignState()
	if campaignQuest(
		t,
		accepted,
		"quest.grove_guardian",
	).Status != campaign.QuestActive ||
		campaignItem(
			t,
			accepted,
			"item.training_sword",
		).Quantity != 1 ||
		campaignEquipment(t, accepted, "weapon").ItemID !=
			"item.training_sword" ||
		accepted.Currency != 25 ||
		controlledAttackDamage(t, processA) != 39 {
		t.Fatalf("accepted campaign = %#v", accepted)
	}

	openVillageMerchantShop(t, processA)
	callRuntime(
		t,
		processA,
		protocol.MethodShopBuy,
		protocol.ShopTradeParams{
			ItemID:   "item.potion",
			Quantity: 1,
		},
	)
	callRuntime(
		t,
		processA,
		protocol.MethodShopClose,
		protocol.EmptyParams{},
	)
	shopped := processA.CampaignState()
	if shopped.Currency != 0 ||
		campaignItem(t, shopped, "item.potion").Quantity != 1 {
		t.Fatalf("campaign after potion purchase = %#v", shopped)
	}

	if err := processA.Tick(ebitapp.Actions{Pause: true}); err != nil {
		t.Fatal(err)
	}
	savedFlow := activateFlow(t, processA, "save")
	if savedFlow.Mode != campaign.ModePaused ||
		!savedFlow.HasSave ||
		savedFlow.Status != "saved" {
		t.Fatalf("pause save flow = %#v", savedFlow)
	}

	// Process B: a brand-new Runtime proves the disk save is the only bridge.
	processB := newFlowRuntime(t, saveRoot)
	if got := flowOptionIDs(processB.View().Flow); !reflect.DeepEqual(
		got,
		[]string{"new_game", "continue", "quit"},
	) {
		t.Fatalf("restart title options = %q", got)
	}
	activateFlow(t, processB, "continue")
	assertLocation(t, processB, "stage.village", "default")
	continued := processB.CampaignState()
	if continued.Mode != campaign.ModePlaying ||
		campaignQuest(
			t,
			continued,
			"quest.grove_guardian",
		).Status != campaign.QuestActive ||
		campaignEquipment(t, continued, "weapon").ItemID !=
			"item.training_sword" ||
		campaignItem(t, continued, "item.potion").Quantity != 1 ||
		continued.Currency != 0 ||
		controlledAttackDamage(t, processB) != 39 {
		t.Fatalf("continued campaign = %#v", continued)
	}

	transitionThroughPortal(
		t,
		processB,
		"to_field",
		"stage.world_hub",
		"village_entry",
	)

	// One 39-health enemy must die from one sword attack. This proves the
	// durable equipment state affects real combat, not only a displayed stat.
	killWithOnePlayerAttack(
		t,
		processB,
		"enemy.slime.1",
		400,
		220,
		39,
	)
	assertObjectiveCount(
		t,
		processB.CampaignState(),
		"quest.grove_guardian",
		"defeat_slimes",
		1,
	)
	killWithOnePlayerAttack(
		t,
		processB,
		"enemy.slime.2",
		620,
		300,
		1,
	)
	fieldComplete := processB.CampaignState()
	assertObjectiveCount(
		t,
		fieldComplete,
		"quest.grove_guardian",
		"defeat_slimes",
		2,
	)
	if campaignQuest(
		t,
		fieldComplete,
		"quest.grove_guardian",
	).Status != campaign.QuestActive {
		t.Fatalf("slime-only quest status = %#v", fieldComplete.Quests)
	}

	transitionThroughPortal(
		t,
		processB,
		"to_grove",
		"stage.world_grove",
		"west_entry",
	)
	killWithOnePlayerAttack(
		t,
		processB,
		"boss.grove_guardian",
		500,
		288,
		1,
	)

	rewarded := processB.CampaignState()
	assertObjectiveCount(
		t,
		rewarded,
		"quest.grove_guardian",
		"defeat_guardian",
		1,
	)
	if campaignQuest(
		t,
		rewarded,
		"quest.grove_guardian",
	).Status != campaign.QuestCompleted ||
		rewarded.Currency != 75 ||
		campaignItem(t, rewarded, "item.potion").Quantity != 2 ||
		!campaignFlag(t, rewarded, "quest.grove_guardian.rewarded") {
		t.Fatalf("completed quest rewards = %#v", rewarded)
	}

	transitionThroughPortal(
		t,
		processB,
		"to_hub",
		"stage.world_hub",
		"grove_return",
	)
	transitionThroughPortal(
		t,
		processB,
		"to_village",
		"stage.village",
		"field_return",
	)

	dialogue := openVillageGuideDialogue(t, processB)
	if got := dialogueChoiceIDs(dialogue); !reflect.DeepEqual(
		got,
		[]string{"completed", "leave"},
	) {
		t.Fatalf("completed guide choices = %q", got)
	}
	dialogue = callRuntime(
		t,
		processB,
		protocol.MethodDialogueChoose,
		protocol.ChooseDialogueParams{ChoiceID: "completed"},
	).(DialogueState)
	ending := processB.CampaignState()
	if dialogue.NodeID != "thanks" ||
		!dialogue.Active ||
		ending.Mode != campaign.ModeEnding ||
		!ending.Flow.Completed ||
		!processB.View().Flow.Active {
		t.Fatalf(
			"campaign ending: dialogue=%#v campaign=%#v flow=%#v",
			dialogue,
			ending,
			processB.View().Flow,
		)
	}
}

func activateFlow(
	t *testing.T,
	runtime *Runtime,
	optionID string,
) FlowState {
	t.Helper()
	result := callRuntime(
		t,
		runtime,
		protocol.MethodFlowActivate,
		protocol.FlowActivateParams{OptionID: optionID},
	)
	state, ok := result.(FlowState)
	if !ok {
		t.Fatalf("Flow.activate result type = %T", result)
	}
	return state
}

func killWithOnePlayerAttack(
	t *testing.T,
	runtime *Runtime,
	targetID string,
	targetX float64,
	targetY float64,
	health float64,
) {
	t.Helper()
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: targetID,
			X:        targetX,
			Y:        targetY,
		},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetHealth,
		protocol.SetHealthParams{
			EntityID: targetID,
			Value:    health,
		},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: "player",
			X:        targetX - 34,
			Y:        targetY,
		},
	)
	scheduleProtocolAction(t, runtime, "attack")
	for range 30 {
		stepProtocol(t, runtime, 1)
		if entitySnapshot(t, runtime, targetID).Dead {
			return
		}
	}
	target := entitySnapshot(t, runtime, targetID)
	t.Fatalf(
		"one controlled attack did not kill %q: health=%d phase=%q",
		targetID,
		target.Health,
		target.Attack.Phase,
	)
}

func transitionThroughPortal(
	t *testing.T,
	runtime *Runtime,
	portalID string,
	targetStageID string,
	targetSpawnID string,
) {
	t.Helper()
	// Entry portals use an authored cooldown and an inside latch to prevent
	// immediate bounce-back. Let both clear while the player remains at the
	// safe entry/combat position, then cross the requested portal edge.
	stepProtocol(t, runtime, 30)
	moveEntityToPortal(t, runtime, "player", portalID)
	for range 2 * 60 {
		stepProtocol(t, runtime, 1)
		state := runtime.CampaignState()
		if state.CurrentStageID == targetStageID {
			assertLocation(t, runtime, targetStageID, targetSpawnID)
			return
		}
	}
	t.Fatalf(
		"portal %q did not reach %s/%s; campaign=%#v",
		portalID,
		targetStageID,
		targetSpawnID,
		runtime.CampaignState(),
	)
}

func dialogueChoiceIDs(state DialogueState) []string {
	result := make([]string, len(state.Choices))
	for index, choice := range state.Choices {
		result[index] = choice.ID
	}
	return result
}
