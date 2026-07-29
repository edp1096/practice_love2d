package projectcheck

import (
	"fmt"
	"math"
	"strings"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/gamebuild"
)

type campaignBuildProfile struct {
	name  string
	state campaign.State
}

// campaignBuildProfiles returns unique equipment states in review order:
// pristine, per-slot maxima/minima for every supported RPG stat, then every
// equippable item alone in canonical item-ID order. Earlier names win when two
// requested profiles resolve to the same equipment state.
func campaignBuildProfiles(
	config campaign.Config,
	rules gamebuild.ContentRules,
) ([]campaignBuildProfile, error) {
	current, err := campaign.NewGame(config)
	if err != nil {
		return nil, fmt.Errorf("create pristine campaign: %w", err)
	}
	pristine := current.Snapshot()
	prepared := current.Config()
	candidates, err := campaignEquipmentCandidates(prepared, rules)
	if err != nil {
		return nil, fmt.Errorf("equipment topology: %w", err)
	}

	profiles := make([]campaignBuildProfile, 0, 7+len(candidates))
	seen := make(map[string]struct{}, 7+len(candidates))
	if err := appendCampaignBuildProfile(
		&profiles,
		seen,
		prepared,
		pristine,
		"pristine",
		nil,
	); err != nil {
		return nil, err
	}

	for _, boundary := range []struct {
		name    string
		value   func(campaignEquipmentCandidate) float64
		maximum bool
	}{
		{
			name: "maximal",
			value: func(candidate campaignEquipmentCandidate) float64 {
				return float64(candidate.attackModifier)
			},
			maximum: true,
		},
		{
			name: "minimal",
			value: func(candidate campaignEquipmentCandidate) float64 {
				return float64(candidate.attackModifier)
			},
		},
		{
			name: "maximal-defense",
			value: func(candidate campaignEquipmentCandidate) float64 {
				return float64(candidate.defenseModifier)
			},
			maximum: true,
		},
		{
			name: "minimal-defense",
			value: func(candidate campaignEquipmentCandidate) float64 {
				return float64(candidate.defenseModifier)
			},
		},
		{
			name: "maximal-move-speed",
			value: func(candidate campaignEquipmentCandidate) float64 {
				return candidate.moveSpeedModifier
			},
			maximum: true,
		},
		{
			name: "minimal-move-speed",
			value: func(candidate campaignEquipmentCandidate) float64 {
				return candidate.moveSpeedModifier
			},
		},
	} {
		loadout := equipmentBoundaryLoadout(
			prepared.EquipmentSlots,
			candidates,
			boundary.value,
			boundary.maximum,
		)
		if err := appendCampaignBuildProfile(
			&profiles,
			seen,
			prepared,
			pristine,
			boundary.name,
			loadout,
		); err != nil {
			return nil, err
		}
	}
	for _, candidate := range candidates {
		if err := appendCampaignBuildProfile(
			&profiles,
			seen,
			prepared,
			pristine,
			candidate.itemID,
			map[string]string{
				candidate.slotID: candidate.itemID,
			},
		); err != nil {
			return nil, err
		}
	}
	return profiles, nil
}

type campaignEquipmentCandidate struct {
	itemID            string
	slotID            string
	attackModifier    int64
	defenseModifier   int64
	moveSpeedModifier float64
}

func equipmentBoundaryLoadout(
	slots []string,
	candidates []campaignEquipmentCandidate,
	value func(campaignEquipmentCandidate) float64,
	maximum bool,
) map[string]string {
	loadout := make(map[string]string, len(slots))
	for _, slotID := range slots {
		var selected campaignEquipmentCandidate
		found := false
		for _, candidate := range candidates {
			if candidate.slotID != slotID {
				continue
			}
			if !found {
				selected = candidate
				found = true
				continue
			}
			candidateValue := value(candidate)
			selectedValue := value(selected)
			if maximum && candidateValue > selectedValue ||
				!maximum && candidateValue < selectedValue {
				selected = candidate
			}
		}
		if found {
			loadout[slotID] = selected.itemID
		}
	}
	return loadout
}

func campaignEquipmentCandidates(
	config campaign.Config,
	rules gamebuild.ContentRules,
) ([]campaignEquipmentCandidate, error) {
	if len(rules.Items) != len(config.Items) {
		return nil, fmt.Errorf(
			"content rules define %d items; campaign config defines %d",
			len(rules.Items),
			len(config.Items),
		)
	}
	result := make([]campaignEquipmentCandidate, 0, len(config.Items))
	for index, item := range config.Items {
		rule := rules.Items[index]
		if rule.ID != item.ID {
			return nil, fmt.Errorf(
				"content rule item %d is %q; campaign item is %q",
				index,
				rule.ID,
				item.ID,
			)
		}
		if item.EquipmentSlot == "" {
			if rule.Equipment != nil {
				return nil, fmt.Errorf(
					"item %q has an equipment rule for slot %q but "+
						"the campaign item is not equipment",
					item.ID,
					rule.Equipment.Slot,
				)
			}
			continue
		}
		if rule.Equipment == nil {
			return nil, fmt.Errorf(
				"item %q campaign slot %q has no equipment rule",
				item.ID,
				item.EquipmentSlot,
			)
		}
		if rule.Equipment.Slot != item.EquipmentSlot {
			return nil, fmt.Errorf(
				"item %q rule slot %q does not match campaign slot %q",
				item.ID,
				rule.Equipment.Slot,
				item.EquipmentSlot,
			)
		}
		attack, err := projectIntegerModifier(
			item.ID,
			"attack",
			rule.Equipment.AttackModifier,
		)
		if err != nil {
			return nil, err
		}
		defense, err := projectIntegerModifier(
			item.ID,
			"defense",
			rule.Equipment.DefenseModifier,
		)
		if err != nil {
			return nil, err
		}
		moveSpeed := rule.Equipment.MoveSpeedModifier
		if math.IsNaN(moveSpeed) ||
			math.IsInf(moveSpeed, 0) ||
			math.Abs(moveSpeed) > 16 {
			return nil, fmt.Errorf(
				"item %q move_speed modifier %v must be finite and "+
					"between -16 and 16",
				item.ID,
				moveSpeed,
			)
		}
		result = append(result, campaignEquipmentCandidate{
			itemID:            item.ID,
			slotID:            item.EquipmentSlot,
			attackModifier:    attack,
			defenseModifier:   defense,
			moveSpeedModifier: moveSpeed,
		})
	}
	return result, nil
}

func projectIntegerModifier(
	itemID string,
	name string,
	modifier float64,
) (int64, error) {
	if math.IsNaN(modifier) ||
		math.IsInf(modifier, 0) ||
		math.Trunc(modifier) != modifier {
		return 0, fmt.Errorf(
			"item %q %s modifier %v must be a finite integer",
			itemID,
			name,
			modifier,
		)
	}
	if math.Abs(modifier) > float64(campaign.MaxJSONInteger) {
		return 0, fmt.Errorf(
			"item %q %s modifier %v exceeds the JSON-safe integer range",
			itemID,
			name,
			modifier,
		)
	}
	return int64(modifier), nil
}

func appendCampaignBuildProfile(
	profiles *[]campaignBuildProfile,
	seen map[string]struct{},
	config campaign.Config,
	pristine campaign.State,
	name string,
	loadout map[string]string,
) error {
	state := pristine.Clone()
	inventoryByID := make(
		map[string]*campaign.InventoryEntry,
		len(state.Inventory),
	)
	for index := range state.Inventory {
		entry := &state.Inventory[index]
		inventoryByID[entry.ItemID] = entry
	}
	for index := range state.Equipment {
		entry := &state.Equipment[index]
		itemID := loadout[entry.SlotID]
		if itemID == "" {
			continue
		}
		inventory, exists := inventoryByID[itemID]
		if !exists {
			return fmt.Errorf(
				"create campaign profile %q: slot %q selected "+
					"unknown item %q",
				name,
				entry.SlotID,
				itemID,
			)
		}
		inventory.Quantity = 1
		entry.ItemID = itemID
	}
	restored, err := campaign.Restore(config, state)
	if err != nil {
		return fmt.Errorf(
			"create campaign profile %q: %w",
			name,
			err,
		)
	}
	state = restored.Snapshot()
	key := campaignEquipmentStateKey(state)
	if _, duplicate := seen[key]; duplicate {
		return nil
	}
	seen[key] = struct{}{}
	*profiles = append(*profiles, campaignBuildProfile{
		name:  name,
		state: state,
	})
	return nil
}

func campaignEquipmentStateKey(state campaign.State) string {
	var key strings.Builder
	for _, entry := range state.Equipment {
		key.WriteString(entry.SlotID)
		key.WriteByte('=')
		key.WriteString(entry.ItemID)
		key.WriteByte(0)
	}
	return key.String()
}
