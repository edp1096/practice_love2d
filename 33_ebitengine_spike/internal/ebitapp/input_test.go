package ebitapp

import (
	"math"
	"reflect"
	"testing"
)

func TestMapRawInputNormalizesDigitalDiagonals(t *testing.T) {
	t.Parallel()

	got := mapRawInput(rawInput{right: true, up: true})
	want := math.Sqrt(0.5)
	if math.Abs(got.MoveX-want) > 1e-12 ||
		math.Abs(got.MoveY+want) > 1e-12 {
		t.Fatalf("movement = (%v,%v), want (%v,%v)",
			got.MoveX, got.MoveY, want, -want)
	}
}

func TestMapRawInputAppliesDeadzone(t *testing.T) {
	t.Parallel()

	got := mapRawInput(rawInput{stickX: 0.1, stickY: -0.1})
	if got.MoveX != 0 || got.MoveY != 0 {
		t.Fatalf("movement = (%v,%v), want zero", got.MoveX, got.MoveY)
	}
}

func TestMapRawInputKeepsActionEdges(t *testing.T) {
	t.Parallel()

	got := mapRawInput(rawInput{
		attack:            true,
		parry:             true,
		dodge:             true,
		dialogueUp:        true,
		dialogueDown:      true,
		dialogueConfirm:   true,
		dialogueCancel:    true,
		shopUp:            true,
		shopDown:          true,
		shopBuy:           true,
		shopSell:          true,
		shopCancel:        true,
		inventoryToggle:   true,
		inventoryUp:       true,
		inventoryDown:     true,
		inventoryActivate: true,
		inventoryUnequip:  true,
		inventoryCancel:   true,
		flowUp:            true,
		flowDown:          true,
		flowConfirm:       true,
		flowCancel:        true,
		pause:             true,
	})
	if !got.Attack || !got.Parry || !got.Dodge ||
		!got.DialogueUp || !got.DialogueDown ||
		!got.DialogueConfirm || !got.DialogueCancel ||
		!got.ShopUp || !got.ShopDown ||
		!got.ShopBuy || !got.ShopSell || !got.ShopCancel ||
		!got.InventoryToggle ||
		!got.InventoryUp || !got.InventoryDown ||
		!got.InventoryActivate || !got.InventoryUnequip ||
		!got.InventoryCancel ||
		!got.FlowUp || !got.FlowDown ||
		!got.FlowConfirm || !got.FlowCancel ||
		!got.Pause {
		t.Fatalf("action edges were lost: %#v", got)
	}
}

func TestActionsForViewLeavesNonModalInputUntouched(t *testing.T) {
	t.Parallel()

	input := Actions{
		MoveX:           1,
		Attack:          true,
		Interact:        true,
		MenuConfirm:     true,
		DialogueConfirm: true,
		InventoryToggle: true,
		Pause:           true,
		Restart:         true,
	}
	if got := actionsForView(input, View{}); !reflect.DeepEqual(got, input) {
		t.Fatalf("non-modal actions = %#v, want %#v", got, input)
	}
}

func TestActionsForViewNormalizesGameplayInventoryToggle(t *testing.T) {
	t.Parallel()

	got := actionsForView(
		Actions{
			InventoryToggle: true,
			InventoryCancel: true,
		},
		View{},
	)
	if got != (Actions{InventoryToggle: true}) {
		t.Fatalf("gameplay inventory toggle = %#v", got)
	}
}

func TestActionsForViewGivesDialogueExclusiveSharedKeys(t *testing.T) {
	t.Parallel()

	got := actionsForView(
		Actions{
			MoveX:         1,
			MoveY:         -1,
			Attack:        true,
			Interact:      true,
			MenuUp:        true,
			MenuConfirm:   true,
			DialogueDown:  true,
			ShopUp:        true,
			ShopBuy:       true,
			InventoryDown: true,
			Restart:       true,
		},
		View{
			Dialogue:  DialogueView{Active: true},
			Shop:      ShopView{Active: true},
			Inventory: InventoryView{Active: true},
		},
	)
	want := Actions{
		DialogueDown: true,
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("modal actions = %#v, want %#v", got, want)
	}
}

func TestActionsForViewResolvesSimultaneousModalEdges(t *testing.T) {
	t.Parallel()

	view := View{Dialogue: DialogueView{Active: true}}
	cancel := actionsForView(
		Actions{
			DialogueUp:      true,
			DialogueConfirm: true,
			DialogueCancel:  true,
			// Escape is both cancel and the legacy pause shortcut. It must
			// cancel the modal without also toggling pause.
			Pause: true,
		},
		view,
	)
	if cancel != (Actions{DialogueCancel: true}) {
		t.Fatalf("cancel-priority actions = %#v", cancel)
	}
	confirm := actionsForView(
		Actions{
			DialogueDown:    true,
			DialogueConfirm: true,
		},
		view,
	)
	if confirm != (Actions{DialogueConfirm: true}) {
		t.Fatalf("confirm-priority actions = %#v", confirm)
	}
	opposites := actionsForView(
		Actions{DialogueUp: true, DialogueDown: true},
		view,
	)
	if opposites != (Actions{}) {
		t.Fatalf("opposite navigation actions = %#v", opposites)
	}
}

func TestActionsForViewKeepsDedicatedPauseEdge(t *testing.T) {
	t.Parallel()

	got := actionsForView(
		Actions{Pause: true},
		View{Dialogue: DialogueView{Active: true}},
	)
	if !got.Pause {
		t.Fatalf("dedicated pause edge was lost: %#v", got)
	}
}

func TestActionsForViewGivesShopPriorityOverGameplayAndMenu(
	t *testing.T,
) {
	t.Parallel()

	got := actionsForView(
		Actions{
			MoveX:           -1,
			MoveY:           1,
			Technique:       true,
			Interact:        true,
			MenuDown:        true,
			MenuConfirm:     true,
			DialogueConfirm: true,
			ShopDown:        true,
			Restart:         true,
		},
		View{
			Shop:      ShopView{Active: true},
			Inventory: InventoryView{Active: true},
		},
	)
	if got != (Actions{ShopDown: true}) {
		t.Fatalf("shop-modal actions = %#v", got)
	}
}

func TestActionsForViewResolvesSimultaneousShopEdges(t *testing.T) {
	t.Parallel()

	view := View{Shop: ShopView{Active: true}}
	cancel := actionsForView(
		Actions{
			ShopUp:     true,
			ShopBuy:    true,
			ShopSell:   true,
			ShopCancel: true,
			// Escape is both close and the legacy pause shortcut.
			Pause: true,
		},
		view,
	)
	if cancel != (Actions{ShopCancel: true}) {
		t.Fatalf("shop cancel-priority actions = %#v", cancel)
	}
	buy := actionsForView(
		Actions{
			ShopDown: true,
			ShopBuy:  true,
			ShopSell: true,
		},
		view,
	)
	if buy != (Actions{ShopBuy: true}) {
		t.Fatalf("shop buy-priority actions = %#v", buy)
	}
	sell := actionsForView(
		Actions{
			ShopUp:   true,
			ShopSell: true,
		},
		view,
	)
	if sell != (Actions{ShopSell: true}) {
		t.Fatalf("shop sell-priority actions = %#v", sell)
	}
	opposites := actionsForView(
		Actions{ShopUp: true, ShopDown: true},
		view,
	)
	if opposites != (Actions{}) {
		t.Fatalf("opposite shop navigation actions = %#v", opposites)
	}
}

func TestActionsForViewKeepsDedicatedPauseInShop(t *testing.T) {
	t.Parallel()

	got := actionsForView(
		Actions{Pause: true},
		View{Shop: ShopView{Active: true}},
	)
	if got != (Actions{Pause: true}) {
		t.Fatalf("shop dedicated pause edge = %#v", got)
	}
}

func TestActionsForViewGivesInventoryPriorityOverGameplayAndMenu(
	t *testing.T,
) {
	t.Parallel()

	got := actionsForView(
		Actions{
			MoveX:         1,
			Attack:        true,
			Interact:      true,
			MenuDown:      true,
			InventoryDown: true,
			Restart:       true,
		},
		View{
			Inventory: InventoryView{
				Active:        true,
				Items:         []InventoryItemView{{ID: "item.potion"}},
				SelectedIndex: 0,
			},
		},
	)
	if got != (Actions{InventoryDown: true}) {
		t.Fatalf("inventory-modal actions = %#v", got)
	}
}

func TestActionsForViewResolvesSimultaneousInventoryEdges(
	t *testing.T,
) {
	t.Parallel()

	view := InventoryView{
		Active:        true,
		Items:         []InventoryItemView{{ID: "item.sword"}},
		SelectedIndex: 0,
	}
	cancel := inventoryActions(
		Actions{
			InventoryToggle:   true,
			InventoryCancel:   true,
			InventoryUp:       true,
			InventoryActivate: true,
			InventoryUnequip:  true,
			Pause:             true,
		},
		view,
	)
	if cancel != (Actions{InventoryCancel: true}) {
		t.Fatalf("inventory cancel-priority actions = %#v", cancel)
	}
	if tab := inventoryActions(
		Actions{InventoryToggle: true},
		view,
	); tab != (Actions{}) {
		t.Fatalf("active inventory tab toggle = %#v", tab)
	}
	activate := inventoryActions(
		Actions{
			InventoryDown:     true,
			InventoryActivate: true,
			InventoryUnequip:  true,
		},
		view,
	)
	if activate != (Actions{InventoryActivate: true}) {
		t.Fatalf("inventory activate-priority actions = %#v", activate)
	}
	unequip := inventoryActions(
		Actions{
			InventoryUp:      true,
			InventoryUnequip: true,
		},
		view,
	)
	if unequip != (Actions{InventoryUnequip: true}) {
		t.Fatalf("inventory unequip-priority actions = %#v", unequip)
	}
	opposites := inventoryActions(
		Actions{InventoryUp: true, InventoryDown: true},
		view,
	)
	if opposites != (Actions{}) {
		t.Fatalf("opposite inventory navigation actions = %#v", opposites)
	}
}

func TestInventoryActionsDefendsInvalidOrEmptySelection(t *testing.T) {
	t.Parallel()

	invalid := InventoryView{
		Items:         []InventoryItemView{{ID: "item.potion"}},
		SelectedIndex: 99,
	}
	if got := inventoryActions(
		Actions{InventoryActivate: true, InventoryUnequip: true},
		invalid,
	); got != (Actions{}) {
		t.Fatalf("invalid inventory activation = %#v", got)
	}
	if got := inventoryActions(
		Actions{InventoryDown: true},
		invalid,
	); got != (Actions{InventoryDown: true}) {
		t.Fatalf("invalid inventory navigation = %#v", got)
	}
	if got := inventoryActions(
		Actions{InventoryUp: true, InventoryActivate: true},
		InventoryView{},
	); got != (Actions{}) {
		t.Fatalf("empty inventory actions = %#v", got)
	}
}

func TestActionsForViewKeepsDedicatedPauseInInventory(t *testing.T) {
	t.Parallel()

	got := actionsForView(
		Actions{Pause: true},
		View{Inventory: InventoryView{Active: true}},
	)
	if got != (Actions{Pause: true}) {
		t.Fatalf("inventory dedicated pause edge = %#v", got)
	}
}

func TestActionsForViewGivesFlowHighestModalPriority(t *testing.T) {
	t.Parallel()

	got := actionsForView(
		Actions{
			MoveX:           1,
			Attack:          true,
			Interact:        true,
			MenuDown:        true,
			DialogueDown:    true,
			DialogueConfirm: true,
			ShopDown:        true,
			ShopBuy:         true,
			InventoryDown:   true,
			FlowDown:        true,
			Restart:         true,
		},
		View{
			Flow: FlowView{
				Active: true,
				Options: []FlowOptionView{
					{ID: "resume", Enabled: true},
				},
				SelectedIndex: 0,
			},
			Dialogue:  DialogueView{Active: true},
			Shop:      ShopView{Active: true},
			Inventory: InventoryView{Active: true},
		},
	)
	if got != (Actions{FlowDown: true}) {
		t.Fatalf("flow-modal actions = %#v", got)
	}
}

func TestActionsForViewResolvesSimultaneousFlowEdges(t *testing.T) {
	t.Parallel()

	view := FlowView{
		Active: true,
		Options: []FlowOptionView{
			{ID: "resume", Enabled: true},
		},
		SelectedIndex: 0,
	}
	cancel := flowActions(
		Actions{
			FlowUp:      true,
			FlowConfirm: true,
			FlowCancel:  true,
			Pause:       true,
		},
		view,
	)
	if cancel != (Actions{FlowCancel: true}) {
		t.Fatalf("flow cancel-priority actions = %#v", cancel)
	}
	confirm := flowActions(
		Actions{FlowDown: true, FlowConfirm: true},
		view,
	)
	if confirm != (Actions{FlowConfirm: true}) {
		t.Fatalf("flow confirm-priority actions = %#v", confirm)
	}
	opposites := flowActions(
		Actions{FlowUp: true, FlowDown: true},
		view,
	)
	if opposites != (Actions{}) {
		t.Fatalf("opposite flow navigation actions = %#v", opposites)
	}
}

func TestFlowActionsDefendsUnavailableSelection(t *testing.T) {
	t.Parallel()

	allDisabled := FlowView{
		Options: []FlowOptionView{
			{ID: "a"},
			{ID: "b"},
		},
		SelectedIndex: 0,
	}
	if got := flowActions(
		Actions{FlowDown: true, FlowConfirm: true},
		allDisabled,
	); got != (Actions{}) {
		t.Fatalf("all-disabled flow actions = %#v", got)
	}
	invalidSelection := FlowView{
		Options: []FlowOptionView{
			{ID: "disabled"},
			{ID: "enabled", Enabled: true},
		},
		SelectedIndex: 0,
	}
	if got := flowActions(
		Actions{FlowConfirm: true},
		invalidSelection,
	); got != (Actions{}) {
		t.Fatalf("disabled-selection confirm = %#v", got)
	}
	if got := flowActions(
		Actions{FlowDown: true},
		invalidSelection,
	); got != (Actions{FlowDown: true}) {
		t.Fatalf("disabled-selection navigation = %#v", got)
	}
}

func TestFlowSelectionSkipsDisabledOptionsAndWraps(t *testing.T) {
	t.Parallel()

	options := []FlowOptionView{
		{ID: "disabled-a"},
		{ID: "one", Enabled: true},
		{ID: "disabled-b"},
		{ID: "two", Enabled: true},
	}
	tests := []struct {
		name      string
		current   int
		direction int
		want      int
	}{
		{name: "start", current: -1, direction: 1, want: 1},
		{name: "down skips", current: 1, direction: 1, want: 3},
		{name: "down wraps", current: 3, direction: 1, want: 1},
		{name: "up skips", current: 3, direction: -1, want: 1},
		{name: "up wraps", current: 1, direction: -1, want: 3},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			if got := nextEnabledFlowOptionIndex(
				options,
				test.current,
				test.direction,
			); got != test.want {
				t.Fatalf(
					"next enabled index = %d, want %d",
					got,
					test.want,
				)
			}
		})
	}
	if got := normalizedFlowSelection(options, -99); got != 1 {
		t.Fatalf("normalized negative flow selection = %d", got)
	}
	if got := normalizedFlowSelection(options, 99); got != 3 {
		t.Fatalf("normalized high flow selection = %d", got)
	}
	if got := normalizedFlowSelection(
		[]FlowOptionView{{}, {}},
		0,
	); got != -1 {
		t.Fatalf("all-disabled normalized selection = %d", got)
	}
}

func TestActionsForViewKeepsDedicatedPauseInFlow(t *testing.T) {
	t.Parallel()

	got := actionsForView(
		Actions{Pause: true},
		View{Flow: FlowView{Active: true}},
	)
	if got != (Actions{Pause: true}) {
		t.Fatalf("flow dedicated pause edge = %#v", got)
	}
}
