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
// pristine, per-slot modifier maximum, per-slot modifier minimum, then every
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

	profiles := make([]campaignBuildProfile, 0, 3+len(candidates))
	seen := make(map[string]struct{}, 3+len(candidates))
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

	maximal := make(map[string]string, len(prepared.EquipmentSlots))
	minimal := make(map[string]string, len(prepared.EquipmentSlots))
	for _, slotID := range prepared.EquipmentSlots {
		var maximum campaignEquipmentCandidate
		var minimum campaignEquipmentCandidate
		found := false
		for _, candidate := range candidates {
			if candidate.slotID != slotID {
				continue
			}
			if !found {
				maximum = candidate
				minimum = candidate
				found = true
				continue
			}
			if candidate.attackModifier > maximum.attackModifier {
				maximum = candidate
			}
			if candidate.attackModifier < minimum.attackModifier {
				minimum = candidate
			}
		}
		if found {
			maximal[slotID] = maximum.itemID
			minimal[slotID] = minimum.itemID
		}
	}
	for _, boundary := range []struct {
		name    string
		loadout map[string]string
	}{
		{name: "maximal", loadout: maximal},
		{name: "minimal", loadout: minimal},
	} {
		if err := appendCampaignBuildProfile(
			&profiles,
			seen,
			prepared,
			pristine,
			boundary.name,
			boundary.loadout,
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
	itemID         string
	slotID         string
	attackModifier int64
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
		modifier := rule.Equipment.AttackModifier
		if math.IsNaN(modifier) ||
			math.IsInf(modifier, 0) ||
			math.Trunc(modifier) != modifier {
			return nil, fmt.Errorf(
				"item %q attack modifier %v must be a finite integer",
				item.ID,
				modifier,
			)
		}
		if math.Abs(modifier) > float64(campaign.MaxJSONInteger) {
			return nil, fmt.Errorf(
				"item %q attack modifier %v exceeds the JSON-safe "+
					"integer range",
				item.ID,
				modifier,
			)
		}
		result = append(result, campaignEquipmentCandidate{
			itemID:         item.ID,
			slotID:         item.EquipmentSlot,
			attackModifier: int64(modifier),
		})
	}
	return result, nil
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
