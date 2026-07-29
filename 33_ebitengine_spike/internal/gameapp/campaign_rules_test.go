package gameapp

import (
	"context"
	"reflect"
	"strings"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/protocol"
	"practice_love2d/33_ebitengine_spike/internal/rulesruntime"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

func TestVillageInteractionUsesAuthoredDialogueAndAtomicCampaignChoice(
	t *testing.T,
) {
	runtime := newCampaignRuntime(t)
	dialogue := openVillageGuideDialogue(t, runtime)
	if dialogue.ID != "dialogue.village_guide" ||
		dialogue.NodeID != "greeting" ||
		dialogue.NPCID != "guide" ||
		len(dialogue.Choices) != 2 ||
		dialogue.Choices[0].ID != "accept" ||
		dialogue.Choices[1].ID != "leave" {
		t.Fatalf("village guide dialogue = %#v", dialogue)
	}
	if runtime.simulation.Snapshot().Dialogue.Active {
		t.Fatal("authored interaction also opened the legacy sim dialogue")
	}

	result := callRuntime(
		t,
		runtime,
		protocol.MethodDialogueChoose,
		protocol.ChooseDialogueParams{ChoiceID: "accept"},
	).(DialogueState)
	if !result.Active || result.NodeID != "accepted" ||
		len(result.Choices) != 0 {
		t.Fatalf("accepted dialogue state = %#v", result)
	}
	state := runtime.CampaignState()
	if got := campaignQuest(t, state, "quest.grove_guardian").Status; got !=
		campaign.QuestActive {
		t.Fatalf("quest.grove_guardian status = %q", got)
	}
	if got := campaignItem(t, state, "item.training_sword").Quantity; got != 1 {
		t.Fatalf("training sword quantity = %d", got)
	}
	if got := campaignEquipment(t, state, "weapon").ItemID; got !=
		"item.training_sword" {
		t.Fatalf("weapon equipment = %q", got)
	}
	if state.Currency != 25 {
		t.Fatalf("campaign currency = %d, want 25", state.Currency)
	}

	result = callRuntime(
		t,
		runtime,
		protocol.MethodDialogueAdvance,
		protocol.EmptyParams{},
	).(DialogueState)
	if result.Active {
		t.Fatalf("terminal dialogue remained active: %#v", result)
	}
}

func TestDialogueOwnsPhysicalInputAndPresentationWhileModal(t *testing.T) {
	runtime := newCampaignRuntime(t)
	openVillageGuideDialogue(t, runtime)
	beforeWorld := runtime.simulation.Snapshot()

	view := runtime.View()
	if !view.Dialogue.Active ||
		len(view.Dialogue.Choices) != 2 ||
		view.Dialogue.SelectedIndex != 0 ||
		view.Dialogue.Choices[0].ID != "accept" {
		t.Fatalf("dialogue presentation = %#v", view.Dialogue)
	}
	if err := runtime.Tick(ebitapp.Actions{
		MoveX:  1,
		Attack: true,
	}); err != nil {
		t.Fatal(err)
	}
	if after := runtime.simulation.Snapshot(); !reflect.DeepEqual(
		after,
		beforeWorld,
	) {
		t.Fatalf("modal gameplay input advanced World: %#v", after)
	}
	if err := runtime.Tick(ebitapp.Actions{DialogueDown: true}); err != nil {
		t.Fatal(err)
	}
	view = runtime.View()
	if view.Dialogue.SelectedIndex != 1 ||
		view.Dialogue.Choices[1].ID != "leave" {
		t.Fatalf("dialogue navigation presentation = %#v", view.Dialogue)
	}
	if err := runtime.Tick(ebitapp.Actions{DialogueConfirm: true}); err != nil {
		t.Fatal(err)
	}
	if runtime.View().Dialogue.Active {
		t.Fatal("confirming selected leave choice did not close dialogue")
	}
	if got := campaignQuest(
		t,
		runtime.CampaignState(),
		"quest.grove_guardian",
	).Status; got != campaign.QuestInactive {
		t.Fatalf("leave choice changed quest status to %q", got)
	}
	if after := runtime.simulation.Snapshot(); !reflect.DeepEqual(
		after,
		beforeWorld,
	) {
		t.Fatalf("dialogue controls advanced World: %#v", after)
	}
}

func TestDialogueChoiceHostIntentFailureRollsBackCampaignAndCursor(
	t *testing.T,
) {
	runtime := newCampaignRuntime(t)
	rules := runtime.contentRules.Clone()
	injected := false
	for dialogueIndex := range rules.Dialogues {
		dialogue := &rules.Dialogues[dialogueIndex]
		if dialogue.ID != "dialogue.village_guide" {
			continue
		}
		for nodeIndex := range dialogue.Nodes {
			node := &dialogue.Nodes[nodeIndex]
			if node.ID != "greeting" {
				continue
			}
			for choiceIndex := range node.Choices {
				choice := &node.Choices[choiceIndex]
				if choice.ID != "accept" {
					continue
				}
				choice.Actions = append(
					choice.Actions,
					gamebuild.RuleAction{
						Type:   gamebuild.RuleActionOpenShop,
						ShopID: "shop.village",
					},
				)
				injected = true
			}
		}
	}
	if !injected {
		t.Fatal("test could not locate village guide accept choice")
	}
	executor, err := rulesruntime.New(runtime.campaignConfig, rules)
	if err != nil {
		t.Fatal(err)
	}
	runtime.contentRules = rules
	runtime.ruleExecutor = executor

	beforeDialogue := openVillageGuideDialogue(t, runtime)
	beforeCampaign := runtime.CampaignState()
	beforeRevision := runtime.revision
	_, err = runtime.ChooseDialogue("accept")
	if err == nil || !strings.Contains(err.Error(), "while a dialogue is active") {
		t.Fatalf("choice host-intent error = %v", err)
	}
	afterDialogue, stateErr := runtime.DialogueState()
	if stateErr != nil {
		t.Fatal(stateErr)
	}
	if !reflect.DeepEqual(afterDialogue, beforeDialogue) {
		t.Fatalf(
			"failed choice moved dialogue cursor:\nbefore=%#v\nafter=%#v",
			beforeDialogue,
			afterDialogue,
		)
	}
	if afterCampaign := runtime.CampaignState(); !reflect.DeepEqual(
		afterCampaign,
		beforeCampaign,
	) {
		t.Fatalf(
			"failed choice leaked durable mutation:\nbefore=%#v\nafter=%#v",
			beforeCampaign,
			afterCampaign,
		)
	}
	if runtime.activeShopID != "" || runtime.revision != beforeRevision {
		t.Fatalf(
			"failed choice leaked presentation: shop=%q revision=%d want %d",
			runtime.activeShopID,
			runtime.revision,
			beforeRevision,
		)
	}
}

func TestDialogueAdvanceHostIntentFailureRollsBackCampaignAndCursor(
	t *testing.T,
) {
	runtime := newCampaignRuntime(t)
	rules := runtime.contentRules.Clone()
	injectedNext := false
	injectedActions := false
	for dialogueIndex := range rules.Dialogues {
		dialogue := &rules.Dialogues[dialogueIndex]
		if dialogue.ID != "dialogue.village_guide" {
			continue
		}
		for nodeIndex := range dialogue.Nodes {
			node := &dialogue.Nodes[nodeIndex]
			switch node.ID {
			case "accepted":
				node.Next = "reminder"
				injectedNext = true
			case "reminder":
				node.Actions = append(
					node.Actions,
					gamebuild.RuleAction{
						Type:     gamebuild.RuleActionAddCurrency,
						Currency: 7,
					},
					gamebuild.RuleAction{
						Type:   gamebuild.RuleActionOpenShop,
						ShopID: "shop.village",
					},
				)
				injectedActions = true
			}
		}
	}
	if !injectedNext || !injectedActions {
		t.Fatal("test could not inject village guide advance actions")
	}
	executor, err := rulesruntime.New(runtime.campaignConfig, rules)
	if err != nil {
		t.Fatal(err)
	}
	runtime.contentRules = rules
	runtime.ruleExecutor = executor

	openVillageGuideDialogue(t, runtime)
	if _, err := runtime.ChooseDialogue("accept"); err != nil {
		t.Fatal(err)
	}
	beforeDialogue, err := runtime.DialogueState()
	if err != nil {
		t.Fatal(err)
	}
	beforeCampaign := runtime.CampaignState()
	beforeRevision := runtime.revision

	_, err = runtime.AdvanceDialogue()
	if err == nil || !strings.Contains(err.Error(), "while a dialogue is active") {
		t.Fatalf("advance host-intent error = %v", err)
	}
	afterDialogue, stateErr := runtime.DialogueState()
	if stateErr != nil {
		t.Fatal(stateErr)
	}
	if !reflect.DeepEqual(afterDialogue, beforeDialogue) {
		t.Fatalf(
			"failed advance moved dialogue cursor:\nbefore=%#v\nafter=%#v",
			beforeDialogue,
			afterDialogue,
		)
	}
	if afterCampaign := runtime.CampaignState(); !reflect.DeepEqual(
		afterCampaign,
		beforeCampaign,
	) {
		t.Fatalf(
			"failed advance leaked durable mutation:\nbefore=%#v\nafter=%#v",
			beforeCampaign,
			afterCampaign,
		)
	}
	if runtime.activeShopID != "" || runtime.revision != beforeRevision {
		t.Fatalf(
			"failed advance leaked presentation: shop=%q revision=%d want %d",
			runtime.activeShopID,
			runtime.revision,
			beforeRevision,
		)
	}
}

func TestCancelledStepRollsBackAuthoredDialogueStart(t *testing.T) {
	runtime := newCampaignRuntime(t)
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
	beforeWorld := runtime.simulation.Snapshot()
	beforeCampaign := runtime.CampaignState()
	beforeVirtual := cloneVirtualActions(runtime.virtual)
	beforeRevision := runtime.revision

	ctx := &cancelAfterContext{Context: context.Background(), checks: 1}
	if _, err := runtime.step(ctx, 2); err == nil {
		t.Fatal("partially cancelled dialogue step unexpectedly succeeded")
	}
	dialogue, err := runtime.DialogueState()
	if err != nil {
		t.Fatal(err)
	}
	if dialogue.Active ||
		!reflect.DeepEqual(runtime.simulation.Snapshot(), beforeWorld) ||
		!reflect.DeepEqual(runtime.CampaignState(), beforeCampaign) ||
		!reflect.DeepEqual(runtime.virtual, beforeVirtual) ||
		runtime.revision != beforeRevision {
		t.Fatalf(
			"cancelled dialogue start leaked state: dialogue=%#v campaign=%#v",
			dialogue,
			runtime.CampaignState(),
		)
	}
}

func TestSimulationKillsAdvanceActorObjectivesExactlyOnce(t *testing.T) {
	runtime := newCampaignRuntime(t)
	openVillageGuideDialogue(t, runtime)
	callRuntime(
		t,
		runtime,
		protocol.MethodDialogueChoose,
		protocol.ChooseDialogueParams{ChoiceID: "accept"},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodDialogueAdvance,
		protocol.EmptyParams{},
	)

	moveEntityToPortal(t, runtime, "player", "to_field")
	stepProtocol(t, runtime, 1)
	assertLocation(t, runtime, "stage.world_hub", "village_entry")

	killWithPlayerAttack(t, runtime, "enemy.slime.1", 400, 220)
	assertObjectiveCount(
		t,
		runtime.CampaignState(),
		"quest.grove_guardian",
		"defeat_slimes",
		1,
	)
	killWithPlayerAttack(t, runtime, "enemy.slime.2", 620, 300)
	assertObjectiveCount(
		t,
		runtime.CampaignState(),
		"quest.grove_guardian",
		"defeat_slimes",
		2,
	)

	moveEntityToPortal(t, runtime, "player", "to_grove")
	stepProtocol(t, runtime, 1)
	assertLocation(t, runtime, "stage.world_grove", "west_entry")
	killWithPlayerAttack(t, runtime, "boss.grove_guardian", 500, 288)

	completed := runtime.CampaignState()
	if campaignQuest(t, completed, "quest.grove_guardian").Status !=
		campaign.QuestCompleted {
		t.Fatalf("guardian quest did not complete: %#v", completed.Quests)
	}
	if completed.Currency != 100 ||
		campaignItem(t, completed, "item.potion").Quantity != 1 ||
		!campaignFlag(t, completed, "quest.grove_guardian.rewarded") {
		t.Fatalf("quest completion rewards = %#v", completed)
	}

	runtime.mu.Lock()
	err := runtime.applyObjectiveEventsLocked([]sim.Event{
		{
			Type:     sim.EventActorKilled,
			TargetID: "boss.grove_guardian",
		},
	})
	runtime.mu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	if after := runtime.CampaignState(); !reflect.DeepEqual(after, completed) {
		t.Fatalf("completed objective was rewarded twice: %#v", after)
	}
}

func TestLoadReloadAndPortalClearDialogueButKeepCampaign(t *testing.T) {
	runtime := newCampaignRuntime(t)
	openVillageGuideDialogue(t, runtime)
	callRuntime(
		t,
		runtime,
		protocol.MethodDialogueChoose,
		protocol.ChooseDialogueParams{ChoiceID: "accept"},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodAppSave,
		protocol.SaveSlotParams{Slot: "dialogue-transient"},
	)
	if dialogue, err := runtime.DialogueState(); err != nil ||
		!dialogue.Active {
		t.Fatalf("save changed transient dialogue: %#v error=%v", dialogue, err)
	}

	callRuntime(
		t,
		runtime,
		protocol.MethodAppLoad,
		protocol.SaveSlotParams{Slot: "dialogue-transient"},
	)
	assertDialogueClearedAndQuestDurable(t, runtime)

	openVillageGuideDialogue(t, runtime)
	callRuntime(
		t,
		runtime,
		protocol.MethodAppReloadContent,
		protocol.EmptyParams{},
	)
	assertDialogueClearedAndQuestDurable(t, runtime)

	openVillageGuideDialogue(t, runtime)
	runtime.mu.Lock()
	portal := findPortal(t, runtime, "to_field")
	err := runtime.transitionPortalLocked(portal)
	if err == nil {
		runtime.revision++
	}
	runtime.mu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	assertDialogueClearedAndQuestDurable(t, runtime)
	if runtime.CampaignState().CurrentStageID != "stage.world_hub" {
		t.Fatalf("portal campaign location = %#v", runtime.CampaignState())
	}
}

func openVillageGuideDialogue(
	t *testing.T,
	runtime *Runtime,
) DialogueState {
	t.Helper()
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
	result := callRuntime(
		t,
		runtime,
		protocol.MethodDialogueGetState,
		protocol.EmptyParams{},
	).(DialogueState)
	if !result.Active {
		t.Fatalf("village guide dialogue did not open: %#v", result)
	}
	return result
}

func killWithPlayerAttack(
	t *testing.T,
	runtime *Runtime,
	targetID string,
	targetX float64,
	targetY float64,
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
		protocol.SetHealthParams{EntityID: targetID, Value: 1},
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
	t.Fatalf("controlled attack did not kill %q", targetID)
}

func assertDialogueClearedAndQuestDurable(
	t *testing.T,
	runtime *Runtime,
) {
	t.Helper()
	dialogue, err := runtime.DialogueState()
	if err != nil {
		t.Fatal(err)
	}
	state := runtime.CampaignState()
	if dialogue.Active || runtime.simulation.Snapshot().Dialogue.Active ||
		campaignQuest(t, state, "quest.grove_guardian").Status !=
			campaign.QuestActive ||
		state.Currency != 25 {
		t.Fatalf(
			"transient/durable split: dialogue=%#v campaign=%#v",
			dialogue,
			state,
		)
	}
}

func campaignQuest(
	t *testing.T,
	state campaign.State,
	id string,
) campaign.QuestState {
	t.Helper()
	for _, quest := range state.Quests {
		if quest.ID == id {
			return quest
		}
	}
	t.Fatalf("campaign quest %q is missing", id)
	return campaign.QuestState{}
}

func campaignItem(
	t *testing.T,
	state campaign.State,
	id string,
) campaign.InventoryEntry {
	t.Helper()
	for _, item := range state.Inventory {
		if item.ItemID == id {
			return item
		}
	}
	t.Fatalf("campaign item %q is missing", id)
	return campaign.InventoryEntry{}
}

func campaignEquipment(
	t *testing.T,
	state campaign.State,
	id string,
) campaign.EquipmentEntry {
	t.Helper()
	for _, equipment := range state.Equipment {
		if equipment.SlotID == id {
			return equipment
		}
	}
	t.Fatalf("campaign equipment %q is missing", id)
	return campaign.EquipmentEntry{}
}

func campaignFlag(t *testing.T, state campaign.State, id string) bool {
	t.Helper()
	for _, flag := range state.Flags {
		if flag.ID == id {
			return flag.Value
		}
	}
	t.Fatalf("campaign flag %q is missing", id)
	return false
}

func assertObjectiveCount(
	t *testing.T,
	state campaign.State,
	questID string,
	objectiveID string,
	want int64,
) {
	t.Helper()
	quest := campaignQuest(t, state, questID)
	for _, objective := range quest.Objectives {
		if objective.ID == objectiveID {
			if objective.Count != want {
				t.Fatalf(
					"%s/%s count = %d, want %d",
					questID,
					objectiveID,
					objective.Count,
					want,
				)
			}
			return
		}
	}
	t.Fatalf("campaign objective %s/%s is missing", questID, objectiveID)
}
