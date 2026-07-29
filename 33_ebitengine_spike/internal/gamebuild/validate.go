package gamebuild

import (
	"encoding/json"
	"fmt"
	"sort"

	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/sim"
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
		activation, _ := data["activation"].([]any)
		if (hitbox == nil || len(effects) == 0) && len(activation) == 0 {
			unsupported(
				"ability has no executable hitbox/effects or activation",
			)
		}
		for _, item := range activation {
			action, _ := item.(map[string]any)
			if action["type"] != "spawn_projectile" {
				unsupported(fmt.Sprintf(
					"ability activation %q is not executed",
					action["type"],
				))
			}
		}
		if _, exists := data["visual"]; exists {
			unsupported(
				"ability visual metadata is not data-driven yet",
			)
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
			"transform":           true,
			"body":                true,
			"control.player":      true,
			"motion.facing":       true,
			"motion.kinematics":   true,
			"movement.topdown":    true,
			"movement.platformer": true,
			"render.sprite":       true,
			"action.health":       true,
			"action.reaction":     true,
			"action.dodge":        true,
			"action.parry":        true,
			"action.combat":       true,
			"action.combat_input": true,
			"action.status":       true,
			"action.chase_ai":     true,
			"rpg.interactable":    true,
		}
		for component := range components {
			if !supported[component] {
				unsupported(fmt.Sprintf(
					"actor component %q is not executed",
					component,
				))
			}
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
		checkEncounterActions := func(value any, scope string) {
			for _, raw := range anySlice(value) {
				action, _ := raw.(map[string]any)
				switch action["type"] {
				case "emit":
					name, _ := action["name"].(string)
					if sim.IsReservedEventType(sim.EventType(name)) {
						unsupported(fmt.Sprintf(
							"%s emit name %q is reserved by the engine",
							scope,
							name,
						))
					}
				case "apply_status":
				default:
					unsupported(fmt.Sprintf(
						"%s action %q is not executed",
						scope,
						action["type"],
					))
				}
			}
		}
		checkEncounterActions(data["on_complete"], "encounter completion")
		for _, rawWave := range anySlice(data["waves"]) {
			wave, _ := rawWave.(map[string]any)
			checkEncounterActions(wave["on_start"], "wave start")
			checkEncounterActions(wave["on_complete"], "wave completion")
			for _, rawPhase := range anySlice(wave["boss_phases"]) {
				phase, _ := rawPhase.(map[string]any)
				checkEncounterActions(phase["actions"], "boss phase")
			}
		}

	case "item":
		if err := validateItemSemantics(catalog, data, id); err != nil {
			return DefinitionValidation{}, err
		}
		unsupported("item definitions are catalogued but not executed")

	case "projectile":
		if err := validateProjectileSemantics(catalog, data, id); err != nil {
			return DefinitionValidation{}, err
		}
		for _, item := range anySlice(data["effects"]) {
			effect, _ := item.(map[string]any)
			switch effect["type"] {
			case "damage", "stagger", "apply_status", "knockback", "hitstop":
			default:
				unsupported(fmt.Sprintf(
					"projectile effect %q is not executed",
					effect["type"],
				))
			}
		}

	case "shop":
		if err := validateShopSemantics(catalog, data, id); err != nil {
			return DefinitionValidation{}, err
		}
		unsupported("shop definitions are catalogued but not executed")

	case "status":
		if err := validateStatusSemantics(catalog, data, id); err != nil {
			return DefinitionValidation{}, err
		}
		for _, field := range []string{"on_apply", "on_expire"} {
			if len(anySlice(data[field])) != 0 {
				unsupported(fmt.Sprintf(
					"status field %q is not executed",
					field,
				))
			}
		}
		for _, item := range anySlice(data["tick_actions"]) {
			action, _ := item.(map[string]any)
			if action["type"] != "damage" {
				unsupported(fmt.Sprintf(
					"status tick action %q is not executed",
					action["type"],
				))
			}
		}

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
