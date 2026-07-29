package gamebuild

import (
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/content"
)

const (
	maxSignedInt64 = int64(^uint64(0) >> 1)
	minSignedInt64 = -maxSignedInt64 - 1
)

// DerivedStats reports campaign-derived attack values for a fresh authored
// stage build. When AttackApplied is false, EffectiveAttackDamage is zero and
// AttackModifier remains available for a later combat-capable stage.
type DerivedStats struct {
	AttackModifier        int  `json:"attack_modifier"`
	EffectiveAttackDamage int  `json:"effective_attack_damage"`
	AttackApplied         bool `json:"attack_applied"`
}

// BuildForCampaign builds a fresh authored stage and derives its validated
// campaign loadout. The modifier is applied exactly once when the controlled
// actor has a primary ability and otherwise remains dormant.
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

	modifier, err := equippedAttackModifier(state, rules)
	if err != nil {
		return nil, DerivedStats{}, fmt.Errorf(
			"build for campaign: equipment: %w",
			err,
		)
	}
	if err := requireSupportedAttackInt(
		modifier,
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
	ability := built.Config.Entities[controlledIndex].PrimaryAbility()
	if ability == nil {
		return built, DerivedStats{
			AttackModifier: int(modifier),
		}, nil
	}
	if ability.Damage <= 0 {
		return nil, DerivedStats{}, fmt.Errorf(
			"build for campaign: controlled actor %q primary ability "+
				"has non-positive base damage %d",
			built.Config.Entities[controlledIndex].ID,
			ability.Damage,
		)
	}

	effective, err := checkedAttackAdd(int64(ability.Damage), modifier)
	if err != nil {
		return nil, DerivedStats{}, fmt.Errorf(
			"build for campaign: effective attack damage: %w",
			err,
		)
	}
	if effective <= 0 {
		return nil, DerivedStats{}, fmt.Errorf(
			"build for campaign: effective attack damage must be positive; "+
				"base=%d modifier=%d final=%d",
			ability.Damage,
			modifier,
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

	ability.Damage = int(effective)
	return built, DerivedStats{
		AttackModifier:        int(modifier),
		EffectiveAttackDamage: int(effective),
		AttackApplied:         true,
	}, nil
}

func equippedAttackModifier(
	state campaign.State,
	rules ContentRules,
) (int64, error) {
	var total int64
	for _, entry := range state.Equipment {
		if entry.ItemID == "" {
			continue
		}
		owned, exists := inventoryQuantity(state.Inventory, entry.ItemID)
		if !exists || owned <= 0 {
			return 0, fmt.Errorf(
				"equipped item %q in slot %q must be owned",
				entry.ItemID,
				entry.SlotID,
			)
		}
		item, exists := rules.Item(entry.ItemID)
		if !exists {
			return 0, fmt.Errorf(
				"equipped item %q has no configured item rule",
				entry.ItemID,
			)
		}
		if item.Equipment == nil {
			return 0, fmt.Errorf(
				"equipped item %q has no equipment rule",
				entry.ItemID,
			)
		}
		if item.Equipment.Slot != entry.SlotID {
			return 0, fmt.Errorf(
				"equipped item %q rule slot %q does not match state slot %q",
				entry.ItemID,
				item.Equipment.Slot,
				entry.SlotID,
			)
		}
		value, err := ruleSignedInteger(
			item.Equipment.AttackModifier,
			fmt.Sprintf(
				"equipped item %q attack modifier",
				entry.ItemID,
			),
		)
		if err != nil {
			return 0, err
		}
		total, err = checkedAttackAdd(total, int64(value))
		if err != nil {
			return 0, fmt.Errorf(
				"aggregate attack modifier after item %q: %w",
				entry.ItemID,
				err,
			)
		}
		if total < -campaign.MaxJSONInteger ||
			total > campaign.MaxJSONInteger {
			return 0, fmt.Errorf(
				"aggregate attack modifier %d exceeds the JSON-safe "+
					"integer range",
				total,
			)
		}
	}
	return total, nil
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
