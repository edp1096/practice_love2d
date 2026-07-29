package projectcheck

import (
	"bytes"
	"encoding/json"
	"reflect"
	"strings"
	"testing"

	gamecatalog "practice_love2d/33_ebitengine_spike/game"
	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

func TestValidateChecksEveryStageEntryAndLocaleDeterministically(
	t *testing.T,
) {
	t.Parallel()

	catalog := loadProjectCatalog(t)
	got, err := Validate(catalog)
	if err != nil {
		t.Fatal(err)
	}
	want := Report{
		DefinitionCount:   54,
		StageCount:        7,
		EntryBuildCount:   22,
		DerivedBuildCount: 44,
		LocaleCount:       2,
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("report = %#v, want %#v", got, want)
	}

	again, err := Validate(catalog)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(again, got) {
		t.Fatalf("report changed between runs: %#v then %#v", got, again)
	}
}

func TestValidateChecksPristineMaximalAndDormantCampaignBuilds(
	t *testing.T,
) {
	t.Parallel()

	catalog := mutateProjectDefinition(
		t,
		loadProjectCatalog(t),
		"actor.runner",
		func(data map[string]any) {
			components := data["components"].(map[string]any)
			delete(components, "action.combat")
		},
	)
	var pristineCalls int
	var maximalCalls int
	var dormantMaximalCalls int
	var appliedMaximalCalls int
	deps := productionDependencies
	deps.buildStageForCampaign = func(
		catalog *content.Catalog,
		options gamebuild.Options,
		state campaign.State,
		rules gamebuild.ContentRules,
	) (*gamebuild.Result, gamebuild.DerivedStats, error) {
		result, derived, err := gamebuild.BuildForCampaign(
			catalog,
			options,
			state,
			rules,
		)
		if err != nil {
			return result, derived, err
		}
		equipped := 0
		for _, entry := range state.Equipment {
			if entry.ItemID == "" {
				continue
			}
			equipped++
			if inventoryQuantityForTest(state, entry.ItemID) < 1 {
				t.Fatalf(
					"derived build equipped unowned item %q",
					entry.ItemID,
				)
			}
		}
		switch equipped {
		case 0:
			pristineCalls++
			if derived.AttackModifier != 0 {
				t.Fatalf("pristine derived stats = %#v", derived)
			}
		case 1:
			maximalCalls++
			if derived.AttackModifier != 5 {
				t.Fatalf("maximal derived stats = %#v", derived)
			}
			if options.StageID == "stage.platformer_room" {
				if derived.AttackApplied ||
					derived.EffectiveAttackDamage != 0 {
					t.Fatalf(
						"dormant platformer stats = %#v",
						derived,
					)
				}
				dormantMaximalCalls++
			} else if derived.AttackApplied {
				appliedMaximalCalls++
			}
		default:
			t.Fatalf("unexpected equipped item count %d", equipped)
		}
		return result, derived, nil
	}

	report, err := validate(catalog, deps)
	if err != nil {
		t.Fatal(err)
	}
	if report.EntryBuildCount != 22 ||
		report.DerivedBuildCount != 44 {
		t.Fatalf("report = %#v", report)
	}
	if pristineCalls != report.EntryBuildCount {
		t.Fatalf(
			"pristine calls = %d, want %d",
			pristineCalls,
			report.EntryBuildCount,
		)
	}
	if maximalCalls != report.EntryBuildCount {
		t.Fatalf(
			"maximal calls = %d, want %d",
			maximalCalls,
			report.EntryBuildCount,
		)
	}
	if dormantMaximalCalls == 0 {
		t.Fatal("maximal loadout was not checked on a non-combat stage")
	}
	if appliedMaximalCalls == 0 {
		t.Fatal("maximal loadout was not checked on a combat stage")
	}
}

func TestCampaignBuildProfilesAreOrderedCanonicalAndDeduplicated(
	t *testing.T,
) {
	t.Parallel()

	catalog := loadProjectCatalog(t)
	config, err := gamebuild.BuildCampaignConfig(catalog)
	if err != nil {
		t.Fatal(err)
	}
	rules, err := gamebuild.BuildContentRules(catalog)
	if err != nil {
		t.Fatal(err)
	}

	profiles, err := campaignBuildProfiles(config, rules)
	if err != nil {
		t.Fatal(err)
	}
	assertProfileNames(t, profiles, "pristine", "maximal")

	withEmptySlot := config.Clone()
	withEmptySlot.EquipmentSlots = append(
		withEmptySlot.EquipmentSlots,
		"armor",
	)
	profiles, err = campaignBuildProfiles(withEmptySlot, rules)
	if err != nil {
		t.Fatal(err)
	}
	assertProfileNames(t, profiles, "pristine", "maximal")
	if got := equippedItemForTest(
		profiles[1].state,
		"armor",
	); got != "" {
		t.Fatalf("unfillable armor slot = %q, want empty", got)
	}

	withAlternative := config.Clone()
	withAlternative.Items = append(
		withAlternative.Items,
		campaign.ItemDefinition{
			ID:            "item.training_sword_alt",
			MaxQuantity:   1,
			EquipmentSlot: "weapon",
		},
	)
	alternativeRules := rules.Clone()
	alternativeRules.Items = append(
		alternativeRules.Items,
		gamebuild.ItemRule{
			ID:         "item.training_sword_alt",
			StackLimit: 1,
			Equipment: &gamebuild.ItemEquipmentRule{
				Slot:           "weapon",
				AttackModifier: 5,
			},
		},
	)
	profiles, err = campaignBuildProfiles(
		withAlternative,
		alternativeRules,
	)
	if err != nil {
		t.Fatal(err)
	}
	assertProfileNames(
		t,
		profiles,
		"pristine",
		"maximal",
		"item.training_sword_alt",
	)
	if got := equippedItemForTest(
		profiles[1].state,
		"weapon",
	); got != "item.training_sword" {
		t.Fatalf("equal maximum chose %q, want first item id", got)
	}
	if got := equippedItemForTest(
		profiles[2].state,
		"weapon",
	); got != "item.training_sword_alt" {
		t.Fatalf("solo alternative equipped %q", got)
	}
	if got := inventoryQuantityForTest(
		profiles[2].state,
		"item.training_sword_alt",
	); got != 1 {
		t.Fatalf("solo alternative quantity = %d, want 1", got)
	}
	if got := inventoryQuantityForTest(
		profiles[2].state,
		"item.training_sword",
	); got != 0 {
		t.Fatalf("solo profile also owned base sword: %d", got)
	}

	alternativeRules.Items[len(alternativeRules.Items)-1].
		Equipment.AttackModifier = -2
	profiles, err = campaignBuildProfiles(
		withAlternative,
		alternativeRules,
	)
	if err != nil {
		t.Fatal(err)
	}
	assertProfileNames(t, profiles, "pristine", "maximal", "minimal")
	if got := equippedItemForTest(
		profiles[2].state,
		"weapon",
	); got != "item.training_sword_alt" {
		t.Fatalf("minimum equipped %q, want alternative", got)
	}

	withoutEquipment := config.Clone()
	withoutEquipmentRules := rules.Clone()
	for index := range withoutEquipment.Items {
		withoutEquipment.Items[index].EquipmentSlot = ""
		withoutEquipmentRules.Items[index].Equipment = nil
	}
	withoutEquipment.EquipmentSlots = nil
	profiles, err = campaignBuildProfiles(
		withoutEquipment,
		withoutEquipmentRules,
	)
	if err != nil {
		t.Fatal(err)
	}
	assertProfileNames(t, profiles, "pristine")
}

func TestCampaignBuildProfilesOrderSoloItemsByID(t *testing.T) {
	t.Parallel()

	catalog := mutateProjectDefinition(
		t,
		loadProjectCatalog(t),
		"item.potion",
		func(data map[string]any) {
			data["equipment"] = map[string]any{
				"slot": "armor",
				"modifiers": map[string]any{
					"attack": json.Number("2"),
				},
			}
		},
	)
	config, err := gamebuild.BuildCampaignConfig(catalog)
	if err != nil {
		t.Fatal(err)
	}
	rules, err := gamebuild.BuildContentRules(catalog)
	if err != nil {
		t.Fatal(err)
	}
	profiles, err := campaignBuildProfiles(config, rules)
	if err != nil {
		t.Fatal(err)
	}
	assertProfileNames(
		t,
		profiles,
		"pristine",
		"maximal",
		"item.potion",
		"item.training_sword",
	)
}

func TestValidateCountsEveryUniqueEquipmentProfile(t *testing.T) {
	t.Parallel()

	catalog := mutateProjectDefinition(
		t,
		loadProjectCatalog(t),
		"item.potion",
		func(data map[string]any) {
			data["equipment"] = map[string]any{
				"slot": "weapon",
				"modifiers": map[string]any{
					"attack": json.Number("0"),
				},
			}
		},
	)
	report, err := Validate(catalog)
	if err != nil {
		t.Fatal(err)
	}
	if report.EntryBuildCount != 22 ||
		report.DerivedBuildCount != 66 {
		t.Fatalf("three-profile report = %#v", report)
	}
}

func TestCampaignBuildProfilesRejectRulesConfigEquipmentMismatch(
	t *testing.T,
) {
	t.Parallel()

	catalog := loadProjectCatalog(t)
	config, err := gamebuild.BuildCampaignConfig(catalog)
	if err != nil {
		t.Fatal(err)
	}
	rules, err := gamebuild.BuildContentRules(catalog)
	if err != nil {
		t.Fatal(err)
	}
	for index := range rules.Items {
		if rules.Items[index].ID == "item.training_sword" {
			rules.Items[index].Equipment.Slot = "armor"
		}
	}
	_, err = campaignBuildProfiles(config, rules)
	assertProjectError(
		t,
		err,
		"equipment topology",
		`item "item.training_sword"`,
		`rule slot "armor"`,
		`campaign slot "weapon"`,
	)
}

func TestValidateRejectsLaterEquipmentProfileFailures(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name         string
		potionSlot   string
		potionAttack json.Number
		swordAttack  json.Number
		wantProfile  string
		wantFailure  string
	}{
		{
			name:         "masked negative final damage",
			potionSlot:   "armor",
			potionAttack: json.Number("100"),
			swordAttack:  json.Number("-34"),
			wantProfile:  "item.training_sword",
			wantFailure:  "effective attack damage must be positive",
		},
		{
			name:         "effective damage overflow",
			potionSlot:   "weapon",
			potionAttack: json.Number("0"),
			swordAttack:  json.Number("9007199254740991"),
			wantProfile:  "maximal",
			wantFailure:  "effective attack damage",
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			catalog := mutateProjectDefinition(
				t,
				loadProjectCatalog(t),
				"item.potion",
				func(data map[string]any) {
					data["equipment"] = map[string]any{
						"slot": test.potionSlot,
						"modifiers": map[string]any{
							"attack": test.potionAttack,
						},
					}
				},
			)
			catalog = mutateProjectDefinition(
				t,
				catalog,
				"item.training_sword",
				func(data map[string]any) {
					equipment := data["equipment"].(map[string]any)
					modifiers := equipment["modifiers"].(map[string]any)
					modifiers["attack"] = test.swordAttack
				},
			)
			_, err := Validate(catalog)
			assertProjectError(
				t,
				err,
				`campaign profile "`+test.wantProfile+`" build`,
				test.wantFailure,
			)
		})
	}
}

func TestValidateRejectsCampaignDerivedEquipmentOverflow(t *testing.T) {
	t.Parallel()

	const maximum = json.Number("9007199254740991")
	tests := []struct {
		name        string
		addArmor    bool
		wantFailure string
	}{
		{
			name:        "aggregate",
			addArmor:    true,
			wantFailure: "aggregate attack modifier",
		},
		{
			name:        "effective damage",
			wantFailure: "effective attack damage",
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			catalog := loadProjectCatalog(t)
			if test.addArmor {
				catalog = mutateProjectDefinition(
					t,
					catalog,
					"item.potion",
					func(data map[string]any) {
						data["equipment"] = map[string]any{
							"slot": "armor",
							"modifiers": map[string]any{
								"attack": maximum,
							},
						}
					},
				)
			}
			catalog = mutateProjectDefinition(
				t,
				catalog,
				"item.training_sword",
				func(data map[string]any) {
					equipment := data["equipment"].(map[string]any)
					modifiers := equipment["modifiers"].(map[string]any)
					modifiers["attack"] = maximum
				},
			)

			_, err := Validate(catalog)
			assertProjectError(
				t,
				err,
				`campaign profile "maximal" build`,
				test.wantFailure,
			)
		})
	}
}

func TestValidateRejectsFractionalEquipmentModifier(t *testing.T) {
	t.Parallel()

	catalog := mutateProjectDefinition(
		t,
		loadProjectCatalog(t),
		"item.training_sword",
		func(data map[string]any) {
			equipment := data["equipment"].(map[string]any)
			modifiers := equipment["modifiers"].(map[string]any)
			modifiers["attack"] = json.Number("0.5")
		},
	)
	_, err := Validate(catalog)
	assertProjectError(
		t,
		err,
		`definition "item.training_sword"`,
		"equipment.modifiers.attack must be an integer",
	)
}

func TestValidateRejectsLongDurableIdentifiers(t *testing.T) {
	t.Parallel()

	longID := strings.Repeat("x", 129)
	tests := []struct {
		name       string
		definition string
		mutate     func(map[string]any)
		want       string
	}{
		{
			name:       "flag",
			definition: "quest.grove_guardian",
			mutate: func(data map[string]any) {
				actions := data["on_complete"].([]any)
				actions[2].(map[string]any)["name"] = longID
			},
			want: "flag",
		},
		{
			name:       "equipment slot",
			definition: "item.training_sword",
			mutate: func(data map[string]any) {
				equipment := data["equipment"].(map[string]any)
				equipment["slot"] = longID
			},
			want: "equipment slot",
		},
		{
			name:       "objective",
			definition: "quest.grove_guardian",
			mutate: func(data map[string]any) {
				objectives := data["objectives"].([]any)
				objectives[0].(map[string]any)["id"] = longID
			},
			want: "objective id",
		},
		{
			name:       "entry spawn",
			definition: "stage.rpg_village",
			mutate: func(data map[string]any) {
				spawns := data["spawn_points"].([]any)
				spawns[1].(map[string]any)["id"] = longID
			},
			want: "entry spawn",
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			catalog := mutateProjectDefinition(
				t,
				loadProjectCatalog(t),
				test.definition,
				test.mutate,
			)
			_, err := Validate(catalog)
			assertProjectError(
				t,
				err,
				`project "recreate.maker_runtime"`,
				"campaign topology",
				test.want,
			)
		})
	}
}

func TestValidateRejectsCatalogAndManifestReferenceFailures(t *testing.T) {
	t.Parallel()

	t.Run("catalog envelope", func(t *testing.T) {
		t.Parallel()
		catalog := loadProjectCatalog(t)
		catalog.DependencyGraph.Total++
		_, err := Validate(catalog)
		assertProjectError(
			t,
			err,
			`project "recreate.maker_runtime"`,
			"catalog",
			"catalog totals disagree",
		)
	})

	t.Run("manifest reference", func(t *testing.T) {
		t.Parallel()
		catalog := loadProjectCatalog(t)
		catalog.Manifest.Flow.StartSpawn = "missing"
		_, err := Validate(catalog)
		assertProjectError(
			t,
			err,
			`project "recreate.maker_runtime"`,
			"manifest references",
			"game/game.lua.flow.start_spawn",
			`missing spawn point "missing"`,
		)
	})
}

func TestValidateChecksSemanticValidityOfEveryDefinition(t *testing.T) {
	t.Parallel()

	catalog := mutateProjectDefinition(
		t,
		loadProjectCatalog(t),
		"status.enraged",
		func(data map[string]any) {
			// status.enraged is the final canonical definition. Checking it
			// prevents a current-stage-only or early-exit validation loop.
			data["duration"] = json.Number("0")
		},
	)
	_, err := Validate(catalog)
	assertProjectError(
		t,
		err,
		`definition "status.enraged"`,
		`from "game/content/statuses/enraged.lua"`,
		"status.enraged.duration must be positive",
	)
}

func TestValidateRejectsMalformedGeometryInLaterStage(t *testing.T) {
	t.Parallel()

	catalog := mutateProjectDefinition(
		t,
		loadProjectCatalog(t),
		"stage.world_grove",
		func(data map[string]any) {
			walls := data["walls"].([]any)
			shape := walls[len(walls)-1].(map[string]any)["shape"].(map[string]any)
			points := shape["points"].([]any)
			points[len(points)-1] = cloneJSONValue(t, points[0])
		},
	)
	_, err := Validate(catalog)
	assertProjectError(
		t,
		err,
		`project "recreate.maker_runtime"`,
		`stage "stage.world_grove"`,
		`from "game/content/stages/generated/world_grove.lua"`,
		`entry "west_entry"`,
		`locale "locale.en"`,
		"polygon repeats point",
	)
}

func TestValidateRejectsCampaignRulesTopologyMismatch(t *testing.T) {
	t.Parallel()

	base := loadProjectCatalog(t)
	staleRules, err := gamebuild.BuildContentRules(base)
	if err != nil {
		t.Fatal(err)
	}
	candidate := mutateProjectDefinition(
		t,
		base,
		"item.potion",
		func(data map[string]any) {
			data["stack_limit"] = json.Number("9")
		},
	)

	deps := productionDependencies
	deps.buildContentRules = func(
		*content.Catalog,
	) (gamebuild.ContentRules, error) {
		// Model a stale or independently changed rule compiler result. The
		// project validator must compare it with the freshly translated
		// campaign topology instead of accepting both in isolation.
		return staleRules, nil
	}
	_, err = validate(candidate, deps)
	assertProjectError(
		t,
		err,
		`project "recreate.maker_runtime"`,
		"campaign/rules topology",
		`item "item.potion" stack limit 10`,
		"campaign maximum 9",
	)
}

func TestValidateRejectsNilCatalog(t *testing.T) {
	t.Parallel()

	_, err := Validate(nil)
	assertProjectError(t, err, "catalog is nil")
}

func loadProjectCatalog(t *testing.T) *content.Catalog {
	t.Helper()
	catalog, err := content.LoadBytes(gamecatalog.Bytes())
	if err != nil {
		t.Fatal(err)
	}
	return catalog
}

func mutateProjectDefinition(
	t *testing.T,
	catalog *content.Catalog,
	id string,
	mutate func(map[string]any),
) *content.Catalog {
	t.Helper()
	raw, exists := catalog.Definition(id)
	if !exists {
		t.Fatalf("definition %q is missing", id)
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	var data map[string]any
	if err := decoder.Decode(&data); err != nil {
		t.Fatal(err)
	}
	mutate(data)
	updated, err := json.Marshal(data)
	if err != nil {
		t.Fatal(err)
	}
	result, err := catalog.WithDefinition(id, updated)
	if err != nil {
		t.Fatalf("mutate definition %q: %v", id, err)
	}
	return result
}

func cloneJSONValue(t *testing.T, value any) any {
	t.Helper()
	data, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber()
	var result any
	if err := decoder.Decode(&result); err != nil {
		t.Fatal(err)
	}
	return result
}

func inventoryQuantityForTest(
	state campaign.State,
	itemID string,
) int64 {
	for _, entry := range state.Inventory {
		if entry.ItemID == itemID {
			return entry.Quantity
		}
	}
	return -1
}

func equippedItemForTest(state campaign.State, slotID string) string {
	for _, entry := range state.Equipment {
		if entry.SlotID == slotID {
			return entry.ItemID
		}
	}
	return "<missing>"
}

func assertProfileNames(
	t *testing.T,
	profiles []campaignBuildProfile,
	want ...string,
) {
	t.Helper()
	got := make([]string, len(profiles))
	for index, profile := range profiles {
		got[index] = profile.name
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("profile names = %#v, want %#v", got, want)
	}
}

func assertProjectError(t *testing.T, err error, fragments ...string) {
	t.Helper()
	if err == nil {
		t.Fatal("Validate() error = nil")
	}
	for _, fragment := range fragments {
		if !strings.Contains(err.Error(), fragment) {
			t.Fatalf(
				"Validate() error = %q, want fragment %q",
				err,
				fragment,
			)
		}
	}
}
