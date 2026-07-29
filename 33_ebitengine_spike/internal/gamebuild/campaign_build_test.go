package gamebuild

import (
	"encoding/json"
	"math"
	"reflect"
	"strings"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

func TestBuildForCampaignWithoutEquipmentMatchesFreshBuild(
	t *testing.T,
) {
	t.Parallel()

	catalog := loadCatalog(t)
	rules := campaignBuildRules(t, catalog)
	state := campaignBuildState(t, catalog)
	want, err := Build(catalog, Options{})
	if err != nil {
		t.Fatal(err)
	}

	got, derived, err := BuildForCampaign(
		catalog,
		Options{},
		state,
		rules,
	)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(
			"zero-equipment campaign build differs from authored build\n"+
				"got:  %#v\nwant: %#v",
			got,
			want,
		)
	}
	if derived != (DerivedStats{
		AttackModifier:        0,
		EffectiveAttackDamage: 34,
		AttackApplied:         true,
	}) {
		t.Fatalf("zero-equipment derived stats = %#v", derived)
	}
}

func TestBuildForCampaignAllowsNonCombatProfileWithoutModifier(
	t *testing.T,
) {
	t.Parallel()

	catalog := campaignBuildNoAbilityCatalog(t)
	rules := campaignBuildRules(t, catalog)
	state := campaignBuildState(t, catalog)
	options := Options{StageID: "stage.platformer_room"}
	want, err := Build(catalog, options)
	if err != nil {
		t.Fatal(err)
	}
	if campaignBuildControlledEntity(t, want).PrimaryAbility() != nil {
		t.Fatal("platformer fixture unexpectedly has a primary ability")
	}

	got, derived, err := BuildForCampaign(
		catalog,
		options,
		state,
		rules,
	)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(
			"non-combat campaign build differs from authored build\n"+
				"got:  %#v\nwant: %#v",
			got,
			want,
		)
	}
	if derived != (DerivedStats{}) {
		t.Fatalf("non-combat derived stats = %#v", derived)
	}
}

func TestBuildForCampaignAppliesSwordOnceToFreshDetachedResult(
	t *testing.T,
) {
	t.Parallel()

	catalog := loadCatalog(t)
	rules := campaignBuildRules(t, catalog)
	state := campaignBuildState(t, catalog)
	equipCampaignBuildItem(
		t,
		&state,
		"weapon",
		"item.training_sword",
	)
	stateBefore := state.Clone()
	rulesBefore, err := json.Marshal(rules)
	if err != nil {
		t.Fatal(err)
	}

	first, firstDerived, err := BuildForCampaign(
		catalog,
		Options{},
		state,
		rules,
	)
	if err != nil {
		t.Fatal(err)
	}
	if firstDerived != (DerivedStats{
		AttackModifier:        5,
		EffectiveAttackDamage: 39,
		AttackApplied:         true,
	}) || campaignBuildDamage(t, first) != 39 {
		t.Fatalf(
			"first sword build stats=%#v damage=%d",
			firstDerived,
			campaignBuildDamage(t, first),
		)
	}

	// Mutating a returned result must not affect the next build. Starting from
	// the prior effective damage would incorrectly produce 44 here.
	campaignBuildControlledEntity(t, first).PrimaryAbility().Damage = 999
	first.Presentation.Instances[0].Tags = append(
		first.Presentation.Instances[0].Tags,
		"mutated",
	)
	second, secondDerived, err := BuildForCampaign(
		catalog,
		Options{},
		state,
		rules,
	)
	if err != nil {
		t.Fatal(err)
	}
	if secondDerived != firstDerived ||
		campaignBuildDamage(t, second) != 39 {
		t.Fatalf(
			"second sword build stats=%#v damage=%d",
			secondDerived,
			campaignBuildDamage(t, second),
		)
	}
	for _, tag := range second.Presentation.Instances[0].Tags {
		if tag == "mutated" {
			t.Fatal("fresh campaign build shares presentation tags")
		}
	}
	if !reflect.DeepEqual(state, stateBefore) {
		t.Fatal("BuildForCampaign mutated its campaign state input")
	}
	rulesAfter, err := json.Marshal(rules)
	if err != nil {
		t.Fatal(err)
	}
	if string(rulesAfter) != string(rulesBefore) {
		t.Fatal("BuildForCampaign mutated its content rules input")
	}
}

func TestBuildForCampaignDeterministicallySumsMultipleSlots(
	t *testing.T,
) {
	t.Parallel()

	catalog := campaignBuildMultiSlotCatalog(t)
	rules := campaignBuildRules(t, catalog)
	state := campaignBuildState(t, catalog)
	equipCampaignBuildItem(t, &state, "armor", "item.potion")
	equipCampaignBuildItem(
		t,
		&state,
		"weapon",
		"item.training_sword",
	)

	result, derived, err := BuildForCampaign(
		catalog,
		Options{},
		state,
		rules,
	)
	if err != nil {
		t.Fatal(err)
	}
	if derived != (DerivedStats{
		AttackModifier:        7,
		EffectiveAttackDamage: 41,
		AttackApplied:         true,
	}) || campaignBuildDamage(t, result) != 41 {
		t.Fatalf(
			"multi-slot stats=%#v damage=%d",
			derived,
			campaignBuildDamage(t, result),
		)
	}
}

func TestBuildForCampaignRejectsInvalidStateWithoutExposingResult(
	t *testing.T,
) {
	t.Parallel()

	catalog := loadCatalog(t)
	rules := campaignBuildRules(t, catalog)
	state := campaignBuildState(t, catalog)
	// Bypass Campaign.Transaction deliberately: an equipped-but-unowned item
	// is the corrupt input this API boundary must reject.
	setCampaignBuildEquipment(
		t,
		&state,
		"weapon",
		"item.training_sword",
	)

	assertCampaignBuildFailure(
		t,
		catalog,
		state,
		rules,
		"is not present in inventory",
	)

	wrongSlot := campaignBuildState(t, catalog)
	equipCampaignBuildItem(
		t,
		&wrongSlot,
		"weapon",
		"item.training_sword",
	)
	wrongSlot.Equipment[0].SlotID = "armor"
	assertCampaignBuildFailure(
		t,
		catalog,
		wrongSlot,
		rules,
		`expected "weapon"`,
	)
}

func TestBuildForCampaignRejectsInvalidEquipmentRules(
	t *testing.T,
) {
	t.Parallel()

	catalog := loadCatalog(t)
	baseRules := campaignBuildRules(t, catalog)
	state := campaignBuildState(t, catalog)
	equipCampaignBuildItem(
		t,
		&state,
		"weapon",
		"item.training_sword",
	)

	tests := []struct {
		name     string
		mutate   func(*testing.T, *ContentRules)
		contains string
	}{
		{
			name: "missing item rule",
			mutate: func(t *testing.T, rules *ContentRules) {
				t.Helper()
				for index, item := range rules.Items {
					if item.ID == "item.training_sword" {
						rules.Items = append(
							rules.Items[:index],
							rules.Items[index+1:]...,
						)
						return
					}
				}
				t.Fatal("content rules have no training sword")
			},
			contains: "no configured item rule",
		},
		{
			name: "non-equipment rule",
			mutate: func(t *testing.T, rules *ContentRules) {
				campaignBuildMutableItemRule(
					t,
					rules,
					"item.training_sword",
				).Equipment = nil
			},
			contains: "has no equipment rule",
		},
		{
			name: "slot mismatch",
			mutate: func(t *testing.T, rules *ContentRules) {
				campaignBuildMutableItemRule(
					t,
					rules,
					"item.training_sword",
				).Equipment.Slot = "armor"
			},
			contains: "does not match state slot",
		},
		{
			name: "fractional modifier",
			mutate: func(t *testing.T, rules *ContentRules) {
				campaignBuildMutableItemRule(
					t,
					rules,
					"item.training_sword",
				).Equipment.AttackModifier = 0.5
			},
			contains: "must be an integer",
		},
		{
			name: "non-finite modifier",
			mutate: func(t *testing.T, rules *ContentRules) {
				campaignBuildMutableItemRule(
					t,
					rules,
					"item.training_sword",
				).Equipment.AttackModifier = math.Inf(1)
			},
			contains: "must be a finite number",
		},
		{
			name: "non-JSON-safe modifier",
			mutate: func(t *testing.T, rules *ContentRules) {
				campaignBuildMutableItemRule(
					t,
					rules,
					"item.training_sword",
				).Equipment.AttackModifier =
					float64(campaign.MaxJSONInteger) + 1
			},
			contains: "JSON-safe integer range",
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			rules := baseRules.Clone()
			test.mutate(t, &rules)
			assertCampaignBuildFailure(
				t,
				catalog,
				state,
				rules,
				test.contains,
			)
		})
	}
}

func TestBuildForCampaignRejectsAggregateAndFinalDamageOverflow(
	t *testing.T,
) {
	t.Parallel()

	t.Run("aggregate", func(t *testing.T) {
		t.Parallel()
		catalog := campaignBuildMultiSlotCatalog(t)
		rules := campaignBuildRules(t, catalog)
		state := campaignBuildState(t, catalog)
		equipCampaignBuildItem(t, &state, "armor", "item.potion")
		equipCampaignBuildItem(
			t,
			&state,
			"weapon",
			"item.training_sword",
		)
		for _, itemID := range []string{
			"item.potion",
			"item.training_sword",
		} {
			campaignBuildMutableItemRule(
				t,
				&rules,
				itemID,
			).Equipment.AttackModifier =
				float64(campaign.MaxJSONInteger)
		}
		assertCampaignBuildFailure(
			t,
			catalog,
			state,
			rules,
			"aggregate attack modifier",
		)
	})

	t.Run("effective damage", func(t *testing.T) {
		t.Parallel()
		catalog := loadCatalog(t)
		rules := campaignBuildRules(t, catalog)
		state := campaignBuildState(t, catalog)
		equipCampaignBuildItem(
			t,
			&state,
			"weapon",
			"item.training_sword",
		)
		campaignBuildMutableItemRule(
			t,
			&rules,
			"item.training_sword",
		).Equipment.AttackModifier =
			float64(campaign.MaxJSONInteger)
		assertCampaignBuildFailure(
			t,
			catalog,
			state,
			rules,
			"effective attack damage",
		)
	})

	if _, err := checkedAttackAdd(maxSignedInt64, 1); err == nil {
		t.Fatal("positive signed overflow was accepted")
	}
	if _, err := checkedAttackAdd(minSignedInt64, -1); err == nil {
		t.Fatal("negative signed overflow was accepted")
	}
}

func TestBuildForCampaignRejectsNonPositiveDamageAndKeepsDormantModifier(
	t *testing.T,
) {
	t.Parallel()

	t.Run("non-positive final damage", func(t *testing.T) {
		t.Parallel()
		catalog := loadCatalog(t)
		rules := campaignBuildRules(t, catalog)
		state := campaignBuildState(t, catalog)
		equipCampaignBuildItem(
			t,
			&state,
			"weapon",
			"item.training_sword",
		)
		campaignBuildMutableItemRule(
			t,
			&rules,
			"item.training_sword",
		).Equipment.AttackModifier = -34
		assertCampaignBuildFailure(
			t,
			catalog,
			state,
			rules,
			"must be positive",
		)
	})

	t.Run("modifier is dormant without ability", func(t *testing.T) {
		t.Parallel()
		catalog := campaignBuildNoAbilityCatalog(t)
		rules := campaignBuildRules(t, catalog)
		state := campaignBuildState(t, catalog)
		equipCampaignBuildItem(
			t,
			&state,
			"weapon",
			"item.training_sword",
		)
		options := Options{StageID: "stage.platformer_room"}
		authored, err := Build(catalog, options)
		if err != nil {
			t.Fatal(err)
		}
		result, derived, err := BuildForCampaign(
			catalog,
			options,
			state,
			rules,
		)
		if err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual(result, authored) {
			t.Fatal("dormant modifier changed non-combat authored build")
		}
		if derived != (DerivedStats{
			AttackModifier: 5,
		}) {
			t.Fatalf("dormant modifier stats = %#v", derived)
		}
	})
}

func TestEquipmentAttackModifierCompilerRequiresJSONSafeInteger(
	t *testing.T,
) {
	t.Parallel()

	tests := []struct {
		name     string
		value    float64
		contains string
	}{
		{
			name:     "fractional",
			value:    1.5,
			contains: "must be an integer",
		},
		{
			name: "outside JSON-safe range",
			value: float64(campaign.MaxJSONInteger) +
				1,
			contains: "JSON-safe integer range",
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			catalog := loadCatalog(t)
			mutateRuleDefinition(
				t,
				catalog,
				"item.training_sword",
				func(data map[string]any) {
					equipment := data["equipment"].(map[string]any)
					modifiers := equipment["modifiers"].(map[string]any)
					modifiers["attack"] = test.value
				},
			)
			if _, err := ValidateDefinition(
				catalog,
				"item.training_sword",
			); err == nil || !strings.Contains(err.Error(), test.contains) {
				t.Fatalf(
					"ValidateDefinition() error = %v, want %q",
					err,
					test.contains,
				)
			}
			if _, err := BuildContentRules(catalog); err == nil ||
				!strings.Contains(err.Error(), test.contains) {
				t.Fatalf(
					"BuildContentRules() error = %v, want %q",
					err,
					test.contains,
				)
			}
		})
	}
}

func campaignBuildMultiSlotCatalog(t *testing.T) *content.Catalog {
	t.Helper()
	catalog := loadCatalog(t)
	mutateRuleDefinition(
		t,
		catalog,
		"item.potion",
		func(data map[string]any) {
			data["equipment"] = map[string]any{
				"slot": "armor",
				"modifiers": map[string]any{
					"attack": float64(2),
				},
			}
		},
	)
	return catalog
}

func campaignBuildNoAbilityCatalog(t *testing.T) *content.Catalog {
	t.Helper()
	catalog := loadCatalog(t)
	raw, exists := catalog.Definition("actor.runner")
	if !exists {
		t.Fatal("catalog has no actor.runner")
	}
	var data map[string]any
	if err := json.Unmarshal(raw, &data); err != nil {
		t.Fatal(err)
	}
	components := data["components"].(map[string]any)
	delete(components, "action.combat")
	raw, err := json.Marshal(data)
	if err != nil {
		t.Fatal(err)
	}
	candidate, err := catalog.WithDefinition("actor.runner", raw)
	if err != nil {
		t.Fatal(err)
	}
	return candidate
}

func campaignBuildRules(
	t *testing.T,
	catalog *content.Catalog,
) ContentRules {
	t.Helper()
	rules, err := BuildContentRules(catalog)
	if err != nil {
		t.Fatal(err)
	}
	return rules
}

func campaignBuildState(
	t *testing.T,
	catalog *content.Catalog,
) campaign.State {
	t.Helper()
	config, err := BuildCampaignConfig(catalog)
	if err != nil {
		t.Fatal(err)
	}
	live, err := campaign.NewGame(config)
	if err != nil {
		t.Fatal(err)
	}
	return live.Snapshot()
}

func equipCampaignBuildItem(
	t *testing.T,
	state *campaign.State,
	slotID string,
	itemID string,
) {
	t.Helper()
	found := false
	for index := range state.Inventory {
		if state.Inventory[index].ItemID == itemID {
			state.Inventory[index].Quantity = 1
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("campaign inventory has no item %q", itemID)
	}
	setCampaignBuildEquipment(t, state, slotID, itemID)
}

func setCampaignBuildEquipment(
	t *testing.T,
	state *campaign.State,
	slotID string,
	itemID string,
) {
	t.Helper()
	for index := range state.Equipment {
		if state.Equipment[index].SlotID == slotID {
			state.Equipment[index].ItemID = itemID
			return
		}
	}
	t.Fatalf("campaign equipment has no slot %q", slotID)
}

func campaignBuildMutableItemRule(
	t *testing.T,
	rules *ContentRules,
	itemID string,
) *ItemRule {
	t.Helper()
	for index := range rules.Items {
		if rules.Items[index].ID == itemID {
			return &rules.Items[index]
		}
	}
	t.Fatalf("content rules have no item %q", itemID)
	return nil
}

func campaignBuildControlledEntity(
	t *testing.T,
	result *Result,
) *sim.EntityConfig {
	t.Helper()
	if result == nil {
		t.Fatal("campaign build result is nil")
	}
	for index := range result.Config.Entities {
		if result.Config.Entities[index].Controlled {
			return &result.Config.Entities[index]
		}
	}
	t.Fatal("campaign build has no controlled entity")
	return nil
}

func campaignBuildDamage(t *testing.T, result *Result) int {
	t.Helper()
	entity := campaignBuildControlledEntity(t, result)
	if entity.PrimaryAbility() == nil {
		t.Fatal("controlled entity has no ability")
	}
	return entity.PrimaryAbility().Damage
}

func assertCampaignBuildFailure(
	t *testing.T,
	catalog *content.Catalog,
	state campaign.State,
	rules ContentRules,
	contains string,
) {
	t.Helper()
	result, derived, err := BuildForCampaign(
		catalog,
		Options{},
		state,
		rules,
	)
	if err == nil || !strings.Contains(err.Error(), contains) {
		t.Fatalf(
			"BuildForCampaign() error = %v, want %q",
			err,
			contains,
		)
	}
	if result != nil || derived != (DerivedStats{}) {
		t.Fatalf(
			"failed build exposed result=%#v derived=%#v",
			result,
			derived,
		)
	}
}
