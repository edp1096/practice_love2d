package gameapp

import (
	"errors"
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

// updatePortalsLocked runs only after the old World has consumed the current
// input edge. A successful transition constructs a fresh World and never
// forwards that edge to it.
func (runtime *Runtime) updatePortalsLocked() error {
	if runtime.portalCooldownTicks > 0 {
		runtime.portalCooldownTicks--
	}

	// Maker preview topology is deliberately stage-local. Keep the old latch
	// while a preview is active so entering a portal is delayed, not silently
	// consumed, until the preview has been cleared.
	if runtime.simulation.HasTemporaryPreview() ||
		len(runtime.pendingRemovals) != 0 {
		return nil
	}

	overlapping, err := portalOverlaps(runtime.built, runtime.simulation)
	if err != nil {
		return fmt.Errorf("evaluate stage portals: %w", err)
	}
	previous := runtime.portalInside
	runtime.portalInside = overlapping
	if runtime.portalCooldownTicks != 0 {
		return nil
	}
	for _, portal := range runtime.built.Stage.Portals {
		if !overlapping[portal.ID] || previous[portal.ID] {
			continue
		}
		return runtime.transitionPortalLocked(portal)
	}
	return nil
}

func (runtime *Runtime) transitionPortalLocked(
	portal gamebuild.Portal,
) error {
	if runtime.campaign == nil {
		return errors.New("portal transition: campaign is unavailable")
	}

	options := runtime.buildOptions
	options.StageID = portal.TargetStageID
	options.SpawnID = portal.TargetSpawnID
	nextCampaign, err := campaign.Restore(
		runtime.campaignConfig,
		runtime.campaign.Snapshot(),
	)
	if err != nil {
		return fmt.Errorf("portal %q clone campaign: %w", portal.ID, err)
	}
	if err := nextCampaign.Transaction(func(state *campaign.State) error {
		state.CurrentStageID = portal.TargetStageID
		state.EntrySpawnID = portal.TargetSpawnID
		return nil
	}); err != nil {
		return fmt.Errorf("portal %q update campaign location: %w", portal.ID, err)
	}
	built, simulation, err := buildCampaignSimulation(
		runtime.catalog,
		options,
		nextCampaign.Snapshot(),
		runtime.contentRules,
	)
	if err != nil {
		return fmt.Errorf(
			"portal %q transition to %s/%s: %w",
			portal.ID,
			portal.TargetStageID,
			portal.TargetSpawnID,
			err,
		)
	}
	if built.Stage.ID != portal.TargetStageID {
		return fmt.Errorf(
			"portal %q built stage %q, want %q",
			portal.ID,
			built.Stage.ID,
			portal.TargetStageID,
		)
	}
	portalInside, err := portalOverlaps(built, simulation)
	if err != nil {
		return fmt.Errorf(
			"portal %q seed target portal latch: %w",
			portal.ID,
			err,
		)
	}

	// Everything above is candidate work. The following assignments are the
	// single no-fail commit boundary for Campaign + World + stage-local input
	// and preview state.
	runtime.buildOptions = options
	runtime.built = built
	runtime.simulation = simulation
	runtime.campaign = nextCampaign
	runtime.virtual = make(map[string]virtualAction)
	runtime.pendingAbilities = make(map[string]bool)
	runtime.pendingRemovals = make(map[string]bool)
	runtime.moving = make(map[string]bool)
	runtime.resetPreviewLocked()
	runtime.resetRulePresentationLocked()
	runtime.resetFlowPresentationLocked()
	runtime.portalCooldownTicks = portal.CooldownTicks
	runtime.portalInside = portalInside
	return nil
}

func portalOverlaps(
	built *gamebuild.Result,
	simulation *sim.Simulation,
) (map[string]bool, error) {
	result := make(map[string]bool)
	if built == nil || simulation == nil {
		return result, nil
	}

	snapshot := simulation.Snapshot()
	entities := make(map[string]sim.EntitySnapshot, len(snapshot.Entities))
	for _, entity := range snapshot.Entities {
		entities[entity.ID] = entity
	}
	for _, portal := range built.Stage.Portals {
		tag := portal.ActorTag
		if tag == "" {
			tag = gamebuild.DefaultPortalActorTag
		}
		// App navigation follows the one semantic-input owner. ActorTag lets
		// content select a tag on that controlled actor; autonomous entities
		// cannot replace the player's Campaign location.
		for _, metadata := range built.Presentation.Instances {
			if !metadata.Controlled || !contains(metadata.Tags, tag) {
				continue
			}
			entity, exists := entities[metadata.ID]
			if !exists || entity.Dead {
				continue
			}
			overlaps, err := sim.WallOverlapsRect(
				sim.Wall{
					ID:     portal.ID,
					Rect:   portal.Rect,
					Points: portal.Points,
				},
				entityBodyRect(entity.Position, entity.Body),
			)
			if err != nil {
				return nil, fmt.Errorf(
					"portal %q has invalid collision geometry: %w",
					portal.ID,
					err,
				)
			}
			if overlaps {
				result[portal.ID] = true
				break
			}
		}
	}
	return result, nil
}

func entityBodyRect(position sim.Vec, body sim.Body) sim.Rect {
	return sim.Rect{
		MinX: position.X - body.HalfWidth,
		MinY: position.Y - body.HalfHeight,
		MaxX: position.X + body.HalfWidth,
		MaxY: position.Y + body.HalfHeight,
	}
}
