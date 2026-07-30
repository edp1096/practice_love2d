package gameapp

import (
	"fmt"
	"math"
	"sort"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

const worldMinutesPerDay = 24 * 60

// updateWorldStateLocked advances the durable project clock, refreshes the
// current authored page, then resolves region edges. The order matches the
// LÖVE implementation: page conditions see the region state from the previous
// tick, while later regions may observe earlier region edges from this tick.
func (runtime *Runtime) updateWorldStateLocked() error {
	if secondsPerDay := runtime.campaignConfig.WorldSecondsPerDay; secondsPerDay > 0 {
		minutes := worldMinutesPerDay /
			(secondsPerDay * float64(sim.TicksPerSecond))
		result, err := runtime.ruleExecutor.Execute(
			runtime.campaign,
			[]gamebuild.RuleAction{{
				Type:         gamebuild.RuleActionAdvanceWorldTime,
				WorldMinutes: minutes,
			}},
		)
		if err != nil {
			return fmt.Errorf("advance automatic world clock: %w", err)
		}
		if len(result.Intents) != 0 {
			return fmt.Errorf(
				"advance automatic world clock produced %d unexpected intents",
				len(result.Intents),
			)
		}
	}

	if err := runtime.refreshWorldPageLocked(!runtime.worldInitialized); err != nil {
		return err
	}
	if runtime.worldModalActiveLocked() {
		return nil
	}
	if err := runtime.updateWorldRegionsLocked(); err != nil {
		return err
	}
	return nil
}

func (runtime *Runtime) refreshWorldPageLocked(initial bool) error {
	selected, err := runtime.selectWorldPageLocked()
	if err != nil {
		return err
	}
	selectedID := ""
	if selected != nil {
		selectedID = selected.ID
	}
	if runtime.worldInitialized && selectedID == runtime.worldActivePage {
		return nil
	}

	previous := runtime.activeWorldPageLocked()
	runtime.worldInitialized = true
	runtime.worldActivePage = selectedID
	if initial {
		return nil
	}

	actions := make([]gamebuild.RuleAction, 0)
	if previous != nil {
		actions = append(actions, previous.OnExit...)
	}
	if selected != nil {
		actions = append(actions, selected.OnEnter...)
	}
	if len(actions) == 0 {
		return nil
	}
	result, err := runtime.ruleExecutor.Execute(runtime.campaign, actions)
	if err != nil {
		return fmt.Errorf(
			"change world page from %q to %q: %w",
			worldPageID(previous),
			selectedID,
			err,
		)
	}
	if err := runtime.applyRuleIntentsForTargetLocked(
		result.Intents,
		"",
		"",
		"world.page:"+selectedID,
	); err != nil {
		return fmt.Errorf(
			"apply world page %q intents: %w",
			selectedID,
			err,
		)
	}
	return nil
}

func (runtime *Runtime) selectWorldPageLocked() (*gamebuild.WorldPage, error) {
	var selected *gamebuild.WorldPage
	for index := range runtime.built.Stage.WorldPages {
		page := &runtime.built.Stage.WorldPages[index]
		matched, err := runtime.evaluateRuleConditionLocked(page.Condition)
		if err != nil {
			return nil, fmt.Errorf(
				"world page %q condition: %w",
				page.ID,
				err,
			)
		}
		if matched {
			// Authored order is precedence order: the last matching page wins.
			selected = page
		}
	}
	return selected, nil
}

func (runtime *Runtime) activeWorldPageLocked() *gamebuild.WorldPage {
	if runtime.worldActivePage == "" {
		return nil
	}
	for index := range runtime.built.Stage.WorldPages {
		page := &runtime.built.Stage.WorldPages[index]
		if page.ID == runtime.worldActivePage {
			return page
		}
	}
	return nil
}

func (runtime *Runtime) updateWorldRegionsLocked() error {
	if runtime.simulation.HasTemporaryPreview() ||
		len(runtime.pendingRemovals) != 0 {
		return nil
	}

	for index := range runtime.built.Stage.Regions {
		region := &runtime.built.Stage.Regions[index]
		eligible, err := runtime.evaluateRuleConditionLocked(region.Condition)
		if err != nil {
			return fmt.Errorf(
				"world region %q condition: %w",
				region.ID,
				err,
			)
		}
		inside := false
		targetID := ""
		if eligible {
			inside, targetID, err = runtime.worldRegionOverlapLocked(region)
			if err != nil {
				return err
			}
		}
		wasInside := runtime.worldActiveRegions[region.ID]
		if inside == wasInside {
			continue
		}

		if inside {
			runtime.worldActiveRegions[region.ID] = true
		} else {
			delete(runtime.worldActiveRegions, region.ID)
		}
		actions := region.OnExit
		edge := "exit"
		if inside {
			actions = region.OnEnter
			edge = "enter"
		}
		if len(actions) == 0 {
			continue
		}
		result, err := runtime.ruleExecutor.Execute(runtime.campaign, actions)
		if err != nil {
			return fmt.Errorf(
				"world region %q %s actions: %w",
				region.ID,
				edge,
				err,
			)
		}
		if err := runtime.applyRuleIntentsForTargetLocked(
			result.Intents,
			"",
			targetID,
			"world.region:"+region.ID,
		); err != nil {
			return fmt.Errorf(
				"world region %q %s intents: %w",
				region.ID,
				edge,
				err,
			)
		}
		if runtime.campaign.Snapshot().Mode != campaign.ModePlaying ||
			runtime.worldModalActiveLocked() {
			return nil
		}
	}
	return nil
}

func (runtime *Runtime) worldRegionOverlapLocked(
	region *gamebuild.WorldRegion,
) (bool, string, error) {
	if region == nil {
		return false, "", nil
	}
	tag := region.ActorTag
	if tag == "" {
		tag = gamebuild.DefaultPortalActorTag
	}
	snapshot := runtime.simulation.Snapshot()
	entities := make(map[string]sim.EntitySnapshot, len(snapshot.Entities))
	for _, entity := range snapshot.Entities {
		entities[entity.ID] = entity
	}
	for _, metadata := range runtime.built.Presentation.Instances {
		if !contains(metadata.Tags, tag) {
			continue
		}
		entity, exists := entities[metadata.ID]
		if !exists || entity.Dead {
			continue
		}
		overlaps, err := sim.WallOverlapsRect(
			sim.Wall{
				ID:     region.ID,
				Rect:   region.Rect,
				Points: region.Points,
			},
			entityBodyRect(entity.Position, entity.Body),
		)
		if err != nil {
			return false, "", fmt.Errorf(
				"world region %q has invalid collision geometry: %w",
				region.ID,
				err,
			)
		}
		if overlaps {
			return true, entity.ID, nil
		}
	}
	return false, "", nil
}

func (runtime *Runtime) resetWorldStateLocked() {
	runtime.worldInitialized = false
	runtime.worldActivePage = ""
	runtime.worldActiveRegions = make(map[string]bool)
}

func (runtime *Runtime) worldModalActiveLocked() bool {
	return runtime.cutscene != nil ||
		runtime.dialogue != nil ||
		runtime.activeShopID != "" ||
		runtime.inventoryOpen ||
		runtime.turnBattle != nil
}

func worldPageID(page *gamebuild.WorldPage) string {
	if page == nil {
		return ""
	}
	return page.ID
}

func formatWorldClock(minute float64) string {
	minute = math.Mod(minute, worldMinutesPerDay)
	if minute < 0 {
		minute += worldMinutesPerDay
	}
	// Repeated fixed-tick additions such as 0.4 can land a few ulps below an
	// exact authored minute. Keep the visible clock stable without changing
	// the durable fractional value used by conditions.
	whole := int(math.Floor(minute + 1e-9))
	return fmt.Sprintf("%02d:%02d", whole/60, whole%60)
}

func applyWorldLayerOverrides(
	tilemap *ebitapp.TilemapView,
	page *gamebuild.WorldPage,
) {
	if tilemap == nil || page == nil {
		return
	}
	overrides := make(map[string]bool, len(page.Layers))
	for _, override := range page.Layers {
		overrides[override.ID] = override.Visible
	}
	for index := range tilemap.Layers {
		visible, exists := overrides[tilemap.Layers[index].ID]
		if exists {
			tilemap.Layers[index].Visible = visible
		}
	}
}

func sortedActiveWorldRegions(active map[string]bool) []string {
	result := make([]string, 0, len(active))
	for id, enabled := range active {
		if enabled {
			result = append(result, id)
		}
	}
	sort.Strings(result)
	return result
}
