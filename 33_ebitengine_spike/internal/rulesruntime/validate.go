package rulesruntime

import (
	"fmt"
	"math"
	"sort"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

func (executor *Executor) validateRules() error {
	if err := validateStrictRuleOrder(executor.rules); err != nil {
		return err
	}
	for _, validate := range []func() error{
		executor.validateItemRules,
		executor.validateQuestRules,
		executor.validateDialogueRules,
		executor.validateShopRules,
		executor.validateInteractionRules,
	} {
		if err := validate(); err != nil {
			return err
		}
	}
	return nil
}

func (executor *Executor) validateCondition(
	condition gamebuild.RuleCondition,
	path string,
) error {
	if condition.Type != gamebuild.RuleConditionQuestState {
		return fmt.Errorf(
			"%s has unsupported condition type %q",
			path,
			condition.Type,
		)
	}
	if _, _, err := findQuestDefinition(
		executor.config,
		condition.QuestID,
	); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	switch condition.QuestState {
	case gamebuild.RuleQuestInactive,
		gamebuild.RuleQuestActive,
		gamebuild.RuleQuestCompleted:
		return nil
	default:
		return fmt.Errorf(
			"%s has unsupported quest state %q",
			path,
			condition.QuestState,
		)
	}
}

func (executor *Executor) validateAction(
	action gamebuild.RuleAction,
	path string,
) error {
	switch action.Type {
	case gamebuild.RuleActionStartQuest:
		if _, _, err := findQuestDefinition(
			executor.config,
			action.QuestID,
		); err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
	case gamebuild.RuleActionGiveItem:
		if _, _, err := findItemDefinition(
			executor.config,
			action.ItemID,
		); err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
		if _, err := positiveRuleInteger(
			action.Quantity,
			path+" quantity",
		); err != nil {
			return err
		}
	case gamebuild.RuleActionEquipItem:
		item, _, err := findItemDefinition(
			executor.config,
			action.ItemID,
		)
		if err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
		if item.EquipmentSlot == "" {
			return fmt.Errorf(
				"%s references non-equipment item %q",
				path,
				action.ItemID,
			)
		}
	case gamebuild.RuleActionAddCurrency:
		if _, err := nonNegativeRuleInteger(
			action.Currency,
			path+" amount",
		); err != nil {
			return err
		}
	case gamebuild.RuleActionSetFlag:
		index := sort.SearchStrings(
			executor.config.Flags,
			action.FlagName,
		)
		if index == len(executor.config.Flags) ||
			executor.config.Flags[index] != action.FlagName {
			return fmt.Errorf(
				"%s references unknown flag %q",
				path,
				action.FlagName,
			)
		}
	case gamebuild.RuleActionFinishGame:
		return nil
	case gamebuild.RuleActionOpenShop:
		if _, exists := executor.rules.Shop(action.ShopID); !exists {
			return fmt.Errorf(
				"%s references unknown shop %q",
				path,
				action.ShopID,
			)
		}
	case gamebuild.RuleActionStartDialogue:
		if _, exists := executor.rules.Dialogue(action.DialogueID); !exists {
			return fmt.Errorf(
				"%s references unknown dialogue %q",
				path,
				action.DialogueID,
			)
		}
	case gamebuild.RuleActionHeal:
		if math.IsNaN(action.HealAmount) ||
			math.IsInf(action.HealAmount, 0) ||
			action.HealAmount <= 0 {
			return fmt.Errorf(
				"%s has invalid heal amount %v",
				path,
				action.HealAmount,
			)
		}
	default:
		return fmt.Errorf("%s has unsupported action type %q", path, action.Type)
	}
	return nil
}

func validateStrictRuleOrder(rules gamebuild.ContentRules) error {
	groups := []struct {
		name string
		ids  []string
	}{
		{name: "dialogue", ids: idsOfDialogues(rules.Dialogues)},
		{name: "quest", ids: idsOfQuests(rules.Quests)},
		{name: "item", ids: idsOfItems(rules.Items)},
		{name: "shop", ids: idsOfShops(rules.Shops)},
		{
			name: "actor interaction",
			ids:  idsOfInteractions(rules.Interactions),
		},
	}
	for _, group := range groups {
		for index, id := range group.ids {
			if id == "" {
				return fmt.Errorf(
					"%s rule %d has empty id",
					group.name,
					index,
				)
			}
			if index > 0 && group.ids[index-1] >= id {
				return fmt.Errorf(
					"%s rules are not in strict canonical ID order at %q",
					group.name,
					id,
				)
			}
		}
	}
	return nil
}

func idsOfDialogues(values []gamebuild.DialogueRule) []string {
	result := make([]string, len(values))
	for index, value := range values {
		result[index] = value.ID
	}
	return result
}

func idsOfQuests(values []gamebuild.QuestRule) []string {
	result := make([]string, len(values))
	for index, value := range values {
		result[index] = value.ID
	}
	return result
}

func idsOfItems(values []gamebuild.ItemRule) []string {
	result := make([]string, len(values))
	for index, value := range values {
		result[index] = value.ID
	}
	return result
}

func idsOfShops(values []gamebuild.ShopRule) []string {
	result := make([]string, len(values))
	for index, value := range values {
		result[index] = value.ID
	}
	return result
}

func idsOfInteractions(values []gamebuild.ActorInteractionRule) []string {
	result := make([]string, len(values))
	for index, value := range values {
		result[index] = value.ActorID
	}
	return result
}

// The compile-time integer types are native ints, while campaign persistence
// is deliberately capped to the JSON-safe integer range.
func validPersistentInt(value int) bool {
	return value >= 0 &&
		uint64(value) <= uint64(campaign.MaxJSONInteger)
}
