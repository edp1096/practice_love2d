package gamebuild

import (
	"fmt"
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
	if combat, exists, err := optionalObject(
		components["action.combat"],
		id+".components.action.combat",
	); err != nil {
		return err
	} else if exists {
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
		seen := make(map[string]struct{}, len(abilities))
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
			if _, duplicate := seen[abilityID]; duplicate {
				return fmt.Errorf("%s duplicates ability %q", id, abilityID)
			}
			seen[abilityID] = struct{}{}
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
				if _, exists := seen[primary]; !exists {
					return fmt.Errorf(
						"%s action.combat primary %q is not in abilities",
						id,
						primary,
					)
				}
			}
		}
	}
	if chase, exists, err := optionalObject(
		components["action.chase_ai"],
		id+".components.action.chase_ai",
	); err != nil {
		return err
	} else if exists {
		if _, err := requiredString(
			chase["target_tag"],
			id+".components.action.chase_ai.target_tag",
		); err != nil {
			return err
		}
		if err := requiredPositiveNumber(
			chase["aggro_range"],
			id+".components.action.chase_ai.aggro_range",
		); err != nil {
			return err
		}
		if err := optionalPositiveNumber(
			chase["attack_distance"],
			id+".components.action.chase_ai.attack_distance",
		); err != nil {
			return err
		}
		if attack, ok := number(chase["attack_distance"]); ok {
			aggro, _ := number(chase["aggro_range"])
			if attack > aggro {
				return fmt.Errorf(
					"%s action.chase_ai attack_distance exceeds aggro_range",
					id,
				)
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
	if interaction, exists, err := optionalObject(
		components["rpg.interactable"],
		id+".components.rpg.interactable",
	); err != nil {
		return err
	} else if exists {
		if err := optionalPositiveNumber(
			interaction["range"],
			id+".components.rpg.interactable.range",
		); err != nil {
			return err
		}
		if interaction["condition"] != nil {
			if err := validateCondition(
				catalog,
				interaction["condition"],
				id+".components.rpg.interactable.condition",
			); err != nil {
				return err
			}
		}
		if err := validateActions(
			catalog,
			interaction["actions"],
			id+".components.rpg.interactable.actions",
			true,
		); err != nil {
			return err
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
