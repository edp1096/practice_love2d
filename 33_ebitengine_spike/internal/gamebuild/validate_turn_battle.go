package gamebuild

import (
	"fmt"
	"math"

	"practice_love2d/33_ebitengine_spike/internal/content"
)

func validateTurnSkillSemantics(data map[string]any, id string) error {
	if err := rejectUnknownKeys(
		data,
		id,
		"schema_version",
		"kind",
		"id",
		"name",
		"name_key",
		"effect",
		"target",
		"power",
	); err != nil {
		return err
	}
	if err := requireNameOrKey(data, id); err != nil {
		return err
	}
	effect, err := requiredString(data["effect"], id+".effect")
	if err != nil {
		return err
	}
	if err := requiredEnum(data["effect"], id+".effect", "damage", "heal"); err != nil {
		return err
	}
	target, err := requiredString(data["target"], id+".target")
	if err != nil {
		return err
	}
	if err := requiredEnum(data["target"], id+".target", "enemy", "self"); err != nil {
		return err
	}
	if effect == "damage" && target != "enemy" {
		return fmt.Errorf("%s damage skills must target enemy", id)
	}
	if effect == "heal" && target != "self" {
		return fmt.Errorf("%s heal skills must target self", id)
	}
	power, err := requiredPositiveNumberValue(data["power"], id+".power")
	if err != nil {
		return err
	}
	if math.Trunc(power) != power {
		return fmt.Errorf("%s.power must be an integer", id)
	}
	return nil
}

func validateTurnBattleSemantics(
	catalog *content.Catalog,
	data map[string]any,
	id string,
) error {
	if err := rejectUnknownKeys(
		data,
		id,
		"schema_version",
		"kind",
		"id",
		"name",
		"name_key",
		"enemies",
		"allow_escape",
		"repeatable",
		"on_start",
		"on_victory",
		"on_escape",
		"on_defeat",
	); err != nil {
		return err
	}
	if err := requireNameOrKey(data, id); err != nil {
		return err
	}
	for _, field := range []string{"allow_escape", "repeatable"} {
		if err := optionalBoolean(data[field], id+"."+field); err != nil {
			return err
		}
	}
	enemies, err := requiredArray(data["enemies"], id+".enemies")
	if err != nil {
		return err
	}
	if len(enemies) == 0 {
		return fmt.Errorf("%s.enemies must not be empty", id)
	}
	seen := make(map[string]struct{}, len(enemies))
	for index, raw := range enemies {
		path := fmt.Sprintf("%s.enemies[%d]", id, index)
		enemy, err := requiredObject(raw, path)
		if err != nil {
			return err
		}
		if err := rejectUnknownKeys(enemy, path, "id", "actor"); err != nil {
			return err
		}
		enemyID, err := requiredString(enemy["id"], path+".id")
		if err != nil {
			return err
		}
		if _, duplicate := seen[enemyID]; duplicate {
			return fmt.Errorf("%s.id duplicates enemy %q", path, enemyID)
		}
		seen[enemyID] = struct{}{}
		actor, err := referenceField(
			catalog,
			enemy,
			"actor",
			"actor",
			path,
			true,
		)
		if err != nil {
			return err
		}
		components, _ := actor["components"].(map[string]any)
		for _, component := range []string{
			"action.health",
			"rpg.stats",
			"rpg.turn_battler",
		} {
			if components[component] == nil {
				return fmt.Errorf(
					"%s.actor %q requires component %q",
					path,
					actor["id"],
					component,
				)
			}
		}
	}
	for _, field := range []string{
		"on_start",
		"on_victory",
		"on_escape",
		"on_defeat",
	} {
		if err := validateActions(
			catalog,
			data[field],
			id+"."+field,
			false,
		); err != nil {
			return err
		}
	}
	return nil
}

func requireNameOrKey(data map[string]any, path string) error {
	name := ""
	nameKey := ""
	var err error
	if data["name"] != nil {
		name, err = requiredString(data["name"], path+".name")
		if err != nil {
			return err
		}
	}
	if data["name_key"] != nil {
		nameKey, err = requiredString(data["name_key"], path+".name_key")
		if err != nil {
			return err
		}
	}
	if name == "" && nameKey == "" {
		return fmt.Errorf("%s requires name or name_key", path)
	}
	return nil
}
