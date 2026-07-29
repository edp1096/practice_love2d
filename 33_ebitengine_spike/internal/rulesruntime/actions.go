package rulesruntime

import (
	"errors"
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

// Execute applies all durable actions in one transaction. External intents are
// accumulated inside the candidate transaction but become observable only
// after the candidate commits successfully.
func (executor *Executor) Execute(
	live *campaign.Campaign,
	actions []gamebuild.RuleAction,
) (ActionResult, error) {
	return executor.executeGuarded(live, actions, nil)
}

// executeGuarded is the single transaction boundary used when a caller must
// prove a campaign-state precondition and apply actions without a TOCTOU gap.
// The guard observes the same detached candidate that applyActions mutates.
// Returning an error from either stage rolls back campaign state and hides all
// candidate intents.
func (executor *Executor) executeGuarded(
	live *campaign.Campaign,
	actions []gamebuild.RuleAction,
	guard func(*campaign.State) error,
) (ActionResult, error) {
	if executor == nil {
		return ActionResult{}, errors.New("execute rule actions: executor is nil")
	}
	if live == nil {
		return ActionResult{}, errors.New("execute rule actions: campaign is nil")
	}
	for index, action := range actions {
		if err := executor.validateAction(
			action,
			fmt.Sprintf("actions[%d]", index),
		); err != nil {
			return ActionResult{}, fmt.Errorf("execute rule actions: %w", err)
		}
	}

	var candidate ActionResult
	err := live.Transaction(func(state *campaign.State) error {
		if err := executor.requireIdentity(state); err != nil {
			return err
		}
		if guard != nil {
			if err := guard(state); err != nil {
				return err
			}
		}
		intents, err := executor.applyActions(state, actions, 0)
		if err != nil {
			return err
		}
		candidate.Intents = intents
		return nil
	})
	if err != nil {
		return ActionResult{}, fmt.Errorf("execute rule actions: %w", err)
	}
	if candidate.Intents == nil {
		candidate.Intents = []Intent{}
	}
	return candidate, nil
}

func (executor *Executor) applyActions(
	state *campaign.State,
	actions []gamebuild.RuleAction,
	depth int,
) ([]Intent, error) {
	if depth > len(executor.rules.Quests) {
		return nil, errors.New("start_quest on_start action recursion is too deep")
	}
	intents := make([]Intent, 0)
	for index, action := range actions {
		path := fmt.Sprintf("actions[%d]", index)
		switch action.Type {
		case gamebuild.RuleActionStartQuest:
			questState, _, err := findQuestState(state, action.QuestID)
			if err != nil {
				return nil, fmt.Errorf("%s: %w", path, err)
			}
			if questState.Status != campaign.QuestInactive {
				return nil, fmt.Errorf(
					"%s: quest %q cannot start from status %q",
					path,
					action.QuestID,
					questState.Status,
				)
			}
			questState.Status = campaign.QuestActive
			rule, exists := executor.rules.Quest(action.QuestID)
			if !exists {
				return nil, fmt.Errorf(
					"%s: quest rule %q is missing",
					path,
					action.QuestID,
				)
			}
			nested, err := executor.applyActions(
				state,
				rule.OnStart,
				depth+1,
			)
			if err != nil {
				return nil, fmt.Errorf(
					"%s: start quest %q: %w",
					path,
					action.QuestID,
					err,
				)
			}
			intents = append(intents, nested...)

		case gamebuild.RuleActionGiveItem:
			entry, definition, err := executor.inventoryEntry(
				state,
				action.ItemID,
			)
			if err != nil {
				return nil, fmt.Errorf("%s: %w", path, err)
			}
			quantity, err := positiveRuleInteger(
				action.Quantity,
				path+" give-item quantity",
			)
			if err != nil {
				return nil, err
			}
			if quantity > definition.MaxQuantity-entry.Quantity {
				return nil, fmt.Errorf(
					"%s: item %q quantity %d exceeds stack limit %d",
					path,
					action.ItemID,
					entry.Quantity+quantity,
					definition.MaxQuantity,
				)
			}
			entry.Quantity += quantity

		case gamebuild.RuleActionEquipItem:
			entry, definition, err := executor.inventoryEntry(
				state,
				action.ItemID,
			)
			if err != nil {
				return nil, fmt.Errorf("%s: %w", path, err)
			}
			if definition.EquipmentSlot == "" {
				return nil, fmt.Errorf(
					"%s: item %q is not equipment",
					path,
					action.ItemID,
				)
			}
			if entry.Quantity < 1 {
				return nil, fmt.Errorf(
					"%s: item %q is not owned",
					path,
					action.ItemID,
				)
			}
			slot, _, err := findEquipmentEntry(
				state,
				definition.EquipmentSlot,
			)
			if err != nil {
				return nil, fmt.Errorf("%s: %w", path, err)
			}
			slot.ItemID = action.ItemID

		case gamebuild.RuleActionAddCurrency:
			amount, err := nonNegativeRuleInteger(
				action.Currency,
				path+" currency amount",
			)
			if err != nil {
				return nil, err
			}
			if amount > campaign.MaxJSONInteger-state.Currency {
				return nil, fmt.Errorf(
					"%s: currency addition exceeds maximum %d",
					path,
					campaign.MaxJSONInteger,
				)
			}
			state.Currency += amount

		case gamebuild.RuleActionSetFlag:
			flag, _, err := findFlagState(state, action.FlagName)
			if err != nil {
				return nil, fmt.Errorf("%s: %w", path, err)
			}
			flag.Value = action.FlagValue

		case gamebuild.RuleActionFinishGame:
			if !state.Flow.Started {
				return nil, fmt.Errorf(
					"%s: cannot finish an unstarted campaign",
					path,
				)
			}
			if state.Flow.Completed {
				return nil, fmt.Errorf(
					"%s: campaign is already completed",
					path,
				)
			}
			state.Flow.Completed = true
			state.Mode = campaign.ModeEnding

		case gamebuild.RuleActionOpenShop:
			intents = append(intents, Intent{
				Type:   IntentOpenShop,
				ShopID: action.ShopID,
			})

		case gamebuild.RuleActionStartDialogue:
			intents = append(intents, Intent{
				Type:       IntentStartDialogue,
				DialogueID: action.DialogueID,
			})

		case gamebuild.RuleActionHeal:
			intents = append(intents, Intent{
				Type:       IntentHeal,
				HealAmount: action.HealAmount,
			})

		default:
			return nil, fmt.Errorf(
				"%s: unsupported action type %q",
				path,
				action.Type,
			)
		}
	}
	return intents, nil
}

func positiveRuleInteger(value int, label string) (int64, error) {
	if value <= 0 || uint64(value) > uint64(campaign.MaxJSONInteger) {
		return 0, fmt.Errorf(
			"%s must be in [1, %d]",
			label,
			campaign.MaxJSONInteger,
		)
	}
	return int64(value), nil
}

func nonNegativeRuleInteger(value int, label string) (int64, error) {
	if value < 0 || uint64(value) > uint64(campaign.MaxJSONInteger) {
		return 0, fmt.Errorf(
			"%s must be in [0, %d]",
			label,
			campaign.MaxJSONInteger,
		)
	}
	return int64(value), nil
}
