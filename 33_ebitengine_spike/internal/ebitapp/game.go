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
	"sort"

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

// Capture is one completely rendered logical frame.
type Capture struct {
	PNG      []byte
	Tick     uint64
	Revision uint64
}

// Options controls deterministic desktop automation. Console builds leave this
// zero-valued and use the debug protocol instead.
type Options struct {
	StopAfterTicks uint64
	ScreenshotPath string
}

// Game adapts a pure fixed-tick Model to Ebitengine.
type Game struct {
	model Model

	canvas  *ebiten.Image
	images  map[string]*ebiten.Image
	font    *text.GoTextFaceSource
	capture chan captureRequest

	options      Options
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
	if options.ScreenshotPath != "" && options.StopAfterTicks == 0 {
		return nil, errors.New(
			"a screenshot path requires a non-zero stop tick",
		)
	}
	images := make(map[string]*ebiten.Image)
	for id, path := range map[string]string{
		"image.player_sheet":    "images/player/player-sheet.png",
		"image.slime_red_sheet": "images/enemies/slime-red-sheet.png",
		"image.guide_sheet":     "images/npcs/guide-sheet.png",
		"image.merchant_sheet":  "images/npcs/merchant-sheet.png",
		"image.slash":           "images/effects/slash.png",
	} {
		data, err := gameassets.ReadFile(path)
		if err != nil {
			return nil, fmt.Errorf("load %s: %w", id, err)
		}
		decoded, err := png.Decode(bytes.NewReader(data))
		if err != nil {
			return nil, fmt.Errorf("decode %s: %w", id, err)
		}
		images[id] = ebiten.NewImageFromImage(decoded)
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
		font:    font,
		capture: make(chan captureRequest, 8),
		options: options,
	}, nil
}

func (game *Game) Update() error {
	if game.autoError != nil {
		return game.autoError
	}
	view := game.model.View()
	if game.options.StopAfterTicks > 0 &&
		view.Tick >= game.options.StopAfterTicks {
		if game.options.ScreenshotPath == "" || game.autoCaptured {
			return ebiten.Termination
		}
		return nil
	}
	if err := game.model.Tick(PollActions()); err != nil {
		return err
	}
	if game.model.View().Quit {
		return ebiten.Termination
	}
	return nil
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
		view.Tick < game.options.StopAfterTicks {
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
	game.canvas.Fill(color.RGBA{R: 16, G: 20, B: 28, A: 255})
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
	game.drawHUD(view)
}

func (game *Game) drawGround(view View) {
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
	spec, found := spriteFrame(view.Tick, entity)
	if found {
		source := game.images[spec.asset]
		if source != nil {
			sub := source.SubImage(spec.source).(*ebiten.Image)
			options := &ebiten.DrawImageOptions{}
			options.Filter = ebiten.FilterNearest
			options.GeoM.Translate(
				-spec.originX,
				-spec.originY,
			)
			options.GeoM.Scale(spec.scale*zoom, spec.scale*zoom)
			options.GeoM.Translate(x, y)
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
		vector.DrawFilledCircle(
			game.canvas,
			float32(x),
			float32(y),
			float32(radius*zoom),
			fill,
			true,
		)
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
	case "slash":
	default:
		return
	}
	source := game.images["image.slash"]
	if source == nil {
		return
	}
	options := &ebiten.DrawImageOptions{}
	options.Filter = ebiten.FilterNearest
	options.GeoM.Translate(
		-float64(source.Bounds().Dx())/2,
		-float64(source.Bounds().Dy())/2,
	)
	options.GeoM.Scale(scale*zoom, scale*zoom)
	options.GeoM.Rotate(effect.Rotation)
	options.GeoM.Translate(x, y)
	options.ColorScale.ScaleAlpha(float32(opacity))
	game.canvas.DrawImage(source, options)
}

func cameraZoom(view View) float64 {
	if view.Camera.Zoom > 0 {
		return view.Camera.Zoom
	}
	return 1
}

func (game *Game) drawHUD(view View) {
	playerHealth, playerMaximum := 0.0, 0.0
	for _, entity := range view.Entities {
		if entity.SpriteID == "sprite.hero" {
			playerHealth, playerMaximum = entity.Health, entity.MaxHealth
			break
		}
	}
	vector.DrawFilledRect(
		game.canvas,
		16,
		14,
		310,
		78,
		color.RGBA{R: 10, G: 13, B: 19, A: 218},
		false,
	)
	if playerMaximum > 0 {
		vector.DrawFilledRect(
			game.canvas,
			28,
			58,
			210,
			12,
			color.RGBA{R: 47, G: 52, B: 62, A: 255},
			false,
		)
		vector.DrawFilledRect(
			game.canvas,
			28,
			58,
			float32(210*max(0, min(1, playerHealth/playerMaximum))),
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
	game.drawText(
		status,
		28,
		74,
		14,
		color.RGBA{R: 189, G: 203, B: 219, A: 255},
	)
	if view.HUD.Help != "" {
		game.drawText(
			view.HUD.Help,
			22,
			ScreenHeight-24,
			14,
			color.RGBA{R: 192, G: 205, B: 218, A: 255},
		)
	}
	if view.HUD.Dialogue != "" {
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
