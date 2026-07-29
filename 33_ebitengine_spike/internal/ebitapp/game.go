package ebitapp

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"math"
	"os"
	"path"
	"sort"
	"strings"
	"unicode"
	"unicode/utf8"

	gameassets "practice_love2d/33_ebitengine_spike/assets"

	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/text/v2"
	"github.com/hajimehoshi/ebiten/v2/vector"
)

type captureResult struct {
	capture Capture
	err     error
}

type captureRequest struct {
	result chan captureResult
}

const (
	dialogueBoxX      = 48
	dialogueBoxY      = 330
	dialogueBoxWidth  = ScreenWidth - dialogueBoxX*2
	dialogueBoxHeight = 190

	maxDialogueBodyRunes      = 46
	maxDialogueBodyLines      = 2
	maxDialogueChoiceRunes    = 48
	maxDialogueSpeakerRunes   = 40
	maxVisibleDialogueChoices = 3

	dialogueContinueHelp = "Enter / E  계속    Esc  닫기"
	dialogueChoiceHelp   = "↑ / ↓  선택    Enter / E  확인    Esc  취소"

	shopPanelX      = 48
	shopPanelY      = 330
	shopPanelWidth  = ScreenWidth - shopPanelX*2
	shopPanelHeight = 190

	maxShopNameRunes      = 24
	maxShopOfferNameRunes = 22
	maxShopStatusRunes    = 62
	maxVisibleShopOffers  = 3
	shopActionHelp        = "↑ / ↓  선택    Enter / E  구매    Q  판매    Esc  닫기"
	shopEmptyHelp         = "Esc  닫기"
	shopEmptyMessage      = "판매 중인 상품이 없습니다."
	shopFallbackName      = "상점"
	shopFallbackOfferName = "이름 없는 상품"
	shopOfferColumnLabel  = "상품"
	shopOwnedColumnLabel  = "보유"
	shopBuyColumnLabel    = "구매"
	shopSellColumnLabel   = "판매"
	shopCurrencyLabel     = "재화"

	inventoryPanelX      = 72
	inventoryPanelY      = 126
	inventoryPanelWidth  = ScreenWidth - inventoryPanelX*2
	inventoryPanelHeight = 354

	maxInventoryTitleRunes       = 28
	maxInventoryItemNameRunes    = 17
	maxInventoryDescriptionRunes = 20
	maxInventoryDescriptionLines = 4
	maxInventoryStatusRunes      = 50
	maxInventoryStatusLines      = 2
	maxInventorySlotRunes        = 16
	maxVisibleInventoryItems     = 6

	inventoryActionHelp        = "↑ / ↓  선택    Enter / E  사용·장착    Q  해제    Esc / I  닫기"
	inventoryEmptyHelp         = "Esc / I  닫기"
	inventoryFallbackTitle     = "소지품"
	inventoryFallbackItemName  = "이름 없는 아이템"
	inventoryEmptyDescription  = "설명이 없습니다."
	inventoryEmptyMessage      = "보유한 아이템이 없습니다."
	inventoryNameColumnLabel   = "아이템"
	inventoryEquippedLabel     = "장착"
	inventoryQuantityLabel     = "보유"
	inventoryStatusLabel       = "상태"
	inventoryConsumableLabel   = "소모품"
	inventoryEquipmentLabel    = "장비"
	inventoryEquippedIndicator = "[장착]"

	flowPanelX      = 180
	flowPanelY      = 78
	flowPanelWidth  = ScreenWidth - flowPanelX*2
	flowPanelHeight = ScreenHeight - flowPanelY*2

	maxFlowHeadingRunes   = 20
	maxFlowMessageRunes   = 32
	maxFlowMessageLines   = 4
	maxFlowOptionRunes    = 26
	maxVisibleFlowOptions = 5

	flowActionHelp        = "↑ / ↓  선택    Enter / E  확인    Esc  뒤로"
	flowBackHelp          = "Esc  뒤로"
	flowFallbackOption    = "이름 없는 항목"
	flowFallbackHeading   = "메뉴"
	flowTitleHeading      = "RECREATE"
	flowPauseHeading      = "일시 정지"
	flowGameOverHeading   = "게임 오버"
	flowEndingHeading     = "끝"
	flowDisabledIndicator = " · 사용 불가"
)

type dialogueChoiceLayout struct {
	Index    int
	ID       string
	Text     string
	Selected bool
}

type dialogueLayout struct {
	BodyLines  []string
	Choices    []dialogueChoiceLayout
	Selected   int
	HasEarlier bool
	HasLater   bool
}

type shopOfferLayout struct {
	Index           int
	ID              string
	Name            string
	ModifierSummary string
	Owned           int64
	CanBuy          bool
	BuyPrice        int64
	CanSell         bool
	SellPrice       int64
	Selected        bool
}

type shopLayout struct {
	Name       string
	Status     string
	Offers     []shopOfferLayout
	Selected   int
	HasEarlier bool
	HasLater   bool
}

type inventoryItemLayout struct {
	Index           int
	ID              string
	Name            string
	Description     []string
	ModifierSummary string
	Quantity        int64
	Consumable      bool
	EquipmentSlot   string
	Equipped        bool
	CanUse          bool
	CanEquip        bool
	Selected        bool
}

type inventoryLayout struct {
	Title      string
	Status     []string
	Items      []inventoryItemLayout
	Detail     inventoryItemLayout
	HasDetail  bool
	Selected   int
	HasEarlier bool
	HasLater   bool
}

type flowOptionLayout struct {
	Index    int
	ID       string
	Label    string
	Enabled  bool
	Selected bool
}

type flowLayout struct {
	Mode       string
	Heading    string
	Message    []string
	Options    []flowOptionLayout
	Selected   int
	HasEarlier bool
	HasLater   bool
}

// Capture is one completely rendered logical frame.
type Capture struct {
	PNG      []byte
	Tick     uint64
	Revision uint64
}

// Options controls deterministic desktop automation. Console builds leave this
// zero-valued and use the debug protocol instead.
type Options struct {
	StopAfterTicks   uint64
	StopAfterUpdates uint64
	ScreenshotPath   string
}

// Game adapts a pure fixed-tick Model to Ebitengine.
type Game struct {
	model Model

	canvas  *ebiten.Image
	images  map[string]*ebiten.Image
	filters map[string]ebiten.Filter
	sprites map[string]loadedSprite
	audio   *audioManager
	font    *text.GoTextFaceSource
	capture chan captureRequest

	options      Options
	updates      uint64
	autoCaptured bool
	autoError    error
}

// New constructs all immutable presentation resources before the main loop.
func New(model Model) (*Game, error) {
	return NewWithOptions(model, Options{})
}

// NewWithOptions constructs a game with optional deterministic automation.
func NewWithOptions(model Model, options Options) (*Game, error) {
	if model == nil {
		return nil, errors.New("ebitapp model is required")
	}
	if options.StopAfterTicks > 0 && options.StopAfterUpdates > 0 {
		return nil, errors.New(
			"stop tick and stop update limits are mutually exclusive",
		)
	}
	if options.ScreenshotPath != "" &&
		options.StopAfterTicks == 0 &&
		options.StopAfterUpdates == 0 {
		return nil, errors.New(
			"a screenshot path requires a non-zero stop limit",
		)
	}
	resources := defaultImageResources()
	if provider, ok := model.(ImageResourceProvider); ok {
		resources = provider.ImageResources()
	}
	images, filters, err := loadImageResources(resources)
	if err != nil {
		return nil, err
	}
	var spriteResources []SpriteResource
	if provider, ok := model.(SpriteResourceProvider); ok {
		spriteResources = provider.SpriteResources()
	}
	sprites, err := loadSpriteResources(spriteResources, images)
	if err != nil {
		return nil, err
	}
	var audioResources AudioResourceManifest
	if provider, ok := model.(AudioResourceProvider); ok {
		audioResources = provider.AudioResources()
	}
	audioManager, err := newAudioManager(audioResources)
	if err != nil {
		return nil, err
	}
	fontData, err := gameassets.ReadFile(
		"fonts/Hakgyoansim_ChaekgalpiR.ttf",
	)
	if err != nil {
		return nil, err
	}
	font, err := text.NewGoTextFaceSource(bytes.NewReader(fontData))
	if err != nil {
		return nil, fmt.Errorf("parse UI font: %w", err)
	}
	return &Game{
		model:   model,
		canvas:  ebiten.NewImage(ScreenWidth, ScreenHeight),
		images:  images,
		filters: filters,
		sprites: sprites,
		audio:   audioManager,
		font:    font,
		capture: make(chan captureRequest, 8),
		options: options,
	}, nil
}

func defaultImageResources() []ImageResource {
	return []ImageResource{
		{
			ID:     "image.guide_sheet",
			Path:   "assets/runtime/images/npcs/guide-sheet.png",
			Width:  384,
			Height: 96,
			Filter: "nearest",
		},
		{
			ID:     "image.merchant_sheet",
			Path:   "assets/runtime/images/npcs/merchant-sheet.png",
			Width:  384,
			Height: 96,
			Filter: "nearest",
		},
		{
			ID:     "image.player_sheet",
			Path:   "assets/runtime/images/player/player-sheet.png",
			Width:  384,
			Height: 960,
			Filter: "nearest",
		},
		{
			ID:     "image.slash",
			Path:   "assets/runtime/images/effects/slash.png",
			Width:  46,
			Height: 39,
			Filter: "nearest",
		},
		{
			ID:     "image.slime_red_sheet",
			Path:   "assets/runtime/images/enemies/slime-red-sheet.png",
			Width:  176,
			Height: 64,
			Filter: "nearest",
		},
		{
			ID:     "image.world_tileset",
			Path:   "assets/runtime/images/tilesets/tileset_area1.png",
			Width:  864,
			Height: 576,
			Filter: "nearest",
		},
	}
}

func loadImageResources(
	resources []ImageResource,
) (map[string]*ebiten.Image, map[string]ebiten.Filter, error) {
	images := make(map[string]*ebiten.Image, len(resources))
	filters := make(map[string]ebiten.Filter, len(resources))
	for index, resource := range resources {
		if resource.ID == "" {
			return nil, nil, fmt.Errorf("image resource %d has an empty ID", index)
		}
		if _, duplicate := images[resource.ID]; duplicate {
			return nil, nil, fmt.Errorf(
				"image resource %q is duplicated",
				resource.ID,
			)
		}
		relative, err := packagedAssetPath(resource.Path)
		if err != nil {
			return nil, nil, fmt.Errorf(
				"image resource %q: %w",
				resource.ID,
				err,
			)
		}
		data, err := gameassets.ReadFile(relative)
		if err != nil {
			return nil, nil, fmt.Errorf("load %s: %w", resource.ID, err)
		}
		decoded, err := png.Decode(bytes.NewReader(data))
		if err != nil {
			return nil, nil, fmt.Errorf("decode %s: %w", resource.ID, err)
		}
		bounds := decoded.Bounds()
		if bounds.Dx() != resource.Width ||
			bounds.Dy() != resource.Height {
			return nil, nil, fmt.Errorf(
				"image resource %q is %dx%d, manifest requires %dx%d",
				resource.ID,
				bounds.Dx(),
				bounds.Dy(),
				resource.Width,
				resource.Height,
			)
		}
		filter, err := imageFilter(resource.Filter)
		if err != nil {
			return nil, nil, fmt.Errorf(
				"image resource %q: %w",
				resource.ID,
				err,
			)
		}
		images[resource.ID] = ebiten.NewImageFromImage(decoded)
		filters[resource.ID] = filter
	}
	return images, filters, nil
}

func packagedAssetPath(authored string) (string, error) {
	const prefix = "assets/runtime/"
	if authored == "" ||
		strings.Contains(authored, "\\") ||
		path.Clean(authored) != authored ||
		!strings.HasPrefix(authored, prefix) {
		return "", fmt.Errorf(
			"path %q must be a clean project-relative path below %s",
			authored,
			prefix,
		)
	}
	relative := strings.TrimPrefix(authored, prefix)
	if relative == "" || relative == "." {
		return "", fmt.Errorf("path %q does not name a file", authored)
	}
	return relative, nil
}

func imageFilter(value string) (ebiten.Filter, error) {
	switch value {
	case "", "nearest":
		return ebiten.FilterNearest, nil
	case "linear":
		return ebiten.FilterLinear, nil
	default:
		return 0, fmt.Errorf("unsupported filter %q", value)
	}
}

func (game *Game) Update() error {
	if game.autoError != nil {
		return game.autoError
	}
	view := game.model.View()
	if err := game.audio.Sync(view.Audio); err != nil {
		return err
	}
	if game.automaticLimitReached(view) {
		if game.options.ScreenshotPath == "" || game.autoCaptured {
			return ebiten.Termination
		}
		return nil
	}
	if err := game.model.Tick(actionsForView(PollActions(), view)); err != nil {
		return err
	}
	game.updates++
	updated := game.model.View()
	if err := game.audio.Sync(updated.Audio); err != nil {
		return err
	}
	if updated.Quit {
		return ebiten.Termination
	}
	return nil
}

func (game *Game) automaticLimitReached(view View) bool {
	if game.options.StopAfterTicks > 0 {
		return view.Tick >= game.options.StopAfterTicks
	}
	return game.options.StopAfterUpdates > 0 &&
		game.updates >= game.options.StopAfterUpdates
}

func (game *Game) Draw(screen *ebiten.Image) {
	captures := game.beginCaptures()
	view := game.model.View()
	game.drawView(view)
	screen.DrawImage(game.canvas, nil)
	game.finishAutomaticCapture(view)
	game.finishCaptures(captures, view)
}

func (game *Game) Layout(_, _ int) (int, int) {
	return ScreenWidth, ScreenHeight
}

// CapturePNG requests the last fully rendered logical screen. Pixel readback is
// performed by Draw on Ebitengine's main-loop goroutine.
func (game *Game) CapturePNG(ctx context.Context) (Capture, error) {
	request := captureRequest{result: make(chan captureResult, 1)}
	select {
	case game.capture <- request:
	case <-ctx.Done():
		return Capture{}, ctx.Err()
	}
	select {
	case result := <-request.result:
		return result.capture, result.err
	case <-ctx.Done():
		return Capture{}, ctx.Err()
	}
}

func (game *Game) beginCaptures() []captureRequest {
	var requests []captureRequest
	for {
		select {
		case request := <-game.capture:
			requests = append(requests, request)
		default:
			return requests
		}
	}
}

func (game *Game) finishCaptures(
	requests []captureRequest,
	view View,
) {
	if len(requests) == 0 {
		return
	}
	data, err := game.encodeCanvas()
	for _, request := range requests {
		request.result <- captureResult{
			capture: Capture{
				PNG:      data,
				Tick:     view.Tick,
				Revision: view.Revision,
			},
			err: err,
		}
	}
}

func (game *Game) finishAutomaticCapture(view View) {
	if game.autoCaptured ||
		game.options.ScreenshotPath == "" ||
		!game.automaticLimitReached(view) {
		return
	}
	data, err := game.encodeCanvas()
	if err == nil {
		err = os.WriteFile(game.options.ScreenshotPath, data, 0o644)
	}
	if err != nil {
		game.autoError = fmt.Errorf("automatic screenshot: %w", err)
		return
	}
	game.autoCaptured = true
}

func (game *Game) encodeCanvas() ([]byte, error) {
	pixels := make(
		[]byte,
		4*game.canvas.Bounds().Dx()*game.canvas.Bounds().Dy(),
	)
	game.canvas.ReadPixels(pixels)
	source := &image.RGBA{
		Pix:    pixels,
		Stride: 4 * ScreenWidth,
		Rect:   image.Rect(0, 0, ScreenWidth, ScreenHeight),
	}
	var encoded bytes.Buffer
	if err := png.Encode(&encoded, source); err != nil {
		return nil, err
	}
	return encoded.Bytes(), nil
}

func (game *Game) drawView(view View) {
	background := view.World.Background
	if background.A == 0 {
		background = color.RGBA{R: 16, G: 20, B: 28, A: 255}
	}
	game.canvas.Fill(background)
	game.drawGround(view)
	for _, wall := range view.Walls {
		fill := wall.Color
		if fill.A == 0 {
			fill = color.RGBA{R: 49, G: 58, B: 71, A: 255}
		}
		stroke := color.RGBA{R: 91, G: 107, B: 127, A: 255}
		if points := wallPolygonScreenPoints(view, wall); len(points) >= 3 {
			var path vector.Path
			path.MoveTo(float32(points[0].X), float32(points[0].Y))
			for _, point := range points[1:] {
				path.LineTo(float32(point.X), float32(point.Y))
			}
			path.Close()
			fillOptions := &vector.DrawPathOptions{}
			fillOptions.ColorScale.ScaleWithColor(fill)
			vector.FillPath(game.canvas, &path, nil, fillOptions)
			strokeOptions := &vector.StrokeOptions{
				Width:      2,
				MiterLimit: 10,
			}
			strokeDrawOptions := &vector.DrawPathOptions{}
			strokeDrawOptions.ColorScale.ScaleWithColor(stroke)
			vector.StrokePath(
				game.canvas,
				&path,
				strokeOptions,
				strokeDrawOptions,
			)
			continue
		}
		x, y := game.screenPoint(view, wall.X, wall.Y)
		zoom := cameraZoom(view)
		vector.DrawFilledRect(
			game.canvas,
			float32(x),
			float32(y),
			float32(wall.Width*zoom),
			float32(wall.Height*zoom),
			fill,
			false,
		)
		vector.StrokeRect(
			game.canvas,
			float32(x),
			float32(y),
			float32(wall.Width*zoom),
			float32(wall.Height*zoom),
			2,
			stroke,
			false,
		)
	}

	entities := append([]EntityView(nil), view.Entities...)
	sort.SliceStable(entities, func(i, j int) bool {
		if entities[i].Layer != entities[j].Layer {
			return entities[i].Layer < entities[j].Layer
		}
		if entities[i].Y != entities[j].Y {
			return entities[i].Y < entities[j].Y
		}
		return entities[i].ID < entities[j].ID
	})
	for _, entity := range entities {
		game.drawEntity(view, entity)
	}
	for _, effect := range view.Effects {
		game.drawEffect(view, effect)
	}
	if view.Flow.Active {
		game.drawHUD(view)
		game.drawFlow(view.Flow)
		return
	}
	if view.Dialogue.Active {
		game.drawDialogue(view.Dialogue)
	} else if view.Shop.Active {
		game.drawShop(view.Shop)
	} else {
		game.drawInventory(view.Inventory)
	}
	game.drawHUD(view)
}

func (game *Game) drawGround(view View) {
	if view.Tilemap != nil {
		game.drawTilemap(view)
		return
	}
	const tile = 48
	zoom := cameraZoom(view)
	startX := int(math.Floor(view.Camera.X/float64(tile))) * tile
	startY := int(math.Floor(view.Camera.Y/float64(tile))) * tile
	worldHeight := int(float64(ScreenHeight)/zoom) + tile
	worldWidth := int(float64(ScreenWidth)/zoom) + tile
	for y := startY; y < int(view.Camera.Y)+worldHeight; y += tile {
		for x := startX; x < int(view.Camera.X)+worldWidth; x += tile {
			sx, sy := game.screenPoint(view, float64(x), float64(y))
			base := color.RGBA{R: 30, G: 54, B: 48, A: 255}
			if (x/tile+y/tile)&1 == 0 {
				base = color.RGBA{R: 34, G: 62, B: 53, A: 255}
			}
			vector.DrawFilledRect(
				game.canvas,
				float32(sx),
				float32(sy),
				float32(tile*zoom),
				float32(tile*zoom),
				base,
				false,
			)
		}
	}
}

const (
	tileFlipHorizontal uint32 = 0x80000000
	tileFlipVertical   uint32 = 0x40000000
	tileFlipDiagonal   uint32 = 0x20000000
	tileGIDMask               = ^(tileFlipHorizontal |
		tileFlipVertical |
		tileFlipDiagonal)
)

type tileDrawCommand struct {
	AssetID        string
	Source         image.Rectangle
	X              float32
	Y              float32
	Width          float32
	Height         float32
	Opacity        float32
	FlipHorizontal bool
	FlipVertical   bool
	FlipDiagonal   bool
}

func (game *Game) drawTilemap(view View) {
	for _, command := range tileDrawCommands(view) {
		source := game.images[command.AssetID]
		if source == nil ||
			command.Source.Min.X < 0 ||
			command.Source.Min.Y < 0 ||
			command.Source.Max.X > source.Bounds().Dx() ||
			command.Source.Max.Y > source.Bounds().Dy() {
			continue
		}
		options := &ebiten.DrawTrianglesOptions{
			Filter: game.filters[command.AssetID],
		}
		game.canvas.DrawTriangles(
			tileVertices(command),
			[]uint16{0, 1, 2, 0, 2, 3},
			source,
			options,
		)
	}
}

func tileDrawCommands(view View) []tileDrawCommand {
	tilemap := view.Tilemap
	if tilemap == nil ||
		tilemap.TileWidth <= 0 ||
		tilemap.TileHeight <= 0 {
		return nil
	}
	zoom := cameraZoom(view)
	if zoom <= 0 {
		return nil
	}
	result := make([]tileDrawCommand, 0)
	for _, layer := range tilemap.Layers {
		if !layer.Visible ||
			layer.Opacity <= 0 ||
			layer.Opacity > 1 ||
			layer.Width <= 0 ||
			layer.Height <= 0 ||
			layer.Width > int(^uint(0)>>1)/layer.Height ||
			len(layer.Data) != layer.Width*layer.Height {
			continue
		}
		for index, encoded := range layer.Data {
			gid := encoded & tileGIDMask
			if gid == 0 {
				continue
			}
			tileset, exists := tilemapTilesetForGID(
				tilemap.Tilesets,
				gid,
			)
			if !exists ||
				tileset.Columns <= 0 ||
				tileset.TileWidth <= 0 ||
				tileset.TileHeight <= 0 {
				continue
			}
			local := int(gid - tileset.FirstGID)
			sourceX := local % tileset.Columns * tileset.TileWidth
			sourceY := local / tileset.Columns * tileset.TileHeight
			column := index % layer.Width
			row := index / layer.Width
			worldX := layer.OffsetX +
				float64(column*tilemap.TileWidth)
			worldY := layer.OffsetY +
				float64(row*tilemap.TileHeight)
			screenX, screenY := worldScreenPoint(view, worldX, worldY)
			width := float64(tilemap.TileWidth) * zoom
			height := float64(tilemap.TileHeight) * zoom
			if screenX+width <= 0 ||
				screenY+height <= 0 ||
				screenX >= ScreenWidth ||
				screenY >= ScreenHeight {
				continue
			}
			result = append(result, tileDrawCommand{
				AssetID: tileset.AssetID,
				Source: image.Rect(
					sourceX,
					sourceY,
					sourceX+tileset.TileWidth,
					sourceY+tileset.TileHeight,
				),
				X:              float32(screenX),
				Y:              float32(screenY),
				Width:          float32(width),
				Height:         float32(height),
				Opacity:        float32(layer.Opacity),
				FlipHorizontal: encoded&tileFlipHorizontal != 0,
				FlipVertical:   encoded&tileFlipVertical != 0,
				FlipDiagonal:   encoded&tileFlipDiagonal != 0,
			})
		}
	}
	return result
}

func tilemapTilesetForGID(
	tilesets []TilesetView,
	gid uint32,
) (TilesetView, bool) {
	for _, tileset := range tilesets {
		first := uint64(tileset.FirstGID)
		last := first + uint64(tileset.TileCount)
		if uint64(gid) >= first && uint64(gid) < last {
			return tileset, true
		}
	}
	return TilesetView{}, false
}

func tileVertices(command tileDrawCommand) []ebiten.Vertex {
	type corner struct {
		x float32
		y float32
	}
	corners := [...]corner{
		{x: 0, y: 0},
		{x: 1, y: 0},
		{x: 1, y: 1},
		{x: 0, y: 1},
	}
	vertices := make([]ebiten.Vertex, len(corners))
	sourceWidth := float32(command.Source.Dx())
	sourceHeight := float32(command.Source.Dy())
	for index, destination := range corners {
		sourceX, sourceY := destination.x, destination.y
		// Invert Tiled's diagonal -> horizontal -> vertical transform to map
		// each fixed destination corner back to its source UV.
		if command.FlipVertical {
			sourceY = 1 - sourceY
		}
		if command.FlipHorizontal {
			sourceX = 1 - sourceX
		}
		if command.FlipDiagonal {
			sourceX, sourceY = sourceY, sourceX
		}
		vertices[index] = ebiten.Vertex{
			DstX:   command.X + destination.x*command.Width,
			DstY:   command.Y + destination.y*command.Height,
			SrcX:   float32(command.Source.Min.X) + sourceX*sourceWidth,
			SrcY:   float32(command.Source.Min.Y) + sourceY*sourceHeight,
			ColorR: 1,
			ColorG: 1,
			ColorB: 1,
			ColorA: command.Opacity,
		}
	}
	return vertices
}

func (game *Game) screenPoint(
	view View,
	worldX float64,
	worldY float64,
) (float64, float64) {
	return worldScreenPoint(view, worldX, worldY)
}

func worldScreenPoint(
	view View,
	worldX float64,
	worldY float64,
) (float64, float64) {
	zoom := cameraZoom(view)
	return (worldX - view.Camera.X + view.Camera.ShakeX) * zoom,
		(worldY - view.Camera.Y + view.Camera.ShakeY) * zoom
}

func wallPolygonScreenPoints(view View, wall RectView) []PointView {
	if len(wall.Points) == 0 {
		return nil
	}
	result := make([]PointView, len(wall.Points))
	for index, point := range wall.Points {
		result[index].X, result[index].Y = worldScreenPoint(
			view,
			point.X,
			point.Y,
		)
	}
	return result
}

func (game *Game) drawEntity(view View, entity EntityView) {
	x, y := game.screenPoint(view, entity.X, entity.Y)
	zoom := cameraZoom(view)
	spec, found := spriteFrame(game.sprites, entity)
	if found {
		source := game.images[spec.asset]
		if source != nil {
			sub := source.SubImage(spec.source).(*ebiten.Image)
			options := &ebiten.DrawImageOptions{}
			options.Filter = game.filters[spec.asset]
			options.GeoM.Translate(
				-spec.originX,
				-spec.originY,
			)
			options.GeoM.Scale(spec.scale*zoom, spec.scale*zoom)
			options.GeoM.Translate(x, y)
			spriteTint := spec.tint
			spriteTintSet := spec.tintSet
			if entity.SpriteTintSet {
				spriteTint = entity.SpriteTint
				spriteTintSet = true
			}
			if spriteTintSet {
				options.ColorScale.ScaleWithColor(spriteTint)
			}
			if entity.Tint.A != 0 {
				options.ColorScale.ScaleWithColor(entity.Tint)
			}
			if entity.Flash {
				options.ColorScale.Scale(1, 0.45, 0.45, 1)
			}
			game.canvas.DrawImage(sub, options)
		}
	} else {
		radius := entity.Radius
		if radius <= 0 {
			radius = 14
		}
		fill := entity.Tint
		if fill.A == 0 {
			fill = color.RGBA{R: 207, G: 213, B: 224, A: 255}
		}
		if entity.Shape == "rectangle" &&
			entity.Width > 0 && entity.Height > 0 {
			left := float32(x - entity.Width*zoom/2)
			top := float32(y - entity.Height*zoom/2)
			width := float32(entity.Width * zoom)
			height := float32(entity.Height * zoom)
			vector.DrawFilledRect(
				game.canvas,
				left,
				top,
				width,
				height,
				fill,
				true,
			)
			if entity.Outline.A != 0 {
				vector.StrokeRect(
					game.canvas,
					left,
					top,
					width,
					height,
					float32(max(1, zoom)),
					entity.Outline,
					true,
				)
			}
		} else {
			vector.DrawFilledCircle(
				game.canvas,
				float32(x),
				float32(y),
				float32(radius*zoom),
				fill,
				true,
			)
			if entity.Outline.A != 0 {
				vector.StrokeCircle(
					game.canvas,
					float32(x),
					float32(y),
					float32(radius*zoom),
					float32(max(1, zoom)),
					entity.Outline,
					true,
				)
			}
		}
	}
	if entity.MaxHealth > 0 && entity.Health < entity.MaxHealth {
		game.drawHealthBar(x, y-(entity.Radius+15)*zoom, entity)
	}
}

func (game *Game) drawHealthBar(
	x float64,
	y float64,
	entity EntityView,
) {
	const width, height = 42, 5
	ratio := max(0, min(1, entity.Health/entity.MaxHealth))
	vector.DrawFilledRect(
		game.canvas,
		float32(x-width/2),
		float32(y),
		width,
		height,
		color.RGBA{R: 28, G: 31, B: 39, A: 230},
		false,
	)
	vector.DrawFilledRect(
		game.canvas,
		float32(x-width/2),
		float32(y),
		float32(width*ratio),
		height,
		color.RGBA{R: 222, G: 76, B: 87, A: 255},
		false,
	)
}

func (game *Game) drawEffect(view View, effect EffectView) {
	x, y := game.screenPoint(view, effect.X, effect.Y)
	zoom := cameraZoom(view)
	scale := effect.Scale
	if scale == 0 {
		scale = 1
	}
	opacity := effect.Opacity
	if opacity == 0 {
		opacity = 1
	}
	alpha := uint8(max(0, min(1, opacity)) * 255)
	if effect.AssetID != "" {
		source := game.images[effect.AssetID]
		if source == nil {
			return
		}
		options := &ebiten.DrawImageOptions{}
		options.Filter = game.filters[effect.AssetID]
		options.GeoM.Translate(
			-float64(source.Bounds().Dx())/2,
			-float64(source.Bounds().Dy())/2,
		)
		options.GeoM.Scale(scale*zoom, scale*zoom)
		options.GeoM.Rotate(effect.Rotation)
		options.GeoM.Translate(x, y)
		options.ColorScale.ScaleAlpha(float32(opacity))
		game.canvas.DrawImage(source, options)
		return
	}
	switch effect.Kind {
	case "parry":
		radius := float32(28 * scale * zoom)
		vector.StrokeCircle(
			game.canvas,
			float32(x),
			float32(y),
			radius,
			float32(4*zoom),
			color.RGBA{R: 112, G: 231, B: 255, A: alpha},
			true,
		)
		vector.StrokeCircle(
			game.canvas,
			float32(x),
			float32(y),
			radius*0.58,
			float32(2*zoom),
			color.RGBA{R: 245, G: 252, B: 255, A: alpha},
			true,
		)
		return
	case "hit":
		vector.DrawFilledCircle(
			game.canvas,
			float32(x),
			float32(y),
			float32(12*scale*zoom),
			color.RGBA{R: 255, G: 222, B: 124, A: alpha},
			true,
		)
		return
	default:
		return
	}
}

func cameraZoom(view View) float64 {
	if view.Camera.Zoom > 0 {
		return view.Camera.Zoom
	}
	return 1
}

func layoutDialogue(view DialogueView) dialogueLayout {
	result := dialogueLayout{
		BodyLines: wrapText(
			view.Text,
			maxDialogueBodyRunes,
			maxDialogueBodyLines,
		),
		Selected: -1,
	}
	if len(view.Choices) == 0 {
		return result
	}

	selected := min(max(view.SelectedIndex, 0), len(view.Choices)-1)
	first := 0
	if selected >= maxVisibleDialogueChoices {
		first = selected - maxVisibleDialogueChoices + 1
	}
	first = min(first, max(0, len(view.Choices)-maxVisibleDialogueChoices))
	last := min(len(view.Choices), first+maxVisibleDialogueChoices)

	result.Selected = selected
	result.HasEarlier = first > 0
	result.HasLater = last < len(view.Choices)
	result.Choices = make(
		[]dialogueChoiceLayout,
		0,
		last-first,
	)
	for index := first; index < last; index++ {
		choice := view.Choices[index]
		label := choice.Text
		if strings.TrimSpace(label) == "" {
			label = choice.ID
		}
		label = ellipsizeText(label, maxDialogueChoiceRunes)
		result.Choices = append(
			result.Choices,
			dialogueChoiceLayout{
				Index:    index,
				ID:       choice.ID,
				Text:     label,
				Selected: index == selected,
			},
		)
	}
	return result
}

func wrapText(
	value string,
	maxRunes int,
	maxLines int,
) []string {
	if maxRunes <= 0 || maxLines <= 0 {
		return nil
	}
	value = strings.ReplaceAll(value, "\r\n", "\n")
	value = strings.ReplaceAll(value, "\r", "\n")
	if strings.TrimSpace(value) == "" {
		return nil
	}

	var lines []string
	for _, explicit := range strings.Split(value, "\n") {
		remaining := strings.TrimSpace(explicit)
		if remaining == "" {
			lines = append(lines, "")
			continue
		}
		for utf8.RuneCountInString(remaining) > maxRunes {
			runes := []rune(remaining)
			breakAt := maxRunes
			for index := maxRunes; index > 0; index-- {
				if unicode.IsSpace(runes[index]) {
					breakAt = index
					break
				}
			}
			line := strings.TrimSpace(string(runes[:breakAt]))
			if line == "" {
				line = string(runes[:maxRunes])
				breakAt = maxRunes
			}
			lines = append(lines, line)
			remaining = strings.TrimSpace(string(runes[breakAt:]))
		}
		if remaining != "" {
			lines = append(lines, remaining)
		}
	}
	if len(lines) <= maxLines {
		return lines
	}

	lines = lines[:maxLines]
	last := []rune(strings.TrimSpace(lines[maxLines-1]))
	if len(last) >= maxRunes {
		last = last[:maxRunes-1]
	}
	lines[maxLines-1] = strings.TrimSpace(string(last)) + "…"
	return lines
}

func ellipsizeText(value string, maxRunes int) string {
	value = strings.TrimSpace(value)
	if maxRunes <= 0 || value == "" {
		return ""
	}
	runes := []rune(value)
	if len(runes) <= maxRunes {
		return value
	}
	if maxRunes == 1 {
		return "…"
	}
	return strings.TrimSpace(string(runes[:maxRunes-1])) + "…"
}

func (game *Game) drawDialogue(view DialogueView) {
	if !view.Active {
		return
	}
	layout := layoutDialogue(view)
	vector.DrawFilledRect(
		game.canvas,
		dialogueBoxX,
		dialogueBoxY,
		dialogueBoxWidth,
		dialogueBoxHeight,
		color.RGBA{R: 9, G: 13, B: 22, A: 244},
		false,
	)
	vector.StrokeRect(
		game.canvas,
		dialogueBoxX,
		dialogueBoxY,
		dialogueBoxWidth,
		dialogueBoxHeight,
		2,
		color.RGBA{R: 126, G: 162, B: 190, A: 255},
		false,
	)
	if view.Speaker != "" {
		game.drawText(
			ellipsizeText(
				view.Speaker,
				maxDialogueSpeakerRunes,
			),
			dialogueBoxX+24,
			dialogueBoxY+13,
			18,
			color.RGBA{R: 244, G: 211, B: 108, A: 255},
		)
	}
	vector.StrokeLine(
		game.canvas,
		dialogueBoxX+20,
		dialogueBoxY+40,
		dialogueBoxX+dialogueBoxWidth-20,
		dialogueBoxY+40,
		1,
		color.RGBA{R: 73, G: 91, B: 112, A: 255},
		false,
	)
	if len(layout.BodyLines) != 0 {
		game.drawText(
			strings.Join(layout.BodyLines, "\n"),
			dialogueBoxX+24,
			dialogueBoxY+49,
			16,
			color.RGBA{R: 235, G: 240, B: 246, A: 255},
		)
	}

	const choiceStartY = dialogueBoxY + 98
	const choiceStep = 23
	for offset, choice := range layout.Choices {
		y := choiceStartY + float32(offset*choiceStep)
		if choice.Selected {
			vector.DrawFilledRect(
				game.canvas,
				dialogueBoxX+20,
				y-2,
				dialogueBoxWidth-40,
				22,
				color.RGBA{R: 42, G: 76, B: 92, A: 238},
				false,
			)
		}
		marker := "  "
		tint := color.RGBA{R: 196, G: 208, B: 221, A: 255}
		if choice.Selected {
			marker = "› "
			tint = color.RGBA{R: 224, G: 248, B: 255, A: 255}
		}
		game.drawText(
			marker+choice.Text,
			dialogueBoxX+30,
			float64(y),
			15,
			tint,
		)
	}
	if layout.HasEarlier {
		game.drawText(
			"▲",
			dialogueBoxX+dialogueBoxWidth-38,
			dialogueBoxY+92,
			12,
			color.RGBA{R: 150, G: 184, B: 205, A: 255},
		)
	}
	if layout.HasLater {
		game.drawText(
			"▼",
			dialogueBoxX+dialogueBoxWidth-38,
			dialogueBoxY+156,
			12,
			color.RGBA{R: 150, G: 184, B: 205, A: 255},
		)
	}
	help := dialogueContinueHelp
	if len(view.Choices) != 0 {
		help = dialogueChoiceHelp
	}
	game.drawText(
		help,
		dialogueBoxX+dialogueBoxWidth-390,
		dialogueBoxY+169,
		12,
		color.RGBA{R: 145, G: 169, B: 190, A: 255},
	)
}

func layoutShop(view ShopView) shopLayout {
	name := strings.TrimSpace(view.Name)
	if name == "" {
		name = shopFallbackName
	}
	result := shopLayout{
		Name:     ellipsizeText(name, maxShopNameRunes),
		Status:   ellipsizeText(view.Status, maxShopStatusRunes),
		Selected: -1,
	}
	if len(view.Offers) == 0 {
		return result
	}

	selected := min(max(view.SelectedIndex, 0), len(view.Offers)-1)
	first := 0
	if selected >= maxVisibleShopOffers {
		first = selected - maxVisibleShopOffers + 1
	}
	first = min(first, max(0, len(view.Offers)-maxVisibleShopOffers))
	last := min(len(view.Offers), first+maxVisibleShopOffers)

	result.Selected = selected
	result.HasEarlier = first > 0
	result.HasLater = last < len(view.Offers)
	result.Offers = make([]shopOfferLayout, 0, last-first)
	for index := first; index < last; index++ {
		offer := view.Offers[index]
		name := strings.TrimSpace(offer.Name)
		if name == "" {
			name = strings.TrimSpace(offer.ID)
		}
		if name == "" {
			name = shopFallbackOfferName
		}
		result.Offers = append(
			result.Offers,
			shopOfferLayout{
				Index: index,
				ID:    offer.ID,
				Name:  ellipsizeText(name, maxShopOfferNameRunes),
				ModifierSummary: ellipsizeText(
					offer.ModifierSummary,
					22,
				),
				Owned:     offer.Owned,
				CanBuy:    offer.CanBuy,
				BuyPrice:  offer.BuyPrice,
				CanSell:   offer.CanSell,
				SellPrice: offer.SellPrice,
				Selected:  index == selected,
			},
		)
	}
	return result
}

func shopPriceText(available bool, price int64) string {
	if !available {
		return "—"
	}
	return fmt.Sprintf("%d G", price)
}

func (game *Game) drawShop(view ShopView) {
	if !view.Active {
		return
	}
	layout := layoutShop(view)
	vector.DrawFilledRect(
		game.canvas,
		shopPanelX,
		shopPanelY,
		shopPanelWidth,
		shopPanelHeight,
		color.RGBA{R: 12, G: 14, B: 21, A: 246},
		false,
	)
	vector.StrokeRect(
		game.canvas,
		shopPanelX,
		shopPanelY,
		shopPanelWidth,
		shopPanelHeight,
		2,
		color.RGBA{R: 198, G: 163, B: 91, A: 255},
		false,
	)
	game.drawText(
		layout.Name,
		shopPanelX+24,
		shopPanelY+11,
		18,
		color.RGBA{R: 247, G: 219, B: 139, A: 255},
	)
	game.drawText(
		fmt.Sprintf("%s  %d G", shopCurrencyLabel, view.Currency),
		shopPanelX+shopPanelWidth-250,
		shopPanelY+13,
		16,
		color.RGBA{R: 235, G: 240, B: 246, A: 255},
	)
	vector.StrokeLine(
		game.canvas,
		shopPanelX+20,
		shopPanelY+38,
		shopPanelX+shopPanelWidth-20,
		shopPanelY+38,
		1,
		color.RGBA{R: 82, G: 77, B: 67, A: 255},
		false,
	)

	columnTint := color.RGBA{R: 151, G: 160, B: 174, A: 255}
	game.drawText(
		shopOfferColumnLabel,
		shopPanelX+30,
		shopPanelY+43,
		12,
		columnTint,
	)
	game.drawText(
		shopOwnedColumnLabel,
		shopPanelX+455,
		shopPanelY+43,
		12,
		columnTint,
	)
	game.drawText(
		shopBuyColumnLabel,
		shopPanelX+565,
		shopPanelY+43,
		12,
		columnTint,
	)
	game.drawText(
		shopSellColumnLabel,
		shopPanelX+705,
		shopPanelY+43,
		12,
		columnTint,
	)

	const offerStartY = shopPanelY + 64
	const offerStep = 23
	if len(layout.Offers) == 0 {
		game.drawText(
			shopEmptyMessage,
			shopPanelX+30,
			shopPanelY+84,
			15,
			color.RGBA{R: 177, G: 185, B: 196, A: 255},
		)
	}
	for offset, offer := range layout.Offers {
		y := offerStartY + float32(offset*offerStep)
		if offer.Selected {
			vector.DrawFilledRect(
				game.canvas,
				shopPanelX+20,
				y-2,
				shopPanelWidth-40,
				22,
				color.RGBA{R: 74, G: 62, B: 40, A: 242},
				false,
			)
		}
		marker := "  "
		nameTint := color.RGBA{R: 207, G: 214, B: 223, A: 255}
		if offer.Selected {
			marker = "› "
			nameTint = color.RGBA{R: 255, G: 237, B: 185, A: 255}
		}
		name := marker + offer.Name
		if offer.ModifierSummary != "" {
			name += "  " + offer.ModifierSummary
		}
		game.drawText(
			name,
			shopPanelX+30,
			float64(y),
			15,
			nameTint,
		)
		game.drawText(
			fmt.Sprintf("%d", offer.Owned),
			shopPanelX+455,
			float64(y),
			12,
			color.RGBA{R: 207, G: 214, B: 223, A: 255},
		)
		buyTint := color.RGBA{R: 107, G: 113, B: 123, A: 255}
		if offer.CanBuy {
			buyTint = color.RGBA{R: 119, G: 224, B: 151, A: 255}
		}
		game.drawText(
			shopPriceText(offer.CanBuy, offer.BuyPrice),
			shopPanelX+565,
			float64(y),
			12,
			buyTint,
		)
		sellTint := color.RGBA{R: 107, G: 113, B: 123, A: 255}
		if offer.CanSell {
			sellTint = color.RGBA{R: 112, G: 196, B: 232, A: 255}
		}
		game.drawText(
			shopPriceText(offer.CanSell, offer.SellPrice),
			shopPanelX+705,
			float64(y),
			12,
			sellTint,
		)
	}
	if layout.HasEarlier {
		game.drawText(
			"▲",
			shopPanelX+shopPanelWidth-38,
			shopPanelY+58,
			12,
			color.RGBA{R: 198, G: 163, B: 91, A: 255},
		)
	}
	if layout.HasLater {
		game.drawText(
			"▼",
			shopPanelX+shopPanelWidth-38,
			shopPanelY+120,
			12,
			color.RGBA{R: 198, G: 163, B: 91, A: 255},
		)
	}
	if layout.Status != "" {
		game.drawText(
			layout.Status,
			shopPanelX+24,
			shopPanelY+139,
			12,
			color.RGBA{R: 225, G: 188, B: 107, A: 255},
		)
	}
	help := shopActionHelp
	if len(view.Offers) == 0 {
		help = shopEmptyHelp
	}
	game.drawText(
		help,
		shopPanelX+shopPanelWidth-510,
		shopPanelY+165,
		12,
		color.RGBA{R: 145, G: 160, B: 178, A: 255},
	)
}

func layoutInventory(view InventoryView) inventoryLayout {
	title := strings.TrimSpace(view.Title)
	if title == "" {
		title = inventoryFallbackTitle
	}
	result := inventoryLayout{
		Title: ellipsizeText(title, maxInventoryTitleRunes),
		Status: wrapText(
			view.Status,
			maxInventoryStatusRunes,
			maxInventoryStatusLines,
		),
		Selected: -1,
	}
	if len(view.Items) == 0 {
		return result
	}

	selected := min(max(view.SelectedIndex, 0), len(view.Items)-1)
	first := 0
	if selected >= maxVisibleInventoryItems {
		first = selected - maxVisibleInventoryItems + 1
	}
	first = min(
		first,
		max(0, len(view.Items)-maxVisibleInventoryItems),
	)
	last := min(len(view.Items), first+maxVisibleInventoryItems)

	result.Selected = selected
	result.HasEarlier = first > 0
	result.HasLater = last < len(view.Items)
	result.Items = make([]inventoryItemLayout, 0, last-first)
	for index := first; index < last; index++ {
		item := layoutInventoryItem(
			index,
			view.Items[index],
			index == selected,
		)
		result.Items = append(result.Items, item)
		if item.Selected {
			result.Detail = item
			result.HasDetail = true
		}
	}
	return result
}

func layoutInventoryItem(
	index int,
	item InventoryItemView,
	selected bool,
) inventoryItemLayout {
	name := strings.TrimSpace(item.Name)
	if name == "" {
		name = strings.TrimSpace(item.ID)
	}
	if name == "" {
		name = inventoryFallbackItemName
	}
	description := strings.TrimSpace(item.Description)
	if description == "" {
		description = inventoryEmptyDescription
	}
	quantity := item.Quantity
	if quantity < 0 {
		quantity = 0
	}
	return inventoryItemLayout{
		Index: index,
		ID:    item.ID,
		Name: ellipsizeText(
			name,
			maxInventoryItemNameRunes,
		),
		Description: wrapText(
			description,
			maxInventoryDescriptionRunes,
			maxInventoryDescriptionLines,
		),
		ModifierSummary: ellipsizeText(item.ModifierSummary, 28),
		Quantity:        quantity,
		Consumable:      item.Consumable,
		EquipmentSlot: ellipsizeText(
			item.EquipmentSlot,
			maxInventorySlotRunes,
		),
		Equipped: item.Equipped,
		CanUse:   item.CanUse,
		CanEquip: item.CanEquip,
		Selected: selected,
	}
}

func inventoryKindText(item inventoryItemLayout) string {
	parts := make([]string, 0, 3)
	if item.Consumable {
		parts = append(parts, inventoryConsumableLabel)
	}
	if item.EquipmentSlot != "" {
		parts = append(
			parts,
			inventoryEquipmentLabel+" · "+item.EquipmentSlot,
		)
	}
	if item.ModifierSummary != "" {
		parts = append(parts, item.ModifierSummary)
	}
	if len(parts) == 0 {
		parts = append(parts, "기타")
	}
	if item.Equipped {
		parts = append(parts, "장착 중")
	}
	return strings.Join(parts, "  ·  ")
}

func inventoryAvailabilityText(item inventoryItemLayout) string {
	if item.Quantity <= 0 {
		return "보유 수량 없음"
	}
	parts := make([]string, 0, 3)
	if item.CanUse {
		parts = append(parts, "사용 가능")
	}
	if item.CanEquip {
		parts = append(parts, "장착 가능")
	}
	if item.Equipped {
		parts = append(parts, "Q로 장착 해제")
	}
	if len(parts) == 0 {
		return "사용·장착 불가"
	}
	return strings.Join(parts, "  ·  ")
}

func (game *Game) drawInventory(view InventoryView) {
	if !view.Active {
		return
	}
	layout := layoutInventory(view)
	vector.DrawFilledRect(
		game.canvas,
		0,
		0,
		ScreenWidth,
		ScreenHeight,
		color.RGBA{R: 3, G: 7, B: 13, A: 164},
		false,
	)
	vector.DrawFilledRect(
		game.canvas,
		inventoryPanelX,
		inventoryPanelY,
		inventoryPanelWidth,
		inventoryPanelHeight,
		color.RGBA{R: 10, G: 16, B: 25, A: 248},
		false,
	)
	vector.StrokeRect(
		game.canvas,
		inventoryPanelX,
		inventoryPanelY,
		inventoryPanelWidth,
		inventoryPanelHeight,
		2,
		color.RGBA{R: 100, G: 174, B: 190, A: 255},
		false,
	)
	game.drawText(
		layout.Title,
		inventoryPanelX+26,
		inventoryPanelY+14,
		22,
		color.RGBA{R: 184, G: 235, B: 241, A: 255},
	)
	vector.StrokeLine(
		game.canvas,
		inventoryPanelX+20,
		inventoryPanelY+49,
		inventoryPanelX+inventoryPanelWidth-20,
		inventoryPanelY+49,
		1,
		color.RGBA{R: 69, G: 102, B: 113, A: 255},
		false,
	)

	const (
		listX         = inventoryPanelX + 20
		listY         = inventoryPanelY + 59
		listWidth     = 440
		contentHeight = 202
		detailX       = inventoryPanelX + 472
		detailWidth   = inventoryPanelWidth - 492
	)
	panelStroke := color.RGBA{R: 54, G: 83, B: 96, A: 255}
	vector.StrokeRect(
		game.canvas,
		listX,
		listY,
		listWidth,
		contentHeight,
		1,
		panelStroke,
		false,
	)
	vector.StrokeRect(
		game.canvas,
		detailX,
		listY,
		detailWidth,
		contentHeight,
		1,
		panelStroke,
		false,
	)

	columnTint := color.RGBA{R: 137, G: 163, B: 176, A: 255}
	game.drawText(
		inventoryNameColumnLabel,
		listX+10,
		listY+7,
		11,
		columnTint,
	)
	game.drawText(
		inventoryEquippedLabel,
		listX+294,
		listY+7,
		11,
		columnTint,
	)
	game.drawText(
		inventoryQuantityLabel,
		listX+388,
		listY+7,
		11,
		columnTint,
	)

	const (
		itemStartY = listY + 31
		itemStep   = 29
	)
	if len(layout.Items) == 0 {
		game.drawText(
			inventoryEmptyMessage,
			listX+18,
			listY+55,
			15,
			color.RGBA{R: 164, G: 177, B: 188, A: 255},
		)
	}
	for offset, item := range layout.Items {
		y := itemStartY + float32(offset*itemStep)
		if item.Selected {
			vector.DrawFilledRect(
				game.canvas,
				listX+8,
				y-3,
				listWidth-16,
				24,
				color.RGBA{R: 31, G: 73, B: 84, A: 242},
				false,
			)
		}
		marker := "  "
		tint := color.RGBA{R: 194, G: 205, B: 216, A: 255}
		if item.Quantity == 0 {
			tint = color.RGBA{R: 101, G: 112, B: 124, A: 255}
		}
		if item.Selected {
			marker = "› "
			if item.Quantity > 0 {
				tint = color.RGBA{R: 226, G: 248, B: 251, A: 255}
			}
		}
		game.drawText(
			marker+item.Name,
			listX+14,
			float64(y),
			15,
			tint,
		)
		if item.Equipped {
			game.drawText(
				inventoryEquippedIndicator,
				listX+292,
				float64(y)+2,
				11,
				color.RGBA{R: 247, G: 215, B: 120, A: 255},
			)
		}
		game.drawText(
			fmt.Sprintf("× %d", item.Quantity),
			listX+386,
			float64(y)+2,
			11,
			tint,
		)
	}
	if layout.HasEarlier {
		game.drawText(
			"▲",
			listX+listWidth-24,
			listY+21,
			11,
			color.RGBA{R: 105, G: 192, B: 207, A: 255},
		)
	}
	if layout.HasLater {
		game.drawText(
			"▼",
			listX+listWidth-24,
			listY+181,
			11,
			color.RGBA{R: 105, G: 192, B: 207, A: 255},
		)
	}

	if layout.HasDetail {
		detail := layout.Detail
		game.drawText(
			detail.Name,
			detailX+16,
			listY+13,
			18,
			color.RGBA{R: 228, G: 241, B: 245, A: 255},
		)
		game.drawText(
			inventoryKindText(detail),
			detailX+16,
			listY+49,
			12,
			color.RGBA{R: 245, G: 211, B: 123, A: 255},
		)
		game.drawText(
			inventoryAvailabilityText(detail),
			detailX+16,
			listY+76,
			12,
			color.RGBA{R: 114, G: 207, B: 166, A: 255},
		)
		game.drawText(
			strings.Join(detail.Description, "\n"),
			detailX+16,
			listY+106,
			13,
			color.RGBA{R: 184, G: 197, B: 209, A: 255},
		)
	}

	const (
		statusX      = inventoryPanelX + 20
		statusY      = inventoryPanelY + 268
		statusWidth  = inventoryPanelWidth - 40
		statusHeight = 49
	)
	vector.DrawFilledRect(
		game.canvas,
		statusX,
		statusY,
		statusWidth,
		statusHeight,
		color.RGBA{R: 14, G: 24, B: 34, A: 245},
		false,
	)
	vector.StrokeRect(
		game.canvas,
		statusX,
		statusY,
		statusWidth,
		statusHeight,
		1,
		panelStroke,
		false,
	)
	game.drawText(
		inventoryStatusLabel,
		statusX+12,
		statusY+8,
		11,
		color.RGBA{R: 120, G: 184, B: 197, A: 255},
	)
	if len(layout.Status) != 0 {
		game.drawText(
			strings.Join(layout.Status, "\n"),
			statusX+64,
			statusY+6,
			12,
			color.RGBA{R: 214, G: 227, B: 234, A: 255},
		)
	}
	help := inventoryActionHelp
	if len(view.Items) == 0 {
		help = inventoryEmptyHelp
	}
	game.drawText(
		help,
		inventoryPanelX+inventoryPanelWidth-590,
		inventoryPanelY+343,
		12,
		color.RGBA{R: 139, G: 166, B: 181, A: 255},
	)
}

func layoutFlow(view FlowView) flowLayout {
	mode := strings.ToLower(strings.TrimSpace(view.Mode))
	heading := strings.TrimSpace(view.Heading)
	if heading == "" {
		heading = fallbackFlowHeading(mode)
	}
	result := flowLayout{
		Mode:    mode,
		Heading: ellipsizeText(heading, maxFlowHeadingRunes),
		Message: wrapText(view.Message, maxFlowMessageRunes, maxFlowMessageLines),
		Selected: normalizedFlowSelection(
			view.Options,
			view.SelectedIndex,
		),
	}

	first := 0
	if result.Selected >= maxVisibleFlowOptions {
		first = result.Selected - maxVisibleFlowOptions + 1
	}
	first = min(first, max(0, len(view.Options)-maxVisibleFlowOptions))
	last := min(len(view.Options), first+maxVisibleFlowOptions)
	result.HasEarlier = first > 0
	result.HasLater = last < len(view.Options)
	result.Options = make([]flowOptionLayout, 0, last-first)
	for index := first; index < last; index++ {
		option := view.Options[index]
		label := strings.TrimSpace(option.Label)
		if label == "" {
			label = strings.TrimSpace(option.ID)
		}
		if label == "" {
			label = flowFallbackOption
		}
		if option.Enabled {
			label = ellipsizeText(label, maxFlowOptionRunes)
		} else {
			labelBudget := maxFlowOptionRunes -
				utf8.RuneCountInString(flowDisabledIndicator)
			label = ellipsizeText(label, max(1, labelBudget)) +
				flowDisabledIndicator
		}
		result.Options = append(
			result.Options,
			flowOptionLayout{
				Index:   index,
				ID:      option.ID,
				Label:   label,
				Enabled: option.Enabled,
				Selected: option.Enabled &&
					index == result.Selected,
			},
		)
	}
	return result
}

func fallbackFlowHeading(mode string) string {
	switch mode {
	case "title":
		return flowTitleHeading
	case "pause", "paused":
		return flowPauseHeading
	case "gameover", "game_over", "game-over":
		return flowGameOverHeading
	case "ending":
		return flowEndingHeading
	default:
		return flowFallbackHeading
	}
}

type flowPalette struct {
	Backdrop color.RGBA
	Panel    color.RGBA
	Border   color.RGBA
	Heading  color.RGBA
	Selected color.RGBA
}

func paletteForFlow(mode string) flowPalette {
	switch mode {
	case "pause", "paused":
		return flowPalette{
			Backdrop: color.RGBA{R: 3, G: 8, B: 15, A: 174},
			Panel:    color.RGBA{R: 10, G: 17, B: 28, A: 224},
			Border:   color.RGBA{R: 112, G: 190, B: 222, A: 255},
			Heading:  color.RGBA{R: 188, G: 235, B: 255, A: 255},
			Selected: color.RGBA{R: 37, G: 82, B: 105, A: 238},
		}
	case "gameover", "game_over", "game-over":
		return flowPalette{
			Backdrop: color.RGBA{R: 22, G: 5, B: 8, A: 255},
			Panel:    color.RGBA{R: 31, G: 9, B: 13, A: 255},
			Border:   color.RGBA{R: 184, G: 71, B: 79, A: 255},
			Heading:  color.RGBA{R: 255, G: 166, B: 166, A: 255},
			Selected: color.RGBA{R: 104, G: 35, B: 42, A: 248},
		}
	case "ending":
		return flowPalette{
			Backdrop: color.RGBA{R: 18, G: 15, B: 7, A: 255},
			Panel:    color.RGBA{R: 29, G: 24, B: 10, A: 255},
			Border:   color.RGBA{R: 213, G: 177, B: 86, A: 255},
			Heading:  color.RGBA{R: 255, G: 226, B: 146, A: 255},
			Selected: color.RGBA{R: 91, G: 72, B: 29, A: 248},
		}
	default:
		return flowPalette{
			Backdrop: color.RGBA{R: 5, G: 9, B: 18, A: 255},
			Panel:    color.RGBA{R: 9, G: 15, B: 27, A: 255},
			Border:   color.RGBA{R: 91, G: 139, B: 190, A: 255},
			Heading:  color.RGBA{R: 190, G: 221, B: 255, A: 255},
			Selected: color.RGBA{R: 32, G: 67, B: 103, A: 248},
		}
	}
}

func (game *Game) drawFlow(view FlowView) {
	if !view.Active {
		return
	}
	layout := layoutFlow(view)
	palette := paletteForFlow(layout.Mode)
	vector.DrawFilledRect(
		game.canvas,
		0,
		0,
		ScreenWidth,
		ScreenHeight,
		palette.Backdrop,
		false,
	)
	vector.DrawFilledRect(
		game.canvas,
		flowPanelX,
		flowPanelY,
		flowPanelWidth,
		flowPanelHeight,
		palette.Panel,
		false,
	)
	vector.StrokeRect(
		game.canvas,
		flowPanelX,
		flowPanelY,
		flowPanelWidth,
		flowPanelHeight,
		2,
		palette.Border,
		false,
	)
	game.drawText(
		layout.Heading,
		flowPanelX+38,
		flowPanelY+23,
		28,
		palette.Heading,
	)
	vector.StrokeLine(
		game.canvas,
		flowPanelX+30,
		flowPanelY+72,
		flowPanelX+flowPanelWidth-30,
		flowPanelY+72,
		1,
		palette.Border,
		false,
	)
	if len(layout.Message) != 0 {
		game.drawText(
			strings.Join(layout.Message, "\n"),
			flowPanelX+38,
			flowPanelY+87,
			16,
			color.RGBA{R: 222, G: 229, B: 238, A: 255},
		)
	}

	const optionStartY = flowPanelY + 198
	const optionStep = 30
	for offset, option := range layout.Options {
		y := optionStartY + float32(offset*optionStep)
		if option.Selected {
			vector.DrawFilledRect(
				game.canvas,
				flowPanelX+34,
				y-3,
				flowPanelWidth-68,
				27,
				palette.Selected,
				false,
			)
		}
		marker := "  "
		tint := color.RGBA{R: 199, G: 208, B: 220, A: 255}
		if !option.Enabled {
			tint = color.RGBA{R: 102, G: 110, B: 122, A: 255}
		} else if option.Selected {
			marker = "› "
			tint = color.RGBA{R: 244, G: 249, B: 255, A: 255}
		}
		game.drawText(
			marker+option.Label,
			flowPanelX+50,
			float64(y),
			18,
			tint,
		)
	}
	if layout.HasEarlier {
		game.drawText(
			"▲",
			flowPanelX+flowPanelWidth-55,
			flowPanelY+188,
			13,
			palette.Border,
		)
	}
	if layout.HasLater {
		game.drawText(
			"▼",
			flowPanelX+flowPanelWidth-55,
			flowPanelY+329,
			13,
			palette.Border,
		)
	}
	help := flowActionHelp
	if layout.Selected < 0 {
		help = flowBackHelp
	}
	game.drawText(
		help,
		flowPanelX+flowPanelWidth-430,
		flowPanelY+354,
		12,
		color.RGBA{R: 148, G: 163, B: 182, A: 255},
	)
}

func (game *Game) drawHUD(view View) {
	playerHealth, playerMaximum := 0.0, 0.0
	for _, entity := range view.Entities {
		if entity.Controlled {
			playerHealth, playerMaximum = entity.Health, entity.MaxHealth
			break
		}
	}
	vector.DrawFilledRect(
		game.canvas,
		16,
		14,
		360,
		hudPanelHeight(view.HUD),
		color.RGBA{R: 10, G: 13, B: 19, A: 218},
		false,
	)
	if playerMaximum > 0 {
		vector.DrawFilledRect(
			game.canvas,
			28,
			52,
			250,
			12,
			color.RGBA{R: 47, G: 52, B: 62, A: 255},
			false,
		)
		vector.DrawFilledRect(
			game.canvas,
			28,
			52,
			float32(250*max(0, min(1, playerHealth/playerMaximum))),
			12,
			color.RGBA{R: 61, G: 202, B: 126, A: 255},
			false,
		)
	}
	title := view.HUD.Title
	if title == "" {
		title = "Recreate · Ebitengine"
	}
	game.drawText(title, 28, 25, 18, color.White)
	status := view.HUD.Status
	if status == "" {
		status = fmt.Sprintf(
			"tick %d · %s · %dG",
			view.Tick,
			view.World.Stage,
			view.HUD.Currency,
		)
	}
	statusY := float64(70)
	if view.HUD.ShowStats {
		game.drawText(
			fmt.Sprintf(
				"ATK %d · DEF %d · MOVE %.2f · %dG",
				view.HUD.Attack,
				view.HUD.Defense,
				view.HUD.MoveSpeed,
				view.HUD.Currency,
			),
			28,
			70,
			13,
			color.RGBA{R: 216, G: 225, B: 235, A: 255},
		)
		statusY = 91
	}
	game.drawText(
		status,
		28,
		statusY,
		13,
		color.RGBA{R: 189, G: 203, B: 219, A: 255},
	)
	if view.HUD.Help != "" &&
		!view.Flow.Active &&
		!view.Dialogue.Active &&
		!view.Shop.Active &&
		!view.Inventory.Active {
		game.drawText(
			view.HUD.Help,
			22,
			ScreenHeight-24,
			14,
			color.RGBA{R: 192, G: 205, B: 218, A: 255},
		)
	}
	if view.HUD.Dialogue != "" &&
		!view.Flow.Active &&
		!view.Dialogue.Active &&
		!view.Shop.Active &&
		!view.Inventory.Active {
		vector.DrawFilledRect(
			game.canvas,
			80,
			ScreenHeight-150,
			ScreenWidth-160,
			112,
			color.RGBA{R: 12, G: 16, B: 24, A: 238},
			false,
		)
		vector.StrokeRect(
			game.canvas,
			80,
			ScreenHeight-150,
			ScreenWidth-160,
			112,
			2,
			color.RGBA{R: 126, G: 162, B: 190, A: 255},
			false,
		)
		game.drawText(
			view.HUD.Dialogue,
			104,
			ScreenHeight-118,
			18,
			color.White,
		)
	}
	if view.HUD.Quest != "" {
		game.drawText(
			view.HUD.Quest,
			ScreenWidth-310,
			30,
			15,
			color.RGBA{R: 244, G: 211, B: 108, A: 255},
		)
	}
	if view.AutomationPaused {
		vector.DrawFilledRect(
			game.canvas,
			ScreenWidth/2-170,
			ScreenHeight/2-54,
			340,
			108,
			color.RGBA{R: 8, G: 12, B: 18, A: 220},
			false,
		)
		vector.StrokeRect(
			game.canvas,
			ScreenWidth/2-170,
			ScreenHeight/2-54,
			340,
			108,
			2,
			color.RGBA{R: 112, G: 231, B: 255, A: 255},
			false,
		)
		game.drawText(
			"AUTOMATION PAUSED",
			ScreenWidth/2-116,
			ScreenHeight/2-18,
			22,
			color.RGBA{R: 224, G: 248, B: 255, A: 255},
		)
		game.drawText(
			"resume: recreatectl pause false",
			ScreenWidth/2-121,
			ScreenHeight/2+20,
			13,
			color.RGBA{R: 166, G: 205, B: 219, A: 255},
		)
	}
}

func hudPanelHeight(hud HUDView) float32 {
	if hud.ShowStats {
		return 104
	}
	return 84
}

func (game *Game) drawText(
	value string,
	x float64,
	y float64,
	size float64,
	tint color.Color,
) {
	options := &text.DrawOptions{}
	options.GeoM.Translate(x, y)
	options.ColorScale.ScaleWithColor(tint)
	options.LineSpacing = size * 1.4
	text.Draw(
		game.canvas,
		value,
		&text.GoTextFace{Source: game.font, Size: size},
		options,
	)
}
