package rulesruntime

import (
	"encoding/json"
	"fmt"
	"math"
	"sort"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

func (executor *Executor) validateRules() error {
	if err := validateStrictRuleOrder(executor.rules); err != nil {
		return err
	}
	for _, validate := range []func() error{
		executor.validateItemRules,
		executor.validateQuestRules,
		executor.validateDialogueRules,
		executor.validateCutsceneRules,
		executor.validateShopRules,
		executor.validateInteractionRules,
		executor.validateTurnBattleRules,
	} {
		if err := validate(); err != nil {
			return err
		}
	}
	return nil
}

func (executor *Executor) validateTurnBattleRules() error {
	if len(executor.rules.TurnBattles) != len(executor.config.TurnBattles) {
		return fmt.Errorf(
			"turn battle rule count %d does not match config count %d",
			len(executor.rules.TurnBattles),
			len(executor.config.TurnBattles),
		)
	}
	for index, battle := range executor.rules.TurnBattles {
		if battle.ID != executor.config.TurnBattles[index].ID {
			return fmt.Errorf(
				"turn battle rule %d is %q; expected %q",
				index,
				battle.ID,
				executor.config.TurnBattles[index].ID,
			)
		}
		if len(battle.Enemies) == 0 {
			return fmt.Errorf("turn battle %q has no enemies", battle.ID)
		}
		for enemyIndex, enemy := range battle.Enemies {
			if enemy.ID == "" || enemy.ActorID == "" ||
				enemy.MaxHealth <= 0 || len(enemy.Skills) == 0 {
				return fmt.Errorf(
					"turn battle %q enemy %d is invalid",
					battle.ID,
					enemyIndex,
				)
			}
			for _, skillID := range enemy.Skills {
				if _, exists := executor.rules.TurnSkill(skillID); !exists {
					return fmt.Errorf(
						"turn battle %q enemy %q references unknown skill %q",
						battle.ID,
						enemy.ID,
						skillID,
					)
				}
			}
		}
		hooks := []struct {
			name    string
			actions []gamebuild.RuleAction
		}{
			{name: "on_start", actions: battle.OnStart},
			{name: "on_victory", actions: battle.OnVictory},
			{name: "on_escape", actions: battle.OnEscape},
			{name: "on_defeat", actions: battle.OnDefeat},
		}
		for _, hook := range hooks {
			for actionIndex, action := range hook.actions {
				if err := executor.validateAction(
					action,
					fmt.Sprintf(
						"turn battle %q %s[%d]",
						battle.ID,
						hook.name,
						actionIndex,
					),
				); err != nil {
					return err
				}
			}
		}
	}
	for _, battler := range executor.rules.TurnBattlers {
		if len(battler.Skills) == 0 {
			return fmt.Errorf(
				"turn battler %q has no skills",
				battler.ActorID,
			)
		}
		for _, skillID := range battler.Skills {
			if _, exists := executor.rules.TurnSkill(skillID); !exists {
				return fmt.Errorf(
					"turn battler %q references unknown skill %q",
					battler.ActorID,
					skillID,
				)
			}
		}
	}
	for _, skill := range executor.rules.TurnSkills {
		if skill.ID == "" || skill.Power <= 0 ||
			(skill.Effect != "damage" && skill.Effect != "heal") ||
			(skill.Target != "enemy" && skill.Target != "self") ||
			(skill.Effect == "damage" && skill.Target != "enemy") ||
			(skill.Effect == "heal" && skill.Target != "self") {
			return fmt.Errorf("turn skill %q is invalid", skill.ID)
		}
	}
	return nil
}

func (executor *Executor) validateCondition(
	condition gamebuild.RuleCondition,
	path string,
) error {
	switch condition.Type {
	case gamebuild.RuleConditionAlways:
		return nil
	case gamebuild.RuleConditionAll, gamebuild.RuleConditionAny:
		for index, child := range condition.Conditions {
			if err := executor.validateCondition(
				child,
				fmt.Sprintf("%s.conditions[%d]", path, index),
			); err != nil {
				return err
			}
		}
		return nil
	case gamebuild.RuleConditionNot:
		if condition.Condition == nil {
			return fmt.Errorf("%s has no child condition", path)
		}
		return executor.validateCondition(
			*condition.Condition,
			path+".condition",
		)
	case gamebuild.RuleConditionFlag:
		index := sort.SearchStrings(
			executor.config.Flags,
			condition.FlagName,
		)
		if index == len(executor.config.Flags) ||
			executor.config.Flags[index] != condition.FlagName {
			return fmt.Errorf(
				"%s references unknown flag %q",
				path,
				condition.FlagName,
			)
		}
		return nil
	case gamebuild.RuleConditionQuestState:
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
	case gamebuild.RuleConditionTurnBattleState:
		if _, _, err := findTurnBattleDefinition(
			executor.config,
			condition.BattleID,
		); err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
		switch condition.BattleState {
		case gamebuild.RuleTurnBattleNever,
			gamebuild.RuleTurnBattleActive,
			gamebuild.RuleTurnBattleWon,
			gamebuild.RuleTurnBattleLost,
			gamebuild.RuleTurnBattleEscaped:
			return nil
		default:
			return fmt.Errorf(
				"%s has unsupported turn battle state %q",
				path,
				condition.BattleState,
			)
		}
	case gamebuild.RuleConditionCutsceneActive:
		if condition.CutsceneID == "" {
			return nil
		}
		if _, exists := executor.rules.Cutscene(
			condition.CutsceneID,
		); !exists {
			return fmt.Errorf(
				"%s references unknown cutscene %q",
				path,
				condition.CutsceneID,
			)
		}
		return nil
	case gamebuild.RuleConditionTimeBetween:
		if !validWorldMinute(condition.StartMinute) ||
			!validWorldMinute(condition.FinishMinute) {
			return fmt.Errorf("%s has invalid world time bounds", path)
		}
		return nil
	case gamebuild.RuleConditionRegionActive:
		if condition.RegionID == "" {
			return fmt.Errorf("%s has an empty region id", path)
		}
		return nil
	default:
		return fmt.Errorf(
			"%s has unsupported condition type %q",
			path,
			condition.Type,
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
	case gamebuild.RuleActionStartCutscene:
		if _, exists := executor.rules.Cutscene(
			action.CutsceneID,
		); !exists {
			return fmt.Errorf(
				"%s references unknown cutscene %q",
				path,
				action.CutsceneID,
			)
		}
	case gamebuild.RuleActionDamage:
		if math.IsNaN(action.DamageAmount) ||
			math.IsInf(action.DamageAmount, 0) ||
			action.DamageAmount <= 0 {
			return fmt.Errorf(
				"%s has invalid damage amount %v",
				path,
				action.DamageAmount,
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
	case gamebuild.RuleActionEmit:
		if action.EventName == "" {
			return fmt.Errorf("%s has an empty event name", path)
		}
		if sim.IsReservedEventType(sim.EventType(action.EventName)) {
			return fmt.Errorf(
				"%s event name %q is reserved by the engine",
				path,
				action.EventName,
			)
		}
		if len(action.EventData) != 0 {
			var data map[string]any
			if !json.Valid(action.EventData) ||
				json.Unmarshal(action.EventData, &data) != nil ||
				data == nil {
				return fmt.Errorf("%s has invalid event data", path)
			}
		}
	case gamebuild.RuleActionShowNotice:
		if action.NoticeText == "" && action.NoticeKey == "" {
			return fmt.Errorf("%s has no notice text or text key", path)
		}
		switch action.NoticeTone {
		case "info", "success", "warning":
		default:
			return fmt.Errorf(
				"%s has invalid notice tone %q",
				path,
				action.NoticeTone,
			)
		}
		if action.NoticeTicks <= 0 ||
			action.NoticeTicks > sim.MaxTickCount {
			return fmt.Errorf(
				"%s has invalid notice duration %d ticks",
				path,
				action.NoticeTicks,
			)
		}
	case gamebuild.RuleActionStartTurnBattle:
		if _, exists := executor.rules.TurnBattle(action.BattleID); !exists {
			return fmt.Errorf(
				"%s references unknown turn battle %q",
				path,
				action.BattleID,
			)
		}
	case gamebuild.RuleActionSetWorldTime:
		if !validWorldMinute(action.WorldMinute) {
			return fmt.Errorf("%s has invalid world minute", path)
		}
		if action.WorldDay < 0 ||
			action.WorldDay > campaign.MaxJSONInteger {
			return fmt.Errorf("%s has invalid world day", path)
		}
	case gamebuild.RuleActionAdvanceWorldTime:
		if math.IsNaN(action.WorldMinutes) ||
			math.IsInf(action.WorldMinutes, 0) ||
			action.WorldMinutes <= 0 {
			return fmt.Errorf("%s has invalid world minutes", path)
		}
	default:
		return fmt.Errorf("%s has unsupported action type %q", path, action.Type)
	}
	return nil
}

func validWorldMinute(value float64) bool {
	return !math.IsNaN(value) &&
		!math.IsInf(value, 0) &&
		value >= 0 &&
		value < 24*60
}

func validateStrictRuleOrder(rules gamebuild.ContentRules) error {
	groups := []struct {
		name string
		ids  []string
	}{
		{name: "dialogue", ids: idsOfDialogues(rules.Dialogues)},
		{name: "cutscene", ids: idsOfCutscenes(rules.Cutscenes)},
		{name: "quest", ids: idsOfQuests(rules.Quests)},
		{name: "item", ids: idsOfItems(rules.Items)},
		{name: "shop", ids: idsOfShops(rules.Shops)},
		{
			name: "actor interaction",
			ids:  idsOfInteractions(rules.Interactions),
		},
		{name: "turn skill", ids: idsOfTurnSkills(rules.TurnSkills)},
		{name: "turn battler", ids: idsOfTurnBattlers(rules.TurnBattlers)},
		{name: "turn battle", ids: idsOfTurnBattles(rules.TurnBattles)},
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

func idsOfCutscenes(values []gamebuild.CutsceneRule) []string {
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

func idsOfTurnSkills(values []gamebuild.TurnSkillRule) []string {
	result := make([]string, len(values))
	for index, value := range values {
		result[index] = value.ID
	}
	return result
}

func idsOfTurnBattlers(values []gamebuild.ActorTurnBattlerRule) []string {
	result := make([]string, len(values))
	for index, value := range values {
		result[index] = value.ActorID
	}
	return result
}

func idsOfTurnBattles(values []gamebuild.TurnBattleRule) []string {
	result := make([]string, len(values))
	for index, value := range values {
		result[index] = value.ID
	}
	return result
}

// The compile-time integer types are native ints, while campaign persistence
// is deliberately capped to the JSON-safe integer range.
func validPersistentInt(value int) bool {
	return value >= 0 &&
		uint64(value) <= uint64(campaign.MaxJSONInteger)
}
