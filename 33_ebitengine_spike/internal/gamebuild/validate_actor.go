package gamebuild

import (
	"fmt"
	"math"
	"strings"

	"practice_love2d/33_ebitengine_spike/internal/content"
)

func validateActorSemantics(
	catalog *content.Catalog,
	data map[string]any,
	id string,
) error {
	if err := optionalString(data["name"], id+".name"); err != nil {
		return err
	}
	if err := validateStringArray(data["tags"], id+".tags", false); err != nil {
		return err
	}
	components, err := requiredObject(data["components"], id+".components")
	if err != nil {
		return err
	}
	for name, raw := range components {
		if _, ok := raw.(map[string]any); !ok {
			return fmt.Errorf("%s.components.%s must be an object", id, name)
		}
	}
	if _, err := requiredObject(
		components["transform"],
		id+".components.transform",
	); err != nil {
		return err
	}
	if body, exists, err := optionalObject(
		components["body"],
		id+".components.body",
	); err != nil {
		return err
	} else if exists {
		if err := validateBody(body, id+".components.body"); err != nil {
			return err
		}
	}

	if health, exists, err := optionalObject(
		components["action.health"],
		id+".components.action.health",
	); err != nil {
		return err
	} else if exists {
		if err := requiredPositiveNumber(
			health["max"],
			id+".components.action.health.max",
		); err != nil {
			return err
		}
	}
	if movement, exists, err := optionalObject(
		components["movement.topdown"],
		id+".components.movement.topdown",
	); err != nil {
		return err
	} else if exists {
		if err := requiredPositiveNumber(
			movement["speed"],
			id+".components.movement.topdown.speed",
		); err != nil {
			return err
		}
	}
	if renderer, exists, err := optionalObject(
		components["render.sprite"],
		id+".components.render.sprite",
	); err != nil {
		return err
	} else if exists {
		spriteID, err := requiredString(
			renderer["sprite"],
			id+".components.render.sprite.sprite",
		)
		if err != nil {
			return err
		}
		if _, err := referencedDefinition(
			catalog,
			spriteID,
			"sprite",
			id+".components.render.sprite.sprite",
		); err != nil {
			return err
		}
		if err := optionalPositiveNumber(
			renderer["scale"],
			id+".components.render.sprite.scale",
		); err != nil {
			return err
		}
		if err := validateColor(
			renderer["tint"],
			id+".components.render.sprite.tint",
			false,
		); err != nil {
			return err
		}
	}
	combatAbilities := make(map[string]struct{})
	hasCombat := false
	if combat, exists, err := optionalObject(
		components["action.combat"],
		id+".components.action.combat",
	); err != nil {
		return err
	} else if exists {
		hasCombat = true
		team, err := requiredString(
			combat["team"],
			id+".components.action.combat.team",
		)
		if err != nil {
			return err
		}
		if strings.TrimSpace(team) == "" {
			return fmt.Errorf("%s action.combat team must not be empty", id)
		}
		abilities, err := requiredArray(
			combat["abilities"],
			id+".components.action.combat.abilities",
		)
		if err != nil {
			return err
		}
		for index, raw := range abilities {
			abilityID, err := requiredString(
				raw,
				fmt.Sprintf(
					"%s.components.action.combat.abilities[%d]",
					id,
					index,
				),
			)
			if err != nil {
				return err
			}
			if _, duplicate := combatAbilities[abilityID]; duplicate {
				return fmt.Errorf("%s duplicates ability %q", id, abilityID)
			}
			combatAbilities[abilityID] = struct{}{}
			if _, err := referencedDefinition(
				catalog,
				abilityID,
				"ability",
				id+".components.action.combat.abilities",
			); err != nil {
				return err
			}
		}
		if combat["primary"] != nil {
			primary, err := requiredString(
				combat["primary"],
				id+".components.action.combat.primary",
			)
			if err != nil {
				return err
			}
			if _, err := referencedDefinition(
				catalog,
				primary,
				"ability",
				id+".components.action.combat.primary",
			); err != nil {
				return err
			}
			if len(abilities) > 0 {
				if _, exists := combatAbilities[primary]; !exists {
					return fmt.Errorf(
						"%s action.combat primary %q is not in abilities",
						id,
						primary,
					)
				}
			}
		}
	}
	if behavior, exists, err := optionalObject(
		components["action.behavior_ai"],
		id+".components.action.behavior_ai",
	); err != nil {
		return err
	} else if exists {
		basePath := id + ".components.action.behavior_ai"
		if !hasCombat {
			return fmt.Errorf("%s requires action.combat", basePath)
		}
		if _, err := requiredString(
			behavior["target_tag"],
			basePath+".target_tag",
		); err != nil {
			return err
		}
		aggroRange, err := requiredPositiveNumberValue(
			behavior["aggro_range"],
			basePath+".aggro_range",
		)
		if err != nil {
			return err
		}
		patterns, err := requiredArray(
			behavior["patterns"],
			basePath+".patterns",
		)
		if err != nil {
			return err
		}
		if len(patterns) == 0 {
			return fmt.Errorf("%s.patterns must not be empty", basePath)
		}
		seenPatterns := make(map[string]struct{}, len(patterns))
		previousThreshold := 1.0
		for patternIndex, rawPattern := range patterns {
			patternPath := fmt.Sprintf(
				"%s.patterns[%d]",
				basePath,
				patternIndex,
			)
			pattern, err := requiredObject(rawPattern, patternPath)
			if err != nil {
				return err
			}
			patternID, err := requiredString(
				pattern["id"],
				patternPath+".id",
			)
			if err != nil {
				return err
			}
			if _, duplicate := seenPatterns[patternID]; duplicate {
				return fmt.Errorf(
					"%s.id duplicates AI pattern %q",
					patternPath,
					patternID,
				)
			}
			seenPatterns[patternID] = struct{}{}
			if patternIndex == 0 {
				if pattern["health_ratio_at_most"] != nil {
					return fmt.Errorf(
						"%s.health_ratio_at_most must be omitted "+
							"for the unconditional fallback",
						patternPath,
					)
				}
			} else {
				threshold, err := requiredNumber(
					pattern["health_ratio_at_most"],
					patternPath+".health_ratio_at_most",
				)
				if err != nil {
					return err
				}
				if threshold <= 0 || threshold >= previousThreshold {
					return fmt.Errorf(
						"%s.health_ratio_at_most must be positive "+
							"and lower than the previous threshold",
						patternPath,
					)
				}
				previousThreshold = threshold
			}
			movement, err := requiredObject(
				pattern["movement"],
				patternPath+".movement",
			)
			if err != nil {
				return err
			}
			minimumRange := 0.0
			if movement["minimum_range"] != nil {
				minimumRange, err = requiredNumber(
					movement["minimum_range"],
					patternPath+".movement.minimum_range",
				)
				if err != nil || minimumRange < 0 {
					if err != nil {
						return err
					}
					return fmt.Errorf(
						"%s.movement.minimum_range must not be negative",
						patternPath,
					)
				}
			}
			preferredRange, err := requiredNumber(
				movement["preferred_range"],
				patternPath+".movement.preferred_range",
			)
			if err != nil {
				return err
			}
			if preferredRange < 0 ||
				minimumRange > preferredRange ||
				preferredRange > aggroRange {
				return fmt.Errorf(
					"%s movement ranges must satisfy "+
						"0 <= minimum_range <= preferred_range <= aggro_range",
					patternPath,
				)
			}
			if err := optionalBoolean(
				movement["orbit"],
				patternPath+".movement.orbit",
			); err != nil {
				return err
			}
			attacks, err := requiredArray(
				pattern["attacks"],
				patternPath+".attacks",
			)
			if err != nil {
				return err
			}
			if len(attacks) == 0 {
				return fmt.Errorf(
					"%s.attacks must not be empty",
					patternPath,
				)
			}
			for attackIndex, rawAttack := range attacks {
				attackPath := fmt.Sprintf(
					"%s.attacks[%d]",
					patternPath,
					attackIndex,
				)
				attack, err := requiredObject(rawAttack, attackPath)
				if err != nil {
					return err
				}
				abilityID, err := requiredString(
					attack["ability"],
					attackPath+".ability",
				)
				if err != nil {
					return err
				}
				if _, err := referencedDefinition(
					catalog,
					abilityID,
					"ability",
					attackPath+".ability",
				); err != nil {
					return err
				}
				if _, included := combatAbilities[abilityID]; !included {
					return fmt.Errorf(
						"%s ability %q is not in action.combat.abilities",
						attackPath,
						abilityID,
					)
				}
				attackMinimum := 0.0
				if attack["minimum_range"] != nil {
					attackMinimum, err = requiredNumber(
						attack["minimum_range"],
						attackPath+".minimum_range",
					)
					if err != nil {
						return err
					}
				}
				attackMaximum, err := requiredPositiveNumberValue(
					attack["maximum_range"],
					attackPath+".maximum_range",
				)
				if err != nil {
					return err
				}
				if attackMinimum < 0 ||
					attackMinimum > attackMaximum ||
					attackMaximum > aggroRange {
					return fmt.Errorf(
						"%s ranges must satisfy "+
							"0 <= minimum_range <= maximum_range <= aggro_range",
						attackPath,
					)
				}
			}
		}
	}
	if reaction, exists, err := optionalObject(
		components["action.reaction"],
		id+".components.action.reaction",
	); err != nil {
		return err
	} else if exists {
		for _, field := range []string{
			"hit_invulnerability",
			"flash_duration",
		} {
			if err := optionalNonNegativeNumber(
				reaction[field],
				id+".components.action.reaction."+field,
			); err != nil {
				return err
			}
		}
	}
	if dodge, exists, err := optionalObject(
		components["action.dodge"],
		id+".components.action.dodge",
	); err != nil {
		return err
	} else if exists {
		if err := optionalString(
			dodge["input"],
			id+".components.action.dodge.input",
		); err != nil {
			return err
		}
		duration := 0.22
		if dodge["duration"] != nil {
			duration, err = requiredPositiveNumberValue(
				dodge["duration"],
				id+".components.action.dodge.duration",
			)
			if err != nil {
				return err
			}
		}
		if err := optionalPositiveNumber(
			dodge["distance"],
			id+".components.action.dodge.distance",
		); err != nil {
			return err
		}
		invulnerability := 0.18
		if dodge["invulnerability"] != nil {
			invulnerability, err = requiredNumber(
				dodge["invulnerability"],
				id+".components.action.dodge.invulnerability",
			)
			if err != nil {
				return err
			}
		}
		if invulnerability < 0 || invulnerability > duration {
			return fmt.Errorf(
				"%s action.dodge invulnerability must be between 0 and duration",
				id,
			)
		}
		if err := optionalNonNegativeNumber(
			dodge["cooldown"],
			id+".components.action.dodge.cooldown",
		); err != nil {
			return err
		}
	}
	if parry, exists, err := optionalObject(
		components["action.parry"],
		id+".components.action.parry",
	); err != nil {
		return err
	} else if exists {
		if err := optionalString(
			parry["input"],
			id+".components.action.parry.input",
		); err != nil {
			return err
		}
		window := 0.32
		if parry["window"] != nil {
			window, err = requiredPositiveNumberValue(
				parry["window"],
				id+".components.action.parry.window",
			)
			if err != nil {
				return err
			}
		}
		perfect := 0.12
		if parry["perfect_window"] != nil {
			perfect, err = requiredPositiveNumberValue(
				parry["perfect_window"],
				id+".components.action.parry.perfect_window",
			)
			if err != nil {
				return err
			}
		}
		if perfect > window {
			return fmt.Errorf(
				"%s action.parry perfect_window exceeds window",
				id,
			)
		}
		for _, field := range []string{
			"cooldown",
			"success_cooldown",
			"stagger",
			"perfect_stagger",
			"hitstop",
			"perfect_hitstop",
		} {
			if parry[field] == nil {
				continue
			}
			value, err := requiredNumber(
				parry[field],
				id+".components.action.parry."+field,
			)
			if err != nil {
				return err
			}
			if value < 0 {
				return fmt.Errorf(
					"%s.components.action.parry.%s must not be negative",
					id,
					field,
				)
			}
			if (field == "hitstop" || field == "perfect_hitstop") &&
				value > 0.25 {
				return fmt.Errorf(
					"%s.components.action.parry.%s must not exceed 0.25",
					id,
					field,
				)
			}
		}
		arc := 170.0
		if parry["arc_degrees"] != nil {
			arc, err = requiredNumber(
				parry["arc_degrees"],
				id+".components.action.parry.arc_degrees",
			)
			if err != nil {
				return err
			}
		}
		if arc <= 0 || arc > 360 {
			return fmt.Errorf(
				"%s action.parry arc_degrees must be greater than 0 and at most 360",
				id,
			)
		}
	}
	if stats, exists, err := optionalObject(
		components["rpg.stats"],
		id+".components.rpg.stats",
	); err != nil {
		return err
	} else if exists {
		path := id + ".components.rpg.stats"
		if err := rejectUnknownKeys(
			stats,
			path,
			"attack",
			"defense",
			"move_speed",
		); err != nil {
			return err
		}
		for _, name := range []string{"attack", "defense"} {
			if stats[name] == nil {
				continue
			}
			value, err := requiredNumber(stats[name], path+"."+name)
			if err != nil {
				return err
			}
			if value < 0 ||
				math.Trunc(value) != value ||
				value > float64(1<<31-1) {
				return fmt.Errorf(
					"%s.%s must be a non-negative portable integer",
					path,
					name,
				)
			}
		}
		if stats["move_speed"] != nil {
			value, err := requiredPositiveNumberValue(
				stats["move_speed"],
				path+".move_speed",
			)
			if err != nil {
				return err
			}
			if value > 16 {
				return fmt.Errorf("%s.move_speed must be at most 16", path)
			}
		}
	}
	if battler, exists, err := optionalObject(
		components["rpg.turn_battler"],
		id+".components.rpg.turn_battler",
	); err != nil {
		return err
	} else if exists {
		path := id + ".components.rpg.turn_battler"
		if components["action.health"] == nil {
			return fmt.Errorf("%s requires action.health", path)
		}
		if components["rpg.stats"] == nil {
			return fmt.Errorf("%s requires rpg.stats", path)
		}
		if err := rejectUnknownKeys(battler, path, "skills"); err != nil {
			return err
		}
		skills, err := requiredArray(battler["skills"], path+".skills")
		if err != nil {
			return err
		}
		if len(skills) == 0 {
			return fmt.Errorf("%s.skills must not be empty", path)
		}
		seen := make(map[string]struct{}, len(skills))
		for index, raw := range skills {
			skillPath := fmt.Sprintf("%s.skills[%d]", path, index)
			skillID, err := requiredString(raw, skillPath)
			if err != nil {
				return err
			}
			if _, duplicate := seen[skillID]; duplicate {
				return fmt.Errorf("%s duplicates skill %q", skillPath, skillID)
			}
			seen[skillID] = struct{}{}
			if _, err := referencedDefinition(
				catalog,
				skillID,
				"turn_skill",
				skillPath,
			); err != nil {
				return err
			}
		}
	}
	if equipment, exists, err := optionalObject(
		components["rpg.equipment"],
		id+".components.rpg.equipment",
	); err != nil {
		return err
	} else if exists {
		path := id + ".components.rpg.equipment"
		if components["rpg.stats"] == nil {
			return fmt.Errorf("%s requires rpg.stats", path)
		}
		if err := rejectUnknownKeys(
			equipment,
			path,
			"loadout",
			"slots",
		); err != nil {
			return err
		}
		if _, err := requiredString(
			equipment["loadout"],
			path+".loadout",
		); err != nil {
			return err
		}
		slots, err := requiredArray(equipment["slots"], path+".slots")
		if err != nil {
			return err
		}
		if len(slots) == 0 {
			return fmt.Errorf("%s.slots must not be empty", path)
		}
		seen := make(map[string]struct{}, len(slots))
		for index, raw := range slots {
			slotPath := fmt.Sprintf("%s.slots[%d]", path, index)
			slot, err := requiredString(raw, slotPath)
			if err != nil {
				return err
			}
			if _, duplicate := seen[slot]; duplicate {
				return fmt.Errorf("%s duplicates slot %q", slotPath, slot)
			}
			seen[slot] = struct{}{}
		}
	}
	if interaction, exists, err := optionalObject(
		components["rpg.interactable"],
		id+".components.rpg.interactable",
	); err != nil {
		return err
	} else if exists {
		path := id + ".components.rpg.interactable"
		if err := rejectUnknownKeys(
			interaction,
			path,
			"input",
			"range",
			"prompt",
			"prompt_key",
			"condition",
			"actions",
			"pages",
		); err != nil {
			return err
		}
		if err := optionalString(
			interaction["input"],
			path+".input",
		); err != nil {
			return err
		}
		if err := optionalPositiveNumber(
			interaction["range"],
			path+".range",
		); err != nil {
			return err
		}
		for _, field := range []string{"prompt", "prompt_key"} {
			if err := optionalString(
				interaction[field],
				path+"."+field,
			); err != nil {
				return err
			}
		}
		if interaction["condition"] != nil {
			if err := validateCondition(
				catalog,
				interaction["condition"],
				path+".condition",
			); err != nil {
				return err
			}
		}
		pages, pagesExist, err := optionalArray(
			interaction["pages"],
			path+".pages",
		)
		if err != nil {
			return err
		}
		if pagesExist && len(pages) == 0 {
			return fmt.Errorf("%s.pages must not be empty", path)
		}
		seenPages := make(map[string]struct{}, len(pages))
		for index, raw := range pages {
			pagePath := fmt.Sprintf("%s.pages[%d]", path, index)
			page, err := requiredObject(raw, pagePath)
			if err != nil {
				return err
			}
			if err := rejectUnknownKeys(
				page,
				pagePath,
				"id",
				"condition",
				"input",
				"range",
				"prompt",
				"prompt_key",
				"actions",
			); err != nil {
				return err
			}
			pageID, err := requiredString(page["id"], pagePath+".id")
			if err != nil {
				return err
			}
			if _, duplicate := seenPages[pageID]; duplicate {
				return fmt.Errorf(
					"%s.id duplicates page %q",
					pagePath,
					pageID,
				)
			}
			seenPages[pageID] = struct{}{}
			if page["condition"] != nil {
				if err := validateCondition(
					catalog,
					page["condition"],
					pagePath+".condition",
				); err != nil {
					return err
				}
			}
			if err := optionalString(
				page["input"],
				pagePath+".input",
			); err != nil {
				return err
			}
			if err := optionalPositiveNumber(
				page["range"],
				pagePath+".range",
			); err != nil {
				return err
			}
			for _, field := range []string{"prompt", "prompt_key"} {
				if err := optionalString(
					page[field],
					pagePath+"."+field,
				); err != nil {
					return err
				}
			}
			if err := validateActions(
				catalog,
				page["actions"],
				pagePath+".actions",
				true,
			); err != nil {
				return err
			}
		}
		if interaction["actions"] != nil || !pagesExist {
			if err := validateActions(
				catalog,
				interaction["actions"],
				path+".actions",
				true,
			); err != nil {
				return err
			}
		}
	}
	return nil
}

func validateBody(body map[string]any, path string) error {
	for _, field := range []string{"static", "solid"} {
		if err := optionalBoolean(body[field], path+"."+field); err != nil {
			return err
		}
	}
	if err := optionalString(
		body["collision_layer"],
		path+".collision_layer",
	); err != nil {
		return err
	}
	if err := validateStringArray(
		body["collision_mask"],
		path+".collision_mask",
		false,
	); err != nil {
		return err
	}
	shape, err := requiredString(body["shape"], path+".shape")
	if err != nil {
		return err
	}
	switch shape {
	case "circle":
		return requiredPositiveNumber(body["radius"], path+".radius")
	case "rectangle":
		if err := requiredPositiveNumber(body["width"], path+".width"); err != nil {
			return err
		}
		return requiredPositiveNumber(body["height"], path+".height")
	case "polygon":
		points, err := requiredArray(body["points"], path+".points")
		if err != nil {
			return err
		}
		if len(points) < 3 {
			return fmt.Errorf("%s.points requires at least three points", path)
		}
		for index, raw := range points {
			point, err := requiredObject(
				raw,
				fmt.Sprintf("%s.points[%d]", path, index),
			)
			if err != nil {
				return err
			}
			for _, axis := range []string{"x", "y"} {
				if _, err := requiredNumber(
					point[axis],
					fmt.Sprintf("%s.points[%d].%s", path, index, axis),
				); err != nil {
					return err
				}
			}
		}
		return nil
	default:
		return fmt.Errorf("%s.shape has unsupported value %q", path, shape)
	}
}
