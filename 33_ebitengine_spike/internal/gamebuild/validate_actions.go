package gamebuild

import (
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/content"
)

func validateActions(
	catalog *content.Catalog,
	value any,
	path string,
	required bool,
) error {
	items, exists, err := optionalArray(value, path)
	if err != nil {
		return err
	}
	if !exists {
		if required {
			return fmt.Errorf("%s is required", path)
		}
		return nil
	}
	if required && len(items) == 0 {
		return fmt.Errorf("%s must not be empty", path)
	}
	for index, raw := range items {
		if err := validateAction(
			catalog,
			raw,
			fmt.Sprintf("%s[%d]", path, index),
		); err != nil {
			return err
		}
	}
	return nil
}

func validateAction(
	catalog *content.Catalog,
	value any,
	path string,
) error {
	action, err := requiredObject(value, path)
	if err != nil {
		return err
	}
	actionType, err := requiredString(action["type"], path+".type")
	if err != nil {
		return err
	}
	switch actionType {
	case "close_dialogue", "close_shop", "finish_game", "save_game":
		return rejectUnknownKeys(action, path, "type")
	case "damage", "heal":
		if err := rejectUnknownKeys(action, path, "type", "amount"); err != nil {
			return err
		}
		return requiredPositiveNumber(action["amount"], path+".amount")
	case "revive":
		if err := rejectUnknownKeys(action, path, "type", "amount"); err != nil {
			return err
		}
		return optionalPositiveNumber(action["amount"], path+".amount")
	case "stagger", "invulnerable":
		if err := rejectUnknownKeys(action, path, "type", "duration"); err != nil {
			return err
		}
		return requiredPositiveNumber(action["duration"], path+".duration")
	case "hitstop":
		if err := rejectUnknownKeys(action, path, "type", "duration"); err != nil {
			return err
		}
		duration, err := requiredPositiveNumberValue(
			action["duration"],
			path+".duration",
		)
		if err != nil {
			return err
		}
		if duration > 0.25 {
			return fmt.Errorf("%s.duration must not exceed 0.25", path)
		}
		return nil
	case "knockback":
		if err := rejectUnknownKeys(
			action,
			path,
			"type",
			"distance",
			"duration",
		); err != nil {
			return err
		}
		if err := requiredPositiveNumber(
			action["distance"],
			path+".distance",
		); err != nil {
			return err
		}
		return requiredPositiveNumber(action["duration"], path+".duration")
	case "camera_shake":
		if err := rejectUnknownKeys(
			action,
			path,
			"type",
			"duration",
			"magnitude",
			"frequency",
		); err != nil {
			return err
		}
		duration, err := requiredPositiveNumberValue(
			action["duration"],
			path+".duration",
		)
		if err != nil {
			return err
		}
		if duration > 1 {
			return fmt.Errorf("%s.duration must not exceed 1", path)
		}
		magnitude, err := requiredPositiveNumberValue(
			action["magnitude"],
			path+".magnitude",
		)
		if err != nil {
			return err
		}
		if magnitude > 64 {
			return fmt.Errorf("%s.magnitude must not exceed 64", path)
		}
		if frequency, ok := number(action["frequency"]); ok {
			if frequency <= 0 || frequency > 120 {
				return fmt.Errorf(
					"%s.frequency must be positive and at most 120",
					path,
				)
			}
		} else if action["frequency"] != nil {
			return fmt.Errorf("%s.frequency must be a finite number", path)
		}
		return nil
	case "emit":
		if err := rejectUnknownKeys(action, path, "type", "name", "data"); err != nil {
			return err
		}
		if _, err := requiredString(action["name"], path+".name"); err != nil {
			return err
		}
		if _, _, err := optionalObject(action["data"], path+".data"); err != nil {
			return err
		}
		return nil
	case "set_flag":
		if err := rejectUnknownKeys(action, path, "type", "name", "value"); err != nil {
			return err
		}
		if _, err := requiredString(action["name"], path+".name"); err != nil {
			return err
		}
		return optionalBoolean(action["value"], path+".value")
	case "clear_flag":
		if err := rejectUnknownKeys(action, path, "type", "name"); err != nil {
			return err
		}
		_, err := requiredString(action["name"], path+".name")
		return err
	case "add_currency", "spend_currency":
		if err := rejectUnknownKeys(
			action,
			path,
			"type",
			"amount",
			"reason",
		); err != nil {
			return err
		}
		if err := requiredNonNegativeInteger(action["amount"], path+".amount"); err != nil {
			return err
		}
		return optionalString(action["reason"], path+".reason")
	case "give_item", "take_item":
		if err := rejectUnknownKeys(
			action,
			path,
			"type",
			"item",
			"amount",
		); err != nil {
			return err
		}
		if _, err := referenceField(
			catalog,
			action,
			"item",
			"item",
			path,
			true,
		); err != nil {
			return err
		}
		return optionalPositiveInteger(action["amount"], path+".amount")
	case "use_item":
		if err := rejectUnknownKeys(action, path, "type", "item"); err != nil {
			return err
		}
		_, err := referenceField(
			catalog,
			action,
			"item",
			"item",
			path,
			true,
		)
		return err
	case "equip_item":
		if err := rejectUnknownKeys(action, path, "type", "item"); err != nil {
			return err
		}
		item, err := referenceField(
			catalog,
			action,
			"item",
			"item",
			path,
			true,
		)
		if err != nil {
			return err
		}
		if _, ok := item["equipment"].(map[string]any); !ok {
			return fmt.Errorf("%s.item references a non-equipment item", path)
		}
		return nil
	case "unequip_slot":
		if err := rejectUnknownKeys(action, path, "type", "slot"); err != nil {
			return err
		}
		_, err := requiredString(action["slot"], path+".slot")
		return err
	case "start_quest":
		if err := rejectUnknownKeys(action, path, "type", "quest"); err != nil {
			return err
		}
		_, err := referenceField(
			catalog,
			action,
			"quest",
			"quest",
			path,
			true,
		)
		return err
	case "start_dialogue":
		if err := rejectUnknownKeys(action, path, "type", "dialogue"); err != nil {
			return err
		}
		_, err := referenceField(
			catalog,
			action,
			"dialogue",
			"dialogue",
			path,
			true,
		)
		return err
	case "set_locale":
		if err := rejectUnknownKeys(action, path, "type", "locale"); err != nil {
			return err
		}
		_, err := referenceField(
			catalog,
			action,
			"locale",
			"locale",
			path,
			true,
		)
		return err
	case "open_shop":
		if err := rejectUnknownKeys(action, path, "type", "shop"); err != nil {
			return err
		}
		_, err := referenceField(
			catalog,
			action,
			"shop",
			"shop",
			path,
			true,
		)
		return err
	case "buy_item", "sell_item":
		return validateTradeAction(catalog, action, path, actionType)
	case "spawn_projectile":
		if err := rejectUnknownKeys(action, path, "type", "projectile"); err != nil {
			return err
		}
		_, err := referenceField(
			catalog,
			action,
			"projectile",
			"projectile",
			path,
			true,
		)
		return err
	case "apply_status":
		if err := rejectUnknownKeys(
			action,
			path,
			"type",
			"status",
			"duration",
			"stacks",
		); err != nil {
			return err
		}
		if _, err := referenceField(
			catalog,
			action,
			"status",
			"status",
			path,
			true,
		); err != nil {
			return err
		}
		if err := optionalPositiveNumber(action["duration"], path+".duration"); err != nil {
			return err
		}
		return optionalPositiveInteger(action["stacks"], path+".stacks")
	case "remove_status":
		if err := rejectUnknownKeys(action, path, "type", "status"); err != nil {
			return err
		}
		_, err := referenceField(
			catalog,
			action,
			"status",
			"status",
			path,
			true,
		)
		return err
	case "start_encounter":
		if err := rejectUnknownKeys(action, path, "type", "encounter"); err != nil {
			return err
		}
		_, err := requiredString(action["encounter"], path+".encounter")
		return err
	default:
		return fmt.Errorf("%s.type has unknown action %q", path, actionType)
	}
}

func validateTradeAction(
	catalog *content.Catalog,
	action map[string]any,
	path string,
	actionType string,
) error {
	if err := rejectUnknownKeys(
		action,
		path,
		"type",
		"shop",
		"item",
		"quantity",
	); err != nil {
		return err
	}
	shop, err := referenceField(
		catalog,
		action,
		"shop",
		"shop",
		path,
		true,
	)
	if err != nil {
		return err
	}
	itemID, err := requiredString(action["item"], path+".item")
	if err != nil {
		return err
	}
	if _, err := referencedDefinition(catalog, itemID, "item", path+".item"); err != nil {
		return err
	}
	priceField := "buy_price"
	if actionType == "sell_item" {
		priceField = "sell_price"
	}
	available := false
	for _, raw := range anySlice(shop["offers"]) {
		offer, _ := raw.(map[string]any)
		if offer["item"] == itemID && offer[priceField] != nil {
			available = true
			break
		}
	}
	if !available {
		return fmt.Errorf(
			"%s.item %q is unavailable for %s",
			path,
			itemID,
			actionType,
		)
	}
	return optionalPositiveInteger(action["quantity"], path+".quantity")
}

func validateCondition(
	catalog *content.Catalog,
	value any,
	path string,
) error {
	condition, err := requiredObject(value, path)
	if err != nil {
		return err
	}
	conditionType, err := requiredString(condition["type"], path+".type")
	if err != nil {
		return err
	}
	switch conditionType {
	case "always":
		return rejectUnknownKeys(condition, path, "type")
	case "all", "any":
		if err := rejectUnknownKeys(condition, path, "type", "conditions"); err != nil {
			return err
		}
		children, err := requiredArray(condition["conditions"], path+".conditions")
		if err != nil {
			return err
		}
		for index, child := range children {
			if err := validateCondition(
				catalog,
				child,
				fmt.Sprintf("%s.conditions[%d]", path, index),
			); err != nil {
				return err
			}
		}
		return nil
	case "not":
		if err := rejectUnknownKeys(condition, path, "type", "condition"); err != nil {
			return err
		}
		return validateCondition(catalog, condition["condition"], path+".condition")
	case "locale_is":
		if err := rejectUnknownKeys(condition, path, "type", "locale"); err != nil {
			return err
		}
		_, err := referenceField(
			catalog,
			condition,
			"locale",
			"locale",
			path,
			true,
		)
		return err
	case "shop_active":
		if err := rejectUnknownKeys(condition, path, "type", "shop"); err != nil {
			return err
		}
		_, err := referenceField(
			catalog,
			condition,
			"shop",
			"shop",
			path,
			false,
		)
		return err
	case "item_equipped":
		if err := rejectUnknownKeys(
			condition,
			path,
			"type",
			"item",
			"slot",
		); err != nil {
			return err
		}
		if _, err := referenceField(
			catalog,
			condition,
			"item",
			"item",
			path,
			true,
		); err != nil {
			return err
		}
		return optionalString(condition["slot"], path+".slot")
	case "health_at_most":
		if err := rejectUnknownKeys(condition, path, "type", "value"); err != nil {
			return err
		}
		_, err := requiredNumber(condition["value"], path+".value")
		return err
	case "has_item":
		if err := rejectUnknownKeys(
			condition,
			path,
			"type",
			"item",
			"amount",
		); err != nil {
			return err
		}
		if _, err := referenceField(
			catalog,
			condition,
			"item",
			"item",
			path,
			true,
		); err != nil {
			return err
		}
		return optionalPositiveInteger(condition["amount"], path+".amount")
	case "quest_state":
		if err := rejectUnknownKeys(
			condition,
			path,
			"type",
			"quest",
			"state",
		); err != nil {
			return err
		}
		if _, err := referenceField(
			catalog,
			condition,
			"quest",
			"quest",
			path,
			true,
		); err != nil {
			return err
		}
		return requiredEnum(
			condition["state"],
			path+".state",
			"inactive",
			"active",
			"completed",
		)
	case "quest_objective":
		if err := rejectUnknownKeys(
			condition,
			path,
			"type",
			"quest",
			"objective",
			"count",
		); err != nil {
			return err
		}
		quest, err := referenceField(
			catalog,
			condition,
			"quest",
			"quest",
			path,
			true,
		)
		if err != nil {
			return err
		}
		objectiveID, err := requiredString(
			condition["objective"],
			path+".objective",
		)
		if err != nil {
			return err
		}
		found := false
		for _, raw := range anySlice(quest["objectives"]) {
			objective, _ := raw.(map[string]any)
			if objective["id"] == objectiveID {
				found = true
				break
			}
		}
		if !found {
			return fmt.Errorf(
				"%s.objective references missing objective %q",
				path,
				objectiveID,
			)
		}
		return optionalPositiveInteger(condition["count"], path+".count")
	case "dialogue_active":
		if err := rejectUnknownKeys(condition, path, "type", "dialogue"); err != nil {
			return err
		}
		_, err := referenceField(
			catalog,
			condition,
			"dialogue",
			"dialogue",
			path,
			false,
		)
		return err
	case "currency_at_least":
		if err := rejectUnknownKeys(condition, path, "type", "amount"); err != nil {
			return err
		}
		return requiredNonNegativeInteger(condition["amount"], path+".amount")
	case "flag":
		if err := rejectUnknownKeys(
			condition,
			path,
			"type",
			"name",
			"value",
		); err != nil {
			return err
		}
		if _, err := requiredString(condition["name"], path+".name"); err != nil {
			return err
		}
		return optionalBoolean(condition["value"], path+".value")
	case "game_flow_state":
		if err := rejectUnknownKeys(condition, path, "type", "state"); err != nil {
			return err
		}
		return requiredEnum(
			condition["state"],
			path+".state",
			"started",
			"completed",
		)
	case "has_status":
		if err := rejectUnknownKeys(
			condition,
			path,
			"type",
			"status",
			"stacks_at_least",
		); err != nil {
			return err
		}
		if _, err := referenceField(
			catalog,
			condition,
			"status",
			"status",
			path,
			true,
		); err != nil {
			return err
		}
		return optionalPositiveInteger(
			condition["stacks_at_least"],
			path+".stacks_at_least",
		)
	case "encounter_state":
		if err := rejectUnknownKeys(
			condition,
			path,
			"type",
			"encounter",
			"state",
		); err != nil {
			return err
		}
		if _, err := requiredString(
			condition["encounter"],
			path+".encounter",
		); err != nil {
			return err
		}
		return requiredEnum(
			condition["state"],
			path+".state",
			"idle",
			"pending",
			"active",
			"completed",
			"failed",
		)
	default:
		return fmt.Errorf("%s.type has unknown condition %q", path, conditionType)
	}
}
