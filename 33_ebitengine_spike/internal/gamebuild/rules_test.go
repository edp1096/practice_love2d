package gamebuild

import (
	"errors"
	"reflect"
	"slices"
	"strings"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/content"
)

func TestBuildContentRulesCompilesCompleteCampaign(t *testing.T) {
	t.Parallel()

	rules, err := BuildContentRules(loadCatalog(t))
	if err != nil {
		t.Fatal(err)
	}
	capabilities := rules.Capabilities
	for _, action := range []RuleActionType{
		RuleActionStartQuest,
		RuleActionGiveItem,
		RuleActionEquipItem,
		RuleActionAddCurrency,
		RuleActionSetFlag,
		RuleActionFinishGame,
		RuleActionOpenShop,
		RuleActionStartDialogue,
		RuleActionHeal,
	} {
		if !capabilities.SupportsAction(action) {
			t.Fatalf("action capability %q is missing", action)
		}
	}
	if !capabilities.SupportsCondition(RuleConditionQuestState) {
		t.Fatal("quest_state condition capability is missing")
	}

	dialogue := requireDialogueRule(t, rules, "dialogue.village_guide")
	if dialogue.Name != "" ||
		dialogue.NameKey != "dialogue.village_guide.name" ||
		dialogue.StartNode != "greeting" {
		t.Fatalf("dialogue header = %#v", dialogue)
	}
	if got, want := ruleNodeIDs(dialogue.Nodes), []string{
		"accepted",
		"greeting",
		"reminder",
		"thanks",
	}; !slices.Equal(got, want) {
		t.Fatalf("node order = %q, want deterministic %q", got, want)
	}
	greeting := requireDialogueNodeRule(t, dialogue, "greeting")
	if greeting.Speaker != "" ||
		greeting.SpeakerKey != "npc.village_guide.name" ||
		greeting.Text != "" ||
		greeting.TextKey != "dialogue.village_guide.greeting" {
		t.Fatalf("greeting localization fields = %#v", greeting)
	}
	if got, want := ruleChoiceIDs(greeting.Choices), []string{
		"accept",
		"progress",
		"completed",
		"leave",
	}; !slices.Equal(got, want) {
		t.Fatalf("choice order = %q, want authored %q", got, want)
	}
	accept := greeting.Choices[0]
	if accept.Next != "accepted" ||
		accept.TextKey != "dialogue.village_guide.accept" ||
		accept.Condition == nil ||
		accept.Condition.Type != RuleConditionQuestState ||
		accept.Condition.QuestID != "quest.grove_guardian" ||
		accept.Condition.QuestState != RuleQuestInactive {
		t.Fatalf("accept choice = %#v", accept)
	}
	if got, want := ruleActionTypes(accept.Actions), []RuleActionType{
		RuleActionStartQuest,
		RuleActionGiveItem,
		RuleActionEquipItem,
		RuleActionAddCurrency,
	}; !slices.Equal(got, want) {
		t.Fatalf("accept action order = %q, want authored %q", got, want)
	}
	if accept.Actions[0].QuestID != "quest.grove_guardian" ||
		accept.Actions[1].ItemID != "item.training_sword" ||
		accept.Actions[1].Quantity != 1 ||
		accept.Actions[2].ItemID != "item.training_sword" ||
		accept.Actions[3].Currency != 25 ||
		accept.Actions[3].Reason != "campaign.starting_supplies" {
		t.Fatalf("accept actions = %#v", accept.Actions)
	}
	thanks := requireDialogueNodeRule(t, dialogue, "thanks")
	if got, want := ruleActionTypes(thanks.Actions), []RuleActionType{
		RuleActionFinishGame,
	}; !slices.Equal(got, want) {
		t.Fatalf("thanks actions = %q, want %q", got, want)
	}

	quest := requireQuestRule(t, rules, "quest.grove_guardian")
	if quest.Name != "" ||
		quest.NameKey != "quest.grove_guardian.name" ||
		quest.Description != "" ||
		quest.DescriptionKey != "quest.grove_guardian.description" ||
		quest.InitiallyActive {
		t.Fatalf("quest header = %#v", quest)
	}
	if got, want := ruleObjectiveIDs(quest.Objectives), []string{
		"defeat_slimes",
		"defeat_guardian",
	}; !slices.Equal(got, want) {
		t.Fatalf("objective order = %q, want authored %q", got, want)
	}
	if quest.Objectives[0].Event != "actor.killed" ||
		quest.Objectives[0].ActorID != "actor.slime" ||
		quest.Objectives[0].Count != 2 ||
		quest.Objectives[1].ActorID != "actor.grove_guardian" ||
		quest.Objectives[1].Count != 1 {
		t.Fatalf("quest objectives = %#v", quest.Objectives)
	}
	if got, want := ruleActionTypes(quest.OnComplete), []RuleActionType{
		RuleActionGiveItem,
		RuleActionAddCurrency,
		RuleActionSetFlag,
	}; !slices.Equal(got, want) {
		t.Fatalf("reward action order = %q, want authored %q", got, want)
	}
	if quest.OnComplete[0].ItemID != "item.potion" ||
		quest.OnComplete[0].Quantity != 1 ||
		quest.OnComplete[1].Currency != 75 ||
		quest.OnComplete[1].Reason != "quest.grove_guardian" ||
		quest.OnComplete[2].FlagName != "quest.grove_guardian.rewarded" ||
		!quest.OnComplete[2].FlagValue {
		t.Fatalf("quest rewards = %#v", quest.OnComplete)
	}

	potion := requireItemRule(t, rules, "item.potion")
	if potion.Name != "" ||
		potion.NameKey != "item.potion.name" ||
		potion.DescriptionKey != "item.potion.description" ||
		potion.StackLimit != 10 ||
		potion.Value != 25 ||
		!potion.Consumable ||
		potion.Equipment != nil ||
		len(potion.Effects) != 1 ||
		potion.Effects[0].Type != RuleActionHeal ||
		potion.Effects[0].HealAmount != 25 {
		t.Fatalf("potion = %#v", potion)
	}
	sword := requireItemRule(t, rules, "item.training_sword")
	if sword.StackLimit != 1 ||
		sword.Value != 60 ||
		sword.Consumable ||
		sword.Equipment == nil ||
		sword.Equipment.Slot != "weapon" ||
		sword.Equipment.AttackModifier != 5 ||
		len(sword.Effects) != 0 {
		t.Fatalf("training sword = %#v", sword)
	}

	shop := requireShopRule(t, rules, "shop.village")
	if shop.Name != "" ||
		shop.NameKey != "shop.village.name" ||
		len(shop.Offers) != 2 {
		t.Fatalf("shop = %#v", shop)
	}
	if got, want := []string{
		shop.Offers[0].ItemID,
		shop.Offers[1].ItemID,
	}, []string{
		"item.potion",
		"item.training_sword",
	}; !slices.Equal(got, want) {
		t.Fatalf("offer order = %q, want authored %q", got, want)
	}
	if !shop.Offers[0].CanBuy ||
		shop.Offers[0].BuyPrice != 25 ||
		!shop.Offers[0].CanSell ||
		shop.Offers[0].SellPrice != 10 ||
		shop.Offers[1].CanBuy ||
		!shop.Offers[1].CanSell ||
		shop.Offers[1].SellPrice != 30 {
		t.Fatalf("offers = %#v", shop.Offers)
	}

	guide := requireInteractionRule(t, rules, "actor.village_guide")
	if guide.Input != "interact" ||
		guide.PromptKey != "interaction.talk" ||
		guide.Range != 70 ||
		len(guide.Actions) != 1 ||
		guide.Actions[0].Type != RuleActionStartDialogue ||
		guide.Actions[0].DialogueID != "dialogue.village_guide" {
		t.Fatalf("guide interaction = %#v", guide)
	}
	merchant := requireInteractionRule(t, rules, "actor.merchant")
	if merchant.PromptKey != "interaction.shop" ||
		len(merchant.Actions) != 1 ||
		merchant.Actions[0].Type != RuleActionOpenShop ||
		merchant.Actions[0].ShopID != "shop.village" {
		t.Fatalf("merchant interaction = %#v", merchant)
	}
}

func TestBuildContentRulesIsDeterministicAndDeepDetached(t *testing.T) {
	t.Parallel()

	catalog := loadCatalog(t)
	first, err := BuildContentRules(catalog)
	if err != nil {
		t.Fatal(err)
	}
	second, err := BuildContentRules(catalog)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(first, second) {
		t.Fatalf("same catalog produced distinct rules\nfirst=%#v\nsecond=%#v",
			first, second)
	}

	first.Capabilities.Actions[0] = RuleActionType("mutated")
	firstDialogue := ruleDialoguePointer(t, &first, "dialogue.village_guide")
	firstGreeting := ruleNodePointer(t, firstDialogue, "greeting")
	firstGreeting.Choices[0].Condition.QuestID = "quest.mutated"
	firstGreeting.Choices[0].Actions[0].QuestID = "quest.mutated"
	firstQuest := ruleQuestPointer(t, &first, "quest.grove_guardian")
	firstQuest.Objectives[0].ActorID = "actor.mutated"
	firstItem := ruleItemPointer(t, &first, "item.training_sword")
	firstItem.Equipment.AttackModifier = 999
	firstShop := ruleShopPointer(t, &first, "shop.village")
	firstShop.Offers[0].BuyPrice = 999
	firstInteraction := ruleInteractionPointer(
		t,
		&first,
		"actor.village_guide",
	)
	firstInteraction.Actions[0].DialogueID = "dialogue.mutated"

	again, err := BuildContentRules(catalog)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(second, again) {
		t.Fatal("mutating one compiled result changed the catalog or a later result")
	}

	cloned := second.Clone()
	ruleShopPointer(t, &cloned, "shop.village").Offers[0].BuyPrice = 777
	if reflect.DeepEqual(cloned, second) {
		t.Fatal("Clone mutation did not affect the clone")
	}
	if requireShopRule(t, second, "shop.village").Offers[0].BuyPrice != 25 {
		t.Fatal("Clone shared nested offer storage with its source")
	}

	lookup, ok := second.Dialogue("dialogue.village_guide")
	if !ok {
		t.Fatal("dialogue lookup failed")
	}
	requireDialogueNodeRule(t, lookup, "greeting").
		Choices[0].Condition.QuestID = "quest.lookup_mutation"
	lookupAgain, _ := second.Dialogue("dialogue.village_guide")
	if requireDialogueNodeRule(t, lookupAgain, "greeting").
		Choices[0].Condition.QuestID != "quest.grove_guardian" {
		t.Fatal("Dialogue lookup exposed rules-owned nested storage")
	}
}

func TestBuildContentRulesRejectsUnsupportedCapabilities(t *testing.T) {
	t.Parallel()

	for _, test := range []struct {
		name       string
		id         string
		mutate     func(map[string]any)
		capability string
		value      string
	}{
		{
			name: "action",
			id:   "dialogue.village_guide",
			mutate: func(data map[string]any) {
				choice := ruleGreetingChoice(data, 0)
				choice["actions"] = []any{
					map[string]any{"type": "close_dialogue"},
				}
			},
			capability: "action",
			value:      "close_dialogue",
		},
		{
			name: "condition",
			id:   "dialogue.village_guide",
			mutate: func(data map[string]any) {
				ruleGreetingChoice(data, 0)["condition"] = map[string]any{
					"type": "always",
				}
			},
			capability: "condition",
			value:      "always",
		},
		{
			name: "objective event",
			id:   "quest.grove_guardian",
			mutate: func(data map[string]any) {
				objectives := data["objectives"].([]any)
				objectives[0].(map[string]any)["event"] = "enemy.defeated"
			},
			capability: "quest objective event",
			value:      "enemy.defeated",
		},
		{
			name: "equipment modifier",
			id:   "item.training_sword",
			mutate: func(data map[string]any) {
				equipment := data["equipment"].(map[string]any)
				modifiers := equipment["modifiers"].(map[string]any)
				modifiers["defense"] = float64(2)
			},
			capability: "equipment modifier",
			value:      "defense",
		},
	} {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			catalog := loadCatalog(t)
			mutateRuleDefinition(t, catalog, test.id, test.mutate)
			_, err := BuildContentRules(catalog)
			var capabilityError *UnsupportedRuleCapabilityError
			if !errors.As(err, &capabilityError) {
				t.Fatalf(
					"BuildContentRules() error = %v, want capability error",
					err,
				)
			}
			if capabilityError.Capability != test.capability ||
				capabilityError.Name != test.value ||
				capabilityError.Path == "" {
				t.Fatalf("capability error = %#v", capabilityError)
			}
		})
	}
}

func TestBuildContentRulesStrictValidation(t *testing.T) {
	t.Parallel()

	for _, test := range []struct {
		name     string
		id       string
		mutate   func(map[string]any)
		contains string
	}{
		{
			name: "missing dialogue start",
			id:   "dialogue.village_guide",
			mutate: func(data map[string]any) {
				data["start"] = "missing"
			},
			contains: "start references missing node",
		},
		{
			name: "missing dialogue next",
			id:   "dialogue.village_guide",
			mutate: func(data map[string]any) {
				ruleGreetingChoice(data, 0)["next"] = "missing"
			},
			contains: "next references missing node",
		},
		{
			name: "missing dialogue reference",
			id:   "actor.village_guide",
			mutate: func(data map[string]any) {
				components := data["components"].(map[string]any)
				interaction := components["rpg.interactable"].(map[string]any)
				actions := interaction["actions"].([]any)
				actions[0].(map[string]any)["dialogue"] = "dialogue.missing"
			},
			contains: "references missing definition",
		},
		{
			name: "duplicate choice",
			id:   "dialogue.village_guide",
			mutate: func(data map[string]any) {
				nodes := data["nodes"].(map[string]any)
				greeting := nodes["greeting"].(map[string]any)
				choices := greeting["choices"].([]any)
				greeting["choices"] = append(choices, choices[0])
			},
			contains: "duplicates choice",
		},
		{
			name: "duplicate objective",
			id:   "quest.grove_guardian",
			mutate: func(data map[string]any) {
				objectives := data["objectives"].([]any)
				data["objectives"] = append(objectives, objectives[0])
			},
			contains: "duplicates objective",
		},
		{
			name: "duplicate shop offer",
			id:   "shop.village",
			mutate: func(data map[string]any) {
				offers := data["offers"].([]any)
				data["offers"] = append(offers, offers[0])
			},
			contains: "duplicates offer",
		},
		{
			name: "fractional objective count",
			id:   "quest.grove_guardian",
			mutate: func(data map[string]any) {
				objectives := data["objectives"].([]any)
				objectives[0].(map[string]any)["count"] = 1.5
			},
			contains: "positive integer",
		},
		{
			name: "negative shop price",
			id:   "shop.village",
			mutate: func(data map[string]any) {
				offers := data["offers"].([]any)
				offers[0].(map[string]any)["buy_price"] = float64(-1)
			},
			contains: "must not be negative",
		},
		{
			name: "integer overflow",
			id:   "item.potion",
			mutate: func(data map[string]any) {
				data["stack_limit"] = 1e100
			},
			contains: "JSON-safe integer range",
		},
		{
			name: "shop price outside JSON-safe range",
			id:   "shop.village",
			mutate: func(data map[string]any) {
				offers := data["offers"].([]any)
				offers[0].(map[string]any)["buy_price"] =
					float64(9_007_199_254_740_992)
			},
			contains: "JSON-safe integer range",
		},
		{
			name: "unknown item field",
			id:   "item.potion",
			mutate: func(data map[string]any) {
				data["silently_ignored"] = true
			},
			contains: "silently_ignored is not a supported field",
		},
	} {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			catalog := loadCatalog(t)
			mutateRuleDefinition(t, catalog, test.id, test.mutate)
			_, err := BuildContentRules(catalog)
			if err == nil || !strings.Contains(err.Error(), test.contains) {
				t.Fatalf(
					"BuildContentRules() error = %v, want %q",
					err,
					test.contains,
				)
			}
		})
	}
}

func mutateRuleDefinition(
	t *testing.T,
	catalog *content.Catalog,
	id string,
	mutate func(map[string]any),
) {
	t.Helper()
	for index := range catalog.Definitions {
		if catalog.Definitions[index].ID() != id {
			continue
		}
		mutate(catalog.Definitions[index].Data)
		return
	}
	t.Fatalf("definition %q not found", id)
}

func ruleGreetingChoice(data map[string]any, index int) map[string]any {
	nodes := data["nodes"].(map[string]any)
	greeting := nodes["greeting"].(map[string]any)
	choices := greeting["choices"].([]any)
	return choices[index].(map[string]any)
}

func requireDialogueRule(
	t *testing.T,
	rules ContentRules,
	id string,
) DialogueRule {
	t.Helper()
	value, exists := rules.Dialogue(id)
	if !exists {
		t.Fatalf("dialogue %q not found", id)
	}
	return value
}

func requireQuestRule(t *testing.T, rules ContentRules, id string) QuestRule {
	t.Helper()
	value, exists := rules.Quest(id)
	if !exists {
		t.Fatalf("quest %q not found", id)
	}
	return value
}

func requireItemRule(t *testing.T, rules ContentRules, id string) ItemRule {
	t.Helper()
	value, exists := rules.Item(id)
	if !exists {
		t.Fatalf("item %q not found", id)
	}
	return value
}

func requireShopRule(t *testing.T, rules ContentRules, id string) ShopRule {
	t.Helper()
	value, exists := rules.Shop(id)
	if !exists {
		t.Fatalf("shop %q not found", id)
	}
	return value
}

func requireInteractionRule(
	t *testing.T,
	rules ContentRules,
	actorID string,
) ActorInteractionRule {
	t.Helper()
	value, exists := rules.Interaction(actorID)
	if !exists {
		t.Fatalf("interaction %q not found", actorID)
	}
	return value
}

func requireDialogueNodeRule(
	t *testing.T,
	dialogue DialogueRule,
	id string,
) DialogueNodeRule {
	t.Helper()
	for _, node := range dialogue.Nodes {
		if node.ID == id {
			return node
		}
	}
	t.Fatalf("dialogue node %q not found", id)
	return DialogueNodeRule{}
}

func ruleNodeIDs(values []DialogueNodeRule) []string {
	result := make([]string, len(values))
	for index, value := range values {
		result[index] = value.ID
	}
	return result
}

func ruleChoiceIDs(values []DialogueChoiceRule) []string {
	result := make([]string, len(values))
	for index, value := range values {
		result[index] = value.ID
	}
	return result
}

func ruleObjectiveIDs(values []QuestObjectiveRule) []string {
	result := make([]string, len(values))
	for index, value := range values {
		result[index] = value.ID
	}
	return result
}

func ruleActionTypes(values []RuleAction) []RuleActionType {
	result := make([]RuleActionType, len(values))
	for index, value := range values {
		result[index] = value.Type
	}
	return result
}

func ruleDialoguePointer(
	t *testing.T,
	rules *ContentRules,
	id string,
) *DialogueRule {
	t.Helper()
	for index := range rules.Dialogues {
		if rules.Dialogues[index].ID == id {
			return &rules.Dialogues[index]
		}
	}
	t.Fatalf("dialogue %q not found", id)
	return nil
}

func ruleNodePointer(
	t *testing.T,
	dialogue *DialogueRule,
	id string,
) *DialogueNodeRule {
	t.Helper()
	for index := range dialogue.Nodes {
		if dialogue.Nodes[index].ID == id {
			return &dialogue.Nodes[index]
		}
	}
	t.Fatalf("dialogue node %q not found", id)
	return nil
}

func ruleQuestPointer(t *testing.T, rules *ContentRules, id string) *QuestRule {
	t.Helper()
	for index := range rules.Quests {
		if rules.Quests[index].ID == id {
			return &rules.Quests[index]
		}
	}
	t.Fatalf("quest %q not found", id)
	return nil
}

func ruleItemPointer(t *testing.T, rules *ContentRules, id string) *ItemRule {
	t.Helper()
	for index := range rules.Items {
		if rules.Items[index].ID == id {
			return &rules.Items[index]
		}
	}
	t.Fatalf("item %q not found", id)
	return nil
}

func ruleShopPointer(t *testing.T, rules *ContentRules, id string) *ShopRule {
	t.Helper()
	for index := range rules.Shops {
		if rules.Shops[index].ID == id {
			return &rules.Shops[index]
		}
	}
	t.Fatalf("shop %q not found", id)
	return nil
}

func ruleInteractionPointer(
	t *testing.T,
	rules *ContentRules,
	actorID string,
) *ActorInteractionRule {
	t.Helper()
	for index := range rules.Interactions {
		if rules.Interactions[index].ActorID == actorID {
			return &rules.Interactions[index]
		}
	}
	t.Fatalf("interaction %q not found", actorID)
	return nil
}
