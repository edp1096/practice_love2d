// Package rulesruntime executes compiled campaign rules without depending on
// rendering, input, audio, or per-stage simulation.
//
// Executor is immutable after construction and is safe to share between
// goroutines. Every durable operation is committed through exactly one
// campaign.Transaction. Presentation and simulation work is returned as an
// ordered Intent only after that transaction commits.
package rulesruntime

import (
	"encoding/json"
	"errors"
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

// IntentType is the closed set of non-durable work delegated to the host.
type IntentType string

const (
	IntentOpenShop        IntentType = "open_shop"
	IntentStartDialogue   IntentType = "start_dialogue"
	IntentDamage          IntentType = "damage"
	IntentHeal            IntentType = "heal"
	IntentEmit            IntentType = "emit"
	IntentShowNotice      IntentType = "show_notice"
	IntentStartTurnBattle IntentType = "start_turn_battle"
	IntentStartCutscene   IntentType = "start_cutscene"
)

// Intent preserves authored action order. Exactly one target field is set for
// open-shop and start-dialogue intents; HealAmount is set for heal intents.
type Intent struct {
	Type         IntentType      `json:"type"`
	ShopID       string          `json:"shop_id,omitempty"`
	DialogueID   string          `json:"dialogue_id,omitempty"`
	DamageAmount float64         `json:"damage_amount,omitempty"`
	HealAmount   float64         `json:"heal_amount,omitempty"`
	EventName    string          `json:"event_name,omitempty"`
	EventData    json.RawMessage `json:"event_data,omitempty"`
	NoticeText   string          `json:"notice_text,omitempty"`
	NoticeKey    string          `json:"notice_key,omitempty"`
	NoticeTone   string          `json:"notice_tone,omitempty"`
	NoticeTicks  int             `json:"notice_ticks,omitempty"`
	BattleID     string          `json:"battle_id,omitempty"`
	CutsceneID   string          `json:"cutscene_id,omitempty"`
}

// ActionResult contains host work produced by a successfully committed action
// list. A failed action list always returns a zero result.
type ActionResult struct {
	Intents []Intent `json:"intents"`
}

// ObjectiveEvent is one counted, already-deduplicated domain event emitted by
// the simulation bridge. Count must be positive. The runtime rejects an event
// that exceeds an objective's remaining count instead of silently clamping it.
type ObjectiveEvent struct {
	Event   string         `json:"event"`
	Payload map[string]any `json:"payload,omitempty"`
	ActorID string         `json:"actor_id,omitempty"`
	Count   int64          `json:"count"`
}

// QuestProgress describes one objective mutation caused by an event.
type QuestProgress struct {
	QuestID     string `json:"quest_id"`
	ObjectiveID string `json:"objective_id"`
	Previous    int64  `json:"previous"`
	Current     int64  `json:"current"`
	Required    int64  `json:"required"`
}

// EventResult is emitted only after progress and all completion rewards commit.
// CompletedQuestIDs follows canonical quest-ID order. Intents retain authored
// on_complete action order within that order.
type EventResult struct {
	Progress          []QuestProgress `json:"progress"`
	CompletedQuestIDs []string        `json:"completed_quest_ids"`
	Intents           []Intent        `json:"intents"`
}

// Executor owns a detached, validated rules snapshot and the canonical
// campaign topology that those rules target.
type Executor struct {
	config campaign.Config
	rules  gamebuild.ContentRules
}

// New validates the complete correspondence between compiled rules and the
// durable campaign config. campaign.NewTitle is intentionally used to obtain
// the same canonical sorting that Campaign uses internally; later state
// lookups verify both the searched ID and the canonical slice entry.
func New(
	config campaign.Config,
	rules gamebuild.ContentRules,
) (*Executor, error) {
	canonicalSource, err := campaign.NewTitle(config)
	if err != nil {
		return nil, fmt.Errorf("create rules executor: %w", err)
	}
	executor := &Executor{
		config: canonicalSource.Config(),
		rules:  rules.Clone(),
	}
	if err := executor.validateRules(); err != nil {
		return nil, fmt.Errorf("create rules executor: %w", err)
	}
	return executor, nil
}

// EvaluateCondition evaluates a compiled condition against one atomic campaign
// snapshot. A nil condition is the unconditional case and evaluates true.
func (executor *Executor) EvaluateCondition(
	live *campaign.Campaign,
	condition *gamebuild.RuleCondition,
) (bool, error) {
	if executor == nil {
		return false, errors.New("evaluate rule condition: executor is nil")
	}
	if live == nil {
		return false, errors.New("evaluate rule condition: campaign is nil")
	}
	state := live.Snapshot()
	if err := executor.requireIdentity(&state); err != nil {
		return false, fmt.Errorf("evaluate rule condition: %w", err)
	}
	if condition == nil {
		return true, nil
	}
	if err := executor.validateCondition(*condition, "condition"); err != nil {
		return false, fmt.Errorf("evaluate rule condition: %w", err)
	}
	result, err := executor.evaluateConditionState(&state, *condition)
	if err != nil {
		return false, fmt.Errorf("evaluate rule condition: %w", err)
	}
	return result, nil
}

func (executor *Executor) evaluateConditionState(
	state *campaign.State,
	condition gamebuild.RuleCondition,
) (bool, error) {
	switch condition.Type {
	case gamebuild.RuleConditionAlways:
		return true, nil
	case gamebuild.RuleConditionAll:
		for _, child := range condition.Conditions {
			matched, err := executor.evaluateConditionState(state, child)
			if err != nil {
				return false, err
			}
			if !matched {
				return false, nil
			}
		}
		return true, nil
	case gamebuild.RuleConditionAny:
		for _, child := range condition.Conditions {
			matched, err := executor.evaluateConditionState(state, child)
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
		matched, err := executor.evaluateConditionState(
			state,
			*condition.Condition,
		)
		return !matched, err
	case gamebuild.RuleConditionFlag:
		flag, _, err := findFlagState(state, condition.FlagName)
		if err != nil {
			return false, err
		}
		return flag.Value == condition.FlagValue, nil
	case gamebuild.RuleConditionQuestState:
		quest, _, err := findQuestState(state, condition.QuestID)
		if err != nil {
			return false, err
		}
		switch condition.QuestState {
		case gamebuild.RuleQuestInactive:
			return quest.Status == campaign.QuestInactive, nil
		case gamebuild.RuleQuestActive:
			return quest.Status == campaign.QuestActive, nil
		case gamebuild.RuleQuestCompleted:
			return quest.Status == campaign.QuestCompleted, nil
		}
	case gamebuild.RuleConditionTurnBattleState:
		battle, _, err := findTurnBattleState(state, condition.BattleID)
		if err != nil {
			return false, err
		}
		if condition.BattleState == gamebuild.RuleTurnBattleActive {
			// Active battle state is deliberately transient and is evaluated
			// by gameapp before this durable executor is called.
			return false, nil
		}
		return string(battle.Outcome) == string(condition.BattleState) ||
			(battle.Outcome == campaign.TurnBattleNever &&
				condition.BattleState == gamebuild.RuleTurnBattleNever), nil
	case gamebuild.RuleConditionCutsceneActive:
		// Cutscene sessions are intentionally transient and owned by gameapp.
		// The host evaluates this node when it appears in an authored page.
		return false, nil
	case gamebuild.RuleConditionTimeBetween:
		minute := state.World.Minute
		start := condition.StartMinute
		finish := condition.FinishMinute
		if start == finish {
			return true, nil
		}
		if start < finish {
			return minute >= start && minute < finish, nil
		}
		return minute >= start || minute < finish, nil
	case gamebuild.RuleConditionRegionActive:
		// Stage regions are transient and evaluated by gameapp.
		return false, nil
	}
	return false, fmt.Errorf(
		"unsupported condition %q",
		condition.Type,
	)
}

func (executor *Executor) requireIdentity(state *campaign.State) error {
	if state.ProjectID != executor.config.ProjectID {
		return fmt.Errorf(
			"campaign project %q does not match executor project %q",
			state.ProjectID,
			executor.config.ProjectID,
		)
	}
	if state.ContentID != executor.config.ContentID {
		return fmt.Errorf(
			"campaign content %q does not match executor content %q",
			state.ContentID,
			executor.config.ContentID,
		)
	}
	return nil
}
