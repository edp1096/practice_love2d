package gameapp

import (
	"errors"

	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

// evaluateRuleConditionLocked resolves host-owned transient nodes and delegates
// durable leaves to rulesruntime. Composite nodes are evaluated here so a
// transient condition can be nested under all/any/not without being erased by
// the durable campaign evaluator.
func (runtime *Runtime) evaluateRuleConditionLocked(
	condition *gamebuild.RuleCondition,
) (bool, error) {
	if condition == nil {
		return true, nil
	}
	switch condition.Type {
	case gamebuild.RuleConditionAll:
		for index := range condition.Conditions {
			matched, err := runtime.evaluateRuleConditionLocked(
				&condition.Conditions[index],
			)
			if err != nil || !matched {
				return matched, err
			}
		}
		return true, nil
	case gamebuild.RuleConditionAny:
		for index := range condition.Conditions {
			matched, err := runtime.evaluateRuleConditionLocked(
				&condition.Conditions[index],
			)
			if err != nil {
				return false, err
			}
			if matched {
				return true, nil
			}
		}
		return false, nil
	case gamebuild.RuleConditionNot:
		if condition.Condition == nil {
			return false, errors.New("not condition has no child")
		}
		matched, err := runtime.evaluateRuleConditionLocked(
			condition.Condition,
		)
		return !matched, err
	case gamebuild.RuleConditionCutsceneActive:
		return runtime.cutscene != nil &&
			(condition.CutsceneID == "" ||
				runtime.cutscene.CutsceneID == condition.CutsceneID), nil
	case gamebuild.RuleConditionTurnBattleState:
		if condition.BattleState == gamebuild.RuleTurnBattleActive {
			return runtime.turnBattle != nil &&
				runtime.turnBattle.BattleID == condition.BattleID, nil
		}
	case gamebuild.RuleConditionRegionActive:
		return runtime.worldActiveRegions[condition.RegionID], nil
	}
	return runtime.ruleExecutor.EvaluateCondition(
		runtime.campaign,
		condition,
	)
}
