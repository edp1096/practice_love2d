package ebitapp

import "image/color"

const (
	ScreenWidth  = 960
	ScreenHeight = 540
)

// Model is the only dependency the Ebitengine adapter has on gameplay.
// Implementations must return copies from View so Draw cannot mutate state.
type Model interface {
	Tick(Actions) error
	View() View
}

// View is an immutable render snapshot produced after a simulation tick.
type View struct {
	Tick             uint64
	Revision         uint64
	AutomationPaused bool
	Quit             bool

	Camera CameraView
	World  WorldView

	Entities []EntityView
	Walls    []RectView
	Effects  []EffectView
	HUD      HUDView
}

type CameraView struct {
	X      float64
	Y      float64
	ShakeX float64
	ShakeY float64
	Zoom   float64
}

type WorldView struct {
	Width  float64
	Height float64
	Stage  string
}

type RectView struct {
	X      float64
	Y      float64
	Width  float64
	Height float64
	Color  color.RGBA
	Points []PointView
}

type PointView struct {
	X float64
	Y float64
}

type EntityView struct {
	ID       string
	SpriteID string
	State    string

	X       float64
	Y       float64
	Radius  float64
	FacingX float64
	FacingY float64
	Layer   int

	Health    float64
	MaxHealth float64
	Flash     bool
	Tint      color.RGBA
}

type EffectView struct {
	Kind     string
	X        float64
	Y        float64
	Rotation float64
	Scale    float64
	Opacity  float64
}

type HUDView struct {
	Title    string
	Status   string
	Help     string
	Dialogue string
	Quest    string
	Currency int
}
