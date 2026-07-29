package rulesruntime

import (
	"reflect"
	"strings"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

func TestUseItemCommitsEffectsAndConsumptionTogether(t *testing.T) {
	t.Parallel()

	executor, live, _ := newCompleteRuntime(t)
	giveItem(t, executor, live, "item.potion", 2)

	result, err := executor.UseItem(live, "item.potion")
	if err != nil {
		t.Fatal(err)
	}
	want := UseItemResult{
		ActionResult: ActionResult{Intents: []Intent{{
			Type:       IntentHeal,
			HealAmount: 25,
		}}},
		ItemID:            "item.potion",
		ConsumedQuantity:  1,
		RemainingQuantity: 1,
	}
	if !reflect.DeepEqual(result, want) {
		t.Fatalf("UseItem() = %#v, want %#v", result, want)
	}
	assertInventory(t, live.Snapshot(), "item.potion", 1)
}

func TestUseItemHealIntentRequiresHostCandidatePublication(t *testing.T) {
	t.Parallel()

	config, rules := completeDefinitions(t)
	executor, err := New(config, rules)
	if err != nil {
		t.Fatal(err)
	}
	live, err := campaign.NewGame(config)
	if err != nil {
		t.Fatal(err)
	}
	giveItem(t, executor, live, "item.potion", 1)

	// A host that also mutates Simulation must use this detached Campaign
	// candidate. If applying the heal intent to its Simulation candidate fails,
	// it discards both candidates and the published live Campaign stays intact.
	candidate, err := campaign.Restore(config, live.Snapshot())
	if err != nil {
		t.Fatal(err)
	}
	result, err := executor.UseItem(candidate, "item.potion")
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Intents) != 1 ||
		result.Intents[0].Type != IntentHeal ||
		result.Intents[0].HealAmount != 25 {
		t.Fatalf("UseItem() intents = %#v", result.Intents)
	}
	assertInventory(t, candidate.Snapshot(), "item.potion", 0)
	assertInventory(t, live.Snapshot(), "item.potion", 1)
}

func TestUseItemRejectsInvalidRequestsWithoutMutation(t *testing.T) {
	t.Parallel()

	executor, live, _ := newCompleteRuntime(t)

	t.Run("nil executor", func(t *testing.T) {
		var nilExecutor *Executor
		before := live.Snapshot()
		result, err := nilExecutor.UseItem(live, "item.potion")
		requireZeroUseResult(t, result, err)
		assertStateUnchanged(t, live, before)
	})

	t.Run("nil campaign", func(t *testing.T) {
		result, err := executor.UseItem(nil, "item.potion")
		requireZeroUseResult(t, result, err)
	})

	for _, test := range []struct {
		name   string
		itemID string
		match  string
	}{
		{
			name:   "unknown item",
			itemID: "item.missing",
			match:  "not configured",
		},
		{
			name:   "nonconsumable",
			itemID: "item.training_sword",
			match:  "not consumable",
		},
		{
			name:   "unowned",
			itemID: "item.potion",
			match:  "not owned",
		},
	} {
		test := test
		t.Run(test.name, func(t *testing.T) {
			before := live.Snapshot()
			result, err := executor.UseItem(live, test.itemID)
			if err == nil || !strings.Contains(err.Error(), test.match) {
				t.Fatalf("UseItem() error = %v, want %q", err, test.match)
			}
			if !reflect.DeepEqual(result, UseItemResult{}) {
				t.Fatalf("failed UseItem() result = %#v", result)
			}
			assertStateUnchanged(t, live, before)
		})
	}

	t.Run("foreign campaign", func(t *testing.T) {
		foreign := newForeignCampaign(t)
		before := foreign.Snapshot()
		result, err := executor.UseItem(foreign, "item.potion")
		if err == nil || !strings.Contains(err.Error(), "does not match") {
			t.Fatalf("UseItem() foreign error = %v", err)
		}
		if !reflect.DeepEqual(result, UseItemResult{}) {
			t.Fatalf("failed UseItem() result = %#v", result)
		}
		assertStateUnchanged(t, foreign, before)
	})
}

func TestUseItemEffectFailureRollsBackConsumptionAndIntents(t *testing.T) {
	t.Parallel()

	executor, live := runtimeWithPotionEffects(t, []gamebuild.RuleAction{
		{
			Type:       gamebuild.RuleActionHeal,
			HealAmount: 25,
		},
		{
			Type:     gamebuild.RuleActionGiveItem,
			ItemID:   "item.potion",
			Quantity: 10,
		},
	})
	giveItem(t, executor, live, "item.potion", 1)
	before := live.Snapshot()

	result, err := executor.UseItem(live, "item.potion")
	if err == nil || !strings.Contains(err.Error(), "stack limit") {
		t.Fatalf("UseItem() rollback error = %v", err)
	}
	if !reflect.DeepEqual(result, UseItemResult{}) {
		t.Fatalf("failed UseItem() leaked result: %#v", result)
	}
	assertStateUnchanged(t, live, before)
}

func TestUseItemOverflowRollsBackConsumption(t *testing.T) {
	t.Parallel()

	executor, live := runtimeWithPotionEffects(t, []gamebuild.RuleAction{{
		Type:     gamebuild.RuleActionAddCurrency,
		Currency: 1,
	}})
	giveItem(t, executor, live, "item.potion", 1)
	if err := live.Transaction(func(state *campaign.State) error {
		state.Currency = campaign.MaxJSONInteger
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	before := live.Snapshot()

	result, err := executor.UseItem(live, "item.potion")
	if err == nil || !strings.Contains(err.Error(), "maximum") {
		t.Fatalf("UseItem() overflow error = %v", err)
	}
	if !reflect.DeepEqual(result, UseItemResult{}) {
		t.Fatalf("failed UseItem() leaked result: %#v", result)
	}
	assertStateUnchanged(t, live, before)
}

func TestUseItemResultIsDefensive(t *testing.T) {
	t.Parallel()

	executor, firstLive, _ := newCompleteRuntime(t)
	giveItem(t, executor, firstLive, "item.potion", 1)
	first, err := executor.UseItem(firstLive, "item.potion")
	if err != nil {
		t.Fatal(err)
	}
	first.Intents[0].Type = IntentOpenShop
	first.Intents[0].HealAmount = 999
	first.ItemID = "item.mutated"
	first.RemainingQuantity = 999
	assertInventory(t, firstLive.Snapshot(), "item.potion", 0)

	secondLive, err := campaign.NewGame(executor.config)
	if err != nil {
		t.Fatal(err)
	}
	giveItem(t, executor, secondLive, "item.potion", 1)
	second, err := executor.UseItem(secondLive, "item.potion")
	if err != nil {
		t.Fatal(err)
	}
	if len(second.Intents) != 1 ||
		second.Intents[0].Type != IntentHeal ||
		second.Intents[0].HealAmount != 25 {
		t.Fatalf("mutated result aliased executor rules: %#v", second)
	}
}

func TestEquipAndUnequipItemReturnCompleteChanges(t *testing.T) {
	t.Parallel()

	executor, live, _ := newCompleteRuntime(t)
	giveItem(t, executor, live, "item.training_sword", 1)

	equipped, err := executor.EquipItem(live, "item.training_sword")
	if err != nil {
		t.Fatal(err)
	}
	wantEquipped := EquipmentChangeResult{
		Changed:                true,
		SlotID:                 "weapon",
		ItemID:                 "item.training_sword",
		PreviousItemID:         "",
		AttackModifier:         5,
		PreviousAttackModifier: 0,
	}
	if !reflect.DeepEqual(equipped, wantEquipped) {
		t.Fatalf("EquipItem() = %#v, want %#v", equipped, wantEquipped)
	}
	assertEquipment(
		t,
		live.Snapshot(),
		"weapon",
		"item.training_sword",
	)

	repeated, err := executor.EquipItem(live, "item.training_sword")
	if err != nil {
		t.Fatal(err)
	}
	if repeated.Changed ||
		repeated.PreviousItemID != "item.training_sword" ||
		repeated.PreviousAttackModifier != 5 ||
		repeated.AttackModifier != 5 {
		t.Fatalf("repeated EquipItem() = %#v", repeated)
	}

	unequipped, err := executor.UnequipItem(live, "weapon")
	if err != nil {
		t.Fatal(err)
	}
	wantUnequipped := EquipmentChangeResult{
		Changed:                true,
		SlotID:                 "weapon",
		ItemID:                 "",
		PreviousItemID:         "item.training_sword",
		AttackModifier:         0,
		PreviousAttackModifier: 5,
	}
	if !reflect.DeepEqual(unequipped, wantUnequipped) {
		t.Fatalf(
			"UnequipItem() = %#v, want %#v",
			unequipped,
			wantUnequipped,
		)
	}
	assertEquipment(t, live.Snapshot(), "weapon", "")

	repeatedUnequip, err := executor.UnequipItem(live, "weapon")
	if err != nil {
		t.Fatal(err)
	}
	if repeatedUnequip.Changed ||
		repeatedUnequip.PreviousItemID != "" ||
		repeatedUnequip.PreviousAttackModifier != 0 {
		t.Fatalf("repeated UnequipItem() = %#v", repeatedUnequip)
	}
}

func TestEquipmentAPIsRejectInvalidRequestsWithoutMutation(t *testing.T) {
	t.Parallel()

	executor, live, _ := newCompleteRuntime(t)

	t.Run("nil receivers", func(t *testing.T) {
		var nilExecutor *Executor
		before := live.Snapshot()
		result, err := nilExecutor.EquipItem(live, "item.training_sword")
		requireZeroEquipmentResult(t, result, err)
		result, err = nilExecutor.UnequipItem(live, "weapon")
		requireZeroEquipmentResult(t, result, err)
		assertStateUnchanged(t, live, before)

		result, err = executor.EquipItem(nil, "item.training_sword")
		requireZeroEquipmentResult(t, result, err)
		result, err = executor.UnequipItem(nil, "weapon")
		requireZeroEquipmentResult(t, result, err)
	})

	for _, test := range []struct {
		name  string
		call  func() (EquipmentChangeResult, error)
		match string
	}{
		{
			name: "unknown item",
			call: func() (EquipmentChangeResult, error) {
				return executor.EquipItem(live, "item.missing")
			},
			match: "not configured",
		},
		{
			name: "non-equipment",
			call: func() (EquipmentChangeResult, error) {
				return executor.EquipItem(live, "item.potion")
			},
			match: "not equipment",
		},
		{
			name: "unowned equipment",
			call: func() (EquipmentChangeResult, error) {
				return executor.EquipItem(live, "item.training_sword")
			},
			match: "not owned",
		},
		{
			name: "unknown slot",
			call: func() (EquipmentChangeResult, error) {
				return executor.UnequipItem(live, "armor")
			},
			match: "not configured",
		},
	} {
		test := test
		t.Run(test.name, func(t *testing.T) {
			before := live.Snapshot()
			result, err := test.call()
			if err == nil || !strings.Contains(err.Error(), test.match) {
				t.Fatalf("equipment API error = %v, want %q", err, test.match)
			}
			if !reflect.DeepEqual(result, EquipmentChangeResult{}) {
				t.Fatalf("failed equipment result = %#v", result)
			}
			assertStateUnchanged(t, live, before)
		})
	}

	t.Run("foreign campaign", func(t *testing.T) {
		foreign := newForeignCampaign(t)
		before := foreign.Snapshot()
		for _, call := range []func() (EquipmentChangeResult, error){
			func() (EquipmentChangeResult, error) {
				return executor.EquipItem(
					foreign,
					"item.training_sword",
				)
			},
			func() (EquipmentChangeResult, error) {
				return executor.UnequipItem(foreign, "weapon")
			},
		} {
			result, err := call()
			if err == nil || !strings.Contains(err.Error(), "does not match") {
				t.Fatalf("foreign equipment API error = %v", err)
			}
			if !reflect.DeepEqual(result, EquipmentChangeResult{}) {
				t.Fatalf("failed equipment result = %#v", result)
			}
			assertStateUnchanged(t, foreign, before)
		}
	})
}

func TestEquipmentAPIsRejectSameIdentitySlotMismatch(t *testing.T) {
	t.Parallel()

	executor, _, _ := newCompleteRuntime(t)
	mismatched := newSameIdentityArmorCampaign(t)
	if err := mismatched.Transaction(func(state *campaign.State) error {
		for index := range state.Inventory {
			if state.Inventory[index].ItemID == "item.training_sword" {
				state.Inventory[index].Quantity = 1
				return nil
			}
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	before := mismatched.Snapshot()

	for _, call := range []func() (EquipmentChangeResult, error){
		func() (EquipmentChangeResult, error) {
			return executor.EquipItem(
				mismatched,
				"item.training_sword",
			)
		},
		func() (EquipmentChangeResult, error) {
			return executor.UnequipItem(mismatched, "weapon")
		},
	} {
		result, err := call()
		if err == nil || !strings.Contains(err.Error(), "slot") {
			t.Fatalf("slot mismatch error = %v", err)
		}
		if !reflect.DeepEqual(result, EquipmentChangeResult{}) {
			t.Fatalf("failed equipment result = %#v", result)
		}
		assertStateUnchanged(t, mismatched, before)
	}
}

func TestEquipmentResultCannotMutateCampaign(t *testing.T) {
	t.Parallel()

	executor, live, _ := newCompleteRuntime(t)
	giveItem(t, executor, live, "item.training_sword", 1)
	result, err := executor.EquipItem(live, "item.training_sword")
	if err != nil {
		t.Fatal(err)
	}
	result.Changed = false
	result.SlotID = "armor"
	result.ItemID = "item.mutated"
	result.PreviousItemID = "item.mutated"
	result.AttackModifier = 999
	result.PreviousAttackModifier = 999

	assertEquipment(
		t,
		live.Snapshot(),
		"weapon",
		"item.training_sword",
	)
}

func giveItem(
	t *testing.T,
	executor *Executor,
	live *campaign.Campaign,
	itemID string,
	quantity int,
) {
	t.Helper()
	if _, err := executor.Execute(live, []gamebuild.RuleAction{{
		Type:     gamebuild.RuleActionGiveItem,
		ItemID:   itemID,
		Quantity: quantity,
	}}); err != nil {
		t.Fatal(err)
	}
}

func runtimeWithPotionEffects(
	t *testing.T,
	effects []gamebuild.RuleAction,
) (*Executor, *campaign.Campaign) {
	t.Helper()
	config, rules := completeDefinitions(t)
	changed := false
	for index := range rules.Items {
		if rules.Items[index].ID != "item.potion" {
			continue
		}
		rules.Items[index].Effects = append(
			[]gamebuild.RuleAction(nil),
			effects...,
		)
		changed = true
		break
	}
	if !changed {
		t.Fatal("potion rule not found")
	}
	executor, err := New(config, rules)
	if err != nil {
		t.Fatal(err)
	}
	live, err := campaign.NewGame(config)
	if err != nil {
		t.Fatal(err)
	}
	return executor, live
}

func newForeignCampaign(t *testing.T) *campaign.Campaign {
	t.Helper()
	config, _ := completeDefinitions(t)
	config.ProjectID += ".foreign"
	live, err := campaign.NewGame(config)
	if err != nil {
		t.Fatal(err)
	}
	return live
}

func newSameIdentityArmorCampaign(t *testing.T) *campaign.Campaign {
	t.Helper()
	config, _ := completeDefinitions(t)
	config.EquipmentSlots = []string{"armor"}
	for index := range config.Items {
		if config.Items[index].ID == "item.training_sword" {
			config.Items[index].EquipmentSlot = "armor"
		}
	}
	live, err := campaign.NewGame(config)
	if err != nil {
		t.Fatal(err)
	}
	return live
}

func requireZeroUseResult(
	t *testing.T,
	result UseItemResult,
	err error,
) {
	t.Helper()
	if err == nil {
		t.Fatal("UseItem() unexpectedly succeeded")
	}
	if !reflect.DeepEqual(result, UseItemResult{}) {
		t.Fatalf("failed UseItem() result = %#v", result)
	}
}

func requireZeroEquipmentResult(
	t *testing.T,
	result EquipmentChangeResult,
	err error,
) {
	t.Helper()
	if err == nil {
		t.Fatal("equipment operation unexpectedly succeeded")
	}
	if !reflect.DeepEqual(result, EquipmentChangeResult{}) {
		t.Fatalf("failed equipment result = %#v", result)
	}
}

func assertStateUnchanged(
	t *testing.T,
	live *campaign.Campaign,
	before campaign.State,
) {
	t.Helper()
	after := live.Snapshot()
	if !reflect.DeepEqual(after, before) {
		t.Fatalf(
			"failed operation mutated campaign\nbefore=%#v\nafter=%#v",
			before,
			after,
		)
	}
}
