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
// not restart an attack or dialogue choice on every tick.
type Actions struct {
	MoveX float64
	MoveY float64

	Attack    bool
	Special   bool
	Technique bool
	Parry     bool
	Dodge     bool
	Interact  bool

	MenuUp      bool
	MenuDown    bool
	MenuLeft    bool
	MenuRight   bool
	MenuConfirm bool
	MenuCancel  bool
	Pause       bool
	Restart     bool
}

type rawInput struct {
	left, right, up, down bool
	stickX, stickY        float64

	attack, special, technique bool
	parry, dodge, interact     bool
	confirm, cancel, pause     bool
	restart                    bool
	menuUp, menuDown           bool
	menuLeft, menuRight        bool
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
		Interact:  raw.interact,

		MenuUp:      raw.menuUp,
		MenuDown:    raw.menuDown,
		MenuLeft:    raw.menuLeft,
		MenuRight:   raw.menuRight,
		MenuConfirm: raw.confirm,
		MenuCancel:  raw.cancel,
		Pause:       raw.pause,
		Restart:     raw.restart,
	}
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
	return mapRawInput(raw)
}
