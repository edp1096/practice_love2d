package gameapp

import (
	"errors"
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
)

// CampaignStateDTO combines durable Campaign state with authored limits that
// are otherwise present only in Campaign Config. Every slice is detached.
type CampaignStateDTO struct {
	Version  int    `json:"version"`
	Revision uint64 `json:"revision"`

	ProjectID string `json:"project_id"`
	ContentID string `json:"content_id"`

	Flow           campaign.FlowProgress `json:"flow"`
	Mode           campaign.Mode         `json:"mode"`
	CurrentStageID string                `json:"current_stage_id,omitempty"`
	EntrySpawnID   string                `json:"entry_spawn_id,omitempty"`
	Locale         string                `json:"locale"`

	Flags     []campaign.FlagState      `json:"flags"`
	Inventory []CampaignInventoryState  `json:"inventory"`
	Equipment []campaign.EquipmentEntry `json:"equipment"`
	Currency  int64                     `json:"currency"`
	Quests    []CampaignQuestState      `json:"quests"`
}

type CampaignInventoryState struct {
	ItemID      string `json:"item_id"`
	Name        string `json:"name"`
	NameKey     string `json:"name_key,omitempty"`
	Quantity    int64  `json:"quantity"`
	MaxQuantity int64  `json:"max_quantity"`
	Equipped    bool   `json:"equipped"`
}

type CampaignQuestState struct {
	ID         string                   `json:"id"`
	Name       string                   `json:"name"`
	NameKey    string                   `json:"name_key,omitempty"`
	Status     campaign.QuestStatus     `json:"status"`
	Objectives []CampaignObjectiveState `json:"objectives"`
}

type CampaignObjectiveState struct {
	ID       string `json:"id"`
	Count    int64  `json:"count"`
	Required int64  `json:"required"`
}

// ShopState is the complete transient presentation/debug contract for the
// currently open authored shop.
type ShopState struct {
	Active        bool             `json:"active"`
	Revision      uint64           `json:"revision"`
	ID            string           `json:"id,omitempty"`
	Name          string           `json:"name,omitempty"`
	NameKey       string           `json:"name_key,omitempty"`
	Balance       int64            `json:"balance"`
	Offers        []ShopOfferState `json:"offers"`
	SelectedIndex int              `json:"selected_index"`
	Status        string           `json:"status,omitempty"`
}

// ShopOfferState distinguishes an unavailable trade direction from a
// zero-priced direction: unavailable prices encode as JSON null.
type ShopOfferState struct {
	ItemID     string `json:"item_id"`
	Name       string `json:"name"`
	NameKey    string `json:"name_key,omitempty"`
	Owned      int64  `json:"owned"`
	StackLimit int64  `json:"stack_limit"`
	Equipped   bool   `json:"equipped"`
	CanBuy     bool   `json:"can_buy"`
	BuyPrice   *int64 `json:"buy_price"`
	CanSell    bool   `json:"can_sell"`
	SellPrice  *int64 `json:"sell_price"`
	Selected   bool   `json:"selected"`
}

type InventoryUseResult struct {
	ItemID            string `json:"item_id"`
	ConsumedQuantity  int64  `json:"consumed_quantity"`
	RemainingQuantity int64  `json:"remaining_quantity"`
}

// CampaignGetState returns a detached, config-complete campaign view.
func (runtime *Runtime) CampaignGetState() (CampaignStateDTO, error) {
	runtime.mu.RLock()
	defer runtime.mu.RUnlock()
	return runtime.campaignStateLocked()
}

func (runtime *Runtime) campaignStateLocked() (CampaignStateDTO, error) {
	if runtime.campaign == nil {
		return CampaignStateDTO{}, errors.New(
			"campaign state: campaign is unavailable",
		)
	}
	state := runtime.campaign.Snapshot()
	itemDefinitions := make(
		map[string]campaign.ItemDefinition,
		len(runtime.campaignConfig.Items),
	)
	for _, definition := range runtime.campaignConfig.Items {
		itemDefinitions[definition.ID] = definition
	}
	questDefinitions := make(
		map[string]campaign.QuestDefinition,
		len(runtime.campaignConfig.Quests),
	)
	for _, definition := range runtime.campaignConfig.Quests {
		questDefinitions[definition.ID] = definition
	}

	result := CampaignStateDTO{
		Version:        state.Version,
		Revision:       runtime.revision,
		ProjectID:      state.ProjectID,
		ContentID:      state.ContentID,
		Flow:           state.Flow,
		Mode:           state.Mode,
		CurrentStageID: state.CurrentStageID,
		EntrySpawnID:   state.EntrySpawnID,
		Locale:         state.Locale,
		Flags:          make([]campaign.FlagState, len(state.Flags)),
		Inventory: make(
			[]CampaignInventoryState,
			len(state.Inventory),
		),
		Equipment: make(
			[]campaign.EquipmentEntry,
			len(state.Equipment),
		),
		Currency: state.Currency,
		Quests: make(
			[]CampaignQuestState,
			len(state.Quests),
		),
	}
	copy(result.Flags, state.Flags)
	copy(result.Equipment, state.Equipment)
	for index, entry := range state.Inventory {
		definition, exists := itemDefinitions[entry.ItemID]
		if !exists {
			return CampaignStateDTO{}, fmt.Errorf(
				"campaign state: item %q has no config definition",
				entry.ItemID,
			)
		}
		rule, exists := runtime.contentRules.Item(entry.ItemID)
		if !exists {
			return CampaignStateDTO{}, fmt.Errorf(
				"campaign state: item %q has no content rule",
				entry.ItemID,
			)
		}
		result.Inventory[index] = CampaignInventoryState{
			ItemID: entry.ItemID,
			Name: runtime.localizeRuleTextLocked(
				rule.Name,
				rule.NameKey,
			),
			NameKey:     rule.NameKey,
			Quantity:    entry.Quantity,
			MaxQuantity: definition.MaxQuantity,
			Equipped:    campaignItemEquipped(state, entry.ItemID),
		}
	}
	for questIndex, quest := range state.Quests {
		definition, exists := questDefinitions[quest.ID]
		if !exists {
			return CampaignStateDTO{}, fmt.Errorf(
				"campaign state: quest %q has no config definition",
				quest.ID,
			)
		}
		required := make(
			map[string]int64,
			len(definition.Objectives),
		)
		for _, objective := range definition.Objectives {
			required[objective.ID] = objective.Required
		}
		rule, exists := runtime.contentRules.Quest(quest.ID)
		if !exists {
			return CampaignStateDTO{}, fmt.Errorf(
				"campaign state: quest %q has no content rule",
				quest.ID,
			)
		}
		questState := CampaignQuestState{
			ID: quest.ID,
			Name: runtime.localizeRuleTextLocked(
				rule.Name,
				rule.NameKey,
			),
			NameKey: rule.NameKey,
			Status:  quest.Status,
			Objectives: make(
				[]CampaignObjectiveState,
				len(quest.Objectives),
			),
		}
		for objectiveIndex, objective := range quest.Objectives {
			limit, exists := required[objective.ID]
			if !exists {
				return CampaignStateDTO{}, fmt.Errorf(
					"campaign state: objective %q/%q has no config definition",
					quest.ID,
					objective.ID,
				)
			}
			questState.Objectives[objectiveIndex] = CampaignObjectiveState{
				ID:       objective.ID,
				Count:    objective.Count,
				Required: limit,
			}
		}
		result.Quests[questIndex] = questState
	}
	return result, nil
}

// ShopState returns a detached snapshot. An inactive shop is a successful
// empty state so polling clients do not need error-driven control flow.
func (runtime *Runtime) ShopState() (ShopState, error) {
	runtime.mu.RLock()
	defer runtime.mu.RUnlock()
	return runtime.shopStateLocked()
}

func (runtime *Runtime) shopStateLocked() (ShopState, error) {
	if runtime.activeShopID == "" {
		balance := int64(0)
		if runtime.campaign != nil {
			balance = runtime.campaign.Snapshot().Currency
		}
		return ShopState{
			Revision:      runtime.revision,
			Balance:       balance,
			Offers:        []ShopOfferState{},
			SelectedIndex: -1,
		}, nil
	}
	shop, exists := runtime.contentRules.Shop(runtime.activeShopID)
	if !exists {
		return ShopState{}, fmt.Errorf(
			"shop state: active shop %q is not configured",
			runtime.activeShopID,
		)
	}
	campaignState := runtime.campaign.Snapshot()
	inventory := make(
		map[string]campaign.InventoryEntry,
		len(campaignState.Inventory),
	)
	for _, entry := range campaignState.Inventory {
		inventory[entry.ItemID] = entry
	}
	definitions := make(
		map[string]campaign.ItemDefinition,
		len(runtime.campaignConfig.Items),
	)
	for _, definition := range runtime.campaignConfig.Items {
		definitions[definition.ID] = definition
	}
	selectedIndex := runtime.shopSelectedIndex
	if len(shop.Offers) == 0 {
		selectedIndex = -1
	} else {
		selectedIndex = min(max(selectedIndex, 0), len(shop.Offers)-1)
	}
	result := ShopState{
		Active:   true,
		Revision: runtime.revision,
		ID:       shop.ID,
		Name: runtime.localizeRuleTextLocked(
			shop.Name,
			shop.NameKey,
		),
		NameKey:       shop.NameKey,
		Balance:       campaignState.Currency,
		Offers:        make([]ShopOfferState, len(shop.Offers)),
		SelectedIndex: selectedIndex,
		Status:        runtime.shopStatus,
	}
	for index, offer := range shop.Offers {
		entry, exists := inventory[offer.ItemID]
		if !exists {
			return ShopState{}, fmt.Errorf(
				"shop state: offer item %q is absent from campaign inventory",
				offer.ItemID,
			)
		}
		definition, exists := definitions[offer.ItemID]
		if !exists {
			return ShopState{}, fmt.Errorf(
				"shop state: offer item %q has no config definition",
				offer.ItemID,
			)
		}
		item, exists := runtime.contentRules.Item(offer.ItemID)
		if !exists {
			return ShopState{}, fmt.Errorf(
				"shop state: offer item %q has no content rule",
				offer.ItemID,
			)
		}
		equipped := campaignItemEquipped(campaignState, offer.ItemID)
		var buyPrice *int64
		if offer.CanBuy {
			value := int64(offer.BuyPrice)
			buyPrice = &value
		}
		var sellPrice *int64
		if offer.CanSell {
			value := int64(offer.SellPrice)
			sellPrice = &value
		}
		canBuy := offer.CanBuy &&
			entry.Quantity < definition.MaxQuantity &&
			campaignState.Currency >= int64(offer.BuyPrice)
		canSell := offer.CanSell &&
			entry.Quantity > 0 &&
			!(equipped && entry.Quantity == 1) &&
			int64(offer.SellPrice) <=
				campaign.MaxJSONInteger-campaignState.Currency
		result.Offers[index] = ShopOfferState{
			ItemID: offer.ItemID,
			Name: runtime.localizeRuleTextLocked(
				item.Name,
				item.NameKey,
			),
			NameKey:    item.NameKey,
			Owned:      entry.Quantity,
			StackLimit: definition.MaxQuantity,
			Equipped:   equipped,
			CanBuy:     canBuy,
			BuyPrice:   buyPrice,
			CanSell:    canSell,
			SellPrice:  sellPrice,
			Selected:   index == selectedIndex,
		}
	}
	return result, nil
}

func (runtime *Runtime) MoveShopSelection(delta int) (ShopState, error) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	return runtime.moveShopSelectionLocked(delta)
}

func (runtime *Runtime) moveShopSelectionLocked(
	delta int,
) (ShopState, error) {
	if runtime.activeShopID == "" {
		return ShopState{}, errors.New("move shop selection: no shop is active")
	}
	shop, exists := runtime.contentRules.Shop(runtime.activeShopID)
	if !exists {
		return ShopState{}, fmt.Errorf(
			"move shop selection: shop %q is not configured",
			runtime.activeShopID,
		)
	}
	changed := false
	if len(shop.Offers) != 0 && delta != 0 {
		index := (runtime.shopSelectedIndex + delta) % len(shop.Offers)
		if index < 0 {
			index += len(shop.Offers)
		}
		changed = index != runtime.shopSelectedIndex
		runtime.shopSelectedIndex = index
	}
	if runtime.shopStatus != "" {
		runtime.shopStatus = ""
		changed = true
	}
	if changed {
		runtime.revision++
	}
	return runtime.shopStateLocked()
}

func (runtime *Runtime) BuyShopItem(
	itemID string,
	quantity int64,
) (ShopState, error) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	return runtime.buyShopItemLocked(itemID, quantity)
}

func (runtime *Runtime) buyShopItemLocked(
	itemID string,
	quantity int64,
) (ShopState, error) {
	return runtime.tradeShopItemLocked(true, itemID, quantity)
}

func (runtime *Runtime) SellShopItem(
	itemID string,
	quantity int64,
) (ShopState, error) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	return runtime.sellShopItemLocked(itemID, quantity)
}

func (runtime *Runtime) sellShopItemLocked(
	itemID string,
	quantity int64,
) (ShopState, error) {
	return runtime.tradeShopItemLocked(false, itemID, quantity)
}

func (runtime *Runtime) tradeShopItemLocked(
	buy bool,
	itemID string,
	quantity int64,
) (ShopState, error) {
	if runtime.activeShopID == "" {
		return ShopState{}, errors.New("shop trade: no shop is active")
	}
	checkpoint := runtime.checkpointLocked()
	if err := runtime.detachMutableLocked(checkpoint); err != nil {
		return ShopState{}, err
	}
	var err error
	if buy {
		err = runtime.ruleExecutor.Buy(
			runtime.campaign,
			runtime.activeShopID,
			itemID,
			quantity,
		)
	} else {
		err = runtime.ruleExecutor.Sell(
			runtime.campaign,
			runtime.activeShopID,
			itemID,
			quantity,
		)
	}
	if err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return ShopState{}, err
	}
	runtime.shopStatus = ""
	runtime.revision++
	state, err := runtime.shopStateLocked()
	if err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return ShopState{}, err
	}
	return state, nil
}

func (runtime *Runtime) CloseShop() (ShopState, error) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	return runtime.closeShopLocked()
}

func (runtime *Runtime) closeShopLocked() (ShopState, error) {
	if runtime.activeShopID == "" {
		return ShopState{}, errors.New("close shop: no shop is active")
	}
	runtime.activeShopID = ""
	runtime.shopSelectedIndex = 0
	runtime.shopStatus = ""
	runtime.revision++
	return runtime.shopStateLocked()
}

// UseInventoryItem publishes Campaign consumption and Simulation intents as
// one candidate. Any failure restores Campaign, Simulation, transient modals,
// and revision to the exact pre-call checkpoint.
func (runtime *Runtime) UseInventoryItem(
	itemID string,
) (InventoryUseResult, error) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	return runtime.useInventoryItemLocked(itemID)
}

func (runtime *Runtime) useInventoryItemLocked(
	itemID string,
) (InventoryUseResult, error) {
	if itemID == "" {
		return InventoryUseResult{}, errors.New(
			"use inventory item: item id is empty",
		)
	}
	checkpoint := runtime.checkpointLocked()
	if err := runtime.detachMutableLocked(checkpoint); err != nil {
		return InventoryUseResult{}, err
	}
	result, err := runtime.ruleExecutor.UseItem(runtime.campaign, itemID)
	if err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return InventoryUseResult{}, err
	}
	if err := runtime.applyRuleIntentsLocked(result.Intents, ""); err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return InventoryUseResult{}, fmt.Errorf(
			"use inventory item %q intents: %w",
			itemID,
			err,
		)
	}
	if err := runtime.reconcileEquipmentChangeLocked(
		checkpoint.campaign,
		true,
	); err != nil {
		runtime.restoreCheckpointLocked(checkpoint)
		return InventoryUseResult{}, fmt.Errorf(
			"use inventory item %q rebuild: %w",
			itemID,
			err,
		)
	}
	runtime.revision++
	return InventoryUseResult{
		ItemID:            result.ItemID,
		ConsumedQuantity:  result.ConsumedQuantity,
		RemainingQuantity: result.RemainingQuantity,
	}, nil
}

func campaignItemEquipped(state campaign.State, itemID string) bool {
	for _, equipment := range state.Equipment {
		if equipment.ItemID == itemID {
			return true
		}
	}
	return false
}

func (runtime *Runtime) selectedShopItemLocked() (string, error) {
	if runtime.activeShopID == "" {
		return "", errors.New("selected shop item: no shop is active")
	}
	shop, exists := runtime.contentRules.Shop(runtime.activeShopID)
	if !exists {
		return "", fmt.Errorf(
			"selected shop item: shop %q is not configured",
			runtime.activeShopID,
		)
	}
	if len(shop.Offers) == 0 {
		return "", fmt.Errorf(
			"selected shop item: shop %q has no offers",
			runtime.activeShopID,
		)
	}
	index := min(max(runtime.shopSelectedIndex, 0), len(shop.Offers)-1)
	return shop.Offers[index].ItemID, nil
}
