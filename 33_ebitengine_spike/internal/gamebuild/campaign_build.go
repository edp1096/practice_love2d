package gamebuild

import (
	"fmt"
	"math"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/content"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

const (
	maxSignedInt64 = int64(^uint64(0) >> 1)
	minSignedInt64 = -maxSignedInt64 - 1
)

// DerivedStats reports campaign-derived RPG stat values for a fresh authored
// stage build. When AttackApplied is false, EffectiveAttackDamage is zero and
// equipment modifiers remain available for a later RPG-stat-capable stage.
type DerivedStats struct {
	AttackModifier        int     `json:"attack_modifier"`
	DefenseModifier       int     `json:"defense_modifier"`
	MoveSpeedModifier     float64 `json:"move_speed_modifier"`
	EffectiveAttackDamage int     `json:"effective_attack_damage"`
	AttackApplied         bool    `json:"attack_applied"`
}

type equipmentStatModifiers struct {
	attack    int64
	defense   int64
	moveSpeed float64
}

// BuildForCampaign builds a fresh authored stage and derives its validated
// campaign loadout. Equipment modifiers are applied exactly once to the
// controlled actor's authored RPG stats and otherwise remain dormant.
//
// The function never accepts or reuses a prior Result. Every error returns a
// nil Result and zero DerivedStats, so callers cannot observe a partial build.
func BuildForCampaign(
	catalog *content.Catalog,
	options Options,
	state campaign.State,
	rules ContentRules,
) (*Result, DerivedStats, error) {
	built, err := Build(catalog, options)
	if err != nil {
		return nil, DerivedStats{}, fmt.Errorf(
			"build for campaign: authored stage: %w",
			err,
		)
	}

	config, err := BuildCampaignConfig(catalog)
	if err != nil {
		return nil, DerivedStats{}, fmt.Errorf(
			"build for campaign: campaign config: %w",
			err,
		)
	}
	if err := state.Validate(config); err != nil {
		return nil, DerivedStats{}, fmt.Errorf(
			"build for campaign: invalid campaign state: %w",
			err,
		)
	}

	modifiers, err := equippedStatModifiers(state, rules)
	if err != nil {
		return nil, DerivedStats{}, fmt.Errorf(
			"build for campaign: equipment: %w",
			err,
		)
	}
	if err := requireSupportedAttackInt(
		modifiers.attack,
		"aggregate attack modifier",
	); err != nil {
		return nil, DerivedStats{}, fmt.Errorf(
			"build for campaign: equipment: %w",
			err,
		)
	}

	controlledIndex, err := controlledEntityIndex(built)
	if err != nil {
		return nil, DerivedStats{}, fmt.Errorf(
			"build for campaign: %w",
			err,
		)
	}
	if err := requireSupportedAttackInt(
		modifiers.defense,
		"aggregate defense modifier",
	); err != nil {
		return nil, DerivedStats{}, fmt.Errorf(
			"build for campaign: equipment: %w",
			err,
		)
	}
	entity := &built.Config.Entities[controlledIndex]
	if entity.Stats != nil {
		effective, err := applyEquipmentStats(*entity.Stats, modifiers)
		if err != nil {
			return nil, DerivedStats{}, fmt.Errorf(
				"build for campaign: equipment stats: %w",
				err,
			)
		}
		entity.Stats = &effective
	}
	derived := DerivedStats{
		AttackModifier:    int(modifiers.attack),
		DefenseModifier:   int(modifiers.defense),
		MoveSpeedModifier: modifiers.moveSpeed,
	}
	ability := entity.PrimaryAbility()
	if ability == nil {
		return built, derived, nil
	}
	if ability.Damage <= 0 {
		return nil, DerivedStats{}, fmt.Errorf(
			"build for campaign: controlled actor %q primary ability "+
				"has non-positive base damage %d",
			entity.ID,
			ability.Damage,
		)
	}
	attack := int64(0)
	if entity.Stats != nil {
		attack = int64(entity.Stats.Attack)
	}
	effective, err := checkedAttackAdd(int64(ability.Damage), attack)
	if err != nil {
		return nil, DerivedStats{}, fmt.Errorf(
			"build for campaign: effective attack damage: %w",
			err,
		)
	}
	if effective <= 0 {
		return nil, DerivedStats{}, fmt.Errorf(
			"build for campaign: effective attack damage must be positive; "+
				"base=%d attack=%d final=%d",
			ability.Damage,
			attack,
			effective,
		)
	}
	if effective > campaign.MaxJSONInteger {
		return nil, DerivedStats{}, fmt.Errorf(
			"build for campaign: effective attack damage %d exceeds "+
				"the JSON-safe integer range",
			effective,
		)
	}
	if err := requireSupportedAttackInt(
		effective,
		"effective attack damage",
	); err != nil {
		return nil, DerivedStats{}, fmt.Errorf(
			"build for campaign: %w",
			err,
		)
	}

	derived.EffectiveAttackDamage = int(effective)
	derived.AttackApplied = true
	return built, derived, nil
}

func equippedStatModifiers(
	state campaign.State,
	rules ContentRules,
) (equipmentStatModifiers, error) {
	var total equipmentStatModifiers
	for _, entry := range state.Equipment {
		if entry.ItemID == "" {
			continue
		}
		owned, exists := inventoryQuantity(state.Inventory, entry.ItemID)
		if !exists || owned <= 0 {
			return equipmentStatModifiers{}, fmt.Errorf(
				"equipped item %q in slot %q must be owned",
				entry.ItemID,
				entry.SlotID,
			)
		}
		item, exists := rules.Item(entry.ItemID)
		if !exists {
			return equipmentStatModifiers{}, fmt.Errorf(
				"equipped item %q has no configured item rule",
				entry.ItemID,
			)
		}
		if item.Equipment == nil {
			return equipmentStatModifiers{}, fmt.Errorf(
				"equipped item %q has no equipment rule",
				entry.ItemID,
			)
		}
		if item.Equipment.Slot != entry.SlotID {
			return equipmentStatModifiers{}, fmt.Errorf(
				"equipped item %q rule slot %q does not match state slot %q",
				entry.ItemID,
				item.Equipment.Slot,
				entry.SlotID,
			)
		}
		for _, field := range []struct {
			name   string
			value  float64
			target *int64
		}{
			{
				name:   "attack",
				value:  item.Equipment.AttackModifier,
				target: &total.attack,
			},
			{
				name:   "defense",
				value:  item.Equipment.DefenseModifier,
				target: &total.defense,
			},
		} {
			value, err := ruleSignedInteger(
				field.value,
				fmt.Sprintf(
					"equipped item %q %s modifier",
					entry.ItemID,
					field.name,
				),
			)
			if err != nil {
				return equipmentStatModifiers{}, err
			}
			*field.target, err = checkedAttackAdd(
				*field.target,
				int64(value),
			)
			if err != nil {
				return equipmentStatModifiers{}, fmt.Errorf(
					"aggregate %s modifier after item %q: %w",
					field.name,
					entry.ItemID,
					err,
				)
			}
			if *field.target < -campaign.MaxJSONInteger ||
				*field.target > campaign.MaxJSONInteger {
				return equipmentStatModifiers{}, fmt.Errorf(
					"aggregate %s modifier %d exceeds the JSON-safe "+
						"integer range",
					field.name,
					*field.target,
				)
			}
		}
		move := item.Equipment.MoveSpeedModifier
		if !finite(move) || math.Abs(move) > 16 {
			return equipmentStatModifiers{}, fmt.Errorf(
				"equipped item %q move_speed modifier is invalid",
				entry.ItemID,
			)
		}
		total.moveSpeed += move
		if !finite(total.moveSpeed) || math.Abs(total.moveSpeed) > 16 {
			return equipmentStatModifiers{}, fmt.Errorf(
				"aggregate move_speed modifier %.6g is outside [-16, 16]",
				total.moveSpeed,
			)
		}
	}
	return total, nil
}

func applyEquipmentStats(
	base sim.RPGStatsConfig,
	modifiers equipmentStatModifiers,
) (sim.RPGStatsConfig, error) {
	attack, err := checkedAttackAdd(
		int64(base.Attack),
		modifiers.attack,
	)
	if err != nil {
		return sim.RPGStatsConfig{}, fmt.Errorf("attack: %w", err)
	}
	defense, err := checkedAttackAdd(
		int64(base.Defense),
		modifiers.defense,
	)
	if err != nil {
		return sim.RPGStatsConfig{}, fmt.Errorf("defense: %w", err)
	}
	attack = max(int64(0), attack)
	defense = max(int64(0), defense)
	if attack > int64(1<<31-1) || defense > int64(1<<31-1) {
		return sim.RPGStatsConfig{}, fmt.Errorf(
			"attack or defense exceeds the portable integer range",
		)
	}
	moveDelta := int64(math.Round(
		modifiers.moveSpeed * float64(sim.UnitsPerPixel),
	))
	move, err := checkedAttackAdd(int64(base.MoveSpeed), moveDelta)
	if err != nil {
		return sim.RPGStatsConfig{}, fmt.Errorf("move_speed: %w", err)
	}
	move = max(int64(0), move)
	if move > int64(16*sim.UnitsPerPixel) {
		return sim.RPGStatsConfig{}, fmt.Errorf(
			"effective move_speed %.6g exceeds 16",
			float64(move)/float64(sim.UnitsPerPixel),
		)
	}
	return sim.RPGStatsConfig{
		Attack:    int(attack),
		Defense:   int(defense),
		MoveSpeed: sim.Coord(move),
	}, nil
}

func inventoryQuantity(
	inventory []campaign.InventoryEntry,
	itemID string,
) (int64, bool) {
	for _, entry := range inventory {
		if entry.ItemID == itemID {
			return entry.Quantity, true
		}
	}
	return 0, false
}

func controlledEntityIndex(result *Result) (int, error) {
	if result == nil {
		return -1, fmt.Errorf("fresh authored result is nil")
	}
	index := -1
	for candidate := range result.Config.Entities {
		if !result.Config.Entities[candidate].Controlled {
			continue
		}
		if index >= 0 {
			return -1, fmt.Errorf(
				"fresh authored result has more than one controlled actor",
			)
		}
		index = candidate
	}
	if index < 0 {
		return -1, fmt.Errorf(
			"fresh authored result has no controlled actor",
		)
	}
	return index, nil
}

func checkedAttackAdd(left int64, right int64) (int64, error) {
	if right > 0 && left > maxSignedInt64-right {
		return 0, fmt.Errorf("signed integer overflow")
	}
	if right < 0 && left < minSignedInt64-right {
		return 0, fmt.Errorf("signed integer underflow")
	}
	return left + right, nil
}

func requireSupportedAttackInt(value int64, name string) error {
	maximum := int64(^uint(0) >> 1)
	minimum := -maximum - 1
	if value < minimum || value > maximum {
		return fmt.Errorf(
			"%s %d exceeds the supported integer range",
			name,
			value,
		)
	}
	return nil
}
