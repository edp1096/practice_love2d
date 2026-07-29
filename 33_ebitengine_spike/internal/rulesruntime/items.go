package rulesruntime

import (
	"errors"
	"fmt"
	"sort"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
)

// UseItemResult describes one committed player-item use. ActionResult is
// embedded so the host can apply presentation and simulation intents in their
// authored order without losing the durable inventory outcome.
type UseItemResult struct {
	ActionResult

	ItemID            string `json:"item_id"`
	ConsumedQuantity  int64  `json:"consumed_quantity"`
	RemainingQuantity int64  `json:"remaining_quantity"`
}

// EquipmentChangeResult describes the complete before/after state of one
// equipment slot. Modifier values let a host update or rebuild derived combat
// stats without reaching into Executor's private rules snapshot.
type EquipmentChangeResult struct {
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
}

type equipmentModifiers struct {
	attack    float64
	defense   float64
	moveSpeed float64
}

// UseItem executes an authored consumable's effects and consumes exactly one
// owned item in the same Campaign transaction. A failed effect, inventory
// mutation, or final Campaign validation rolls back both durable effects and
// consumption and returns a zero result with no leaked intents.
//
// Intents are deliberately not applied here. In particular, a heal intent
// targets stage-local Simulation state, which Campaign cannot roll back. A host
// requiring full Campaign+Simulation atomicity must call UseItem on a detached
// Campaign candidate, apply every returned intent to a detached Simulation
// candidate, and publish both candidates only after all work succeeds.
func (executor *Executor) UseItem(
	live *campaign.Campaign,
	itemID string,
) (UseItemResult, error) {
	if executor == nil {
		return UseItemResult{}, errors.New("use item: executor is nil")
	}
	if live == nil {
		return UseItemResult{}, errors.New("use item: campaign is nil")
	}
	rule, exists := executor.rules.Item(itemID)
	if !exists {
		return UseItemResult{}, fmt.Errorf(
			"use item: item %q is not configured",
			itemID,
		)
	}
	if !rule.Consumable {
		return UseItemResult{}, fmt.Errorf(
			"use item: item %q is not consumable",
			itemID,
		)
	}

	var candidate UseItemResult
	err := live.Transaction(func(state *campaign.State) error {
		if err := executor.requireIdentity(state); err != nil {
			return err
		}
		entry, _, err := executor.inventoryEntry(state, itemID)
		if err != nil {
			return err
		}
		if entry.Quantity < 1 {
			return fmt.Errorf("item %q is not owned", itemID)
		}

		intents, err := executor.applyActions(state, rule.Effects, 0)
		if err != nil {
			return fmt.Errorf("apply effects: %w", err)
		}
		entry.Quantity--
		if intents == nil {
			intents = []Intent{}
		}
		candidate = UseItemResult{
			ActionResult:      ActionResult{Intents: intents},
			ItemID:            itemID,
			ConsumedQuantity:  1,
			RemainingQuantity: entry.Quantity,
		}
		return nil
	})
	if err != nil {
		return UseItemResult{}, fmt.Errorf("use item %q: %w", itemID, err)
	}
	return candidate, nil
}

// EquipItem equips one owned equipment item in its authored slot. Re-equipping
// the same item is a successful no-op with Changed=false.
func (executor *Executor) EquipItem(
	live *campaign.Campaign,
	itemID string,
) (EquipmentChangeResult, error) {
	if executor == nil {
		return EquipmentChangeResult{}, errors.New(
			"equip item: executor is nil",
		)
	}
	if live == nil {
		return EquipmentChangeResult{}, errors.New(
			"equip item: campaign is nil",
		)
	}
	rule, exists := executor.rules.Item(itemID)
	if !exists {
		return EquipmentChangeResult{}, fmt.Errorf(
			"equip item: item %q is not configured",
			itemID,
		)
	}
	if rule.Equipment == nil {
		return EquipmentChangeResult{}, fmt.Errorf(
			"equip item: item %q is not equipment",
			itemID,
		)
	}

	var candidate EquipmentChangeResult
	err := live.Transaction(func(state *campaign.State) error {
		if err := executor.requireIdentity(state); err != nil {
			return err
		}
		entry, definition, err := executor.inventoryEntry(state, itemID)
		if err != nil {
			return err
		}
		if definition.EquipmentSlot == "" ||
			definition.EquipmentSlot != rule.Equipment.Slot {
			return fmt.Errorf(
				"item %q equipment slot %q does not match rule slot %q",
				itemID,
				definition.EquipmentSlot,
				rule.Equipment.Slot,
			)
		}
		if entry.Quantity < 1 {
			return fmt.Errorf("item %q is not owned", itemID)
		}
		slot, _, err := findEquipmentEntry(
			state,
			definition.EquipmentSlot,
		)
		if err != nil {
			return err
		}
		previousModifiers, err := executor.itemModifiers(
			slot.ItemID,
			definition.EquipmentSlot,
		)
		if err != nil {
			return err
		}
		previous := slot.ItemID
		slot.ItemID = itemID
		candidate = EquipmentChangeResult{
			Changed:                   previous != itemID,
			SlotID:                    definition.EquipmentSlot,
			ItemID:                    itemID,
			PreviousItemID:            previous,
			AttackModifier:            rule.Equipment.AttackModifier,
			PreviousAttackModifier:    previousModifiers.attack,
			DefenseModifier:           rule.Equipment.DefenseModifier,
			PreviousDefenseModifier:   previousModifiers.defense,
			MoveSpeedModifier:         rule.Equipment.MoveSpeedModifier,
			PreviousMoveSpeedModifier: previousModifiers.moveSpeed,
		}
		return nil
	})
	if err != nil {
		return EquipmentChangeResult{}, fmt.Errorf(
			"equip item %q: %w",
			itemID,
			err,
		)
	}
	return candidate, nil
}

// UnequipItem clears one configured equipment slot. Clearing an already empty
// slot is a successful no-op with Changed=false.
func (executor *Executor) UnequipItem(
	live *campaign.Campaign,
	slotID string,
) (EquipmentChangeResult, error) {
	if executor == nil {
		return EquipmentChangeResult{}, errors.New(
			"unequip item: executor is nil",
		)
	}
	if live == nil {
		return EquipmentChangeResult{}, errors.New(
			"unequip item: campaign is nil",
		)
	}
	index := sort.SearchStrings(executor.config.EquipmentSlots, slotID)
	if index == len(executor.config.EquipmentSlots) ||
		executor.config.EquipmentSlots[index] != slotID {
		return EquipmentChangeResult{}, fmt.Errorf(
			"unequip item: equipment slot %q is not configured",
			slotID,
		)
	}

	var candidate EquipmentChangeResult
	err := live.Transaction(func(state *campaign.State) error {
		if err := executor.requireIdentity(state); err != nil {
			return err
		}
		slot, _, err := findEquipmentEntry(state, slotID)
		if err != nil {
			return err
		}
		previousModifiers, err := executor.itemModifiers(
			slot.ItemID,
			slotID,
		)
		if err != nil {
			return err
		}
		previous := slot.ItemID
		slot.ItemID = ""
		candidate = EquipmentChangeResult{
			Changed:                   previous != "",
			SlotID:                    slotID,
			ItemID:                    "",
			PreviousItemID:            previous,
			PreviousAttackModifier:    previousModifiers.attack,
			PreviousDefenseModifier:   previousModifiers.defense,
			PreviousMoveSpeedModifier: previousModifiers.moveSpeed,
		}
		return nil
	})
	if err != nil {
		return EquipmentChangeResult{}, fmt.Errorf(
			"unequip item %q: %w",
			slotID,
			err,
		)
	}
	return candidate, nil
}

func (executor *Executor) itemModifiers(
	itemID string,
	slotID string,
) (equipmentModifiers, error) {
	if itemID == "" {
		return equipmentModifiers{}, nil
	}
	rule, exists := executor.rules.Item(itemID)
	if !exists {
		return equipmentModifiers{}, fmt.Errorf(
			"equipped item %q is not configured",
			itemID,
		)
	}
	if rule.Equipment == nil {
		return equipmentModifiers{}, fmt.Errorf(
			"equipped item %q has no equipment rule",
			itemID,
		)
	}
	if rule.Equipment.Slot != slotID {
		return equipmentModifiers{}, fmt.Errorf(
			"equipped item %q belongs to slot %q, not %q",
			itemID,
			rule.Equipment.Slot,
			slotID,
		)
	}
	return equipmentModifiers{
		attack:    rule.Equipment.AttackModifier,
		defense:   rule.Equipment.DefenseModifier,
		moveSpeed: rule.Equipment.MoveSpeedModifier,
	}, nil
}
