package gamebuild

import (
	"encoding/json"
	"fmt"
	"sort"

	"practice_love2d/33_ebitengine_spike/internal/content"
)

// DefinitionValidation separates data validity from current vertical-slice
// coverage. A definition can be well formed while containing Maker features
// that this spike deliberately does not execute yet.
type DefinitionValidation struct {
	ID           string   `json:"id"`
	Kind         string   `json:"kind"`
	SchemaValid  bool     `json:"schema_valid"`
	FullyApplied bool     `json:"fully_applied"`
	Warnings     []string `json:"warnings"`
}

// ValidateDefinition performs semantic checks for every catalog kind and
// reports fields which the current Ebitengine vertical slice would ignore.
func ValidateDefinition(
	catalog *content.Catalog,
	id string,
) (DefinitionValidation, error) {
	if catalog == nil {
		return DefinitionValidation{}, fmt.Errorf(
			"validate definition %q: catalog is nil",
			id,
		)
	}
	raw, exists := catalog.Definition(id)
	if !exists {
		return DefinitionValidation{}, fmt.Errorf(
			"validate definition %q: not found",
			id,
		)
	}
	var data map[string]any
	if err := json.Unmarshal(raw, &data); err != nil {
		return DefinitionValidation{}, fmt.Errorf(
			"validate definition %q: %w",
			id,
			err,
		)
	}
	kind, _ := data["kind"].(string)
	if data["id"] != id || kind == "" || data["schema_version"] != float64(1) {
		return DefinitionValidation{}, fmt.Errorf(
			"validate definition %q: invalid header",
			id,
		)
	}
	if err := validateSemanticNumbers(data, id); err != nil {
		return DefinitionValidation{}, err
	}

	warnings := make(map[string]struct{})
	warn := func(message string) {
		warnings[message] = struct{}{}
	}
	fullyApplied := true
	unsupported := func(message string) {
		fullyApplied = false
		warn(message)
	}

	switch kind {
	case "ability":
		if err := validateAbilitySemantics(catalog, data, id); err != nil {
			return DefinitionValidation{}, err
		}
		hitbox, _ := data["hitbox"].(map[string]any)
		effects, _ := data["effects"].([]any)
		if hitbox == nil || len(effects) == 0 {
			unsupported(
				"runtime executes arc hitbox/effects abilities only",
			)
		}
		if _, exists := data["activation"]; exists {
			unsupported(
				"ability activation/projectile actions are not executed",
			)
		}
		if _, exists := data["visual"]; exists {
			unsupported(
				"ability visual metadata is not data-driven yet",
			)
		}
		if hitbox != nil {
			if _, exists := hitbox["max_hits"]; exists {
				unsupported("multi-hit ability metadata is not executed")
			}
			if _, exists := hitbox["repeat_interval"]; exists {
				unsupported("repeat_interval is not executed")
			}
		}
		for _, item := range effects {
			effect, _ := item.(map[string]any)
			switch effect["type"] {
			case "damage", "stagger", "knockback", "hitstop":
			default:
				unsupported(fmt.Sprintf(
					"ability effect %q is not executed",
					effect["type"],
				))
			}
		}

	case "actor":
		if err := validateActorSemantics(catalog, data, id); err != nil {
			return DefinitionValidation{}, err
		}
		components, _ := data["components"].(map[string]any)
		if _, exists := components["body"]; !exists {
			unsupported("Ebitengine adapter requires an actor body")
		}
		supported := map[string]bool{
			"transform":         true,
			"body":              true,
			"control.player":    true,
			"motion.facing":     true,
			"motion.kinematics": true,
			"movement.topdown":  true,
			"render.sprite":     true,
			"action.health":     true,
			"action.reaction":   true,
			"action.dodge":      true,
			"action.parry":      true,
			"action.combat":     true,
			"action.chase_ai":   true,
			"rpg.interactable":  true,
		}
		for component := range components {
			if !supported[component] {
				unsupported(fmt.Sprintf(
					"actor component %q is not executed",
					component,
				))
			}
		}
		if _, exists := components["action.combat_input"]; exists {
			unsupported("secondary combat input bindings are not executed")
		}
		if interaction, ok := components["rpg.interactable"].(map[string]any); ok {
			if interaction["range"] == nil {
				unsupported(
					"Ebitengine adapter does not apply the rpg.interactable.range default",
				)
			}
			if interaction["condition"] != nil {
				unsupported("interaction conditions are not executed")
			}
			for _, item := range anySlice(interaction["actions"]) {
				action, _ := item.(map[string]any)
				if action["type"] != "start_dialogue" {
					unsupported(fmt.Sprintf(
						"interaction action %q is not executed",
						action["type"],
					))
				}
			}
		}
		if combat, ok := components["action.combat"].(map[string]any); ok {
			if abilities := anySlice(combat["abilities"]); len(abilities) > 1 {
				unsupported("only the primary ability is executed")
			}
			if combat["primary"] == nil {
				unsupported(
					"Ebitengine adapter does not apply the default primary ability",
				)
			}
		}
		for _, componentName := range []string{
			"action.reaction",
			"action.dodge",
			"action.parry",
		} {
			component, ok := components[componentName].(map[string]any)
			if !ok {
				continue
			}
			requiredFields := map[string][]string{
				"action.reaction": {
					"hit_invulnerability",
					"flash_duration",
				},
				"action.dodge": {
					"duration",
					"distance",
					"invulnerability",
					"cooldown",
				},
				"action.parry": {
					"window",
					"perfect_window",
					"cooldown",
					"success_cooldown",
					"arc_degrees",
					"stagger",
					"perfect_stagger",
					"hitstop",
					"perfect_hitstop",
				},
			}[componentName]
			for _, field := range requiredFields {
				if component[field] == nil {
					unsupported(fmt.Sprintf(
						"Ebitengine adapter does not apply %s.%s default",
						componentName,
						field,
					))
				}
			}
		}

	case "stage":
		if err := validateStageSemantics(catalog, data, id); err != nil {
			return DefinitionValidation{}, err
		}
		for _, issue := range stageRuntimeCoverageIssues(catalog, data, id) {
			unsupported(issue)
		}
		for _, field := range []string{
			"encounters",
			"triggers",
			"completion",
			"metadata",
			"mode",
		} {
			if _, exists := data[field]; exists {
				unsupported(fmt.Sprintf(
					"stage field %q is not executed",
					field,
				))
			}
		}

	case "dialogue":
		if err := validateDialogueSemantics(catalog, data, id); err != nil {
			return DefinitionValidation{}, err
		}
		nodes := data["nodes"].(map[string]any)
		if len(nodes) > 1 {
			unsupported(
				"dialogue branching and non-start nodes are not executed",
			)
		}
		unsupported(
			"dialogue choices, conditions, and most actions are not executed",
		)

	case "quest":
		if err := validateQuestSemantics(catalog, data, id); err != nil {
			return DefinitionValidation{}, err
		}
		objectives := data["objectives"].([]any)
		if len(objectives) > 1 {
			unsupported("only the first supported objective is executed")
		}
		if _, exists := data["on_complete"]; exists {
			unsupported("quest completion reward actions are not executed")
		}

	case "locale":
		if err := validateLocaleSemantics(data, id); err != nil {
			return DefinitionValidation{}, err
		}

	case "asset":
		if err := validateAssetSemantics(data, id); err != nil {
			return DefinitionValidation{}, err
		}
		unsupported(
			"asset definitions are currently bound by embedded asset IDs",
		)

	case "sprite":
		if err := validateSpriteSemantics(catalog, data, id); err != nil {
			return DefinitionValidation{}, err
		}
		unsupported(
			"sprite clips are currently mapped by the renderer adapter",
		)

	case "encounter":
		if err := validateEncounterSemantics(catalog, data, id); err != nil {
			return DefinitionValidation{}, err
		}
		unsupported(
			"encounter definitions are catalogued but not executed",
		)

	case "item":
		if err := validateItemSemantics(catalog, data, id); err != nil {
			return DefinitionValidation{}, err
		}
		unsupported("item definitions are catalogued but not executed")

	case "projectile":
		if err := validateProjectileSemantics(catalog, data, id); err != nil {
			return DefinitionValidation{}, err
		}
		unsupported(
			"projectile definitions are catalogued but not executed",
		)

	case "shop":
		if err := validateShopSemantics(catalog, data, id); err != nil {
			return DefinitionValidation{}, err
		}
		unsupported("shop definitions are catalogued but not executed")

	case "status":
		if err := validateStatusSemantics(catalog, data, id); err != nil {
			return DefinitionValidation{}, err
		}
		unsupported(fmt.Sprintf(
			"%s definitions are catalogued but not executed",
			kind,
		))

	default:
		return DefinitionValidation{}, fmt.Errorf(
			"%s has unsupported content kind %q",
			id,
			kind,
		)
	}

	resultWarnings := make([]string, 0, len(warnings))
	for warning := range warnings {
		resultWarnings = append(resultWarnings, warning)
	}
	sort.Strings(resultWarnings)
	return DefinitionValidation{
		ID:           id,
		Kind:         kind,
		SchemaValid:  true,
		FullyApplied: fullyApplied,
		Warnings:     resultWarnings,
	}, nil
}
