package gamebuild

import (
	"sort"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/content"
)

func TestTurnBattleContentCompilesTypedRules(t *testing.T) {
	catalog := turnBattleCatalog()
	for _, id := range catalog.IDs() {
		validation, err := ValidateDefinition(catalog, id)
		if err != nil {
			t.Fatalf("ValidateDefinition(%q): %v", id, err)
		}
		if !validation.SchemaValid {
			t.Fatalf("validation %q = %#v", id, validation)
		}
		if (validation.Kind == "turn_skill" ||
			validation.Kind == "turn_battle") &&
			!validation.FullyApplied {
			t.Fatalf("turn content validation %q = %#v", id, validation)
		}
	}
	rules, err := BuildContentRules(catalog)
	if err != nil {
		t.Fatal(err)
	}
	skill, exists := rules.TurnSkill("turn_skill.strike")
	if !exists || skill.Effect != "damage" ||
		skill.Target != "enemy" || skill.Power != 12 {
		t.Fatalf("turn skill = %#v exists=%v", skill, exists)
	}
	battle, exists := rules.TurnBattle("turn_battle.training")
	if !exists || !battle.AllowEscape || battle.Repeatable ||
		len(battle.Enemies) != 1 ||
		battle.Enemies[0].ActorID != "actor.slime" ||
		battle.Enemies[0].MaxHealth != 24 ||
		battle.Enemies[0].Attack != 2 ||
		battle.Enemies[0].Defense != 1 ||
		len(battle.OnVictory) != 1 {
		t.Fatalf("turn battle = %#v exists=%v", battle, exists)
	}
	interaction, exists := rules.Interaction("actor.player")
	if !exists || len(interaction.Actions) != 1 ||
		interaction.Actions[0].Type != RuleActionStartTurnBattle ||
		interaction.Actions[0].BattleID != "turn_battle.training" ||
		interaction.Condition == nil ||
		interaction.Condition.Type != RuleConditionTurnBattleState ||
		interaction.Condition.BattleState != RuleTurnBattleNever {
		t.Fatalf("turn battle interaction = %#v exists=%v", interaction, exists)
	}
}

func TestInteractionEventPagesCompileWithCompositeConditions(t *testing.T) {
	catalog := turnBattleCatalog()
	for index := range catalog.Definitions {
		definition := &catalog.Definitions[index]
		if definition.ID() != "actor.player" {
			continue
		}
		components := definition.Data["components"].(map[string]any)
		interaction := components["rpg.interactable"].(map[string]any)
		delete(interaction, "condition")
		delete(interaction, "actions")
		interaction["pages"] = []any{
			map[string]any{
				"id":     "before",
				"prompt": "Begin",
				"actions": []any{
					map[string]any{
						"type":   "start_turn_battle",
						"battle": "turn_battle.training",
					},
				},
			},
			map[string]any{
				"id": "after",
				"condition": map[string]any{
					"type": "all",
					"conditions": []any{
						map[string]any{
							"type":   "turn_battle_state",
							"battle": "turn_battle.training",
							"state":  "won",
						},
						map[string]any{
							"type":  "flag",
							"name":  "story.report_ready",
							"value": true,
						},
					},
				},
				"actions": []any{
					map[string]any{
						"type":   "add_currency",
						"amount": float64(3),
					},
				},
			},
		}
	}

	for _, id := range catalog.IDs() {
		if _, err := ValidateDefinition(catalog, id); err != nil {
			t.Fatalf("ValidateDefinition(%q): %v", id, err)
		}
	}
	rules, err := BuildContentRules(catalog)
	if err != nil {
		t.Fatal(err)
	}
	interaction, exists := rules.Interaction("actor.player")
	if !exists || len(interaction.Actions) != 0 ||
		len(interaction.Pages) != 2 {
		t.Fatalf("event-page interaction = %#v, exists=%v", interaction, exists)
	}
	before := interaction.Pages[0]
	if before.ID != "before" || before.Prompt != "Begin" ||
		before.Range != 72 || before.Input != "interact" ||
		len(before.Actions) != 1 {
		t.Fatalf("before page = %#v", before)
	}
	after := interaction.Pages[1]
	if after.Condition == nil ||
		after.Condition.Type != RuleConditionAll ||
		len(after.Condition.Conditions) != 2 ||
		after.Condition.Conditions[1].Type != RuleConditionFlag ||
		after.Condition.Conditions[1].FlagName != "story.report_ready" ||
		!after.Condition.Conditions[1].FlagValue {
		t.Fatalf("after page condition = %#v", after.Condition)
	}

	flags := map[string]struct{}{}
	for _, definition := range catalog.Definitions {
		if err := collectCampaignFlags(definition.Data, flags); err != nil {
			t.Fatal(err)
		}
	}
	if _, exists := flags["story.report_ready"]; !exists {
		t.Fatalf("flag condition was not added to campaign topology: %#v", flags)
	}
}

func turnBattleCatalog() *content.Catalog {
	definitions := []content.Definition{
		{
			Source: "game/content/actors/player.lua",
			Data: map[string]any{
				"schema_version": float64(1),
				"kind":           "actor",
				"id":             "actor.player",
				"name":           "Player",
				"tags":           []any{"player"},
				"components": map[string]any{
					"transform": map[string]any{},
					"body": map[string]any{
						"shape":  "circle",
						"radius": float64(15),
					},
					"action.health": map[string]any{
						"max": float64(100),
					},
					"rpg.stats": map[string]any{
						"attack":     float64(2),
						"defense":    float64(1),
						"move_speed": float64(1),
					},
					"rpg.turn_battler": map[string]any{
						"skills": []any{"turn_skill.strike"},
					},
					"rpg.interactable": map[string]any{
						"input":      "interact",
						"prompt_key": "interaction.battle",
						"range":      float64(72),
						"condition": map[string]any{
							"type":   "turn_battle_state",
							"battle": "turn_battle.training",
							"state":  "never",
						},
						"actions": []any{
							map[string]any{
								"type":   "start_turn_battle",
								"battle": "turn_battle.training",
							},
						},
					},
				},
			},
		},
		{
			Source: "game/content/actors/slime.lua",
			Data: map[string]any{
				"schema_version": float64(1),
				"kind":           "actor",
				"id":             "actor.slime",
				"name":           "Slime",
				"components": map[string]any{
					"transform": map[string]any{},
					"body": map[string]any{
						"shape":  "circle",
						"radius": float64(18),
					},
					"action.health": map[string]any{
						"max": float64(24),
					},
					"rpg.stats": map[string]any{
						"attack":     float64(2),
						"defense":    float64(1),
						"move_speed": float64(1),
					},
					"rpg.turn_battler": map[string]any{
						"skills": []any{"turn_skill.strike"},
					},
				},
			},
		},
		{
			Source: "game/content/battles/training.lua",
			Data: map[string]any{
				"schema_version": float64(1),
				"kind":           "turn_battle",
				"id":             "turn_battle.training",
				"name":           "Training",
				"allow_escape":   true,
				"enemies": []any{
					map[string]any{
						"id":    "slime",
						"actor": "actor.slime",
					},
				},
				"on_victory": []any{
					map[string]any{
						"type":   "add_currency",
						"amount": float64(7),
					},
				},
			},
		},
		{
			Source: "game/content/skills/strike.lua",
			Data: map[string]any{
				"schema_version": float64(1),
				"kind":           "turn_skill",
				"id":             "turn_skill.strike",
				"name":           "Strike",
				"effect":         "damage",
				"target":         "enemy",
				"power":          float64(12),
			},
		},
	}
	sort.Slice(definitions, func(i, j int) bool {
		return definitions[i].ID() < definitions[j].ID()
	})
	return &content.Catalog{
		SchemaVersion: content.CatalogSchemaVersion,
		Definitions:   definitions,
	}
}
