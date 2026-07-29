package rulesruntime

import (
	"errors"
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

// ApplyObjectiveEvent advances every active quest objective matching the
// event name and authored scalar payload filter. A single quest cannot contain
// duplicate match filters
// because New rejects that ambiguous topology. Unmatched, inactive-only,
// completed-only, duplicate, and over-counted events fail closed.
//
// Completion status, objective progress, durable on_complete rewards, and any
// intents are produced by one campaign.Transaction. Therefore reward failure
// also rolls back the objective count and completed status.
func (executor *Executor) ApplyObjectiveEvent(
	live *campaign.Campaign,
	event ObjectiveEvent,
) (EventResult, error) {
	if executor == nil {
		return EventResult{}, errors.New("apply objective event: executor is nil")
	}
	if live == nil {
		return EventResult{}, errors.New("apply objective event: campaign is nil")
	}
	if event.Event == "" {
		return EventResult{}, errors.New("apply objective event: event is empty")
	}
	if event.Count <= 0 || event.Count > campaign.MaxJSONInteger {
		return EventResult{}, fmt.Errorf(
			"apply objective event: count must be in [1, %d]",
			campaign.MaxJSONInteger,
		)
	}
	payload, err := objectiveEventPayload(event)
	if err != nil {
		return EventResult{}, fmt.Errorf("apply objective event: %w", err)
	}

	var candidate EventResult
	err = live.Transaction(func(state *campaign.State) error {
		if err := executor.requireIdentity(state); err != nil {
			return err
		}

		knownMatch := false
		activeMatch := false
		for _, questRule := range executor.rules.Quests {
			questState, _, err := findQuestState(state, questRule.ID)
			if err != nil {
				return err
			}
			objectiveRule, exists := matchingObjective(
				questRule,
				event.Event,
				payload,
			)
			if !exists {
				continue
			}
			knownMatch = true
			if questState.Status != campaign.QuestActive {
				continue
			}

			objectiveState, _, err := findObjectiveState(
				questState,
				objectiveRule.ID,
			)
			if err != nil {
				return err
			}
			required, err := executor.objectiveRequired(
				questRule.ID,
				objectiveRule.ID,
			)
			if err != nil {
				return err
			}
			remaining := required - objectiveState.Count
			if remaining == 0 {
				// Another active quest may share this event filter while this
				// objective is already capped and waits on a different
				// objective. Do not let the capped counter block the remaining
				// quest. If every match is capped, activeMatch remains false
				// and the existing duplicate-event error is returned.
				continue
			}
			activeMatch = true
			if event.Count > remaining {
				return fmt.Errorf(
					"quest %q objective %q event count %d exceeds "+
						"remaining count %d",
					questRule.ID,
					objectiveRule.ID,
					event.Count,
					remaining,
				)
			}

			previous := objectiveState.Count
			objectiveState.Count += event.Count
			candidate.Progress = append(
				candidate.Progress,
				QuestProgress{
					QuestID:     questRule.ID,
					ObjectiveID: objectiveRule.ID,
					Previous:    previous,
					Current:     objectiveState.Count,
					Required:    required,
				},
			)
			if !executor.questComplete(questState, questRule.ID) {
				continue
			}

			questState.Status = campaign.QuestCompleted
			candidate.CompletedQuestIDs = append(
				candidate.CompletedQuestIDs,
				questRule.ID,
			)
			intents, err := executor.applyActions(
				state,
				questRule.OnComplete,
				0,
			)
			if err != nil {
				return fmt.Errorf(
					"complete quest %q: %w",
					questRule.ID,
					err,
				)
			}
			candidate.Intents = append(candidate.Intents, intents...)
		}

		switch {
		case !knownMatch:
			return fmt.Errorf(
				"no quest objective matches event %q and payload",
				event.Event,
			)
		case !activeMatch:
			return fmt.Errorf(
				"event %q and payload have no active objective; "+
					"it is inactive, completed, or duplicated",
				event.Event,
			)
		default:
			return nil
		}
	})
	if err != nil {
		return EventResult{}, fmt.Errorf("apply objective event: %w", err)
	}
	if candidate.Progress == nil {
		candidate.Progress = []QuestProgress{}
	}
	if candidate.CompletedQuestIDs == nil {
		candidate.CompletedQuestIDs = []string{}
	}
	if candidate.Intents == nil {
		candidate.Intents = []Intent{}
	}
	return candidate, nil
}

func (executor *Executor) objectiveRequired(
	questID string,
	objectiveID string,
) (int64, error) {
	quest, _, err := findQuestDefinition(executor.config, questID)
	if err != nil {
		return 0, err
	}
	objective, _, err := findObjectiveDefinition(quest, objectiveID)
	if err != nil {
		return 0, err
	}
	return objective.Required, nil
}

func (executor *Executor) questComplete(
	state *campaign.QuestState,
	questID string,
) bool {
	definition, _, err := findQuestDefinition(executor.config, questID)
	if err != nil || len(state.Objectives) != len(definition.Objectives) {
		return false
	}
	for index, objective := range definition.Objectives {
		if state.Objectives[index].ID != objective.ID ||
			state.Objectives[index].Count != objective.Required {
			return false
		}
	}
	return true
}

func matchingObjective(
	quest gamebuild.QuestRule,
	event string,
	payload map[string]any,
) (gamebuild.QuestObjectiveRule, bool) {
	for _, objective := range quest.Objectives {
		if objective.Matches(event, payload) {
			return objective, true
		}
	}
	return gamebuild.QuestObjectiveRule{}, false
}

func objectiveEventPayload(event ObjectiveEvent) (map[string]any, error) {
	result := make(map[string]any, len(event.Payload)+1)
	for key, value := range event.Payload {
		if key == "" {
			return nil, errors.New("payload has an empty key")
		}
		switch value.(type) {
		case string, float64, bool:
		default:
			return nil, fmt.Errorf(
				"payload %q must be a string, number, or boolean",
				key,
			)
		}
		result[key] = value
	}
	if event.ActorID != "" {
		if value, exists := result["actor_id"]; exists &&
			value != event.ActorID {
			return nil, errors.New(
				"actor id conflicts with payload actor_id",
			)
		}
		result["actor_id"] = event.ActorID
	}
	return result, nil
}
