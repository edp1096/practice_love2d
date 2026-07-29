// Package rulesruntime executes compiled campaign rules without depending on
// rendering, input, audio, or per-stage simulation.
//
// Executor is immutable after construction and is safe to share between
// goroutines. Every durable operation is committed through exactly one
// campaign.Transaction. Presentation and simulation work is returned as an
// ordered Intent only after that transaction commits.
package rulesruntime

import (
	"errors"
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

// IntentType is the closed set of non-durable work delegated to the host.
type IntentType string

const (
	IntentOpenShop      IntentType = "open_shop"
	IntentStartDialogue IntentType = "start_dialogue"
	IntentHeal          IntentType = "heal"
)

// Intent preserves authored action order. Exactly one target field is set for
// open-shop and start-dialogue intents; HealAmount is set for heal intents.
type Intent struct {
	Type       IntentType `json:"type"`
	ShopID     string     `json:"shop_id,omitempty"`
	DialogueID string     `json:"dialogue_id,omitempty"`
	HealAmount float64    `json:"heal_amount,omitempty"`
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
	quest, _, err := findQuestState(&state, condition.QuestID)
	if err != nil {
		return false, fmt.Errorf("evaluate rule condition: %w", err)
	}

	switch condition.QuestState {
	case gamebuild.RuleQuestInactive:
		return quest.Status == campaign.QuestInactive, nil
	case gamebuild.RuleQuestActive:
		return quest.Status == campaign.QuestActive, nil
	case gamebuild.RuleQuestCompleted:
		return quest.Status == campaign.QuestCompleted, nil
	default:
		return false, fmt.Errorf(
			"evaluate rule condition: unsupported quest state %q",
			condition.QuestState,
		)
	}
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
