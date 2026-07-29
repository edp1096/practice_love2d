package gameapp

import (
	"errors"
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/rulesruntime"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

// EquipmentMutationResult is the debug/UI acknowledgement for one atomic
// Campaign equipment change and its derived World rebuild.
type EquipmentMutationResult struct {
	Changed                   bool    `json:"changed"`
	SlotID                    string  `json:"slot_id"`
	ItemID                    string  `json:"item_id"`
	PreviousItemID            string  `json:"previous_item_id"`
	AttackModifier            float64 `json:"attack_modifier"`
	PreviousAttackModifier    float64 `json:"previous_attack_modifier"`
	DefenseModifier           float64 `json:"defense_modifier"`
	PreviousDefenseModifier   float64 `json:"previous_defense_modifier"`
	MoveSpeedModifier         float64 `json:"move_speed_modifier"`
	PreviousMoveSpeedModifier float64 `json:"previous_move_speed_modifier"`
	EffectiveAttack           int     `json:"effective_attack"`
	EffectiveDefense          int     `json:"effective_defense"`
	EffectiveMoveSpeed        float64 `json:"effective_move_speed"`
	EffectiveAttackDamage     int     `json:"effective_attack_damage"`
	Revision                  uint64  `json:"revision"`
}

func (runtime *Runtime) EquipCampaignItem(
	itemID string,
) (EquipmentMutationResult, error) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	return runtime.equipCampaignItemLocked(itemID)
}

func (runtime *Runtime) equipCampaignItemLocked(
	itemID string,
) (EquipmentMutationResult, error) {
	if itemID == "" {
		return EquipmentMutationResult{}, errors.New(
			"equip campaign item: item id is empty",
		)
	}
	return runtime.changeCampaignEquipmentLocked(func() (
		rulesruntime.EquipmentChangeResult,
		error,
	) {
		return runtime.ruleExecutor.EquipItem(runtime.campaign, itemID)
	})
}

func (runtime *Runtime) UnequipCampaignItem(
	slotID string,
) (EquipmentMutationResult, error) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	return runtime.unequipCampaignItemLocked(slotID)
}

func (runtime *Runtime) unequipCampaignItemLocked(
	slotID string,
) (EquipmentMutationResult, error) {
	if slotID == "" {
		return EquipmentMutationResult{}, errors.New(
			"unequip campaign item: slot id is empty",
		)
	}
	return runtime.changeCampaignEquipmentLocked(func() (
		rulesruntime.EquipmentChangeResult,
		error,
	) {
		return runtime.ruleExecutor.UnequipItem(runtime.campaign, slotID)
	})
}

func (runtime *Runtime) changeCampaignEquipmentLocked(
	mutate func() (rulesruntime.EquipmentChangeResult, error),
) (EquipmentMutationResult, error) {
	if mutate == nil {
		return EquipmentMutationResult{}, errors.New(
			"change campaign equipment: mutation is nil",
		)
	}
	if err := runtime.requireCampaignRebuildSafeLocked(false); err != nil {
		return EquipmentMutationResult{}, err
	}
	checkpoint := runtime.checkpointLocked()
	if err := runtime.detachMutableLocked(checkpoint); err != nil {
		return EquipmentMutationResult{}, err
	}
	change, err := mutate()
	if err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return EquipmentMutationResult{}, err
	}
	if !change.Changed {
		// A successful rules-level no-op must not rebind otherwise identical
		// candidates or create an observable revision.
		runtime.restoreCheckpointLocked(checkpoint)
		return runtime.equipmentMutationResultLocked(change), nil
	}
	if err := runtime.reconcileCampaignWorldLocked(false); err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return EquipmentMutationResult{}, fmt.Errorf(
			"change campaign equipment: %w",
			err,
		)
	}
	runtime.revision++
	return runtime.equipmentMutationResultLocked(change), nil
}

func (runtime *Runtime) equipmentMutationResultLocked(
	change rulesruntime.EquipmentChangeResult,
) EquipmentMutationResult {
	stats := runtime.controlledStatsLocked()
	return EquipmentMutationResult{
		Changed:                   change.Changed,
		SlotID:                    change.SlotID,
		ItemID:                    change.ItemID,
		PreviousItemID:            change.PreviousItemID,
		AttackModifier:            change.AttackModifier,
		PreviousAttackModifier:    change.PreviousAttackModifier,
		DefenseModifier:           change.DefenseModifier,
		PreviousDefenseModifier:   change.PreviousDefenseModifier,
		MoveSpeedModifier:         change.MoveSpeedModifier,
		PreviousMoveSpeedModifier: change.PreviousMoveSpeedModifier,
		EffectiveAttack:           stats.Attack,
		EffectiveDefense:          stats.Defense,
		EffectiveMoveSpeed: float64(stats.MoveSpeed) /
			float64(sim.UnitsPerPixel),
		EffectiveAttackDamage: runtime.controlledAttackDamageLocked(),
		Revision:              runtime.revision,
	}
}

func (runtime *Runtime) controlledAttackDamageLocked() int {
	controlledID := runtime.built.Config.Camera.TargetEntityID
	for _, entity := range runtime.built.Config.Entities {
		if entity.ID != controlledID && !entity.Controlled {
			continue
		}
		ability := entity.PrimaryAbility()
		if ability == nil {
			return 0
		}
		damage := ability.Damage
		if entity.Stats != nil {
			damage += entity.Stats.Attack
		}
		return damage
	}
	return 0
}

func (runtime *Runtime) controlledStatsLocked() sim.RPGStatsConfig {
	controlledID := runtime.built.Config.Camera.TargetEntityID
	for _, entity := range runtime.built.Config.Entities {
		if entity.ID != controlledID && !entity.Controlled {
			continue
		}
		if entity.Stats != nil {
			return *entity.Stats
		}
		return sim.RPGStatsConfig{MoveSpeed: sim.UnitsPerPixel}
	}
	return sim.RPGStatsConfig{MoveSpeed: sim.UnitsPerPixel}
}
