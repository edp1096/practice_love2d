package rulesruntime

import (
	"reflect"
	"strings"
	"sync"
	"testing"

	gamecatalog "practice_love2d/33_ebitengine_spike/game"
	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

func TestCompleteCampaignRulesAndNumbers(t *testing.T) {
	t.Parallel()

	executor, live, rules := newCompleteRuntime(t)
	inactive := gamebuild.RuleCondition{
		Type:       gamebuild.RuleConditionQuestState,
		QuestID:    "quest.grove_guardian",
		QuestState: gamebuild.RuleQuestInactive,
	}
	ok, err := executor.EvaluateCondition(live, &inactive)
	if err != nil || !ok {
		t.Fatalf("inactive condition = %v, %v", ok, err)
	}

	accept := dialogueChoice(
		t,
		rules,
		"dialogue.village_guide",
		"greeting",
		"accept",
	)
	result, err := executor.Execute(live, accept.Actions)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := result.Intents, []Intent{{
		Type:        IntentShowNotice,
		NoticeKey:   "notice.quest.accepted",
		NoticeTone:  "success",
		NoticeTicks: 240,
	}}; !reflect.DeepEqual(got, want) {
		t.Fatalf("accept intents = %#v, want %#v", got, want)
	}
	state := live.Snapshot()
	assertQuestStatus(t, state, "quest.grove_guardian", campaign.QuestActive)
	assertInventory(t, state, "item.training_sword", 1)
	assertEquipment(t, state, "weapon", "item.training_sword")
	if state.Currency != 25 {
		t.Fatalf("starting currency = %d, want 25", state.Currency)
	}

	active := inactive
	active.QuestState = gamebuild.RuleQuestActive
	ok, err = executor.EvaluateCondition(live, &active)
	if err != nil || !ok {
		t.Fatalf("active condition = %v, %v", ok, err)
	}

	if err := executor.Buy(
		live,
		"shop.village",
		"item.potion",
		1,
	); err != nil {
		t.Fatal(err)
	}
	state = live.Snapshot()
	assertInventory(t, state, "item.potion", 1)
	if state.Currency != 0 {
		t.Fatalf("currency after potion purchase = %d, want 0", state.Currency)
	}

	first, err := executor.ApplyObjectiveEvent(live, ObjectiveEvent{
		Event:   "actor.killed",
		ActorID: "actor.slime",
		Count:   1,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(first.Progress) != 1 ||
		first.Progress[0].Previous != 0 ||
		first.Progress[0].Current != 1 ||
		first.Progress[0].Required != 2 ||
		len(first.CompletedQuestIDs) != 0 {
		t.Fatalf("first slime result = %#v", first)
	}
	second, err := executor.ApplyObjectiveEvent(live, ObjectiveEvent{
		Event:   "actor.killed",
		ActorID: "actor.slime",
		Count:   1,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(second.Progress) != 1 ||
		second.Progress[0].Current != 2 ||
		len(second.CompletedQuestIDs) != 0 {
		t.Fatalf("second slime result = %#v", second)
	}

	completedEvent, err := executor.ApplyObjectiveEvent(
		live,
		ObjectiveEvent{
			Event:   "actor.killed",
			ActorID: "actor.grove_guardian",
			Count:   1,
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := completedEvent.CompletedQuestIDs,
		[]string{"quest.grove_guardian"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("completed quests = %q, want %q", got, want)
	}
	if got, want := completedEvent.Intents, []Intent{{
		Type:        IntentShowNotice,
		NoticeKey:   "notice.quest.completed",
		NoticeTone:  "success",
		NoticeTicks: 240,
	}}; !reflect.DeepEqual(got, want) {
		t.Fatalf("completion intents = %#v, want %#v", got, want)
	}

	state = live.Snapshot()
	assertQuestStatus(
		t,
		state,
		"quest.grove_guardian",
		campaign.QuestCompleted,
	)
	assertInventory(t, state, "item.potion", 2)
	assertFlag(t, state, "quest.grove_guardian.rewarded", true)
	if state.Currency != 75 {
		t.Fatalf("completion currency = %d, want 75", state.Currency)
	}
	completed := inactive
	completed.QuestState = gamebuild.RuleQuestCompleted
	ok, err = executor.EvaluateCondition(live, &completed)
	if err != nil || !ok {
		t.Fatalf("completed condition = %v, %v", ok, err)
	}

	thanks := dialogueNode(
		t,
		rules,
		"dialogue.village_guide",
		"thanks",
	)
	if _, err := executor.Execute(live, thanks.Actions); err != nil {
		t.Fatal(err)
	}
	state = live.Snapshot()
	if !state.Flow.Completed || state.Mode != campaign.ModeEnding {
		t.Fatalf("ending flow = %#v, mode = %q", state.Flow, state.Mode)
	}
}

func TestCutsceneActionsStayTypedAndTransientAtTheHostBoundary(
	t *testing.T,
) {
	t.Parallel()
	executor, live, rules := newCompleteRuntime(t)
	cutscene, exists := rules.Cutscene("cutscene.village_arrival")
	if !exists || len(cutscene.Steps) != 2 {
		t.Fatalf("cutscene = %#v, exists=%v", cutscene, exists)
	}
	result, err := executor.Execute(live, []gamebuild.RuleAction{{
		Type:       gamebuild.RuleActionStartCutscene,
		CutsceneID: cutscene.ID,
	}})
	if err != nil {
		t.Fatal(err)
	}
	if got, want := result.Intents, []Intent{{
		Type:       IntentStartCutscene,
		CutsceneID: cutscene.ID,
	}}; !reflect.DeepEqual(got, want) {
		t.Fatalf("cutscene intents = %#v, want %#v", got, want)
	}
	active, err := executor.EvaluateCondition(
		live,
		&gamebuild.RuleCondition{
			Type:       gamebuild.RuleConditionCutsceneActive,
			CutsceneID: cutscene.ID,
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	if active {
		t.Fatal("durable executor claimed ownership of transient cutscene state")
	}
}

func TestWorldClockActionsAndOvernightConditionAreDurable(t *testing.T) {
	t.Parallel()
	executor, live, _ := newCompleteRuntime(t)

	if _, err := executor.Execute(live, []gamebuild.RuleAction{{
		Type:        gamebuild.RuleActionSetWorldTime,
		WorldDay:    5,
		WorldMinute: 23*60 + 30,
	}}); err != nil {
		t.Fatal(err)
	}
	night := gamebuild.RuleCondition{
		Type:         gamebuild.RuleConditionTimeBetween,
		StartMinute:  18 * 60,
		FinishMinute: 6 * 60,
	}
	matched, err := executor.EvaluateCondition(live, &night)
	if err != nil || !matched {
		t.Fatalf("23:30 overnight condition = %t, %v", matched, err)
	}

	if _, err := executor.Execute(live, []gamebuild.RuleAction{{
		Type:         gamebuild.RuleActionAdvanceWorldTime,
		WorldMinutes: 90,
	}}); err != nil {
		t.Fatal(err)
	}
	state := live.Snapshot()
	if state.World.Day != 6 || state.World.Minute != 60 {
		t.Fatalf("advanced world clock = %#v", state.World)
	}
	matched, err = executor.EvaluateCondition(live, &night)
	if err != nil || !matched {
		t.Fatalf("01:00 overnight condition = %t, %v", matched, err)
	}

	day := gamebuild.RuleCondition{
		Type:         gamebuild.RuleConditionTimeBetween,
		StartMinute:  6 * 60,
		FinishMinute: 18 * 60,
	}
	matched, err = executor.EvaluateCondition(live, &day)
	if err != nil {
		t.Fatal(err)
	}
	if matched {
		t.Fatal("01:00 matched daytime condition")
	}
}

func TestCompositeAndFlagConditionsUseOneCampaignSnapshot(t *testing.T) {
	t.Parallel()

	executor, live, _ := newCompleteRuntime(t)
	if len(executor.config.Flags) == 0 {
		t.Fatal("complete runtime has no configured flag")
	}
	flagName := executor.config.Flags[0]
	flagTrue := gamebuild.RuleCondition{
		Type:      gamebuild.RuleConditionFlag,
		FlagName:  flagName,
		FlagValue: true,
	}
	before := gamebuild.RuleCondition{
		Type: gamebuild.RuleConditionAll,
		Conditions: []gamebuild.RuleCondition{
			{Type: gamebuild.RuleConditionAlways},
			{
				Type:      gamebuild.RuleConditionNot,
				Condition: &flagTrue,
			},
		},
	}
	matched, err := executor.EvaluateCondition(live, &before)
	if err != nil || !matched {
		t.Fatalf("before condition = %v, %v", matched, err)
	}
	if _, err := executor.Execute(live, []gamebuild.RuleAction{{
		Type:      gamebuild.RuleActionSetFlag,
		FlagName:  flagName,
		FlagValue: true,
	}}); err != nil {
		t.Fatal(err)
	}
	after := gamebuild.RuleCondition{
		Type: gamebuild.RuleConditionAny,
		Conditions: []gamebuild.RuleCondition{
			{
				Type:       gamebuild.RuleConditionQuestState,
				QuestID:    "quest.grove_guardian",
				QuestState: gamebuild.RuleQuestCompleted,
			},
			flagTrue,
		},
	}
	matched, err = executor.EvaluateCondition(live, &after)
	if err != nil || !matched {
		t.Fatalf("after condition = %v, %v", matched, err)
	}
}

func TestExecutePreservesIntentOrderAndHidesIntentsOnRollback(t *testing.T) {
	t.Parallel()

	executor, live, _ := newCompleteRuntime(t)
	ordered := []gamebuild.RuleAction{
		{
			Type:       gamebuild.RuleActionStartDialogue,
			DialogueID: "dialogue.village_guide",
		},
		{
			Type:       gamebuild.RuleActionHeal,
			HealAmount: 25,
		},
		{
			Type:   gamebuild.RuleActionOpenShop,
			ShopID: "shop.village",
		},
		{
			Type:     gamebuild.RuleActionAddCurrency,
			Currency: 7,
		},
	}
	result, err := executor.Execute(live, ordered)
	if err != nil {
		t.Fatal(err)
	}
	want := []Intent{
		{
			Type:       IntentStartDialogue,
			DialogueID: "dialogue.village_guide",
		},
		{Type: IntentHeal, HealAmount: 25},
		{Type: IntentOpenShop, ShopID: "shop.village"},
	}
	if !reflect.DeepEqual(result.Intents, want) {
		t.Fatalf("intents = %#v, want %#v", result.Intents, want)
	}
	if live.Snapshot().Currency != 7 {
		t.Fatalf("currency = %d, want 7", live.Snapshot().Currency)
	}

	before := live.Snapshot()
	failed, err := executor.Execute(live, []gamebuild.RuleAction{
		{
			Type:       gamebuild.RuleActionStartDialogue,
			DialogueID: "dialogue.village_guide",
		},
		{
			Type:     gamebuild.RuleActionGiveItem,
			ItemID:   "item.potion",
			Quantity: 11,
		},
		{
			Type:   gamebuild.RuleActionOpenShop,
			ShopID: "shop.village",
		},
	})
	if err == nil || !strings.Contains(err.Error(), "stack limit") {
		t.Fatalf("Execute() error = %v, want stack limit", err)
	}
	if !reflect.DeepEqual(failed, ActionResult{}) {
		t.Fatalf("failed action leaked intents: %#v", failed)
	}
	if after := live.Snapshot(); !reflect.DeepEqual(after, before) {
		t.Fatalf("failed action mutated campaign\nbefore=%#v\nafter=%#v",
			before, after)
	}
}

func TestObjectiveCompletionIsExactlyOnceAndRewardFailureRollsBack(
	t *testing.T,
) {
	t.Parallel()

	t.Run("exactly once", func(t *testing.T) {
		executor, live, rules := newCompleteRuntime(t)
		startGroveQuest(t, executor, live, rules)
		progressSlimes(t, executor, live)
		if _, err := executor.ApplyObjectiveEvent(live, ObjectiveEvent{
			Event:   "actor.killed",
			ActorID: "actor.grove_guardian",
			Count:   1,
		}); err != nil {
			t.Fatal(err)
		}
		before := live.Snapshot()
		result, err := executor.ApplyObjectiveEvent(live, ObjectiveEvent{
			Event:   "actor.killed",
			ActorID: "actor.grove_guardian",
			Count:   1,
		})
		if err == nil || !strings.Contains(err.Error(), "duplicated") {
			t.Fatalf("duplicate event error = %v", err)
		}
		if !reflect.DeepEqual(result, EventResult{}) {
			t.Fatalf("duplicate event leaked result: %#v", result)
		}
		if after := live.Snapshot(); !reflect.DeepEqual(after, before) {
			t.Fatalf("duplicate completion changed state")
		}
		assertInventory(t, before, "item.potion", 1)
		if before.Currency != 100 {
			t.Fatalf("reward currency = %d, want 100", before.Currency)
		}
	})

	t.Run("reward overflow", func(t *testing.T) {
		executor, live, rules := newCompleteRuntime(t)
		startGroveQuest(t, executor, live, rules)
		progressSlimes(t, executor, live)
		if err := live.Transaction(func(state *campaign.State) error {
			state.Currency = campaign.MaxJSONInteger
			return nil
		}); err != nil {
			t.Fatal(err)
		}
		before := live.Snapshot()
		result, err := executor.ApplyObjectiveEvent(live, ObjectiveEvent{
			Event:   "actor.killed",
			ActorID: "actor.grove_guardian",
			Count:   1,
		})
		if err == nil || !strings.Contains(err.Error(), "maximum") {
			t.Fatalf("reward overflow error = %v", err)
		}
		if !reflect.DeepEqual(result, EventResult{}) {
			t.Fatalf("failed completion leaked result: %#v", result)
		}
		after := live.Snapshot()
		if !reflect.DeepEqual(after, before) {
			t.Fatalf("failed reward did not roll back\nbefore=%#v\nafter=%#v",
				before, after)
		}
		assertQuestStatus(
			t,
			after,
			"quest.grove_guardian",
			campaign.QuestActive,
		)
		assertObjective(t, after, "quest.grove_guardian", "defeat_guardian", 0)
		assertInventory(t, after, "item.potion", 0)
		assertFlag(t, after, "quest.grove_guardian.rewarded", false)
	})
}

func TestObjectiveEventSkipsCappedActiveQuestWhenSharedQuestRemains(
	t *testing.T,
) {
	t.Parallel()

	config, rules := completeDefinitions(t)
	config.Quests = append(config.Quests, campaign.QuestDefinition{
		ID:              "quest.zz_shared_slimes",
		InitiallyActive: true,
		Objectives: []campaign.ObjectiveDefinition{{
			ID:       "defeat_shared_slimes",
			Required: 3,
		}},
	})
	rules.Quests = append(rules.Quests, gamebuild.QuestRule{
		ID:              "quest.zz_shared_slimes",
		InitiallyActive: true,
		Objectives: []gamebuild.QuestObjectiveRule{{
			ID:      "defeat_shared_slimes",
			Event:   "actor.killed",
			ActorID: "actor.slime",
			Count:   3,
		}},
		OnStart:    []gamebuild.RuleAction{},
		OnComplete: []gamebuild.RuleAction{},
	})
	executor, err := New(config, rules)
	if err != nil {
		t.Fatal(err)
	}
	live, err := campaign.NewGame(config)
	if err != nil {
		t.Fatal(err)
	}
	startGroveQuest(t, executor, live, rules)

	event := ObjectiveEvent{
		Event:   "actor.killed",
		ActorID: "actor.slime",
		Count:   1,
	}
	for range 2 {
		if _, err := executor.ApplyObjectiveEvent(live, event); err != nil {
			t.Fatal(err)
		}
	}
	state := live.Snapshot()
	assertObjective(
		t,
		state,
		"quest.grove_guardian",
		"defeat_slimes",
		2,
	)
	assertObjective(
		t,
		state,
		"quest.zz_shared_slimes",
		"defeat_shared_slimes",
		2,
	)

	result, err := executor.ApplyObjectiveEvent(live, event)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Progress) != 1 ||
		result.Progress[0].QuestID != "quest.zz_shared_slimes" ||
		result.Progress[0].Previous != 2 ||
		result.Progress[0].Current != 3 ||
		!reflect.DeepEqual(
			result.CompletedQuestIDs,
			[]string{"quest.zz_shared_slimes"},
		) {
		t.Fatalf("shared third event = %#v", result)
	}
	state = live.Snapshot()
	assertObjective(
		t,
		state,
		"quest.grove_guardian",
		"defeat_slimes",
		2,
	)

	before := live.Snapshot()
	if _, err := executor.ApplyObjectiveEvent(live, event); err == nil ||
		!strings.Contains(err.Error(), "duplicated") {
		t.Fatalf("fully capped event error = %v", err)
	}
	if after := live.Snapshot(); !reflect.DeepEqual(after, before) {
		t.Fatal("fully capped shared event mutated campaign")
	}
}

func TestObjectiveEventsRejectOvercountUnknownAndInactive(t *testing.T) {
	t.Parallel()

	executor, live, rules := newCompleteRuntime(t)
	startGroveQuest(t, executor, live, rules)
	before := live.Snapshot()
	for _, event := range []ObjectiveEvent{
		{
			Event:   "actor.killed",
			ActorID: "actor.slime",
			Count:   3,
		},
		{
			Event:   "actor.killed",
			ActorID: "actor.unknown",
			Count:   1,
		},
		{
			Event:   "actor.killed",
			ActorID: "actor.slime",
			Count:   0,
		},
	} {
		if _, err := executor.ApplyObjectiveEvent(live, event); err == nil {
			t.Fatalf("ApplyObjectiveEvent(%#v) unexpectedly succeeded", event)
		}
		if after := live.Snapshot(); !reflect.DeepEqual(after, before) {
			t.Fatalf("invalid event %#v mutated campaign", event)
		}
	}

	otherExecutor, otherLive, _ := newCompleteRuntime(t)
	if _, err := otherExecutor.ApplyObjectiveEvent(
		otherLive,
		ObjectiveEvent{
			Event:   "actor.killed",
			ActorID: "actor.slime",
			Count:   1,
		},
	); err == nil || !strings.Contains(err.Error(), "no active objective") {
		t.Fatalf("inactive objective error = %v", err)
	}
}

func TestGenericQuestEventWithoutActorFilterProgresses(t *testing.T) {
	t.Parallel()

	config, rules := completeDefinitions(t)
	for questIndex := range rules.Quests {
		if rules.Quests[questIndex].ID != "quest.grove_guardian" {
			continue
		}
		rules.Quests[questIndex].Objectives[0].Event =
			"maker.quest.progress"
		rules.Quests[questIndex].Objectives[0].Where =
			map[string]any{}
		rules.Quests[questIndex].Objectives[0].ActorID = ""
	}
	executor, err := New(config, rules)
	if err != nil {
		t.Fatal(err)
	}
	live, err := campaign.NewGame(config)
	if err != nil {
		t.Fatal(err)
	}
	startGroveQuest(t, executor, live, rules)
	for count := 1; count <= 2; count++ {
		result, err := executor.ApplyObjectiveEvent(
			live,
			ObjectiveEvent{
				Event: "maker.quest.progress",
				Count: 1,
			},
		)
		if err != nil {
			t.Fatal(err)
		}
		if len(result.Progress) != 1 ||
			result.Progress[0].Current != int64(count) {
			t.Fatalf("generic event %d result = %#v", count, result)
		}
	}
}

func TestShopBuySellValidationAndAtomicity(t *testing.T) {
	t.Parallel()

	executor, live, rules := newCompleteRuntime(t)
	startGroveQuest(t, executor, live, rules)
	if err := executor.Buy(
		live,
		"shop.village",
		"item.potion",
		1,
	); err != nil {
		t.Fatal(err)
	}
	state := live.Snapshot()
	assertInventory(t, state, "item.potion", 1)
	if state.Currency != 0 {
		t.Fatalf("currency after buy = %d, want 0", state.Currency)
	}

	before := live.Snapshot()
	for _, operation := range []func() error{
		func() error {
			return executor.Buy(
				live,
				"shop.village",
				"item.potion",
				1,
			)
		},
		func() error {
			return executor.Buy(
				live,
				"shop.village",
				"item.training_sword",
				1,
			)
		},
		func() error {
			return executor.Sell(
				live,
				"shop.village",
				"item.training_sword",
				1,
			)
		},
	} {
		if err := operation(); err == nil {
			t.Fatal("invalid shop operation unexpectedly succeeded")
		}
		if after := live.Snapshot(); !reflect.DeepEqual(after, before) {
			t.Fatal("failed shop operation mutated campaign")
		}
	}

	if err := executor.Sell(
		live,
		"shop.village",
		"item.potion",
		1,
	); err != nil {
		t.Fatal(err)
	}
	state = live.Snapshot()
	assertInventory(t, state, "item.potion", 0)
	if state.Currency != 10 {
		t.Fatalf("currency after sale = %d, want 10", state.Currency)
	}
}

func TestOverflowAndInvalidReferencesFailWithoutMutation(t *testing.T) {
	t.Parallel()

	executor, live, _ := newCompleteRuntime(t)
	if err := live.Transaction(func(state *campaign.State) error {
		state.Currency = campaign.MaxJSONInteger
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	before := live.Snapshot()
	if result, err := executor.Execute(live, []gamebuild.RuleAction{{
		Type:     gamebuild.RuleActionAddCurrency,
		Currency: 1,
	}}); err == nil || !reflect.DeepEqual(result, ActionResult{}) {
		t.Fatalf("overflow result = %#v, error = %v", result, err)
	}
	if after := live.Snapshot(); !reflect.DeepEqual(after, before) {
		t.Fatal("currency overflow mutated campaign")
	}
	if result, err := executor.Execute(live, []gamebuild.RuleAction{{
		Type:     gamebuild.RuleActionGiveItem,
		ItemID:   "item.missing",
		Quantity: 1,
	}}); err == nil || !reflect.DeepEqual(result, ActionResult{}) {
		t.Fatalf("missing item result = %#v, error = %v", result, err)
	}
	if after := live.Snapshot(); !reflect.DeepEqual(after, before) {
		t.Fatal("invalid reference mutated campaign")
	}
}

func TestNewRejectsBrokenRuleReferencesAndOrdering(t *testing.T) {
	t.Parallel()

	config, rules := completeDefinitions(t)
	broken := rules.Clone()
	quest, ok := broken.Quest("quest.grove_guardian")
	if !ok {
		t.Fatal("grove quest missing")
	}
	for index := range broken.Quests {
		if broken.Quests[index].ID == quest.ID {
			broken.Quests[index].OnComplete[2].FlagName = "flag.missing"
		}
	}
	if _, err := New(config, broken); err == nil ||
		!strings.Contains(err.Error(), "unknown flag") {
		t.Fatalf("broken flag error = %v", err)
	}

	reordered := rules.Clone()
	reordered.Items[0], reordered.Items[1] =
		reordered.Items[1], reordered.Items[0]
	if _, err := New(config, reordered); err == nil ||
		!strings.Contains(err.Error(), "canonical ID order") {
		t.Fatalf("reordered rules error = %v", err)
	}
}

func TestConcurrentActionsSerializeWithoutDataRace(t *testing.T) {
	executor, live, _ := newCompleteRuntime(t)

	const workers = 32
	errs := make(chan error, workers)
	var wait sync.WaitGroup
	wait.Add(workers)
	for range workers {
		go func() {
			defer wait.Done()
			_, err := executor.Execute(live, []gamebuild.RuleAction{{
				Type:     gamebuild.RuleActionAddCurrency,
				Currency: 1,
			}})
			errs <- err
		}()
	}
	wait.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	if got := live.Snapshot().Currency; got != workers {
		t.Fatalf("currency = %d, want %d", got, workers)
	}
}

func newCompleteRuntime(
	t *testing.T,
) (*Executor, *campaign.Campaign, gamebuild.ContentRules) {
	t.Helper()
	config, rules := completeDefinitions(t)
	executor, err := New(config, rules)
	if err != nil {
		t.Fatal(err)
	}
	live, err := campaign.NewGame(config)
	if err != nil {
		t.Fatal(err)
	}
	return executor, live, rules
}

func completeDefinitions(
	t *testing.T,
) (campaign.Config, gamebuild.ContentRules) {
	t.Helper()
	catalog, err := content.LoadBytes(gamecatalog.Bytes())
	if err != nil {
		t.Fatal(err)
	}
	config, err := gamebuild.BuildCampaignConfig(catalog)
	if err != nil {
		t.Fatal(err)
	}
	rules, err := gamebuild.BuildContentRules(catalog)
	if err != nil {
		t.Fatal(err)
	}
	return config, rules
}

func startGroveQuest(
	t *testing.T,
	executor *Executor,
	live *campaign.Campaign,
	rules gamebuild.ContentRules,
) {
	t.Helper()
	choice := dialogueChoice(
		t,
		rules,
		"dialogue.village_guide",
		"greeting",
		"accept",
	)
	if _, err := executor.Execute(live, choice.Actions); err != nil {
		t.Fatal(err)
	}
}

func progressSlimes(
	t *testing.T,
	executor *Executor,
	live *campaign.Campaign,
) {
	t.Helper()
	for range 2 {
		if _, err := executor.ApplyObjectiveEvent(live, ObjectiveEvent{
			Event:   "actor.killed",
			ActorID: "actor.slime",
			Count:   1,
		}); err != nil {
			t.Fatal(err)
		}
	}
}

func dialogueChoice(
	t *testing.T,
	rules gamebuild.ContentRules,
	dialogueID string,
	nodeID string,
	choiceID string,
) gamebuild.DialogueChoiceRule {
	t.Helper()
	node := dialogueNode(t, rules, dialogueID, nodeID)
	for _, choice := range node.Choices {
		if choice.ID == choiceID {
			return choice
		}
	}
	t.Fatalf("choice %q not found", choiceID)
	return gamebuild.DialogueChoiceRule{}
}

func dialogueNode(
	t *testing.T,
	rules gamebuild.ContentRules,
	dialogueID string,
	nodeID string,
) gamebuild.DialogueNodeRule {
	t.Helper()
	dialogue, exists := rules.Dialogue(dialogueID)
	if !exists {
		t.Fatalf("dialogue %q not found", dialogueID)
	}
	for _, node := range dialogue.Nodes {
		if node.ID == nodeID {
			return node
		}
	}
	t.Fatalf("node %q not found", nodeID)
	return gamebuild.DialogueNodeRule{}
}

func assertQuestStatus(
	t *testing.T,
	state campaign.State,
	id string,
	want campaign.QuestStatus,
) {
	t.Helper()
	for _, quest := range state.Quests {
		if quest.ID == id {
			if quest.Status != want {
				t.Fatalf("quest %q status = %q, want %q", id, quest.Status, want)
			}
			return
		}
	}
	t.Fatalf("quest %q not found", id)
}

func assertObjective(
	t *testing.T,
	state campaign.State,
	questID string,
	objectiveID string,
	want int64,
) {
	t.Helper()
	for _, quest := range state.Quests {
		if quest.ID != questID {
			continue
		}
		for _, objective := range quest.Objectives {
			if objective.ID == objectiveID {
				if objective.Count != want {
					t.Fatalf(
						"objective %q count = %d, want %d",
						objectiveID,
						objective.Count,
						want,
					)
				}
				return
			}
		}
	}
	t.Fatalf("objective %q/%q not found", questID, objectiveID)
}

func assertInventory(
	t *testing.T,
	state campaign.State,
	id string,
	want int64,
) {
	t.Helper()
	for _, entry := range state.Inventory {
		if entry.ItemID == id {
			if entry.Quantity != want {
				t.Fatalf(
					"inventory %q = %d, want %d",
					id,
					entry.Quantity,
					want,
				)
			}
			return
		}
	}
	t.Fatalf("inventory item %q not found", id)
}

func assertEquipment(
	t *testing.T,
	state campaign.State,
	slot string,
	want string,
) {
	t.Helper()
	for _, entry := range state.Equipment {
		if entry.SlotID == slot {
			if entry.ItemID != want {
				t.Fatalf(
					"equipment %q = %q, want %q",
					slot,
					entry.ItemID,
					want,
				)
			}
			return
		}
	}
	t.Fatalf("equipment slot %q not found", slot)
}

func assertFlag(
	t *testing.T,
	state campaign.State,
	id string,
	want bool,
) {
	t.Helper()
	for _, flag := range state.Flags {
		if flag.ID == id {
			if flag.Value != want {
				t.Fatalf("flag %q = %v, want %v", id, flag.Value, want)
			}
			return
		}
	}
	t.Fatalf("flag %q not found", id)
}
