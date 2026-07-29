package ebitapp

import (
	"math"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/inpututil"
)

const gamepadDeadzone = 0.22

// Actions is one fixed tick of device-independent player intent.
//
// Held movement is continuous. Buttons are edge-triggered so a held key does
// not restart an attack, dialogue choice, shop transaction, or flow action on
// every tick.
type Actions struct {
	MoveX float64
	MoveY float64

	Attack    bool
	Special   bool
	Technique bool
	Parry     bool
	Dodge     bool
	Jump      bool
	Interact  bool

	MenuUp      bool
	MenuDown    bool
	MenuLeft    bool
	MenuRight   bool
	MenuConfirm bool
	MenuCancel  bool

	DialogueUp      bool
	DialogueDown    bool
	DialogueConfirm bool
	DialogueCancel  bool

	ShopUp     bool
	ShopDown   bool
	ShopBuy    bool
	ShopSell   bool
	ShopCancel bool

	InventoryToggle   bool
	InventoryUp       bool
	InventoryDown     bool
	InventoryActivate bool
	InventoryUnequip  bool
	InventoryCancel   bool

	FlowUp      bool
	FlowDown    bool
	FlowConfirm bool
	FlowCancel  bool

	Pause   bool
	Restart bool
}

type rawInput struct {
	left, right, up, down bool
	stickX, stickY        float64

	attack, special, technique   bool
	parry, dodge, jump, interact bool
	confirm, cancel, pause       bool
	restart                      bool
	menuUp, menuDown             bool
	menuLeft, menuRight          bool
	dialogueUp, dialogueDown     bool
	dialogueConfirm              bool
	dialogueCancel               bool
	shopUp, shopDown             bool
	shopBuy, shopSell            bool
	shopCancel                   bool
	inventoryToggle              bool
	inventoryUp, inventoryDown   bool
	inventoryActivate            bool
	inventoryUnequip             bool
	inventoryCancel              bool
	flowUp, flowDown             bool
	flowConfirm                  bool
	flowCancel                   bool
}

func mapRawInput(raw rawInput) Actions {
	x, y := raw.stickX, raw.stickY
	if raw.left {
		x--
	}
	if raw.right {
		x++
	}
	if raw.up {
		y--
	}
	if raw.down {
		y++
	}
	length := math.Hypot(x, y)
	if length < gamepadDeadzone {
		x, y = 0, 0
	} else if length > 1 {
		x /= length
		y /= length
	}
	return Actions{
		MoveX: x,
		MoveY: y,

		Attack:    raw.attack,
		Special:   raw.special,
		Technique: raw.technique,
		Parry:     raw.parry,
		Dodge:     raw.dodge,
		Jump:      raw.jump,
		Interact:  raw.interact,

		MenuUp:      raw.menuUp,
		MenuDown:    raw.menuDown,
		MenuLeft:    raw.menuLeft,
		MenuRight:   raw.menuRight,
		MenuConfirm: raw.confirm,
		MenuCancel:  raw.cancel,

		DialogueUp:      raw.dialogueUp,
		DialogueDown:    raw.dialogueDown,
		DialogueConfirm: raw.dialogueConfirm,
		DialogueCancel:  raw.dialogueCancel,

		ShopUp:     raw.shopUp,
		ShopDown:   raw.shopDown,
		ShopBuy:    raw.shopBuy,
		ShopSell:   raw.shopSell,
		ShopCancel: raw.shopCancel,

		InventoryToggle:   raw.inventoryToggle,
		InventoryUp:       raw.inventoryUp,
		InventoryDown:     raw.inventoryDown,
		InventoryActivate: raw.inventoryActivate,
		InventoryUnequip:  raw.inventoryUnequip,
		InventoryCancel:   raw.inventoryCancel,

		FlowUp:      raw.flowUp,
		FlowDown:    raw.flowDown,
		FlowConfirm: raw.flowConfirm,
		FlowCancel:  raw.flowCancel,

		Pause:   raw.pause,
		Restart: raw.restart,
	}
}

// actionsForView gives the highest-priority active modal exclusive ownership
// of shared gameplay and menu keys. Flow precedes dialogue, then shop, then
// inventory. E, Enter, Q, Escape, I, and the directional keys intentionally
// map to more than one semantic action in PollActions; this routing step
// prevents one physical edge from triggering multiple layers. The dedicated
// P/gamepad pause edge remains available.
func actionsForView(actions Actions, view View) Actions {
	if view.Flow.Active {
		return flowActions(actions, view.Flow)
	}
	if view.Dialogue.Active {
		return dialogueActions(actions)
	}
	if view.Shop.Active {
		return shopActions(actions)
	}
	if view.Inventory.Active {
		return inventoryActions(actions, view.Inventory)
	}
	if actions.InventoryToggle {
		// I is both the gameplay toggle and the inventory cancel key. Outside
		// the modal it has exactly one meaning: open inventory.
		actions.InventoryCancel = false
	}
	return actions
}

func dialogueActions(actions Actions) Actions {
	result := Actions{
		Pause: actions.Pause && !actions.DialogueCancel,
	}
	// A single tick has one modal outcome. Cancel takes precedence over
	// confirm, confirm over navigation, and opposite navigation edges cancel
	// each other. This keeps simultaneous keyboard/gamepad input deterministic.
	switch {
	case actions.DialogueCancel:
		result.DialogueCancel = true
	case actions.DialogueConfirm:
		result.DialogueConfirm = true
	case actions.DialogueUp != actions.DialogueDown:
		result.DialogueUp = actions.DialogueUp
		result.DialogueDown = actions.DialogueDown
	}
	return result
}

func shopActions(actions Actions) Actions {
	result := Actions{
		Pause: actions.Pause && !actions.ShopCancel,
	}
	// Only one transaction or navigation edge reaches the model in a tick.
	// Closing wins over a transaction, buying over selling, and opposite
	// navigation edges cancel each other.
	switch {
	case actions.ShopCancel:
		result.ShopCancel = true
	case actions.ShopBuy:
		result.ShopBuy = true
	case actions.ShopSell:
		result.ShopSell = true
	case actions.ShopUp != actions.ShopDown:
		result.ShopUp = actions.ShopUp
		result.ShopDown = actions.ShopDown
	}
	return result
}

func inventoryActions(actions Actions, view InventoryView) Actions {
	result := Actions{
		Pause: actions.Pause && !actions.InventoryCancel,
	}
	validSelection := view.SelectedIndex >= 0 &&
		view.SelectedIndex < len(view.Items)
	// Closing wins over item actions, activation over unequip, and opposite
	// navigation edges cancel each other. A stale selection may still navigate
	// so the model can repair it, but it cannot activate an unknown item.
	switch {
	case actions.InventoryCancel:
		result.InventoryCancel = true
	case actions.InventoryActivate && validSelection:
		result.InventoryActivate = true
	case actions.InventoryUnequip && validSelection:
		result.InventoryUnequip = true
	case len(view.Items) != 0 &&
		actions.InventoryUp != actions.InventoryDown:
		result.InventoryUp = actions.InventoryUp
		result.InventoryDown = actions.InventoryDown
	}
	return result
}

func normalizedFlowSelection(
	options []FlowOptionView,
	selected int,
) int {
	if len(options) == 0 {
		return -1
	}
	if selected >= 0 &&
		selected < len(options) &&
		options[selected].Enabled {
		return selected
	}
	switch {
	case selected < 0:
		return nextEnabledFlowOptionIndex(options, -1, 1)
	case selected >= len(options):
		return nextEnabledFlowOptionIndex(options, 0, -1)
	default:
		return nextEnabledFlowOptionIndex(options, selected, 1)
	}
}

func nextEnabledFlowOptionIndex(
	options []FlowOptionView,
	current int,
	direction int,
) int {
	if len(options) == 0 || direction == 0 {
		return -1
	}
	step := 1
	if direction < 0 {
		step = -1
	}
	if current < 0 || current >= len(options) {
		if step > 0 {
			current = -1
		} else {
			current = 0
		}
	}
	for range options {
		current = (current + step + len(options)) % len(options)
		if options[current].Enabled {
			return current
		}
	}
	return -1
}

func flowActions(actions Actions, view FlowView) Actions {
	result := Actions{
		Pause: actions.Pause && !actions.FlowCancel,
	}
	effective := normalizedFlowSelection(
		view.Options,
		view.SelectedIndex,
	)
	// Cancel always remains safe. Confirm requires the model-provided
	// selection itself to be enabled; a defensively normalized Draw selection
	// is not enough to guess which authored action the model would execute.
	switch {
	case actions.FlowCancel:
		result.FlowCancel = true
	case actions.FlowConfirm &&
		effective >= 0 &&
		effective == view.SelectedIndex:
		result.FlowConfirm = true
	case effective >= 0 && actions.FlowUp != actions.FlowDown:
		result.FlowUp = actions.FlowUp
		result.FlowDown = actions.FlowDown
	}
	return result
}

// PollActions reads keyboard and the first standard-layout gamepad.
func PollActions() Actions {
	raw := rawInput{
		left: ebiten.IsKeyPressed(ebiten.KeyA) ||
			ebiten.IsKeyPressed(ebiten.KeyArrowLeft),
		right: ebiten.IsKeyPressed(ebiten.KeyD) ||
			ebiten.IsKeyPressed(ebiten.KeyArrowRight),
		up: ebiten.IsKeyPressed(ebiten.KeyW) ||
			ebiten.IsKeyPressed(ebiten.KeyArrowUp),
		down: ebiten.IsKeyPressed(ebiten.KeyS) ||
			ebiten.IsKeyPressed(ebiten.KeyArrowDown),

		attack: inpututil.IsKeyJustPressed(ebiten.KeySpace) ||
			inpututil.IsKeyJustPressed(ebiten.KeyZ),
		special: inpututil.IsKeyJustPressed(ebiten.KeyF) ||
			inpututil.IsKeyJustPressed(ebiten.KeyV),
		technique: inpututil.IsKeyJustPressed(ebiten.KeyQ),
		parry: inpututil.IsKeyJustPressed(ebiten.KeyC) ||
			inpututil.IsKeyJustPressed(ebiten.KeyControlLeft) ||
			inpututil.IsKeyJustPressed(ebiten.KeyControlRight),
		dodge: inpututil.IsKeyJustPressed(ebiten.KeyX) ||
			inpututil.IsKeyJustPressed(ebiten.KeyShiftLeft) ||
			inpututil.IsKeyJustPressed(ebiten.KeyShiftRight),
		jump: inpututil.IsKeyJustPressed(ebiten.KeyW) ||
			inpututil.IsKeyJustPressed(ebiten.KeyArrowUp),
		interact: inpututil.IsKeyJustPressed(ebiten.KeyE),
		confirm: inpututil.IsKeyJustPressed(ebiten.KeyEnter) ||
			inpututil.IsKeyJustPressed(ebiten.KeySpace),
		cancel: inpututil.IsKeyJustPressed(ebiten.KeyEscape) ||
			inpututil.IsKeyJustPressed(ebiten.KeyBackspace),
		pause: inpututil.IsKeyJustPressed(ebiten.KeyEscape) ||
			inpututil.IsKeyJustPressed(ebiten.KeyP),
		restart: inpututil.IsKeyJustPressed(ebiten.KeyR),
		menuUp: inpututil.IsKeyJustPressed(ebiten.KeyW) ||
			inpututil.IsKeyJustPressed(ebiten.KeyArrowUp),
		menuDown: inpututil.IsKeyJustPressed(ebiten.KeyS) ||
			inpututil.IsKeyJustPressed(ebiten.KeyArrowDown),
		menuLeft: inpututil.IsKeyJustPressed(ebiten.KeyA) ||
			inpututil.IsKeyJustPressed(ebiten.KeyArrowLeft),
		menuRight: inpututil.IsKeyJustPressed(ebiten.KeyD) ||
			inpututil.IsKeyJustPressed(ebiten.KeyArrowRight),
		dialogueUp: inpututil.IsKeyJustPressed(ebiten.KeyW) ||
			inpututil.IsKeyJustPressed(ebiten.KeyArrowUp),
		dialogueDown: inpututil.IsKeyJustPressed(ebiten.KeyS) ||
			inpututil.IsKeyJustPressed(ebiten.KeyArrowDown),
		dialogueConfirm: inpututil.IsKeyJustPressed(ebiten.KeyEnter) ||
			inpututil.IsKeyJustPressed(ebiten.KeyE),
		dialogueCancel: inpututil.IsKeyJustPressed(ebiten.KeyEscape) ||
			inpututil.IsKeyJustPressed(ebiten.KeyBackspace),
		shopUp: inpututil.IsKeyJustPressed(ebiten.KeyW) ||
			inpututil.IsKeyJustPressed(ebiten.KeyArrowUp),
		shopDown: inpututil.IsKeyJustPressed(ebiten.KeyS) ||
			inpututil.IsKeyJustPressed(ebiten.KeyArrowDown),
		shopBuy: inpututil.IsKeyJustPressed(ebiten.KeyEnter) ||
			inpututil.IsKeyJustPressed(ebiten.KeyE),
		shopSell: inpututil.IsKeyJustPressed(ebiten.KeyQ),
		shopCancel: inpututil.IsKeyJustPressed(ebiten.KeyEscape) ||
			inpututil.IsKeyJustPressed(ebiten.KeyBackspace),
		inventoryToggle: inpututil.IsKeyJustPressed(ebiten.KeyI) ||
			inpututil.IsKeyJustPressed(ebiten.KeyTab),
		inventoryUp: inpututil.IsKeyJustPressed(ebiten.KeyW) ||
			inpututil.IsKeyJustPressed(ebiten.KeyArrowUp),
		inventoryDown: inpututil.IsKeyJustPressed(ebiten.KeyS) ||
			inpututil.IsKeyJustPressed(ebiten.KeyArrowDown),
		inventoryActivate: inpututil.IsKeyJustPressed(ebiten.KeyEnter) ||
			inpututil.IsKeyJustPressed(ebiten.KeyE),
		inventoryUnequip: inpututil.IsKeyJustPressed(ebiten.KeyQ),
		inventoryCancel: inpututil.IsKeyJustPressed(ebiten.KeyEscape) ||
			inpututil.IsKeyJustPressed(ebiten.KeyBackspace) ||
			inpututil.IsKeyJustPressed(ebiten.KeyI),
		flowUp: inpututil.IsKeyJustPressed(ebiten.KeyW) ||
			inpututil.IsKeyJustPressed(ebiten.KeyArrowUp),
		flowDown: inpututil.IsKeyJustPressed(ebiten.KeyS) ||
			inpututil.IsKeyJustPressed(ebiten.KeyArrowDown),
		flowConfirm: inpututil.IsKeyJustPressed(ebiten.KeyEnter) ||
			inpututil.IsKeyJustPressed(ebiten.KeyE),
		flowCancel: inpututil.IsKeyJustPressed(ebiten.KeyEscape) ||
			inpututil.IsKeyJustPressed(ebiten.KeyBackspace),
	}
	gamepads := ebiten.AppendGamepadIDs(nil)
	if len(gamepads) == 0 {
		return mapRawInput(raw)
	}
	gamepad := gamepads[0]
	raw.stickX = ebiten.StandardGamepadAxisValue(
		gamepad,
		ebiten.StandardGamepadAxisLeftStickHorizontal,
	)
	raw.stickY = ebiten.StandardGamepadAxisValue(
		gamepad,
		ebiten.StandardGamepadAxisLeftStickVertical,
	)
	held := func(button ebiten.StandardGamepadButton) bool {
		return ebiten.IsStandardGamepadButtonPressed(gamepad, button)
	}
	pressed := func(button ebiten.StandardGamepadButton) bool {
		return inpututil.IsStandardGamepadButtonJustPressed(gamepad, button)
	}
	raw.left = raw.left || held(ebiten.StandardGamepadButtonLeftLeft)
	raw.right = raw.right || held(ebiten.StandardGamepadButtonLeftRight)
	raw.up = raw.up || held(ebiten.StandardGamepadButtonLeftTop)
	raw.down = raw.down || held(ebiten.StandardGamepadButtonLeftBottom)
	raw.attack = raw.attack ||
		pressed(ebiten.StandardGamepadButtonRightLeft)
	raw.special = raw.special ||
		pressed(ebiten.StandardGamepadButtonRightTop)
	raw.technique = raw.technique ||
		pressed(ebiten.StandardGamepadButtonFrontTopRight)
	raw.parry = raw.parry ||
		pressed(ebiten.StandardGamepadButtonFrontTopLeft)
	raw.dodge = raw.dodge ||
		pressed(ebiten.StandardGamepadButtonRightRight)
	raw.jump = raw.jump ||
		pressed(ebiten.StandardGamepadButtonRightBottom)
	raw.interact = raw.interact ||
		pressed(ebiten.StandardGamepadButtonRightLeft)
	raw.confirm = raw.confirm ||
		pressed(ebiten.StandardGamepadButtonRightBottom)
	raw.cancel = raw.cancel ||
		pressed(ebiten.StandardGamepadButtonRightRight)
	raw.pause = raw.pause ||
		pressed(ebiten.StandardGamepadButtonCenterRight)
	raw.menuUp = raw.menuUp ||
		pressed(ebiten.StandardGamepadButtonLeftTop)
	raw.menuDown = raw.menuDown ||
		pressed(ebiten.StandardGamepadButtonLeftBottom)
	raw.menuLeft = raw.menuLeft ||
		pressed(ebiten.StandardGamepadButtonLeftLeft)
	raw.menuRight = raw.menuRight ||
		pressed(ebiten.StandardGamepadButtonLeftRight)
	raw.dialogueUp = raw.dialogueUp ||
		pressed(ebiten.StandardGamepadButtonLeftTop)
	raw.dialogueDown = raw.dialogueDown ||
		pressed(ebiten.StandardGamepadButtonLeftBottom)
	raw.dialogueConfirm = raw.dialogueConfirm ||
		pressed(ebiten.StandardGamepadButtonRightBottom)
	raw.dialogueCancel = raw.dialogueCancel ||
		pressed(ebiten.StandardGamepadButtonRightRight)
	raw.shopUp = raw.shopUp ||
		pressed(ebiten.StandardGamepadButtonLeftTop)
	raw.shopDown = raw.shopDown ||
		pressed(ebiten.StandardGamepadButtonLeftBottom)
	raw.shopBuy = raw.shopBuy ||
		pressed(ebiten.StandardGamepadButtonRightBottom)
	raw.shopSell = raw.shopSell ||
		pressed(ebiten.StandardGamepadButtonRightLeft)
	raw.shopCancel = raw.shopCancel ||
		pressed(ebiten.StandardGamepadButtonRightRight)
	raw.inventoryToggle = raw.inventoryToggle ||
		pressed(ebiten.StandardGamepadButtonCenterLeft)
	raw.inventoryUp = raw.inventoryUp ||
		pressed(ebiten.StandardGamepadButtonLeftTop)
	raw.inventoryDown = raw.inventoryDown ||
		pressed(ebiten.StandardGamepadButtonLeftBottom)
	raw.inventoryActivate = raw.inventoryActivate ||
		pressed(ebiten.StandardGamepadButtonRightBottom)
	raw.inventoryUnequip = raw.inventoryUnequip ||
		pressed(ebiten.StandardGamepadButtonRightLeft)
	raw.inventoryCancel = raw.inventoryCancel ||
		pressed(ebiten.StandardGamepadButtonRightRight)
	raw.flowUp = raw.flowUp ||
		pressed(ebiten.StandardGamepadButtonLeftTop)
	raw.flowDown = raw.flowDown ||
		pressed(ebiten.StandardGamepadButtonLeftBottom)
	raw.flowConfirm = raw.flowConfirm ||
		pressed(ebiten.StandardGamepadButtonRightBottom)
	raw.flowCancel = raw.flowCancel ||
		pressed(ebiten.StandardGamepadButtonRightRight)
	return mapRawInput(raw)
}
