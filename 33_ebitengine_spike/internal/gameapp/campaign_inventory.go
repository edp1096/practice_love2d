package gameapp

import (
	"errors"
	"fmt"

	"practice_love2d/33_ebitengine_spike/internal/campaign"
	"practice_love2d/33_ebitengine_spike/internal/ebitapp"
)

func (runtime *Runtime) inventoryViewLocked() (
	ebitapp.InventoryView,
	error,
) {
	result := ebitapp.InventoryView{
		Active:        runtime.inventoryOpen,
		Title:         "소지품",
		Items:         []ebitapp.InventoryItemView{},
		SelectedIndex: -1,
		Status:        runtime.inventoryStatus,
	}
	if !runtime.inventoryOpen {
		return result, nil
	}
	if runtime.campaign == nil {
		return result, errors.New("inventory: campaign is unavailable")
	}

	state := runtime.campaign.Snapshot()
	controlledAlive := false
	equipmentChangeAvailable :=
		runtime.requireCampaignRebuildSafeLocked(false) == nil
	controlledID := runtime.built.Config.Camera.TargetEntityID
	for _, entity := range runtime.simulation.Snapshot().Entities {
		if entity.ID == controlledID {
			controlledAlive = !entity.Dead
			break
		}
	}
	for _, entry := range state.Inventory {
		if entry.Quantity <= 0 {
			continue
		}
		rule, exists := runtime.contentRules.Item(entry.ItemID)
		if !exists {
			return result, fmt.Errorf(
				"inventory: item %q has no content rule",
				entry.ItemID,
			)
		}
		item := ebitapp.InventoryItemView{
			ID: entry.ItemID,
			Name: runtime.localizeRuleTextLocked(
				rule.Name,
				rule.NameKey,
			),
			Description: runtime.localizeRuleTextLocked(
				rule.Description,
				rule.DescriptionKey,
			),
			ModifierSummary: equipmentModifierSummary(rule.Equipment),
			Quantity:        entry.Quantity,
			Consumable:      rule.Consumable,
			Equipped:        campaignItemEquipped(state, entry.ItemID),
			CanUse:          rule.Consumable && controlledAlive,
		}
		if rule.Equipment != nil {
			item.EquipmentSlot = rule.Equipment.Slot
			item.CanEquip = !item.Equipped && equipmentChangeAvailable
		}
		result.Items = append(result.Items, item)
	}
	if len(result.Items) != 0 {
		result.SelectedIndex = min(
			max(runtime.inventorySelected, 0),
			len(result.Items)-1,
		)
	}
	return result, nil
}

func (runtime *Runtime) openInventoryLocked() error {
	if runtime.inventoryOpen {
		return nil
	}
	if runtime.campaign.Snapshot().Mode != campaign.ModePlaying {
		return errors.New("open inventory: game flow is modal")
	}
	if runtime.dialogue != nil || runtime.activeShopID != "" ||
		runtime.simulation.Snapshot().Dialogue.Active {
		return errors.New(
			"open inventory: another modal is active",
		)
	}
	runtime.inventoryOpen = true
	runtime.inventoryStatus = ""
	view, err := runtime.inventoryViewLocked()
	if err != nil {
		runtime.inventoryOpen = false
		return err
	}
	if len(view.Items) == 0 {
		runtime.inventorySelected = -1
	} else {
		runtime.inventorySelected = 0
	}
	runtime.queueAudioEventLocked("ui.confirm")
	runtime.revision++
	return nil
}

func (runtime *Runtime) closeInventoryLocked() {
	if !runtime.inventoryOpen {
		return
	}
	runtime.inventoryOpen = false
	runtime.inventorySelected = 0
	runtime.inventoryStatus = ""
	runtime.queueAudioEventLocked("ui.cancel")
	runtime.revision++
}

func (runtime *Runtime) moveInventorySelectionLocked(delta int) error {
	view, err := runtime.inventoryViewLocked()
	if err != nil {
		return err
	}
	if !view.Active {
		return errors.New("move inventory selection: inventory is not active")
	}
	if len(view.Items) == 0 || delta == 0 {
		return nil
	}
	index := (view.SelectedIndex + delta) % len(view.Items)
	if index < 0 {
		index += len(view.Items)
	}
	runtime.inventorySelected = index
	runtime.inventoryStatus = ""
	runtime.revision++
	return nil
}

func (runtime *Runtime) selectedInventoryItemLocked() (
	ebitapp.InventoryItemView,
	error,
) {
	view, err := runtime.inventoryViewLocked()
	if err != nil {
		return ebitapp.InventoryItemView{}, err
	}
	if !view.Active {
		return ebitapp.InventoryItemView{}, errors.New(
			"inventory is not active",
		)
	}
	if view.SelectedIndex < 0 || view.SelectedIndex >= len(view.Items) {
		return ebitapp.InventoryItemView{}, errors.New(
			"inventory has no selected item",
		)
	}
	return view.Items[view.SelectedIndex], nil
}

func (runtime *Runtime) activateInventorySelectionLocked() error {
	item, err := runtime.selectedInventoryItemLocked()
	if err != nil {
		return err
	}
	beforeRevision := runtime.revision
	switch {
	case item.Consumable:
		if _, err := runtime.useInventoryItemLocked(item.ID); err != nil {
			return err
		}
		runtime.inventoryStatus = item.Name + " 사용"

	case item.EquipmentSlot != "":
		change, err := runtime.equipCampaignItemLocked(item.ID)
		if err != nil {
			return err
		}
		if change.Changed {
			runtime.inventoryStatus = item.Name + " 장착"
		} else {
			runtime.inventoryStatus = item.Name + " 장착 중"
		}

	default:
		return fmt.Errorf("item %q cannot be used or equipped", item.ID)
	}
	runtime.normalizeInventorySelectionLocked()
	runtime.queueAudioEventLocked("ui.confirm")
	if runtime.revision == beforeRevision {
		runtime.revision++
	}
	return nil
}

func (runtime *Runtime) unequipInventorySelectionLocked() error {
	item, err := runtime.selectedInventoryItemLocked()
	if err != nil {
		return err
	}
	if item.EquipmentSlot == "" {
		return fmt.Errorf("item %q is not equipment", item.ID)
	}
	if !item.Equipped {
		return fmt.Errorf("item %q is not equipped", item.ID)
	}
	beforeRevision := runtime.revision
	if _, err := runtime.unequipCampaignItemLocked(
		item.EquipmentSlot,
	); err != nil {
		return err
	}
	runtime.inventoryStatus = item.Name + " 장착 해제"
	runtime.queueAudioEventLocked("ui.confirm")
	if runtime.revision == beforeRevision {
		runtime.revision++
	}
	return nil
}

func (runtime *Runtime) normalizeInventorySelectionLocked() {
	view, err := runtime.inventoryViewLocked()
	if err != nil || len(view.Items) == 0 {
		runtime.inventorySelected = -1
		return
	}
	runtime.inventorySelected = min(
		max(runtime.inventorySelected, 0),
		len(view.Items)-1,
	)
}

func (runtime *Runtime) setInventoryFailureLocked(err error) {
	if err == nil {
		return
	}
	runtime.inventoryStatus = err.Error()
	runtime.normalizeInventorySelectionLocked()
	runtime.revision++
}
