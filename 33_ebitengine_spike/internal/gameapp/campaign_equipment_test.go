package gameapp

import (
	"context"
	"reflect"
	"strings"
	"testing"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
	"practice_love2d/33_ebitengine_spike/internal/protocol"
	"practice_love2d/33_ebitengine_spike/internal/sim"
)

func TestGuideEquipmentDamageSurvivesEveryPlayerWorldRebuildOnce(
	t *testing.T,
) {
	runtime := newCampaignRuntime(t)
	if got := controlledAttackDamage(t, runtime); got != 34 {
		t.Fatalf("fresh controlled attack damage = %d, want 34", got)
	}
	acceptVillageGuideQuest(t, runtime)
	assertEquippedSwordDamage(t, runtime)

	runtime.mu.Lock()
	if err := runtime.resetLocked(); err != nil {
		runtime.mu.Unlock()
		t.Fatal(err)
	}
	runtime.mu.Unlock()
	assertEquippedSwordDamage(t, runtime)

	moveEntityToPortal(t, runtime, "player", "to_field")
	stepProtocol(t, runtime, 1)
	assertEquippedSwordDamage(t, runtime)

	callRuntime(
		t,
		runtime,
		protocol.MethodAppReloadContent,
		protocol.EmptyParams{},
	)
	assertEquippedSwordDamage(t, runtime)

	callRuntime(
		t,
		runtime,
		protocol.MethodAppSave,
		protocol.SaveSlotParams{Slot: "equipped"},
	)
	unequipped := callRuntime(
		t,
		runtime,
		protocol.MethodEquipmentUnequip,
		protocol.EquipmentUnequipParams{SlotID: "weapon"},
	).(EquipmentMutationResult)
	if !unequipped.Changed || unequipped.EffectiveAttackDamage != 34 {
		t.Fatalf("unequip result = %#v", unequipped)
	}
	callRuntime(
		t,
		runtime,
		protocol.MethodAppLoad,
		protocol.SaveSlotParams{Slot: "equipped"},
	)
	assertEquippedSwordDamage(t, runtime)
}

func TestEquipmentProtocolPreservesSessionAndRollsBackFailures(
	t *testing.T,
) {
	runtime := newCampaignRuntime(t)
	giveCampaignItems(t, runtime, 0, 1)
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetPosition,
		protocol.SetPositionParams{
			EntityID: "player",
			X:        360,
			Y:        250,
		},
	)
	beforeSession := runtime.simulation.SaveSession()
	beforeRevision := runtime.revision

	equipped := callRuntime(
		t,
		runtime,
		protocol.MethodEquipmentEquip,
		protocol.EquipmentEquipParams{ItemID: "item.training_sword"},
	).(EquipmentMutationResult)
	if !equipped.Changed ||
		equipped.SlotID != "weapon" ||
		equipped.ItemID != "item.training_sword" ||
		equipped.AttackModifier != 5 ||
		equipped.EffectiveAttackDamage != 39 ||
		equipped.Revision != beforeRevision+1 {
		t.Fatalf("equip result = %#v", equipped)
	}
	if got := runtime.simulation.SaveSession(); !reflect.DeepEqual(
		got,
		beforeSession,
	) {
		t.Fatalf("equip did not preserve active session:\n got %#v\nwant %#v", got, beforeSession)
	}

	repeatedRevision := runtime.revision
	repeated := callRuntime(
		t,
		runtime,
		protocol.MethodEquipmentEquip,
		protocol.EquipmentEquipParams{ItemID: "item.training_sword"},
	).(EquipmentMutationResult)
	if repeated.Changed || repeated.Revision != repeatedRevision ||
		repeated.EffectiveAttackDamage != 39 {
		t.Fatalf("repeated equip result = %#v", repeated)
	}

	unequipSession := runtime.simulation.SaveSession()
	unequipped := callRuntime(
		t,
		runtime,
		protocol.MethodEquipmentUnequip,
		protocol.EquipmentUnequipParams{SlotID: "weapon"},
	).(EquipmentMutationResult)
	if !unequipped.Changed ||
		unequipped.PreviousItemID != "item.training_sword" ||
		unequipped.PreviousAttackModifier != 5 ||
		unequipped.EffectiveAttackDamage != 34 {
		t.Fatalf("unequip result = %#v", unequipped)
	}
	if got := runtime.simulation.SaveSession(); !reflect.DeepEqual(
		got,
		unequipSession,
	) {
		t.Fatalf("unequip did not preserve active session:\n got %#v\nwant %#v", got, unequipSession)
	}

	if err := runtime.Tick(ebitapp.Actions{Attack: true}); err != nil {
		t.Fatal(err)
	}
	assertEquipmentProtocolFailureAtomic(
		t,
		runtime,
		protocol.MethodEquipmentEquip,
		protocol.EquipmentEquipParams{ItemID: "item.training_sword"},
		"attacking",
	)
}

func TestEquipmentProtocolRebuildsEveryEffectiveRPGStat(
	t *testing.T,
) {
	runtime := newTestRuntime(t)
	if err := runtime.campaign.Transaction(func(state *campaign.State) error {
		for index := range state.Inventory {
			switch state.Inventory[index].ItemID {
			case "item.training_sword",
				"item.leather_vest",
				"item.traveler_boots":
				state.Inventory[index].Quantity = 1
			}
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}

	for _, test := range []struct {
		itemID string
		check  func(EquipmentMutationResult) bool
	}{
		{
			itemID: "item.training_sword",
			check: func(result EquipmentMutationResult) bool {
				return result.AttackModifier == 5 &&
					result.EffectiveAttack == 5 &&
					result.EffectiveAttackDamage == 39
			},
		},
		{
			itemID: "item.leather_vest",
			check: func(result EquipmentMutationResult) bool {
				return result.DefenseModifier == 3 &&
					result.EffectiveDefense == 3
			},
		},
		{
			itemID: "item.traveler_boots",
			check: func(result EquipmentMutationResult) bool {
				return result.MoveSpeedModifier == 0.25 &&
					result.EffectiveMoveSpeed == 1.25
			},
		},
	} {
		equipped := callRuntime(
			t,
			runtime,
			protocol.MethodEquipmentEquip,
			protocol.EquipmentEquipParams{ItemID: test.itemID},
		).(EquipmentMutationResult)
		if !equipped.Changed || !test.check(equipped) {
			t.Fatalf("equip %q result = %#v", test.itemID, equipped)
		}
	}
	runtime.mu.RLock()
	configStats := runtime.controlledStatsLocked()
	snapshotStats := sim.RPGStatsConfig{}
	for _, entity := range runtime.simulation.Snapshot().Entities {
		if entity.ID == "player" {
			snapshotStats = entity.Stats
			break
		}
	}
	world := runtime.worldSnapshotLocked()
	runtime.mu.RUnlock()
	if configStats.Attack != 5 ||
		configStats.Defense != 3 ||
		configStats.MoveSpeed != sim.UnitsPerPixel*5/4 ||
		snapshotStats != configStats {
		t.Fatalf(
			"config/snapshot RPG stats = %#v / %#v",
			configStats,
			snapshotStats,
		)
	}
	if dto := worldEntity(t, world, "player").Stats; dto.Attack != 5 ||
		dto.Defense != 3 || dto.MoveSpeed != 1.25 {
		t.Fatalf("debug protocol RPG stats = %#v", dto)
	}
	view := runtime.View()
	if !view.HUD.ShowStats ||
		view.HUD.Attack != 5 ||
		view.HUD.Defense != 3 ||
		view.HUD.MoveSpeed != 1.25 {
		t.Fatalf("HUD RPG stats = %#v", view.HUD)
	}
	foundControlled := false
	for _, entity := range view.Entities {
		if !entity.Controlled {
			continue
		}
		foundControlled = true
		if entity.ID != "player" ||
			entity.Attack != 5 ||
			entity.Defense != 3 ||
			entity.MoveSpeed != 1.25 {
			t.Fatalf("controlled presentation entity = %#v", entity)
		}
	}
	if !foundControlled {
		t.Fatal("presentation has no controlled entity")
	}

	boots := callRuntime(
		t,
		runtime,
		protocol.MethodEquipmentUnequip,
		protocol.EquipmentUnequipParams{SlotID: "accessory"},
	).(EquipmentMutationResult)
	if !boots.Changed ||
		boots.PreviousMoveSpeedModifier != 0.25 ||
		boots.EffectiveAttack != 5 ||
		boots.EffectiveDefense != 3 ||
		boots.EffectiveMoveSpeed != 1 {
		t.Fatalf("boots unequip result = %#v", boots)
	}
	vest := callRuntime(
		t,
		runtime,
		protocol.MethodEquipmentUnequip,
		protocol.EquipmentUnequipParams{SlotID: "armor"},
	).(EquipmentMutationResult)
	if !vest.Changed ||
		vest.PreviousDefenseModifier != 3 ||
		vest.EffectiveAttack != 5 ||
		vest.EffectiveDefense != 0 {
		t.Fatalf("vest unequip result = %#v", vest)
	}
	sword := callRuntime(
		t,
		runtime,
		protocol.MethodEquipmentUnequip,
		protocol.EquipmentUnequipParams{SlotID: "weapon"},
	).(EquipmentMutationResult)
	if !sword.Changed ||
		sword.PreviousAttackModifier != 5 ||
		sword.EffectiveAttack != 0 ||
		sword.EffectiveDefense != 0 ||
		sword.EffectiveMoveSpeed != 1 {
		t.Fatalf("sword unequip result = %#v", sword)
	}
}

func TestEquipmentProtocolRejectsAmbiguousWorldAndModalStatesAtomically(
	t *testing.T,
) {
	t.Run("hitstop", func(t *testing.T) {
		runtime := newCampaignRuntime(t)
		giveCampaignItems(t, runtime, 0, 1)
		session := runtime.simulation.SaveSession()
		session.Hitstop = 1
		if err := runtime.simulation.LoadSession(session); err != nil {
			t.Fatal(err)
		}
		assertEquipmentProtocolFailureAtomic(
			t,
			runtime,
			protocol.MethodEquipmentEquip,
			protocol.EquipmentEquipParams{
				ItemID: "item.training_sword",
			},
			"hitstop",
		)
	})

	t.Run("maker preview", func(t *testing.T) {
		runtime := newCampaignRuntime(t)
		giveCampaignItems(t, runtime, 0, 1)
		x, y := 520.0, 260.0
		if _, err := runtime.spawnEntity(protocol.SpawnEntityParams{
			ActorID:  "actor.slime",
			EntityID: "preview.slime",
			X:        &x,
			Y:        &y,
		}); err != nil {
			t.Fatal(err)
		}
		assertEquipmentProtocolFailureAtomic(
			t,
			runtime,
			protocol.MethodEquipmentEquip,
			protocol.EquipmentEquipParams{
				ItemID: "item.training_sword",
			},
			"Maker preview",
		)
	})

	t.Run("maker wall edit", func(t *testing.T) {
		runtime := newCampaignRuntime(t)
		giveCampaignItems(t, runtime, 0, 1)
		callRuntime(
			t,
			runtime,
			protocol.MethodWorldSetWall,
			protocol.SetWallParams{
				WallID: "north_boundary",
				X:      0,
				Y:      2,
				Width:  960,
				Height: 20,
			},
		)
		assertEquipmentProtocolFailureAtomic(
			t,
			runtime,
			protocol.MethodEquipmentEquip,
			protocol.EquipmentEquipParams{
				ItemID: "item.training_sword",
			},
			"Maker preview",
		)
	})

	t.Run("authored dialogue", func(t *testing.T) {
		runtime := newCampaignRuntime(t)
		giveCampaignItems(t, runtime, 0, 1)
		openVillageGuideDialogue(t, runtime)
		assertEquipmentProtocolFailureAtomic(
			t,
			runtime,
			protocol.MethodEquipmentEquip,
			protocol.EquipmentEquipParams{
				ItemID: "item.training_sword",
			},
			"dialogue",
		)
	})
}

func TestAuthoredEquipmentChangeDefersUntilCombatSessionIsSafe(
	t *testing.T,
) {
	runtime := newCampaignRuntime(t)
	openVillageGuideDialogue(t, runtime)
	runtime.mu.Lock()
	runtime.simulation.Tick(sim.Input{Attack: true})
	runtime.mu.Unlock()

	callRuntime(
		t,
		runtime,
		protocol.MethodDialogueChoose,
		protocol.ChooseDialogueParams{ChoiceID: "accept"},
	)
	if !runtime.equipmentRebuildPending ||
		controlledAttackDamage(t, runtime) != 34 ||
		campaignEquipment(
			t,
			runtime.CampaignState(),
			"weapon",
		).ItemID != "item.training_sword" {
		t.Fatalf(
			"authored combat equip was not deferred: pending=%v damage=%d state=%#v",
			runtime.equipmentRebuildPending,
			controlledAttackDamage(t, runtime),
			runtime.CampaignState(),
		)
	}
	if _, err := runtime.save(
		context.Background(),
		"pending-equipment",
	); err == nil || !strings.Contains(err.Error(), "pending") {
		t.Fatalf("pending equipment save error = %v", err)
	}
	runtime.mu.Lock()
	if err := runtime.pauseFlowLocked(); err != nil {
		runtime.mu.Unlock()
		t.Fatal(err)
	}
	modeAfterPause := runtime.campaign.Snapshot().Mode
	runtime.mu.Unlock()
	if modeAfterPause != campaign.ModePlaying {
		t.Fatalf("pending equipment entered flow mode %q", modeAfterPause)
	}
	assertEquipmentProtocolFailureAtomic(
		t,
		runtime,
		protocol.MethodWorldSetWall,
		protocol.SetWallParams{
			WallID: "north",
			X:      0,
			Y:      2,
			Width:  960,
			Height: 20,
		},
		"pending",
	)
	spawnX, spawnY := 520.0, 260.0
	assertEquipmentProtocolFailureAtomic(
		t,
		runtime,
		protocol.MethodEntitySpawn,
		protocol.SpawnEntityParams{
			ActorID:  "actor.slime",
			EntityID: "pending.preview",
			X:        &spawnX,
			Y:        &spawnY,
		},
		"pending",
	)
	assertEquipmentProtocolFailureAtomic(
		t,
		runtime,
		protocol.MethodEntityRemove,
		protocol.RemoveEntityParams{EntityID: "guide"},
		"pending",
	)
	assertEquipmentProtocolFailureAtomic(
		t,
		runtime,
		protocol.MethodDialogueStart,
		protocol.StartDialogueParams{
			DialogueID: "dialogue.village_guide",
		},
		"pending",
	)
	callRuntime(
		t,
		runtime,
		protocol.MethodDialogueAdvance,
		protocol.EmptyParams{},
	)
	for range 60 {
		if err := runtime.Tick(ebitapp.Actions{}); err != nil {
			t.Fatal(err)
		}
		if !runtime.equipmentRebuildPending {
			break
		}
	}
	if runtime.equipmentRebuildPending ||
		controlledAttackDamage(t, runtime) != 39 {
		t.Fatalf(
			"deferred authored equip did not publish: pending=%v damage=%d",
			runtime.equipmentRebuildPending,
			controlledAttackDamage(t, runtime),
		)
	}
}

func TestPendingAuthoredEquipmentPortalBuildsConsistentTargetWorld(
	t *testing.T,
) {
	runtime := newCampaignRuntime(t)
	openVillageGuideDialogue(t, runtime)
	runtime.mu.Lock()
	runtime.simulation.Tick(sim.Input{Attack: true})
	runtime.mu.Unlock()
	callRuntime(
		t,
		runtime,
		protocol.MethodDialogueChoose,
		protocol.ChooseDialogueParams{ChoiceID: "accept"},
	)
	if !runtime.equipmentRebuildPending {
		t.Fatal("authored combat equip did not enter pending state")
	}

	runtime.mu.Lock()
	portal := findPortal(t, runtime, "to_field")
	err := runtime.transitionPortalLocked(portal)
	runtime.mu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	if runtime.equipmentRebuildPending {
		t.Fatal("portal retained a stale equipment rebuild")
	}
	assertLocation(t, runtime, "stage.world_hub", "village_entry")
	assertEquippedSwordDamage(t, runtime)
}

func TestInventoryModalFreezesWorldAndUsesEquipsAndUnequips(t *testing.T) {
	runtime := newCampaignRuntime(t)
	giveCampaignItems(t, runtime, 2, 1)
	callRuntime(
		t,
		runtime,
		protocol.MethodEntitySetHealth,
		protocol.SetHealthParams{EntityID: "player", Value: 50},
	)

	if err := runtime.Tick(ebitapp.Actions{InventoryToggle: true}); err != nil {
		t.Fatal(err)
	}
	view := runtime.View().Inventory
	if !view.Active || len(view.Items) != 2 ||
		view.SelectedIndex != 0 ||
		view.Items[0].ID != "item.potion" ||
		!view.Items[0].CanUse ||
		view.Items[1].ID != "item.training_sword" ||
		view.Items[1].ModifierSummary != "ATK +5" ||
		!view.Items[1].CanEquip {
		t.Fatalf("opened inventory view = %#v", view)
	}
	beforeWorld := runtime.simulation.Snapshot()
	if err := runtime.Tick(ebitapp.Actions{
		MoveX:  1,
		Attack: true,
	}); err != nil {
		t.Fatal(err)
	}
	if got := runtime.simulation.Snapshot(); !reflect.DeepEqual(
		got,
		beforeWorld,
	) {
		t.Fatalf("inventory gameplay input advanced World: %#v", got)
	}

	if err := runtime.Tick(ebitapp.Actions{
		InventoryActivate: true,
	}); err != nil {
		t.Fatal(err)
	}
	if got := entitySnapshot(t, runtime, "player").Health; got != 75 {
		t.Fatalf("inventory potion health = %d, want 75", got)
	}
	view = runtime.View().Inventory
	if !view.Active || view.Items[0].Quantity != 1 ||
		view.Status == "" {
		t.Fatalf("potion result view = %#v", view)
	}

	if err := runtime.Tick(ebitapp.Actions{InventoryDown: true}); err != nil {
		t.Fatal(err)
	}
	if err := runtime.Tick(ebitapp.Actions{
		InventoryActivate: true,
	}); err != nil {
		t.Fatal(err)
	}
	view = runtime.View().Inventory
	if !view.Active || view.SelectedIndex != 1 ||
		!view.Items[1].Equipped ||
		view.Items[1].CanEquip ||
		controlledAttackDamage(t, runtime) != 39 {
		t.Fatalf("equipment inventory view = %#v", view)
	}

	if err := runtime.Tick(ebitapp.Actions{
		InventoryUnequip: true,
	}); err != nil {
		t.Fatal(err)
	}
	if got := controlledAttackDamage(t, runtime); got != 34 {
		t.Fatalf("inventory unequip damage = %d, want 34", got)
	}
	if err := runtime.Tick(ebitapp.Actions{
		InventoryUnequip: true,
	}); err != nil {
		t.Fatal(err)
	}
	if status := runtime.View().Inventory.Status; status == "" ||
		!strings.Contains(status, "not equipped") {
		t.Fatalf("inventory failure status = %q", status)
	}

	if err := runtime.Tick(ebitapp.Actions{
		InventoryCancel: true,
	}); err != nil {
		t.Fatal(err)
	}
	if runtime.View().Inventory.Active {
		t.Fatal("inventory cancel did not close the modal")
	}
}

func TestInventoryRejectsCompetingProtocolDialogueAtomically(t *testing.T) {
	runtime := newCampaignRuntime(t)
	if err := runtime.Tick(ebitapp.Actions{InventoryToggle: true}); err != nil {
		t.Fatal(err)
	}
	assertEquipmentProtocolFailureAtomic(
		t,
		runtime,
		protocol.MethodDialogueStart,
		protocol.StartDialogueParams{
			DialogueID: "dialogue.village_guide",
		},
		"another modal",
	)
	if !runtime.View().Inventory.Active {
		t.Fatal("rejected protocol dialogue closed inventory")
	}
}

func TestInventoryTransientClearsAcrossPlayerWorldLifecycles(t *testing.T) {
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
				runtime.mu.Unlock()
				if err != nil {
					t.Fatal(err)
				}
			},
		},
		{
			name: "load",
			action: func(t *testing.T, runtime *Runtime) {
				t.Helper()
				callRuntime(
					t,
					runtime,
					protocol.MethodAppLoad,
					protocol.SaveSlotParams{Slot: "inventory-lifecycle"},
				)
			},
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			runtime := newCampaignRuntime(t)
			giveCampaignItems(t, runtime, 1, 1)
			callRuntime(
				t,
				runtime,
				protocol.MethodAppSave,
				protocol.SaveSlotParams{Slot: "inventory-lifecycle"},
			)
			if err := runtime.Tick(ebitapp.Actions{
				InventoryToggle: true,
			}); err != nil {
				t.Fatal(err)
			}
			runtime.inventorySelected = 1
			runtime.inventoryStatus = "transient status"

			test.action(t, runtime)

			view := runtime.View().Inventory
			if view.Active ||
				view.SelectedIndex != -1 ||
				len(view.Items) != 0 ||
				view.Status != "" ||
				runtime.inventoryOpen ||
				runtime.inventorySelected != 0 ||
				runtime.inventoryStatus != "" {
				t.Fatalf(
					"%s retained transient inventory: view=%#v runtime=%v/%d/%q",
					test.name,
					view,
					runtime.inventoryOpen,
					runtime.inventorySelected,
					runtime.inventoryStatus,
				)
			}
		})
	}
}

func giveCampaignItems(
	t *testing.T,
	runtime *Runtime,
	potions int64,
	swords int64,
) {
	t.Helper()
	if err := runtime.campaign.Transaction(func(state *campaign.State) error {
		for index := range state.Inventory {
			switch state.Inventory[index].ItemID {
			case "item.potion":
				state.Inventory[index].Quantity = potions
			case "item.training_sword":
				state.Inventory[index].Quantity = swords
			}
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
}

func controlledAttackDamage(t *testing.T, runtime *Runtime) int {
	t.Helper()
	runtime.mu.RLock()
	defer runtime.mu.RUnlock()
	return runtime.controlledAttackDamageLocked()
}

func assertEquippedSwordDamage(t *testing.T, runtime *Runtime) {
	t.Helper()
	state := runtime.CampaignState()
	if got := campaignEquipment(t, state, "weapon").ItemID; got !=
		"item.training_sword" {
		t.Fatalf("equipped weapon = %q", got)
	}
	if got := controlledAttackDamage(t, runtime); got != 39 {
		t.Fatalf("equipped controlled attack damage = %d, want 39", got)
	}
}

func assertEquipmentProtocolFailureAtomic(
	t *testing.T,
	runtime *Runtime,
	method string,
	params any,
	message string,
) {
	t.Helper()
	runtime.mu.RLock()
	beforeCampaign := runtime.campaign
	beforeBuilt := runtime.built
	beforeSimulation := runtime.simulation
	beforeDialogue := runtime.dialogue
	beforeShopID := runtime.activeShopID
	beforeState := runtime.campaign.Snapshot()
	beforeSession := runtime.simulation.SaveSession()
	beforeRevision := runtime.revision
	beforeInventoryOpen := runtime.inventoryOpen
	beforeInventorySelected := runtime.inventorySelected
	beforeInventoryStatus := runtime.inventoryStatus
	beforeEquipmentPending := runtime.equipmentRebuildPending
	runtime.mu.RUnlock()

	_, err := runtime.Call(context.Background(), protocol.Call{
		Method: method,
		Params: params,
	})
	if err == nil || !strings.Contains(err.Error(), message) {
		t.Fatalf("%s error = %v, want containing %q", method, err, message)
	}

	runtime.mu.RLock()
	defer runtime.mu.RUnlock()
	if runtime.campaign != beforeCampaign ||
		runtime.built != beforeBuilt ||
		runtime.simulation != beforeSimulation ||
		runtime.dialogue != beforeDialogue ||
		runtime.activeShopID != beforeShopID ||
		runtime.revision != beforeRevision ||
		runtime.inventoryOpen != beforeInventoryOpen ||
		runtime.inventorySelected != beforeInventorySelected ||
		runtime.inventoryStatus != beforeInventoryStatus ||
		runtime.equipmentRebuildPending != beforeEquipmentPending ||
		!reflect.DeepEqual(runtime.campaign.Snapshot(), beforeState) ||
		!reflect.DeepEqual(runtime.simulation.SaveSession(), beforeSession) {
		t.Fatalf("%s failure changed runtime state", method)
	}
}
