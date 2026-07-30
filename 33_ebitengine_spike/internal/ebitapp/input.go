package ebitapp

import (
	"fmt"
	"math"
	"strings"

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

type inputBinding struct {
	keys    []ebiten.Key
	buttons []ebiten.StandardGamepadButton
}

type inputBindings map[string]inputBinding

func newInputBindings(resources []InputActionResource) (inputBindings, error) {
	if len(resources) == 0 {
		resources = defaultInputResources()
	}
	result := make(inputBindings, len(resources))
	for _, resource := range resources {
		if strings.TrimSpace(resource.Action) == "" {
			return nil, fmt.Errorf("input action name is empty")
		}
		if _, exists := result[resource.Action]; exists {
			return nil, fmt.Errorf(
				"duplicate input action %q",
				resource.Action,
			)
		}
		binding := inputBinding{
			keys: make([]ebiten.Key, 0, len(resource.Keys)),
			buttons: make(
				[]ebiten.StandardGamepadButton,
				0,
				len(resource.Buttons),
			),
		}
		for _, name := range resource.Keys {
			key, err := loveKey(name)
			if err != nil {
				return nil, fmt.Errorf(
					"input action %q: %w",
					resource.Action,
					err,
				)
			}
			binding.keys = append(binding.keys, key)
		}
		for _, name := range resource.Buttons {
			button, err := loveGamepadButton(name)
			if err != nil {
				return nil, fmt.Errorf(
					"input action %q: %w",
					resource.Action,
					err,
				)
			}
			binding.buttons = append(binding.buttons, button)
		}
		result[resource.Action] = binding
	}
	return result, nil
}

func loveKey(name string) (ebiten.Key, error) {
	normalized := strings.ToLower(strings.TrimSpace(name))
	aliases := map[string]string{
		"`":      "backquote",
		"\\":     "backslash",
		"'":      "quote",
		",":      "comma",
		"-":      "minus",
		".":      "period",
		"/":      "slash",
		";":      "semicolon",
		"=":      "equal",
		"[":      "bracketleft",
		"]":      "bracketright",
		"lalt":   "altleft",
		"lctrl":  "controlleft",
		"lgui":   "metaleft",
		"lshift": "shiftleft",
		"kp+":    "kpadd",
		"kp.":    "kpdecimal",
		"kp/":    "kpdivide",
		"kp=":    "kpequal",
		"kp*":    "kpmultiply",
		"kp-":    "kpsubtract",
		"ralt":   "altright",
		"rctrl":  "controlright",
		"return": "enter",
		"rgui":   "metaright",
		"rshift": "shiftright",
	}
	if alias, exists := aliases[normalized]; exists {
		normalized = alias
	}
	var key ebiten.Key
	if err := key.UnmarshalText([]byte(normalized)); err != nil {
		return 0, fmt.Errorf("unsupported LÖVE key %q", name)
	}
	return key, nil
}

func loveGamepadButton(
	name string,
) (ebiten.StandardGamepadButton, error) {
	switch strings.ToLower(strings.TrimSpace(name)) {
	case "a":
		return ebiten.StandardGamepadButtonRightBottom, nil
	case "b":
		return ebiten.StandardGamepadButtonRightRight, nil
	case "x":
		return ebiten.StandardGamepadButtonRightLeft, nil
	case "y":
		return ebiten.StandardGamepadButtonRightTop, nil
	case "back":
		return ebiten.StandardGamepadButtonCenterLeft, nil
	case "guide":
		return ebiten.StandardGamepadButtonCenterCenter, nil
	case "start":
		return ebiten.StandardGamepadButtonCenterRight, nil
	case "leftstick":
		return ebiten.StandardGamepadButtonLeftStick, nil
	case "rightstick":
		return ebiten.StandardGamepadButtonRightStick, nil
	case "leftshoulder":
		return ebiten.StandardGamepadButtonFrontTopLeft, nil
	case "rightshoulder":
		return ebiten.StandardGamepadButtonFrontTopRight, nil
	case "dpup":
		return ebiten.StandardGamepadButtonLeftTop, nil
	case "dpdown":
		return ebiten.StandardGamepadButtonLeftBottom, nil
	case "dpleft":
		return ebiten.StandardGamepadButtonLeftLeft, nil
	case "dpright":
		return ebiten.StandardGamepadButtonLeftRight, nil
	default:
		return 0, fmt.Errorf("unsupported LÖVE gamepad button %q", name)
	}
}

func defaultInputResources() []InputActionResource {
	return []InputActionResource{
		{Action: "move_up", Keys: []string{"w", "up"}, Buttons: []string{"dpup"}},
		{Action: "move_down", Keys: []string{"s", "down"}, Buttons: []string{"dpdown"}},
		{Action: "move_left", Keys: []string{"a", "left"}, Buttons: []string{"dpleft"}},
		{Action: "move_right", Keys: []string{"d", "right"}, Buttons: []string{"dpright"}},
		{Action: "attack", Keys: []string{"space", "z"}, Buttons: []string{"x"}},
		{Action: "special", Keys: []string{"f", "v"}, Buttons: []string{"y"}},
		{Action: "technique", Keys: []string{"q"}, Buttons: []string{"rightshoulder"}},
		{Action: "jump", Keys: []string{"w", "up"}, Buttons: []string{"a"}},
		{Action: "parry", Keys: []string{"c", "lctrl", "rctrl"}, Buttons: []string{"leftshoulder"}},
		{Action: "dodge", Keys: []string{"lshift", "rshift", "x"}, Buttons: []string{"b"}},
		{Action: "interact", Keys: []string{"e"}, Buttons: []string{"x"}},
		{Action: "menu_up", Keys: []string{"w", "up"}, Buttons: []string{"dpup"}},
		{Action: "menu_down", Keys: []string{"s", "down"}, Buttons: []string{"dpdown"}},
		{Action: "menu_left", Keys: []string{"a", "left"}, Buttons: []string{"dpleft"}},
		{Action: "menu_right", Keys: []string{"d", "right"}, Buttons: []string{"dpright"}},
		{Action: "menu_confirm", Keys: []string{"return", "space"}, Buttons: []string{"a"}},
		{Action: "menu_cancel", Keys: []string{"escape", "backspace"}, Buttons: []string{"b"}},
		{Action: "pause", Keys: []string{"escape", "p"}, Buttons: []string{"start"}},
		{Action: "restart", Keys: []string{"r"}, Buttons: []string{"back"}},
	}
}

func (bindings inputBindings) keyHeld(
	action string,
	read func(ebiten.Key) bool,
) bool {
	for _, key := range bindings[action].keys {
		if read(key) {
			return true
		}
	}
	return false
}

func (bindings inputBindings) keyPressed(
	action string,
	read func(ebiten.Key) bool,
) bool {
	return bindings.keyHeld(action, read)
}

func (bindings inputBindings) buttonHeld(
	action string,
	read func(ebiten.StandardGamepadButton) bool,
) bool {
	for _, button := range bindings[action].buttons {
		if read(button) {
			return true
		}
	}
	return false
}

func (bindings inputBindings) buttonPressed(
	action string,
	read func(ebiten.StandardGamepadButton) bool,
) bool {
	return bindings.buttonHeld(action, read)
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
// of shared gameplay and menu keys. Flow precedes cutscene, turn battle,
// dialogue, shop, then inventory. Enter, Space, Q, Escape, I, and the
// directional keys intentionally map to more than one semantic action in
// PollActions; this routing step prevents one physical edge from triggering
// multiple layers.
func actionsForView(actions Actions, view View) Actions {
	if view.Flow.Active {
		return flowActions(actions, view.Flow)
	}
	if view.Cutscene.Active {
		return cutsceneActions(actions)
	}
	if view.TurnBattle.Active {
		return turnBattleActions(actions)
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

func cutsceneActions(actions Actions) Actions {
	result := Actions{}
	switch {
	case actions.MenuCancel:
		result.MenuCancel = true
	case actions.MenuConfirm:
		result.MenuConfirm = true
	}
	return result
}

func turnBattleActions(actions Actions) Actions {
	result := Actions{Pause: actions.Pause}
	switch {
	case actions.MenuCancel:
		result.MenuCancel = true
	case actions.MenuConfirm:
		result.MenuConfirm = true
	case actions.MenuUp != actions.MenuDown:
		result.MenuUp = actions.MenuUp
		result.MenuDown = actions.MenuDown
	}
	return result
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

// PollActions reads keyboard and the first standard-layout gamepad using the
// legacy defaults. Production Game instances use their project manifest.
func PollActions() Actions {
	bindings, err := newInputBindings(nil)
	if err != nil {
		panic(err)
	}
	return pollActions(bindings)
}

func pollActions(bindings inputBindings) Actions {
	keyHeld := func(action string) bool {
		return bindings.keyHeld(action, ebiten.IsKeyPressed)
	}
	keyPressed := func(action string) bool {
		return bindings.keyPressed(action, inpututil.IsKeyJustPressed)
	}
	raw := rawInput{
		left:  keyHeld("move_left"),
		right: keyHeld("move_right"),
		up:    keyHeld("move_up"),
		down:  keyHeld("move_down"),

		attack:          keyPressed("attack"),
		special:         keyPressed("special"),
		technique:       keyPressed("technique"),
		parry:           keyPressed("parry"),
		dodge:           keyPressed("dodge"),
		jump:            keyPressed("jump"),
		interact:        keyPressed("interact"),
		confirm:         keyPressed("menu_confirm"),
		cancel:          keyPressed("menu_cancel"),
		pause:           keyPressed("pause"),
		restart:         keyPressed("restart"),
		menuUp:          keyPressed("menu_up"),
		menuDown:        keyPressed("menu_down"),
		menuLeft:        keyPressed("menu_left"),
		menuRight:       keyPressed("menu_right"),
		dialogueUp:      keyPressed("menu_up"),
		dialogueDown:    keyPressed("menu_down"),
		dialogueConfirm: keyPressed("menu_confirm"),
		dialogueCancel:  keyPressed("menu_cancel"),
		shopUp:          keyPressed("menu_up"),
		shopDown:        keyPressed("menu_down"),
		shopBuy:         keyPressed("menu_confirm"),
		shopSell:        inpututil.IsKeyJustPressed(ebiten.KeyQ),
		shopCancel:      keyPressed("menu_cancel"),
		inventoryToggle: inpututil.IsKeyJustPressed(ebiten.KeyI) ||
			inpututil.IsKeyJustPressed(ebiten.KeyTab),
		inventoryUp:       keyPressed("menu_up"),
		inventoryDown:     keyPressed("menu_down"),
		inventoryActivate: keyPressed("menu_confirm"),
		inventoryUnequip:  inpututil.IsKeyJustPressed(ebiten.KeyQ),
		inventoryCancel: keyPressed("menu_cancel") ||
			inpututil.IsKeyJustPressed(ebiten.KeyI),
		flowUp:      keyPressed("menu_up"),
		flowDown:    keyPressed("menu_down"),
		flowConfirm: keyPressed("menu_confirm"),
		flowCancel:  keyPressed("menu_cancel"),
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
	buttonHeld := func(action string) bool {
		return bindings.buttonHeld(action, held)
	}
	buttonPressed := func(action string) bool {
		return bindings.buttonPressed(action, pressed)
	}
	raw.left = raw.left || buttonHeld("move_left")
	raw.right = raw.right || buttonHeld("move_right")
	raw.up = raw.up || buttonHeld("move_up")
	raw.down = raw.down || buttonHeld("move_down")
	raw.attack = raw.attack || buttonPressed("attack")
	raw.special = raw.special || buttonPressed("special")
	raw.technique = raw.technique || buttonPressed("technique")
	raw.parry = raw.parry || buttonPressed("parry")
	raw.dodge = raw.dodge || buttonPressed("dodge")
	raw.jump = raw.jump || buttonPressed("jump")
	raw.interact = raw.interact || buttonPressed("interact")
	raw.confirm = raw.confirm || buttonPressed("menu_confirm")
	raw.cancel = raw.cancel || buttonPressed("menu_cancel")
	raw.pause = raw.pause || buttonPressed("pause")
	raw.restart = raw.restart || buttonPressed("restart")
	raw.menuUp = raw.menuUp || buttonPressed("menu_up")
	raw.menuDown = raw.menuDown || buttonPressed("menu_down")
	raw.menuLeft = raw.menuLeft || buttonPressed("menu_left")
	raw.menuRight = raw.menuRight || buttonPressed("menu_right")
	raw.dialogueUp = raw.dialogueUp || buttonPressed("menu_up")
	raw.dialogueDown = raw.dialogueDown || buttonPressed("menu_down")
	raw.dialogueConfirm = raw.dialogueConfirm ||
		buttonPressed("menu_confirm")
	raw.dialogueCancel = raw.dialogueCancel ||
		buttonPressed("menu_cancel")
	raw.shopUp = raw.shopUp || buttonPressed("menu_up")
	raw.shopDown = raw.shopDown || buttonPressed("menu_down")
	raw.shopBuy = raw.shopBuy || buttonPressed("menu_confirm")
	raw.shopSell = raw.shopSell ||
		pressed(ebiten.StandardGamepadButtonRightLeft)
	raw.shopCancel = raw.shopCancel || buttonPressed("menu_cancel")
	raw.inventoryToggle = raw.inventoryToggle ||
		pressed(ebiten.StandardGamepadButtonCenterLeft)
	raw.inventoryUp = raw.inventoryUp || buttonPressed("menu_up")
	raw.inventoryDown = raw.inventoryDown || buttonPressed("menu_down")
	raw.inventoryActivate = raw.inventoryActivate ||
		buttonPressed("menu_confirm")
	raw.inventoryUnequip = raw.inventoryUnequip ||
		pressed(ebiten.StandardGamepadButtonRightLeft)
	raw.inventoryCancel = raw.inventoryCancel ||
		buttonPressed("menu_cancel")
	raw.flowUp = raw.flowUp || buttonPressed("menu_up")
	raw.flowDown = raw.flowDown || buttonPressed("menu_down")
	raw.flowConfirm = raw.flowConfirm || buttonPressed("menu_confirm")
	raw.flowCancel = raw.flowCancel || buttonPressed("menu_cancel")
	return mapRawInput(raw)
}
