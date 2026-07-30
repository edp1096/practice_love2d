package gamebuild

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/content"
)

func TestValidateDefinitionChecksEveryCatalogDefinition(t *testing.T) {
	t.Parallel()

	catalog := loadCatalog(t)
	for _, id := range catalog.IDs() {
		id := id
		t.Run(id, func(t *testing.T) {
			t.Parallel()
			result, err := ValidateDefinition(catalog, id)
			if err != nil {
				t.Fatal(err)
			}
			if !result.SchemaValid {
				t.Fatalf("validation result = %#v", result)
			}
		})
	}
}

func TestValidateDefinitionRejectsHeaderOnlyDefinitions(t *testing.T) {
	t.Parallel()

	catalog := loadCatalog(t)
	for _, id := range []string{
		"ability.sword_slash",
		"actor.hero",
		"font.ui",
		"dialogue.guide",
		"encounter.slime_trial",
		"item.potion",
		"locale.ko",
		"projectile.fire_bolt",
		"quest.slime_patrol",
		"shop.village",
		"sprite.hero",
		"stage.rpg_village",
		"status.burning",
	} {
		id := id
		t.Run(id, func(t *testing.T) {
			t.Parallel()
			raw, exists := catalog.Definition(id)
			if !exists {
				t.Fatalf("%s is missing", id)
			}
			var original map[string]any
			if err := json.Unmarshal(raw, &original); err != nil {
				t.Fatal(err)
			}
			header := map[string]any{
				"schema_version": float64(1),
				"kind":           original["kind"],
				"id":             id,
			}
			candidate := withDefinition(t, catalog, id, header)
			if _, err := ValidateDefinition(candidate, id); err == nil {
				t.Fatalf("header-only %s passed semantic validation", id)
			}
		})
	}
}

func TestValidateDefinitionMarksActorWithoutBodyAsNotFullyApplied(t *testing.T) {
	t.Parallel()

	catalog := loadCatalog(t)
	raw, exists := catalog.Definition("actor.hero")
	if !exists {
		t.Fatal("actor.hero is missing")
	}
	var draft map[string]any
	if err := json.Unmarshal(raw, &draft); err != nil {
		t.Fatal(err)
	}
	components, ok := draft["components"].(map[string]any)
	if !ok {
		t.Fatal("actor.hero components are missing")
	}
	delete(components, "body")
	candidate := withDefinition(t, catalog, "actor.hero", draft)

	result, err := ValidateDefinition(candidate, "actor.hero")
	if err != nil {
		t.Fatal(err)
	}
	if !result.SchemaValid || result.FullyApplied {
		t.Fatalf("validation result = %#v", result)
	}
	if !warningsContain(result.Warnings, "requires an actor body") {
		t.Fatalf("warnings = %q, want body coverage diagnostic", result.Warnings)
	}
}

func TestValidateDefinitionChecksFollowTagAgainstEditedStage(t *testing.T) {
	t.Parallel()

	catalog := loadCatalog(t)
	const stageID = "stage.platformer_room"
	raw, exists := catalog.Definition(stageID)
	if !exists {
		t.Fatalf("%s is missing", stageID)
	}
	var draft map[string]any
	if err := json.Unmarshal(raw, &draft); err != nil {
		t.Fatal(err)
	}
	camera, ok := draft["camera"].(map[string]any)
	if !ok {
		t.Fatalf("%s camera is missing", stageID)
	}
	// This tag exists on an actor in another stage. Validation must resolve
	// only this stage's actor definitions, not the default/current stage.
	camera["follow_tag"] = "merchant"
	candidate := withDefinition(t, catalog, stageID, draft)

	result, err := ValidateDefinition(candidate, stageID)
	if err != nil {
		t.Fatal(err)
	}
	if !result.SchemaValid || result.FullyApplied {
		t.Fatalf("validation result = %#v", result)
	}
	if !warningsContain(
		result.Warnings,
		`follow_tag "merchant" matches no actor`,
	) {
		t.Fatalf("warnings = %q, want stage-local follow_tag diagnostic", result.Warnings)
	}
}

func TestValidateDefinitionChecksPortalTagAgainstControlledActor(
	t *testing.T,
) {
	t.Parallel()

	catalog := loadCatalog(t)
	const stageID = "stage.rpg_village"
	draft := definitionMap(t, catalog, stageID)
	portals := draft["portals"].([]any)
	portals[0].(map[string]any)["actor_tag"] = "merchant"
	candidate := withDefinition(t, catalog, stageID, draft)

	result, err := ValidateDefinition(candidate, stageID)
	if err != nil {
		t.Fatal(err)
	}
	if !result.SchemaValid || result.FullyApplied {
		t.Fatalf("validation result = %#v", result)
	}
	if !warningsContain(
		result.Warnings,
		`actor_tag "merchant" matches no controlled actor`,
	) {
		t.Fatalf(
			"warnings = %q, want controlled portal actor_tag diagnostic",
			result.Warnings,
		)
	}
}

func TestValidateDefinitionRejectsInvalidActionPayloadAndType(t *testing.T) {
	t.Parallel()

	for _, test := range []struct {
		name   string
		mutate func(map[string]any)
	}{
		{
			name: "missing damage amount",
			mutate: func(draft map[string]any) {
				effects := draft["effects"].([]any)
				delete(effects[0].(map[string]any), "amount")
			},
		},
		{
			name: "unknown action",
			mutate: func(draft map[string]any) {
				effects := draft["effects"].([]any)
				effects[0].(map[string]any)["type"] = "typo_damage"
			},
		},
	} {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			catalog := loadCatalog(t)
			draft := definitionMap(t, catalog, "ability.sword_slash")
			test.mutate(draft)
			candidate := withDefinition(
				t,
				catalog,
				"ability.sword_slash",
				draft,
			)
			if _, err := ValidateDefinition(
				candidate,
				"ability.sword_slash",
			); err == nil {
				t.Fatal("invalid action passed semantic validation")
			}
		})
	}
}

func TestValidateDefinitionRejectsInvalidConditionPayload(t *testing.T) {
	t.Parallel()

	catalog := loadCatalog(t)
	draft := definitionMap(t, catalog, "dialogue.guide")
	nodes := draft["nodes"].(map[string]any)
	greeting := nodes["greeting"].(map[string]any)
	choices := greeting["choices"].([]any)
	condition := choices[0].(map[string]any)["condition"].(map[string]any)
	delete(condition, "state")
	candidate := withDefinition(t, catalog, "dialogue.guide", draft)

	if _, err := ValidateDefinition(candidate, "dialogue.guide"); err == nil {
		t.Fatal("condition without required state passed semantic validation")
	}
}

func TestValidateDefinitionChecksDodgeRelationships(t *testing.T) {
	t.Parallel()

	for _, test := range []struct {
		name   string
		mutate func(map[string]any)
	}{
		{
			name: "zero duration",
			mutate: func(dodge map[string]any) {
				dodge["duration"] = float64(0)
			},
		},
		{
			name: "invulnerability exceeds duration",
			mutate: func(dodge map[string]any) {
				dodge["duration"] = float64(0.1)
				dodge["invulnerability"] = float64(0.2)
			},
		},
	} {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			catalog := loadCatalog(t)
			draft := definitionMap(t, catalog, "actor.hero")
			components := draft["components"].(map[string]any)
			test.mutate(components["action.dodge"].(map[string]any))
			candidate := withDefinition(t, catalog, "actor.hero", draft)
			if _, err := ValidateDefinition(
				candidate,
				"actor.hero",
			); err == nil {
				t.Fatal("invalid dodge passed semantic validation")
			}
		})
	}
}

func TestValidateDefinitionChecksBehaviorAIRelationships(t *testing.T) {
	t.Parallel()

	for _, test := range []struct {
		name   string
		mutate func(map[string]any)
	}{
		{
			name: "attack outside combat loadout",
			mutate: func(components map[string]any) {
				behavior := components["action.behavior_ai"].(map[string]any)
				pattern := behavior["patterns"].([]any)[0].(map[string]any)
				attack := pattern["attacks"].([]any)[0].(map[string]any)
				attack["ability"] = "ability.sword_slash"
			},
		},
		{
			name: "first pattern is conditional",
			mutate: func(components map[string]any) {
				behavior := components["action.behavior_ai"].(map[string]any)
				pattern := behavior["patterns"].([]any)[0].(map[string]any)
				pattern["health_ratio_at_most"] = 0.75
			},
		},
		{
			name: "phase threshold is not descending",
			mutate: func(components map[string]any) {
				behavior := components["action.behavior_ai"].(map[string]any)
				patterns := behavior["patterns"].([]any)
				patterns[1].(map[string]any)["health_ratio_at_most"] = 1
			},
		},
		{
			name: "attack exceeds aggro range",
			mutate: func(components map[string]any) {
				behavior := components["action.behavior_ai"].(map[string]any)
				pattern := behavior["patterns"].([]any)[1].(map[string]any)
				attack := pattern["attacks"].([]any)[0].(map[string]any)
				attack["maximum_range"] = 521
			},
		},
	} {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			catalog := loadCatalog(t)
			draft := definitionMap(t, catalog, "actor.grove_guardian")
			components := draft["components"].(map[string]any)
			test.mutate(components)
			candidate := withDefinition(
				t,
				catalog,
				"actor.grove_guardian",
				draft,
			)
			if _, err := ValidateDefinition(
				candidate,
				"actor.grove_guardian",
			); err == nil {
				t.Fatal("invalid behavior AI passed semantic validation")
			}
		})
	}
}

func TestValidateDefinitionChecksStageSectionPayloads(t *testing.T) {
	t.Parallel()

	t.Run("portal target spawn", func(t *testing.T) {
		t.Parallel()
		catalog := loadCatalog(t)
		draft := definitionMap(t, catalog, "stage.rpg_village")
		portals := draft["portals"].([]any)
		portals[0].(map[string]any)["target_spawn"] = "missing"
		candidate := withDefinition(t, catalog, "stage.rpg_village", draft)
		if _, err := ValidateDefinition(
			candidate,
			"stage.rpg_village",
		); err == nil {
			t.Fatal("invalid portal passed semantic validation")
		}
	})

	t.Run("tile layer length", func(t *testing.T) {
		t.Parallel()
		catalog := loadCatalog(t)
		draft := definitionMap(t, catalog, "stage.world_hub")
		tilemap := draft["tilemap"].(map[string]any)
		layers := tilemap["layers"].([]any)
		layer := layers[0].(map[string]any)
		gids := layer["data"].([]any)
		layer["data"] = gids[:len(gids)-1]
		candidate := withDefinition(t, catalog, "stage.world_hub", draft)
		if _, err := ValidateDefinition(
			candidate,
			"stage.world_hub",
		); err == nil {
			t.Fatal("invalid tile layer passed semantic validation")
		}
	})
}

func TestValidateDefinitionReportsSpawnWallCollisionAsRuntimeGap(t *testing.T) {
	t.Parallel()

	catalog := loadCatalog(t)
	draft := definitionMap(t, catalog, "stage.rpg_village")
	spawns := draft["spawns"].([]any)
	player := spawns[0].(map[string]any)
	position := player["position"].(map[string]any)
	position["x"] = float64(16)
	position["y"] = float64(16)
	candidate := withDefinition(t, catalog, "stage.rpg_village", draft)

	result, err := ValidateDefinition(candidate, "stage.rpg_village")
	if err != nil {
		t.Fatal(err)
	}
	if !result.SchemaValid || result.FullyApplied ||
		!warningsContain(result.Warnings, "overlaps wall") {
		t.Fatalf("validation result = %#v", result)
	}
}

func TestValidateDefinitionAppliesInteractableConditionRecursively(t *testing.T) {
	t.Parallel()

	catalog := loadCatalog(t)
	draft := definitionMap(t, catalog, "actor.guide")
	components := draft["components"].(map[string]any)
	interaction := components["rpg.interactable"].(map[string]any)
	leaf := map[string]any{
		"type": "flag",
		"name": "guide_available",
	}
	interaction["condition"] = map[string]any{
		"type": "all",
		"conditions": []any{
			map[string]any{
				"type":      "not",
				"condition": leaf,
			},
		},
	}

	valid := withDefinition(t, catalog, "actor.guide", draft)
	result, err := ValidateDefinition(valid, "actor.guide")
	if err != nil {
		t.Fatal(err)
	}
	if !result.SchemaValid ||
		warningsContain(result.Warnings, "conditions are not executed") {
		t.Fatalf("validation result = %#v", result)
	}

	delete(leaf, "name")
	invalid := withDefinition(t, catalog, "actor.guide", draft)
	if _, err := ValidateDefinition(invalid, "actor.guide"); err == nil ||
		!strings.Contains(
			err.Error(),
			".condition.conditions[0].condition.name",
		) {
		t.Fatalf("nested condition validation error = %v", err)
	}
}

func TestValidateDefinitionAppliesOmittedInteractableRangeDefault(
	t *testing.T,
) {
	t.Parallel()

	catalog := loadCatalog(t)
	draft := definitionMap(t, catalog, "actor.guide")
	components := draft["components"].(map[string]any)
	interaction := components["rpg.interactable"].(map[string]any)
	delete(interaction, "range")
	candidate := withDefinition(t, catalog, "actor.guide", draft)

	result, err := ValidateDefinition(candidate, "actor.guide")
	if err != nil {
		t.Fatal(err)
	}
	if !result.SchemaValid ||
		warningsContain(
			result.Warnings,
			"does not apply the rpg.interactable.range default",
		) {
		t.Fatalf("validation result = %#v", result)
	}
}

func definitionMap(
	t *testing.T,
	catalog *content.Catalog,
	id string,
) map[string]any {
	t.Helper()
	raw, exists := catalog.Definition(id)
	if !exists {
		t.Fatalf("%s is missing", id)
	}
	var result map[string]any
	if err := json.Unmarshal(raw, &result); err != nil {
		t.Fatal(err)
	}
	return result
}

func warningsContain(warnings []string, substring string) bool {
	for _, warning := range warnings {
		if strings.Contains(warning, substring) {
			return true
		}
	}
	return false
}

func withDefinition(
	t *testing.T,
	catalog *content.Catalog,
	id string,
	data map[string]any,
) *content.Catalog {
	t.Helper()
	raw, err := json.Marshal(data)
	if err != nil {
		t.Fatal(err)
	}
	candidate, err := catalog.WithDefinition(id, raw)
	if err != nil {
		t.Fatalf("replace %s: %v\n%s", id, err, fmt.Sprintf("%s", raw))
	}
	return candidate
}
