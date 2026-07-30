package rulesruntime

import (
	"fmt"
	"sort"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
)

// The campaign package canonicalizes each topology slice by ID. These helpers
// use binary search and verify the ID at the found index so a positional
// mismatch fails explicitly instead of mutating the wrong durable record.

func (executor *Executor) inventoryEntry(
	state *campaign.State,
	itemID string,
) (*campaign.InventoryEntry, campaign.ItemDefinition, error) {
	definition, definitionIndex, err := findItemDefinition(
		executor.config,
		itemID,
	)
	if err != nil {
		return nil, campaign.ItemDefinition{}, err
	}
	if definitionIndex >= len(state.Inventory) ||
		state.Inventory[definitionIndex].ItemID != itemID {
		return nil, campaign.ItemDefinition{}, fmt.Errorf(
			"campaign inventory is not in canonical item-ID order at %q",
			itemID,
		)
	}
	return &state.Inventory[definitionIndex], definition, nil
}

func findItemDefinition(
	config campaign.Config,
	id string,
) (campaign.ItemDefinition, int, error) {
	index := sort.Search(len(config.Items), func(index int) bool {
		return config.Items[index].ID >= id
	})
	if index == len(config.Items) || config.Items[index].ID != id {
		return campaign.ItemDefinition{}, 0, fmt.Errorf(
			"item %q is not configured",
			id,
		)
	}
	return config.Items[index], index, nil
}

func findQuestDefinition(
	config campaign.Config,
	id string,
) (campaign.QuestDefinition, int, error) {
	index := sort.Search(len(config.Quests), func(index int) bool {
		return config.Quests[index].ID >= id
	})
	if index == len(config.Quests) || config.Quests[index].ID != id {
		return campaign.QuestDefinition{}, 0, fmt.Errorf(
			"quest %q is not configured",
			id,
		)
	}
	return config.Quests[index], index, nil
}

func findTurnBattleDefinition(
	config campaign.Config,
	id string,
) (campaign.TurnBattleDefinition, int, error) {
	index := sort.Search(len(config.TurnBattles), func(index int) bool {
		return config.TurnBattles[index].ID >= id
	})
	if index == len(config.TurnBattles) ||
		config.TurnBattles[index].ID != id {
		return campaign.TurnBattleDefinition{}, 0, fmt.Errorf(
			"turn battle %q is not configured",
			id,
		)
	}
	return config.TurnBattles[index], index, nil
}

func findTurnBattleState(
	state *campaign.State,
	id string,
) (*campaign.TurnBattleState, int, error) {
	index := sort.Search(len(state.TurnBattles), func(index int) bool {
		return state.TurnBattles[index].ID >= id
	})
	if index == len(state.TurnBattles) ||
		state.TurnBattles[index].ID != id {
		return nil, 0, fmt.Errorf(
			"campaign turn battle state %q is missing or not canonical",
			id,
		)
	}
	return &state.TurnBattles[index], index, nil
}

func findObjectiveDefinition(
	quest campaign.QuestDefinition,
	id string,
) (campaign.ObjectiveDefinition, int, error) {
	index := sort.Search(len(quest.Objectives), func(index int) bool {
		return quest.Objectives[index].ID >= id
	})
	if index == len(quest.Objectives) ||
		quest.Objectives[index].ID != id {
		return campaign.ObjectiveDefinition{}, 0, fmt.Errorf(
			"quest %q objective %q is not configured",
			quest.ID,
			id,
		)
	}
	return quest.Objectives[index], index, nil
}

func findQuestState(
	state *campaign.State,
	id string,
) (*campaign.QuestState, int, error) {
	index := sort.Search(len(state.Quests), func(index int) bool {
		return state.Quests[index].ID >= id
	})
	if index == len(state.Quests) || state.Quests[index].ID != id {
		return nil, 0, fmt.Errorf(
			"campaign quest state %q is missing or not canonical",
			id,
		)
	}
	return &state.Quests[index], index, nil
}

func findObjectiveState(
	quest *campaign.QuestState,
	id string,
) (*campaign.ObjectiveState, int, error) {
	index := sort.Search(len(quest.Objectives), func(index int) bool {
		return quest.Objectives[index].ID >= id
	})
	if index == len(quest.Objectives) ||
		quest.Objectives[index].ID != id {
		return nil, 0, fmt.Errorf(
			"campaign quest %q objective state %q is missing or not canonical",
			quest.ID,
			id,
		)
	}
	return &quest.Objectives[index], index, nil
}

func findFlagState(
	state *campaign.State,
	id string,
) (*campaign.FlagState, int, error) {
	index := sort.Search(len(state.Flags), func(index int) bool {
		return state.Flags[index].ID >= id
	})
	if index == len(state.Flags) || state.Flags[index].ID != id {
		return nil, 0, fmt.Errorf(
			"campaign flag state %q is missing or not canonical",
			id,
		)
	}
	return &state.Flags[index], index, nil
}

func findEquipmentEntry(
	state *campaign.State,
	id string,
) (*campaign.EquipmentEntry, int, error) {
	index := sort.Search(len(state.Equipment), func(index int) bool {
		return state.Equipment[index].SlotID >= id
	})
	if index == len(state.Equipment) ||
		state.Equipment[index].SlotID != id {
		return nil, 0, fmt.Errorf(
			"campaign equipment slot %q is missing or not canonical",
			id,
		)
	}
	return &state.Equipment[index], index, nil
}
