package rulesruntime

import (
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

// CompleteTurnBattle records one durable outcome and executes the matching
// authored hook in the same Campaign transaction. Transient combat state and
// player health remain host-owned and can be rolled back by the host before
// publishing returned intents.
func (executor *Executor) CompleteTurnBattle(
	live *campaign.Campaign,
	battleID string,
	outcome campaign.TurnBattleOutcome,
) (ActionResult, error) {
	if executor == nil {
		return ActionResult{}, fmt.Errorf(
			"complete turn battle: executor is nil",
		)
	}
	rule, exists := executor.rules.TurnBattle(battleID)
	if !exists {
		return ActionResult{}, fmt.Errorf(
			"complete turn battle: unknown battle %q",
			battleID,
		)
	}
	var actions []gamebuild.RuleAction
	switch outcome {
	case campaign.TurnBattleWon:
		actions = rule.OnVictory
	case campaign.TurnBattleLost:
		actions = rule.OnDefeat
	case campaign.TurnBattleEscaped:
		actions = rule.OnEscape
	default:
		return ActionResult{}, fmt.Errorf(
			"complete turn battle: invalid outcome %q",
			outcome,
		)
	}
	for index, action := range actions {
		if err := executor.validateAction(
			action,
			fmt.Sprintf("turn battle %q outcome actions[%d]", battleID, index),
		); err != nil {
			return ActionResult{}, fmt.Errorf("complete turn battle: %w", err)
		}
	}

	var result ActionResult
	err := live.Transaction(func(state *campaign.State) error {
		if err := executor.requireIdentity(state); err != nil {
			return err
		}
		battle, _, err := findTurnBattleState(state, battleID)
		if err != nil {
			return err
		}
		battle.Outcome = outcome
		intents, err := executor.applyActions(state, actions, 0)
		if err != nil {
			return err
		}
		result.Intents = intents
		return nil
	})
	if err != nil {
		return ActionResult{}, fmt.Errorf("complete turn battle: %w", err)
	}
	if result.Intents == nil {
		result.Intents = []Intent{}
	}
	return result, nil
}
