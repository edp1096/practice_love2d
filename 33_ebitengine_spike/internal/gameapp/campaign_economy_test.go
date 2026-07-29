package gameapp

import (
	"bytes"
	"context"
	"encoding/json"
	"reflect"
	"strings"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/protocol"
)

func TestCampaignStateCombinesRequiredCountsAndIsDetached(t *testing.T) {
	runtime := newCampaignRuntime(t)
	state := callRuntime(
		t,
		runtime,
		protocol.MethodCampaignGetState,
		protocol.EmptyParams{},
	).(CampaignStateDTO)
	if state.Revision != runtime.revision ||
		state.CurrentStageID != "stage.village" {
		t.Fatalf("campaign DTO identity = %#v", state)
	}
	potion := campaignInventoryDTO(t, state, "item.potion")
	if potion.MaxQuantity != 10 ||
		potion.Quantity != 0 ||
		potion.Name == "" ||
		potion.Equipped {
		t.Fatalf("potion campaign DTO = %#v", potion)
	}
	quest := campaignQuestDTO(t, state, "quest.grove_guardian")
	if objective := campaignObjectiveDTO(
		t,
		quest,
		"defeat_slimes",
	); objective.Count != 0 || objective.Required != 2 {
		t.Fatalf("slime objective DTO = %#v", objective)
	}
	if objective := campaignObjectiveDTO(
		t,
		quest,
		"defeat_guardian",
	); objective.Count != 0 || objective.Required != 1 {
		t.Fatalf("guardian objective DTO = %#v", objective)
	}

	state.Flags[0].Value = !state.Flags[0].Value
	state.Inventory[0].Quantity = 9
	state.Equipment[0].ItemID = "mutated"
	state.Quests[0].Objectives[0].Count = 99
	again, err := runtime.CampaignGetState()
	if err != nil {
		t.Fatal(err)
	}
	if reflect.DeepEqual(state, again) ||
		campaignInventoryDTO(t, again, "item.potion").Quantity != 0 ||
		campaignObjectiveDTO(
			t,
			campaignQuestDTO(t, again, "quest.grove_guardian"),
			"defeat_guardian",
		).Count != 0 {
		t.Fatalf("mutating CampaignStateDTO reached runtime: %#v", again)
	}
}

func TestEmptyCampaignAndShopDTOCollectionsEncodeAsArrays(t *testing.T) {
	config := campaign.Config{
		Version:             campaign.CurrentConfigVersion,
		ProjectID:           "test.empty",
		ContentID:           "content:empty-v1",
		DefaultLocale:       "en",
		Locales:             []string{"en"},
		InitialStageID:      "stage.empty",
		InitialEntrySpawnID: "default",
		Stages: []campaign.StageDefinition{{
			ID:          "stage.empty",
			EntrySpawns: []string{"default"},
		}},
	}
	live, err := campaign.NewGame(config)
	if err != nil {
		t.Fatal(err)
	}
	runtime := &Runtime{
		campaignConfig: config,
		campaign:       live,
		revision:       7,
	}
	state, err := runtime.CampaignGetState()
	if err != nil {
		t.Fatal(err)
	}
	if state.Flags == nil ||
		state.Inventory == nil ||
		state.Equipment == nil ||
		state.Quests == nil {
		t.Fatalf("empty CampaignStateDTO contains nil slice: %#v", state)
	}
	data, err := json.Marshal(state)
	if err != nil {
		t.Fatal(err)
	}
	for _, field := range []string{
		`"flags":[]`,
		`"inventory":[]`,
		`"equipment":[]`,
		`"quests":[]`,
	} {
		if !bytes.Contains(data, []byte(field)) {
			t.Fatalf("CampaignStateDTO JSON lacks %s: %s", field, data)
		}
	}

	shop, err := runtime.ShopState()
	if err != nil {
		t.Fatal(err)
	}
	if shop.Active ||
		shop.Revision != 7 ||
		shop.SelectedIndex != -1 ||
		shop.Offers == nil {
		t.Fatalf("inactive ShopState = %#v", shop)
	}
	shopJSON, err := json.Marshal(shop)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(shopJSON, []byte(`"offers":[]`)) {
		t.Fatalf("inactive ShopState JSON = %s", shopJSON)
	}
}

func TestMerchantShopBuyCloseUseAndSaveBoundary(t *testing.T) {
	runtime := newCampaignRuntime(t)
	acceptVillageGuideQuest(t, runtime)
	shop := openVillageMerchantShop(t, runtime)
	if shop.ID != "shop.village" ||
		shop.Name == "" ||
		shop.Balance != 25 ||
		shop.SelectedIndex != 0 ||
		shop.Revision != runtime.revision {
		t.Fatalf("opened village shop = %#v", shop)
	}
	presented := runtime.View().Shop
	modifiers := make(map[string]string, len(presented.Offers))
	for _, offer := range presented.Offers {
		modifiers[offer.ID] = offer.ModifierSummary
	}
	if modifiers["item.training_sword"] != "ATK +5" ||
		modifiers["item.leather_vest"] != "DEF +3" ||
		modifiers["item.traveler_boots"] != "MOVE +0.25" {
		t.Fatalf("shop equipment summaries = %#v", modifiers)
	}
	potion := shopOffer(t, shop, "item.potion")
	if potion.BuyPrice == nil || *potion.BuyPrice != 25 ||
		potion.SellPrice == nil || *potion.SellPrice != 10 ||
		!potion.CanBuy || potion.CanSell ||
		potion.Owned != 0 || potion.StackLimit != 10 ||
		potion.Equipped {
		t.Fatalf("potion offer = %#v", potion)
	}
	sword := shopOffer(t, shop, "item.training_sword")
	if sword.BuyPrice != nil ||
		sword.SellPrice == nil || *sword.SellPrice != 30 ||
		sword.CanBuy || sword.CanSell ||
		sword.Owned != 1 || !sword.Equipped {
		t.Fatalf("equipped sword offer = %#v", sword)
	}
	swordJSON, err := json.Marshal(sword)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(swordJSON, []byte(`"buy_price":null`)) ||
		!bytes.Contains(swordJSON, []byte(`"sell_price":30`)) {
		t.Fatalf("nullable sword prices = %s", swordJSON)
	}
	detached, err := runtime.ShopState()
	if err != nil {
		t.Fatal(err)
	}
	detached.Offers[0].Owned = 9
	*detached.Offers[0].BuyPrice = 999
	again, err := runtime.ShopState()
	if err != nil {
		t.Fatal(err)
	}
	if got := shopOffer(t, again, "item.potion"); got.Owned != 0 ||
		got.BuyPrice == nil || *got.BuyPrice != 25 {
		t.Fatalf("mutating ShopState reached runtime: %#v", got)
	}

	worldBeforeModal := runtime.simulation.Snapshot()
	if err := runtime.Tick(ebitapp.Actions{
		MoveX:  1,
		Attack: true,
	}); err != nil {
		t.Fatal(err)
	}
	if after := runtime.simulation.Snapshot(); !reflect.DeepEqual(
		after,
		worldBeforeModal,
	) {
		t.Fatalf("active shop advanced World: %#v", after)
	}
	runtime.virtual["move_right"] = virtualAction{
		value:     1,
		remaining: 5,
		fresh:     true,
	}
	virtualBeforeModalStep := cloneVirtualActions(runtime.virtual)
	stepProtocol(t, runtime, 3)
	if after := runtime.simulation.Snapshot(); !reflect.DeepEqual(
		after,
		worldBeforeModal,
	) {
		t.Fatalf("debug stepping advanced modal shop World: %#v", after)
	}
	if !reflect.DeepEqual(runtime.virtual, virtualBeforeModalStep) {
		t.Fatal("debug stepping consumed gameplay input behind modal shop")
	}
	delete(runtime.virtual, "move_right")

	beforeBuyRevision := runtime.revision
	shop = callRuntime(
		t,
		runtime,
		protocol.MethodShopBuy,
		protocol.ShopTradeParams{
			ItemID:   "item.potion",
			Quantity: 1,
		},
	).(ShopState)
	if shop.Revision != beforeBuyRevision+1 ||
		shop.Revision != runtime.revision ||
		shop.Balance != 0 {
		t.Fatalf("shop state after buy = %#v", shop)
	}
	potion = shopOffer(t, shop, "item.potion")
	if potion.Owned != 1 || potion.CanBuy || !potion.CanSell {
		t.Fatalf("potion after buy = %#v", potion)
	}

	callRuntime(
		t,
		runtime,
		protocol.MethodAppSave,
		protocol.SaveSlotParams{Slot: "economy-boundary"},
	)
	closed := callRuntime(
		t,
		runtime,
		protocol.MethodShopClose,
		protocol.EmptyParams{},
	).(ShopState)
	if closed.Active || closed.SelectedIndex != -1 ||
		closed.Revision != runtime.revision {
		t.Fatalf("closed shop state = %#v", closed)
	}

	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetHealth,
		protocol.SetHealthParams{EntityID: "player", Value: 40},
	)
	beforeUseRevision := runtime.revision
	used := callRuntime(
		t,
		runtime,
		protocol.MethodInventoryUse,
		protocol.InventoryUseParams{ItemID: "item.potion"},
	).(InventoryUseResult)
	if used.ItemID != "item.potion" ||
		used.ConsumedQuantity != 1 ||
		used.RemainingQuantity != 0 ||
		runtime.revision != beforeUseRevision+1 ||
		entitySnapshot(t, runtime, "player").Health != 65 {
		t.Fatalf(
			"potion use = %#v player=%#v revision=%d",
			used,
			entitySnapshot(t, runtime, "player"),
			runtime.revision,
		)
	}

	callRuntime(
		t,
		runtime,
		protocol.MethodAppLoad,
		protocol.SaveSlotParams{Slot: "economy-boundary"},
	)
	restored := runtime.CampaignState()
	if campaignItem(t, restored, "item.potion").Quantity != 1 ||
		restored.Currency != 0 ||
		entitySnapshot(t, runtime, "player").Health !=
			entitySnapshot(t, runtime, "player").MaxHealth {
		t.Fatalf(
			"save boundary did not restore durable purchase and fresh World: %#v",
			restored,
		)
	}
	shop, err = runtime.ShopState()
	if err != nil {
		t.Fatal(err)
	}
	if shop.Active || shop.SelectedIndex != -1 {
		t.Fatalf("load retained transient shop: %#v", shop)
	}
}

func TestShopFailuresSeparateProtocolAtomicityFromUIStatus(t *testing.T) {
	runtime := newCampaignRuntime(t)
	beforeOpenWorld := runtime.simulation.Snapshot()
	shop := openVillageMerchantShop(t, runtime)
	if shop.Balance != 0 {
		t.Fatalf("initial shop balance = %d", shop.Balance)
	}
	worldAtShop := runtime.simulation.Snapshot()
	if reflect.DeepEqual(worldAtShop, beforeOpenWorld) {
		t.Fatal("opening shop did not consume one authored interaction tick")
	}

	beforeCampaign := runtime.CampaignState()
	beforeRevision := runtime.revision
	beforeShop := shop
	_, err := runtime.Call(
		context.Background(),
		protocol.Call{
			Method: protocol.MethodShopBuy,
			Params: protocol.ShopTradeParams{
				ItemID:   "item.potion",
				Quantity: 1,
			},
		},
	)
	if err == nil || !strings.Contains(err.Error(), "currency") {
		t.Fatalf("protocol insufficient-funds error = %v", err)
	}
	afterShop, stateErr := runtime.ShopState()
	if stateErr != nil {
		t.Fatal(stateErr)
	}
	if runtime.revision != beforeRevision ||
		!reflect.DeepEqual(runtime.CampaignState(), beforeCampaign) ||
		!reflect.DeepEqual(afterShop, beforeShop) ||
		!reflect.DeepEqual(runtime.simulation.Snapshot(), worldAtShop) {
		t.Fatal("failed protocol shop trade changed runtime state")
	}

	if err := runtime.Tick(ebitapp.Actions{ShopBuy: true}); err != nil {
		t.Fatalf("UI shop failure escaped model: %v", err)
	}
	afterUI, err := runtime.ShopState()
	if err != nil {
		t.Fatal(err)
	}
	if runtime.revision != beforeRevision+1 ||
		afterUI.Status == "" ||
		!strings.Contains(afterUI.Status, "currency") ||
		!reflect.DeepEqual(runtime.CampaignState(), beforeCampaign) ||
		!reflect.DeepEqual(runtime.simulation.Snapshot(), worldAtShop) {
		t.Fatalf("UI shop failure state = %#v", afterUI)
	}
	if view := runtime.View(); !view.Shop.Active ||
		view.Shop.Status != afterUI.Status {
		t.Fatalf("UI shop status was not presented: %#v", view.Shop)
	}

	if err := runtime.Tick(ebitapp.Actions{ShopDown: true}); err != nil {
		t.Fatal(err)
	}
	navigated, err := runtime.ShopState()
	if err != nil {
		t.Fatal(err)
	}
	if navigated.SelectedIndex != 1 || navigated.Status != "" {
		t.Fatalf("shop navigation = %#v", navigated)
	}
	if err := runtime.Tick(ebitapp.Actions{ShopCancel: true}); err != nil {
		t.Fatal(err)
	}
	if state, err := runtime.ShopState(); err != nil || state.Active {
		t.Fatalf("UI shop cancel = %#v error=%v", state, err)
	}
	if !reflect.DeepEqual(runtime.simulation.Snapshot(), worldAtShop) {
		t.Fatal("shop UI controls advanced World")
	}
}

func TestOpenShopSellCommitsDurableCampaign(t *testing.T) {
	runtime := newCampaignRuntime(t)
	if err := runtime.campaign.Transaction(func(state *campaign.State) error {
		state.Currency = 5
		for index := range state.Inventory {
			if state.Inventory[index].ItemID == "item.potion" {
				state.Inventory[index].Quantity = 1
			}
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	openVillageMerchantShop(t, runtime)
	beforeRevision := runtime.revision
	shop := callRuntime(
		t,
		runtime,
		protocol.MethodShopSell,
		protocol.ShopTradeParams{
			ItemID:   "item.potion",
			Quantity: 1,
		},
	).(ShopState)
	if shop.Revision != beforeRevision+1 ||
		shop.Balance != 15 ||
		shopOffer(t, shop, "item.potion").Owned != 0 ||
		campaignItem(
			t,
			runtime.CampaignState(),
			"item.potion",
		).Quantity != 0 {
		t.Fatalf("shop sell result = %#v", shop)
	}
}

func TestInventoryUseHealFailureRollsBackCampaignSimulationAndRevision(
	t *testing.T,
) {
	runtime := newCampaignRuntime(t)
	if err := runtime.campaign.Transaction(func(state *campaign.State) error {
		for index := range state.Inventory {
			if state.Inventory[index].ItemID == "item.potion" {
				state.Inventory[index].Quantity = 1
			}
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetHealth,
		protocol.SetHealthParams{EntityID: "player", Value: 0},
	)
	beforeCampaign := runtime.CampaignState()
	beforeWorld := runtime.simulation.Snapshot()
	beforeCampaignIdentity := runtime.campaign
	beforeWorldIdentity := runtime.simulation
	beforeRevision := runtime.revision

	_, err := runtime.Call(
		context.Background(),
		protocol.Call{
			Method: protocol.MethodInventoryUse,
			Params: protocol.InventoryUseParams{ItemID: "item.potion"},
		},
	)
	if err == nil || !strings.Contains(err.Error(), "cannot revive") {
		t.Fatalf("dead-player potion error = %v", err)
	}
	if runtime.campaign != beforeCampaignIdentity ||
		runtime.simulation != beforeWorldIdentity ||
		runtime.revision != beforeRevision ||
		!reflect.DeepEqual(runtime.CampaignState(), beforeCampaign) ||
		!reflect.DeepEqual(runtime.simulation.Snapshot(), beforeWorld) {
		t.Fatal("failed Inventory.use published a partial candidate")
	}
}

func TestShopTransientClearsAcrossWorldAndContentLifecycles(t *testing.T) {
	tests := []struct {
		name   string
		action func(*testing.T, *Runtime)
	}{
		{
			name: "reset",
			action: func(t *testing.T, runtime *Runtime) {
				t.Helper()
				runtime.mu.Lock()
				err := runtime.resetLocked()
				runtime.mu.Unlock()
				if err != nil {
					t.Fatal(err)
				}
			},
		},
		{
			name: "reload",
			action: func(t *testing.T, runtime *Runtime) {
				t.Helper()
				callRuntime(
					t,
					runtime,
					protocol.MethodAppReloadContent,
					protocol.EmptyParams{},
				)
			},
		},
		{
			name: "new game",
			action: func(t *testing.T, runtime *Runtime) {
				t.Helper()
				callRuntime(
					t,
					runtime,
					protocol.MethodAppStartNewGame,
					protocol.EmptyParams{},
				)
			},
		},
		{
			name: "portal",
			action: func(t *testing.T, runtime *Runtime) {
				t.Helper()
				runtime.mu.Lock()
				portal := findPortal(t, runtime, "to_field")
				err := runtime.transitionPortalLocked(portal)
				if err == nil {
					runtime.revision++
				}
				runtime.mu.Unlock()
				if err != nil {
					t.Fatal(err)
				}
			},
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			runtime := newCampaignRuntime(t)
			openVillageMerchantShop(t, runtime)
			runtime.shopSelectedIndex = 1
			runtime.shopStatus = "transient status"
			test.action(t, runtime)
			state, err := runtime.ShopState()
			if err != nil {
				t.Fatal(err)
			}
			if state.Active ||
				state.SelectedIndex != -1 ||
				state.Status != "" ||
				runtime.activeShopID != "" ||
				runtime.shopSelectedIndex != 0 ||
				runtime.shopStatus != "" {
				t.Fatalf(
					"%s retained transient shop: state=%#v runtime=%q/%d/%q",
					test.name,
					state,
					runtime.activeShopID,
					runtime.shopSelectedIndex,
					runtime.shopStatus,
				)
			}
		})
	}
}

func TestCancelledStepRollsBackAuthoredShopStart(t *testing.T) {
	runtime := newCampaignRuntime(t)
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: "player",
			X:        450,
			Y:        240,
		},
	)
	scheduleProtocolAction(t, runtime, "interact")
	beforeWorld := runtime.simulation.Snapshot()
	beforeCampaign := runtime.CampaignState()
	beforeVirtual := cloneVirtualActions(runtime.virtual)
	beforeRevision := runtime.revision

	ctx := &cancelAfterContext{Context: context.Background(), checks: 1}
	if _, err := runtime.step(ctx, 2); err == nil {
		t.Fatal("partially cancelled shop step unexpectedly succeeded")
	}
	shop, err := runtime.ShopState()
	if err != nil {
		t.Fatal(err)
	}
	if shop.Active ||
		!reflect.DeepEqual(runtime.simulation.Snapshot(), beforeWorld) ||
		!reflect.DeepEqual(runtime.CampaignState(), beforeCampaign) ||
		!reflect.DeepEqual(runtime.virtual, beforeVirtual) ||
		runtime.revision != beforeRevision {
		t.Fatalf(
			"cancelled shop start leaked state: shop=%#v campaign=%#v",
			shop,
			runtime.CampaignState(),
		)
	}
}

func TestShopTradesRequireAnActiveAuthoredShop(t *testing.T) {
	runtime := newCampaignRuntime(t)
	before := runtime.CampaignState()
	beforeRevision := runtime.revision
	for name, trade := range map[string]func() error{
		"buy": func() error {
			_, err := runtime.BuyShopItem("item.potion", 1)
			return err
		},
		"sell": func() error {
			_, err := runtime.SellShopItem("item.potion", 1)
			return err
		},
	} {
		t.Run(name, func(t *testing.T) {
			if err := trade(); err == nil ||
				!strings.Contains(err.Error(), "no shop is active") {
				t.Fatalf("closed-shop %s error = %v", name, err)
			}
			if runtime.revision != beforeRevision ||
				!reflect.DeepEqual(runtime.CampaignState(), before) {
				t.Fatalf("closed-shop %s changed campaign", name)
			}
		})
	}
}

func acceptVillageGuideQuest(t *testing.T, runtime *Runtime) {
	t.Helper()
	openVillageGuideDialogue(t, runtime)
	callRuntime(
		t,
		runtime,
		protocol.MethodDialogueChoose,
		protocol.ChooseDialogueParams{ChoiceID: "accept"},
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodDialogueAdvance,
		protocol.EmptyParams{},
	)
}

func openVillageMerchantShop(t *testing.T, runtime *Runtime) ShopState {
	t.Helper()
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: "player",
			X:        450,
			Y:        240,
		},
	)
	scheduleProtocolAction(t, runtime, "interact")
	stepProtocol(t, runtime, 1)
	state := callRuntime(
		t,
		runtime,
		protocol.MethodShopGetState,
		protocol.EmptyParams{},
	).(ShopState)
	if !state.Active {
		t.Fatalf("merchant interaction did not open shop: %#v", state)
	}
	return state
}

func shopOffer(t *testing.T, state ShopState, itemID string) ShopOfferState {
	t.Helper()
	for _, offer := range state.Offers {
		if offer.ItemID == itemID {
			return offer
		}
	}
	t.Fatalf("shop offer %q is missing", itemID)
	return ShopOfferState{}
}

func campaignInventoryDTO(
	t *testing.T,
	state CampaignStateDTO,
	itemID string,
) CampaignInventoryState {
	t.Helper()
	for _, item := range state.Inventory {
		if item.ItemID == itemID {
			return item
		}
	}
	t.Fatalf("campaign DTO item %q is missing", itemID)
	return CampaignInventoryState{}
}

func campaignQuestDTO(
	t *testing.T,
	state CampaignStateDTO,
	questID string,
) CampaignQuestState {
	t.Helper()
	for _, quest := range state.Quests {
		if quest.ID == questID {
			return quest
		}
	}
	t.Fatalf("campaign DTO quest %q is missing", questID)
	return CampaignQuestState{}
}

func campaignObjectiveDTO(
	t *testing.T,
	quest CampaignQuestState,
	objectiveID string,
) CampaignObjectiveState {
	t.Helper()
	for _, objective := range quest.Objectives {
		if objective.ID == objectiveID {
			return objective
		}
	}
	t.Fatalf("campaign DTO objective %q is missing", objectiveID)
	return CampaignObjectiveState{}
}
