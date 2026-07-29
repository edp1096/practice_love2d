package rulesruntime

import (
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

func (executor *Executor) validateItemRules() error {
	if len(executor.rules.Items) != len(executor.config.Items) {
		return fmt.Errorf(
			"rules define %d items; campaign config defines %d",
			len(executor.rules.Items),
			len(executor.config.Items),
		)
	}
	for index, definition := range executor.config.Items {
		rule := executor.rules.Items[index]
		if rule.ID != definition.ID {
			return fmt.Errorf(
				"rule item %d is %q; canonical campaign item is %q",
				index,
				rule.ID,
				definition.ID,
			)
		}
		if rule.StackLimit <= 0 ||
			int64(rule.StackLimit) != definition.MaxQuantity {
			return fmt.Errorf(
				"item %q stack limit %d does not match campaign maximum %d",
				rule.ID,
				rule.StackLimit,
				definition.MaxQuantity,
			)
		}
		if !validPersistentInt(rule.Value) {
			return fmt.Errorf("item %q has invalid value %d", rule.ID, rule.Value)
		}
		ruleSlot := ""
		if rule.Equipment != nil {
			ruleSlot = rule.Equipment.Slot
		}
		if ruleSlot != definition.EquipmentSlot {
			return fmt.Errorf(
				"item %q equipment slot %q does not match campaign slot %q",
				rule.ID,
				ruleSlot,
				definition.EquipmentSlot,
			)
		}
		if err := executor.validateActionList(
			rule.Effects,
			fmt.Sprintf("item %q effects", rule.ID),
		); err != nil {
			return err
		}
	}
	return nil
}

func (executor *Executor) validateQuestRules() error {
	if len(executor.rules.Quests) != len(executor.config.Quests) {
		return fmt.Errorf(
			"rules define %d quests; campaign config defines %d",
			len(executor.rules.Quests),
			len(executor.config.Quests),
		)
	}
	for index, definition := range executor.config.Quests {
		rule := executor.rules.Quests[index]
		if rule.ID != definition.ID {
			return fmt.Errorf(
				"rule quest %d is %q; canonical campaign quest is %q",
				index,
				rule.ID,
				definition.ID,
			)
		}
		if rule.InitiallyActive != definition.InitiallyActive {
			return fmt.Errorf(
				"quest %q initially_active does not match campaign config",
				rule.ID,
			)
		}
		if len(rule.Objectives) != len(definition.Objectives) {
			return fmt.Errorf(
				"quest %q rule has %d objectives; campaign has %d",
				rule.ID,
				len(rule.Objectives),
				len(definition.Objectives),
			)
		}
		filters := make(map[string]string, len(rule.Objectives))
		seenObjectives := make(map[string]struct{}, len(rule.Objectives))
		for _, objective := range rule.Objectives {
			if _, duplicate := seenObjectives[objective.ID]; duplicate {
				return fmt.Errorf(
					"quest %q has duplicate objective rule %q",
					rule.ID,
					objective.ID,
				)
			}
			seenObjectives[objective.ID] = struct{}{}
			configObjective, _, err := findObjectiveDefinition(
				definition,
				objective.ID,
			)
			if err != nil {
				return err
			}
			if objective.Count <= 0 ||
				int64(objective.Count) != configObjective.Required {
				return fmt.Errorf(
					"quest %q objective %q count %d does not match "+
						"campaign requirement %d",
					rule.ID,
					objective.ID,
					objective.Count,
					configObjective.Required,
				)
			}
			if objective.Event == "" || objective.ActorID == "" {
				return fmt.Errorf(
					"quest %q objective %q requires event and actor id",
					rule.ID,
					objective.ID,
				)
			}
			filter := objective.Event + "\x00" + objective.ActorID
			if previous, duplicate := filters[filter]; duplicate {
				return fmt.Errorf(
					"quest %q objectives %q and %q have duplicate "+
						"event/actor filters",
					rule.ID,
					previous,
					objective.ID,
				)
			}
			filters[filter] = objective.ID
		}
		if err := executor.validateActionList(
			rule.OnStart,
			fmt.Sprintf("quest %q on_start", rule.ID),
		); err != nil {
			return err
		}
		if err := executor.validateActionList(
			rule.OnComplete,
			fmt.Sprintf("quest %q on_complete", rule.ID),
		); err != nil {
			return err
		}
	}
	return nil
}

func (executor *Executor) validateShopRules() error {
	for _, shop := range executor.rules.Shops {
		offerIDs := make(map[string]struct{}, len(shop.Offers))
		for _, offer := range shop.Offers {
			if _, duplicate := offerIDs[offer.ItemID]; duplicate {
				return fmt.Errorf(
					"shop %q has duplicate offer for item %q",
					shop.ID,
					offer.ItemID,
				)
			}
			offerIDs[offer.ItemID] = struct{}{}
			if _, _, err := findItemDefinition(
				executor.config,
				offer.ItemID,
			); err != nil {
				return fmt.Errorf("shop %q: %w", shop.ID, err)
			}
			if !offer.CanBuy && !offer.CanSell {
				return fmt.Errorf(
					"shop %q offer %q is neither buyable nor sellable",
					shop.ID,
					offer.ItemID,
				)
			}
			if !validPersistentInt(offer.BuyPrice) ||
				!validPersistentInt(offer.SellPrice) {
				return fmt.Errorf(
					"shop %q offer %q has a price outside the "+
						"persistent integer range",
					shop.ID,
					offer.ItemID,
				)
			}
		}
	}
	return nil
}

func (executor *Executor) validateInteractionRules() error {
	for _, interaction := range executor.rules.Interactions {
		if interaction.Condition != nil {
			if err := executor.validateCondition(
				*interaction.Condition,
				fmt.Sprintf("actor %q interaction condition", interaction.ActorID),
			); err != nil {
				return err
			}
		}
		if err := executor.validateActionList(
			interaction.Actions,
			fmt.Sprintf("actor %q interaction actions", interaction.ActorID),
		); err != nil {
			return err
		}
	}
	return nil
}

func (executor *Executor) validateActionList(
	actions []gamebuild.RuleAction,
	path string,
) error {
	for index, action := range actions {
		if err := executor.validateAction(
			action,
			fmt.Sprintf("%s[%d]", path, index),
		); err != nil {
			return err
		}
	}
	return nil
}
