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

// ImageResourceProvider is the optional immutable resource manifest exposed by
// a production model. Paths are resolved by the platform adapter's packaged
// asset filesystem, never by the process working directory.
type ImageResourceProvider interface {
	ImageResources() []ImageResource
}

// SpriteResourceProvider optionally supplies authored animation resources.
// Definitions are immutable copies and refer to ImageResource IDs.
type SpriteResourceProvider interface {
	SpriteResources() []SpriteResource
}

type AudioResourceProvider interface {
	AudioResources() AudioResourceManifest
}

type ImageResource struct {
	ID     string
	Path   string
	Width  int
	Height int
	Filter string
}

type SpriteResource struct {
	ID          string
	AssetID     string
	FrameWidth  int
	FrameHeight int
	OriginX     float64
	OriginY     float64
	Scale       float64
	Tint        color.RGBA
	TintSet     bool
	DefaultClip string
	Clips       []SpriteClipResource
	StateMap    []SpriteStateResource
}

type SpriteClipResource struct {
	ID     string
	FPS    float64
	Loop   bool
	Frames []SpriteFrameResource
}

type SpriteFrameResource struct {
	Column int
	Row    int
}

type SpriteStateResource struct {
	State string
	Clip  string
}

type AudioResourceManifest struct {
	MasterVolume float64
	MusicVolume  float64
	SFXVolume    float64
	Assets       []AudioResource
}

type AudioResource struct {
	ID   string
	Path string
}

// View is an immutable render snapshot produced after a simulation tick.
type View struct {
	Tick             uint64
	Revision         uint64
	AutomationPaused bool
	Quit             bool

	Camera  CameraView
	World   WorldView
	Tilemap *TilemapView

	Entities  []EntityView
	Walls     []RectView
	Effects   []EffectView
	Audio     AudioView
	Flow      FlowView
	Dialogue  DialogueView
	Shop      ShopView
	Inventory InventoryView
	HUD       HUDView
}

type CameraView struct {
	X      float64
	Y      float64
	ShakeX float64
	ShakeY float64
	Zoom   float64
}

type WorldView struct {
	Width      float64
	Height     float64
	Stage      string
	Background color.RGBA
}

type TilemapView struct {
	Source     string
	TileWidth  int
	TileHeight int
	Tilesets   []TilesetView
	Layers     []TileLayerView
}

type TilesetView struct {
	ID         string
	AssetID    string
	FirstGID   uint32
	TileCount  int
	Columns    int
	TileWidth  int
	TileHeight int
}

type TileLayerView struct {
	ID      string
	Name    string
	Width   int
	Height  int
	Visible bool
	Opacity float64
	OffsetX float64
	OffsetY float64
	Data    []uint32
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
	ID            string
	SpriteID      string
	State         string
	AnimationTick uint64
	SpriteScale   float64
	SpriteTint    color.RGBA
	SpriteTintSet bool

	X       float64
	Y       float64
	Radius  float64
	Width   float64
	Height  float64
	Shape   string
	FacingX float64
	FacingY float64
	Layer   int

	Health    float64
	MaxHealth float64
	Flash     bool
	Tint      color.RGBA
	Outline   color.RGBA
}

type EffectView struct {
	Kind     string
	AssetID  string
	X        float64
	Y        float64
	Rotation float64
	Scale    float64
	Opacity  float64
}

type AudioView struct {
	MusicAssetID string
	MusicVolume  float64
	Cues         []AudioCueView
}

type AudioCueView struct {
	Sequence uint64
	Event    string
	AssetID  string
	Volume   float64
}

// DialogueView is presentation-neutral modal dialogue state. Choices contains
// only currently eligible entries and retains authored order. SelectedIndex is
// interpreted defensively by the adapter, so a stale index cannot panic Draw.
type DialogueView struct {
	Active        bool
	Speaker       string
	Text          string
	Choices       []DialogueChoiceView
	SelectedIndex int
}

// DialogueChoiceView identifies one eligible authored choice.
type DialogueChoiceView struct {
	ID   string
	Text string
}

// ShopView is presentation-neutral modal shop state. Offers retains authored
// order. Affordability, stock, equipment, and all other domain rules are
// resolved by the model into CanBuy and CanSell before reaching the adapter.
type ShopView struct {
	Active        bool
	Name          string
	Currency      int64
	Offers        []ShopOfferView
	SelectedIndex int
	Status        string
}

// ShopOfferView is one authored offer with its current presentation facts.
type ShopOfferView struct {
	ID        string
	Name      string
	Owned     int64
	CanBuy    bool
	BuyPrice  int64
	CanSell   bool
	SellPrice int64
}

// InventoryView is presentation-neutral inventory modal state. The model owns
// selection changes and decides whether InventoryActivate uses a consumable or
// equips an item. The adapter only renders these resolved presentation facts
// and forwards generic inventory intent.
type InventoryView struct {
	Active        bool
	Title         string
	Items         []InventoryItemView
	SelectedIndex int
	Status        string
}

// InventoryItemView is one owned inventory entry. CanUse and CanEquip are
// model-resolved facts for presentation; they do not move gameplay rules into
// the Ebitengine adapter.
type InventoryItemView struct {
	ID            string
	Name          string
	Description   string
	Quantity      int64
	Consumable    bool
	EquipmentSlot string
	Equipped      bool
	CanUse        bool
	CanEquip      bool
}

// FlowView is presentation-neutral state for title, pause, game-over, ending,
// and other authored flow menus. Mode selects visual treatment; behavior stays
// in the model.
type FlowView struct {
	Mode          string
	Active        bool
	Heading       string
	Message       string
	Options       []FlowOptionView
	SelectedIndex int
}

// FlowOptionView is one authored flow action. Disabled options remain visible
// but cannot become the adapter's effective selection.
type FlowOptionView struct {
	ID      string
	Label   string
	Enabled bool
}

type HUDView struct {
	Title    string
	Status   string
	Help     string
	Dialogue string
	Quest    string
	Currency int64
}
