package gameapp

import (
	"fmt"
	"sort"
	"strings"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

const triggerActorSeparator = "\x00"

// updateTriggersLocked mirrors the authored LÖVE navigation contract:
// actions run on an outside-to-inside edge, once is global to the trigger,
// and cooldown is tracked per trigger/actor pair.
func (runtime *Runtime) updateTriggersLocked() error {
	for key, remaining := range runtime.triggerCooldowns {
		remaining--
		if remaining <= 0 {
			delete(runtime.triggerCooldowns, key)
		} else {
			runtime.triggerCooldowns[key] = remaining
		}
	}

	if runtime.simulation.HasTemporaryPreview() ||
		len(runtime.pendingRemovals) != 0 {
		return nil
	}

	overlapping, targets, err := triggerOverlaps(
		runtime.built,
		runtime.simulation,
	)
	if err != nil {
		return fmt.Errorf("evaluate stage triggers: %w", err)
	}
	previous := runtime.triggerInside
	runtime.triggerInside = overlapping

	keys := make([]string, 0, len(overlapping))
	for key := range overlapping {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	triggers := make(
		map[string]gamebuild.Trigger,
		len(runtime.built.Stage.Triggers),
	)
	for _, trigger := range runtime.built.Stage.Triggers {
		triggers[trigger.ID] = trigger
	}

	for _, key := range keys {
		if previous[key] || runtime.triggerCooldowns[key] > 0 {
			continue
		}
		triggerID, _, found := strings.Cut(key, triggerActorSeparator)
		if !found {
			return fmt.Errorf("invalid trigger overlap key %q", key)
		}
		trigger, exists := triggers[triggerID]
		if !exists {
			return fmt.Errorf("trigger overlap references missing %q", triggerID)
		}
		if runtime.triggerFired[trigger.ID] {
			continue
		}
		eligible, err := runtime.evaluateRuleConditionLocked(
			trigger.Condition,
		)
		if err != nil {
			return fmt.Errorf("trigger %q condition: %w", trigger.ID, err)
		}
		if !eligible {
			continue
		}
		pageID := ""
		actions := trigger.Actions
		once := trigger.Once
		cooldownTicks := trigger.CooldownTicks
		if len(trigger.Pages) > 0 {
			matched := false
			for pageIndex := len(trigger.Pages) - 1; pageIndex >= 0; pageIndex-- {
				page := trigger.Pages[pageIndex]
				eligible, err := runtime.evaluateRuleConditionLocked(
					page.Condition,
				)
				if err != nil {
					return fmt.Errorf(
						"trigger %q page %q condition: %w",
						trigger.ID,
						page.ID,
						err,
					)
				}
				if !eligible {
					continue
				}
				pageID = page.ID
				actions = page.Actions
				once = page.Once
				cooldownTicks = page.CooldownTicks
				matched = true
				break
			}
			if !matched {
				continue
			}
		}
		firedID := trigger.ID
		if pageID != "" {
			firedID += "::" + pageID
		}
		if runtime.triggerFired[firedID] {
			continue
		}
		result, err := runtime.ruleExecutor.Execute(
			runtime.campaign,
			actions,
		)
		if err != nil {
			return fmt.Errorf("trigger %q actions: %w", trigger.ID, err)
		}
		if err := runtime.applyRuleIntentsForTargetLocked(
			result.Intents,
			"",
			targets[key],
			trigger.ID,
		); err != nil {
			return fmt.Errorf("trigger %q intents: %w", trigger.ID, err)
		}
		if once {
			runtime.triggerFired[firedID] = true
		}
		if cooldownTicks > 0 {
			runtime.triggerCooldowns[key] = cooldownTicks
		}
		if runtime.campaign.Snapshot().Mode != campaign.ModePlaying {
			return nil
		}
	}
	return nil
}

func triggerOverlaps(
	built *gamebuild.Result,
	simulation *sim.Simulation,
) (map[string]bool, map[string]string, error) {
	inside := make(map[string]bool)
	targets := make(map[string]string)
	if built == nil || simulation == nil {
		return inside, targets, nil
	}

	snapshot := simulation.Snapshot()
	entities := make(map[string]sim.EntitySnapshot, len(snapshot.Entities))
	for _, entity := range snapshot.Entities {
		entities[entity.ID] = entity
	}
	for _, trigger := range built.Stage.Triggers {
		tag := trigger.ActorTag
		if tag == "" {
			tag = gamebuild.DefaultPortalActorTag
		}
		for _, metadata := range built.Presentation.Instances {
			if !contains(metadata.Tags, tag) {
				continue
			}
			entity, exists := entities[metadata.ID]
			if !exists || entity.Dead {
				continue
			}
			overlaps, err := sim.WallOverlapsRect(
				sim.Wall{
					ID:     trigger.ID,
					Rect:   trigger.Rect,
					Points: trigger.Points,
				},
				entityBodyRect(entity.Position, entity.Body),
			)
			if err != nil {
				return nil, nil, fmt.Errorf(
					"trigger %q has invalid collision geometry: %w",
					trigger.ID,
					err,
				)
			}
			if !overlaps {
				continue
			}
			key := trigger.ID + triggerActorSeparator + metadata.ID
			inside[key] = true
			targets[key] = metadata.ID
		}
	}
	return inside, targets, nil
}
