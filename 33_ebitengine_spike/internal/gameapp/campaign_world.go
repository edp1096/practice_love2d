package gameapp

import (
	"errors"
	"fmt"
	"reflect"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

type campaignRebuildBlockedError struct {
	message    string
	deferrable bool
}

func (err *campaignRebuildBlockedError) Error() string {
	return err.message
}

func campaignRebuildBlocked(message string, deferrable bool) error {
	return &campaignRebuildBlockedError{
		message:    message,
		deferrable: deferrable,
	}
}

func isCampaignRebuildBlocked(err error) bool {
	var blocked *campaignRebuildBlockedError
	return errors.As(err, &blocked)
}

func isCampaignRebuildDeferrable(err error) bool {
	var blocked *campaignRebuildBlockedError
	return errors.As(err, &blocked) && blocked.deferrable
}

// buildCampaignSimulation is the only constructor for a player-owned World.
// BuildForCampaign always starts from authored base content, so an equipped
// modifier is applied once rather than accumulating across rebuilds.
func buildCampaignSimulation(
	catalog *content.Catalog,
	options gamebuild.Options,
	state campaign.State,
	rules gamebuild.ContentRules,
) (*gamebuild.Result, *sim.Simulation, error) {
	built, _, err := gamebuild.BuildForCampaign(
		catalog,
		options,
		state,
		rules,
	)
	if err != nil {
		return nil, nil, fmt.Errorf("build game content for campaign: %w", err)
	}
	simulation, err := sim.New(built.Config)
	if err != nil {
		return nil, nil, fmt.Errorf("construct campaign simulation: %w", err)
	}
	return built, simulation, nil
}

// requireCampaignRebuildSafeLocked rejects states whose meaning depends on the
// immutable ability definition being replaced. Inventory itself is allowed so
// its equip action can rebuild the World while retaining modal selection.
func (runtime *Runtime) requireCampaignRebuildSafeLocked(
	allowAuthoredModal bool,
) error {
	if runtime.campaign == nil || runtime.ruleExecutor == nil {
		return errors.New("campaign rebuild: campaign rules are unavailable")
	}
	if runtime.simulation == nil || runtime.built == nil {
		return errors.New("campaign rebuild: world is unavailable")
	}
	if !allowAuthoredModal &&
		runtime.campaign.Snapshot().Mode != campaign.ModePlaying {
		return errors.New(
			"equipment change is unavailable while game flow is modal",
		)
	}
	if !allowAuthoredModal {
		if runtime.equipmentRebuildPending {
			return campaignRebuildBlocked(
				"equipment change is unavailable while an authored equipment rebuild is pending",
				false,
			)
		}
		if runtime.dialogue != nil {
			return campaignRebuildBlocked(
				"equipment change is unavailable while dialogue is active",
				false,
			)
		}
		if runtime.activeShopID != "" {
			return campaignRebuildBlocked(
				"equipment change is unavailable while a shop is active",
				false,
			)
		}
	}
	if runtime.simulation.HasTemporaryPreview() ||
		len(runtime.pendingRemovals) != 0 ||
		!simulationWallsEqual(
			runtime.simulation.RenderFrame().Walls,
			runtime.built.Config.Walls,
		) {
		return campaignRebuildBlocked(
			"equipment change is unavailable while Maker preview state is active",
			false,
		)
	}
	if len(runtime.pendingAbilities) != 0 ||
		virtualAttackPending(runtime.virtual) {
		return campaignRebuildBlocked(
			"equipment change is unavailable while an attack is queued",
			true,
		)
	}
	snapshot := runtime.simulation.Snapshot()
	if snapshot.Dialogue.Active {
		return campaignRebuildBlocked(
			"equipment change is unavailable while preview dialogue is active",
			false,
		)
	}
	if snapshot.HitstopTicks != 0 {
		return campaignRebuildBlocked(
			"equipment change is unavailable during hitstop",
			true,
		)
	}
	if len(snapshot.Projectiles) != 0 {
		return campaignRebuildBlocked(
			"equipment change is unavailable while projectiles are active",
			true,
		)
	}
	for _, encounter := range snapshot.Encounters {
		if encounter.Status == sim.EncounterPending ||
			encounter.Status == sim.EncounterActive {
			return campaignRebuildBlocked(
				fmt.Sprintf(
					"equipment change is unavailable while encounter %q is %s",
					encounter.ID,
					encounter.Status,
				),
				true,
			)
		}
	}
	for _, entity := range snapshot.Entities {
		if entity.Attack.Phase != sim.AttackIdle {
			return campaignRebuildBlocked(
				fmt.Sprintf(
					"equipment change is unavailable while entity %q is attacking",
					entity.ID,
				),
				true,
			)
		}
		if len(entity.Statuses) != 0 ||
			entity.StaggerTicks != 0 ||
			entity.KnockbackTicks != 0 ||
			entity.DodgeTicks != 0 ||
			entity.ParryTicks != 0 {
			return campaignRebuildBlocked(
				fmt.Sprintf(
					"equipment change is unavailable while entity %q has transient combat state",
					entity.ID,
				),
				true,
			)
		}
	}
	return nil
}

func simulationWallsEqual(left, right []sim.Wall) bool {
	if len(left) != len(right) {
		return false
	}
	byID := make(map[string]sim.Wall, len(right))
	for _, wall := range right {
		if _, duplicate := byID[wall.ID]; duplicate {
			return false
		}
		byID[wall.ID] = wall
	}
	for _, wall := range left {
		expected, exists := byID[wall.ID]
		if !exists || wall.Rect != expected.Rect ||
			len(wall.Points) != len(expected.Points) {
			return false
		}
		for pointIndex := range wall.Points {
			if wall.Points[pointIndex] != expected.Points[pointIndex] {
				return false
			}
		}
		delete(byID, wall.ID)
	}
	return len(byID) == 0
}

func virtualAttackPending(actions map[string]virtualAction) bool {
	for _, name := range []string{"attack", "special", "technique"} {
		action, exists := actions[name]
		if exists && action.value > 0 && action.remaining > 0 {
			return true
		}
	}
	return false
}

func (runtime *Runtime) rejectMakerMutationWhileEquipmentPendingLocked(
	operation string,
) error {
	if !runtime.equipmentRebuildPending {
		return nil
	}
	return fmt.Errorf(
		"%s is unavailable while an authored equipment rebuild is pending",
		operation,
	)
}

// reconcileCampaignWorldLocked rebuilds derived combat configuration after an
// authored rule transaction. It publishes only when Campaign equipment changed
// the immutable simulation config and the active session can be loaded in full.
func (runtime *Runtime) reconcileCampaignWorldLocked(
	allowAuthoredModal bool,
) error {
	built, candidate, err := buildCampaignSimulation(
		runtime.catalog,
		runtime.buildOptions,
		runtime.campaign.Snapshot(),
		runtime.contentRules,
	)
	if err != nil {
		return err
	}
	if reflect.DeepEqual(built.Config, runtime.built.Config) {
		runtime.equipmentRebuildPending = false
		return nil
	}
	if err := runtime.requireCampaignRebuildSafeLocked(
		allowAuthoredModal,
	); err != nil {
		return err
	}
	session := runtime.simulation.SaveSession()
	if err := candidate.LoadSession(session); err != nil {
		return fmt.Errorf(
			"campaign rebuild is incompatible with the active session: %w",
			err,
		)
	}
	portalInside, err := portalOverlaps(built, candidate)
	if err != nil {
		return fmt.Errorf("campaign rebuild portal latch: %w", err)
	}

	runtime.built = built
	runtime.simulation = candidate
	runtime.resetPreviewLocked()
	runtime.portalInside = portalInside
	runtime.equipmentRebuildPending = false
	return nil
}

func (runtime *Runtime) reconcileEquipmentChangeLocked(
	previous *campaign.Campaign,
	allowAuthoredModal bool,
) error {
	if previous == nil || runtime.campaign == nil {
		return errors.New(
			"campaign equipment reconciliation requires both campaign states",
		)
	}
	if reflect.DeepEqual(
		previous.Snapshot().Equipment,
		runtime.campaign.Snapshot().Equipment,
	) {
		return nil
	}
	err := runtime.reconcileCampaignWorldLocked(allowAuthoredModal)
	if allowAuthoredModal && isCampaignRebuildDeferrable(err) {
		// Authored rule actions own a deterministic Campaign transaction. Keep
		// that durable result and publish its derived immutable World config at
		// the first safe session boundary instead of rolling the action back on
		// every combat tick.
		runtime.equipmentRebuildPending = true
		return nil
	}
	return err
}

func (runtime *Runtime) publishPendingEquipmentRebuildLocked() error {
	if !runtime.equipmentRebuildPending {
		return nil
	}
	if err := runtime.requireCampaignRebuildSafeLocked(true); err != nil {
		if isCampaignRebuildDeferrable(err) {
			return nil
		}
		return err
	}
	err := runtime.reconcileCampaignWorldLocked(true)
	if isCampaignRebuildDeferrable(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("publish pending equipment rebuild: %w", err)
	}
	runtime.revision++
	return nil
}

// mergeResetBuild preserves deliberate in-process immutable-config overrides
// used by Maker/debug tooling while taking campaign-derived RPG stats only
// from the fresh BuildForCampaign result.
func mergeResetBuild(
	fresh *gamebuild.Result,
	current *gamebuild.Result,
) *gamebuild.Result {
	if fresh == nil || current == nil ||
		reflect.DeepEqual(fresh.Config, current.Config) {
		return fresh
	}
	result := *fresh
	result.Config = current.Config
	result.Config.Entities = append(
		[]sim.EntityConfig(nil),
		current.Config.Entities...,
	)
	freshStats := make(map[string]*sim.RPGStatsConfig)
	for _, entity := range fresh.Config.Entities {
		if entity.Stats == nil {
			freshStats[entity.ID] = nil
			continue
		}
		stats := *entity.Stats
		freshStats[entity.ID] = &stats
	}
	for index := range result.Config.Entities {
		entity := &result.Config.Entities[index]
		stats, exists := freshStats[entity.ID]
		if !exists {
			continue
		}
		if stats == nil {
			entity.Stats = nil
			continue
		}
		copy := *stats
		entity.Stats = &copy
	}
	return &result
}
