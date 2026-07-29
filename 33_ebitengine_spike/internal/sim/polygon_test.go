package sim

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"
)

func TestWallOverlapsRectUsesExactPolygonAndStrictEdgeTouch(t *testing.T) {
	t.Parallel()
	diamond := polygonWall(
		"portal",
		Vec{X: Pixels(10), Y: Pixels(0)},
		Vec{X: Pixels(20), Y: Pixels(10)},
		Vec{X: Pixels(10), Y: Pixels(20)},
		Vec{X: Pixels(0), Y: Pixels(10)},
	)
	tests := []struct {
		name string
		rect Rect
		want bool
	}{
		{
			name: "inside",
			rect: Rect{
				MinX: Pixels(9),
				MinY: Pixels(9),
				MaxX: Pixels(11),
				MaxY: Pixels(11),
			},
			want: true,
		},
		{
			name: "bounds only",
			rect: Rect{
				MinX: Pixels(0),
				MinY: Pixels(0),
				MaxX: Pixels(2),
				MaxY: Pixels(2),
			},
			want: false,
		},
		{
			name: "touching vertex edge",
			rect: Rect{
				MinX: Pixels(20),
				MinY: Pixels(9),
				MaxX: Pixels(22),
				MaxY: Pixels(11),
			},
			want: false,
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			got, err := WallOverlapsRect(diamond, test.rect)
			if err != nil {
				t.Fatal(err)
			}
			if got != test.want {
				t.Fatalf("WallOverlapsRect() = %t, want %t", got, test.want)
			}
		})
	}
	if _, err := WallOverlapsRect(diamond, Rect{}); err == nil {
		t.Fatal("invalid overlap rectangle was accepted")
	}
}

func TestRectangleWallRetainsOriginalJSONShape(t *testing.T) {
	t.Parallel()
	wall := Wall{
		ID: "rectangle",
		Rect: Rect{
			MinX: Pixels(10),
			MinY: Pixels(20),
			MaxX: Pixels(30),
			MaxY: Pixels(40),
		},
	}
	encoded, err := json.Marshal(wall)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(encoded), "points") {
		t.Fatalf("rectangle wire shape gained polygon data: %s", encoded)
	}
	var decoded Wall
	if err := json.Unmarshal(encoded, &decoded); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(decoded, wall) {
		t.Fatalf("rectangle JSON round trip = %#v, want %#v", decoded, wall)
	}
}

func TestPolygonWallRejectsMalformedGeometry(t *testing.T) {
	t.Parallel()
	valid := polygonWall(
		"polygon",
		Vec{X: Pixels(120), Y: Pixels(80)},
		Vec{X: Pixels(180), Y: Pixels(80)},
		Vec{X: Pixels(180), Y: Pixels(140)},
		Vec{X: Pixels(120), Y: Pixels(140)},
	)
	tests := []struct {
		name string
		wall Wall
	}{
		{
			name: "too few points",
			wall: Wall{
				ID: "polygon",
				Rect: Rect{
					MinX: Pixels(120),
					MinY: Pixels(80),
					MaxX: Pixels(180),
					MaxY: Pixels(140),
				},
				Points: []Vec{
					{X: Pixels(120), Y: Pixels(80)},
					{X: Pixels(180), Y: Pixels(140)},
				},
			},
		},
		{
			name: "bounds mismatch",
			wall: func() Wall {
				result := cloneWall(valid)
				result.Rect.MaxX++
				return result
			}(),
		},
		{
			name: "repeated point",
			wall: polygonWall(
				"polygon",
				Vec{X: Pixels(120), Y: Pixels(80)},
				Vec{X: Pixels(180), Y: Pixels(80)},
				Vec{X: Pixels(180), Y: Pixels(140)},
				Vec{X: Pixels(120), Y: Pixels(80)},
			),
		},
		{
			name: "collinear edge",
			wall: polygonWall(
				"polygon",
				Vec{X: Pixels(120), Y: Pixels(80)},
				Vec{X: Pixels(150), Y: Pixels(80)},
				Vec{X: Pixels(180), Y: Pixels(80)},
				Vec{X: Pixels(180), Y: Pixels(140)},
				Vec{X: Pixels(120), Y: Pixels(140)},
			),
		},
		{
			name: "concave",
			wall: polygonWall(
				"polygon",
				Vec{X: Pixels(120), Y: Pixels(80)},
				Vec{X: Pixels(180), Y: Pixels(80)},
				Vec{X: Pixels(150), Y: Pixels(105)},
				Vec{X: Pixels(180), Y: Pixels(140)},
				Vec{X: Pixels(120), Y: Pixels(140)},
			),
		},
		{
			name: "self intersecting",
			wall: polygonWall(
				"polygon",
				Vec{X: Pixels(120), Y: Pixels(80)},
				Vec{X: Pixels(180), Y: Pixels(140)},
				Vec{X: Pixels(120), Y: Pixels(140)},
				Vec{X: Pixels(180), Y: Pixels(80)},
			),
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			config := baseConfig()
			config.Walls = []Wall{test.wall}
			if _, err := New(config); err == nil {
				t.Fatal("malformed polygon was accepted")
			}
		})
	}
}

func TestPolygonMovementSlidesAndCannotTunnel(t *testing.T) {
	t.Parallel()
	wall := polygonWall(
		"diamond",
		Vec{X: Pixels(100), Y: Pixels(100)},
		Vec{X: Pixels(150), Y: Pixels(50)},
		Vec{X: Pixels(200), Y: Pixels(100)},
		Vec{X: Pixels(150), Y: Pixels(150)},
	)
	tests := []struct {
		name  string
		start Vec
		input Input
		want  Vec
	}{
		{
			name:  "left to right",
			start: Vec{X: Pixels(50), Y: Pixels(100)},
			input: Input{MoveX: 1},
			want:  Vec{X: Pixels(95), Y: Pixels(100)},
		},
		{
			name:  "right to left",
			start: Vec{X: Pixels(250), Y: Pixels(100)},
			input: Input{MoveX: -1},
			want:  Vec{X: Pixels(205), Y: Pixels(100)},
		},
		{
			name:  "top to bottom",
			start: Vec{X: Pixels(150), Y: Pixels(20)},
			input: Input{MoveY: 1},
			want:  Vec{X: Pixels(150), Y: Pixels(45)},
		},
		{
			name:  "bottom to top",
			start: Vec{X: Pixels(150), Y: Pixels(180)},
			input: Input{MoveY: -1},
			want:  Vec{X: Pixels(150), Y: Pixels(155)},
		},
	}
	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			t.Parallel()
			config := baseConfig()
			config.Entities = config.Entities[:1]
			config.Entities[0].Position = test.start
			config.Entities[0].MovePerTick = Pixels(200)
			config.Walls = []Wall{wall}
			simulation := mustNew(t, config)

			simulation.Tick(test.input)
			hero := entityByID(t, simulation.Snapshot(), "hero")
			if hero.Position != test.want {
				t.Fatalf(
					"large movement tunneled through polygon: position=%#v, want %#v",
					hero.Position,
					test.want,
				)
			}
			if wallOverlapsRect(wall, entityRect(hero.Position, hero.Body)) {
				t.Fatalf("edge-touching result counts as overlap: %#v", hero)
			}
			simulation.Tick(test.input)
			if got := entityByID(
				t,
				simulation.Snapshot(),
				"hero",
			).Position; got != test.want {
				t.Fatalf("contact position drifted: got %#v, want %#v", got, test.want)
			}
		})
	}

	config := baseConfig()
	config.Entities = config.Entities[:1]
	config.Entities[0].Position = Vec{X: Pixels(50), Y: Pixels(100)}
	config.Entities[0].MovePerTick = Pixels(10)
	config.Walls = []Wall{wall}
	simulation := mustNew(t, config)
	for range 6 {
		simulation.Tick(Input{MoveX: 1, MoveY: 1})
	}
	hero := entityByID(t, simulation.Snapshot(), "hero")
	if wallOverlapsRect(
		config.Walls[0],
		entityRect(hero.Position, hero.Body),
	) {
		t.Fatalf("diagonal slide ended inside polygon: %#v", hero)
	}
	if hero.Position.Y <= Pixels(100) {
		t.Fatalf("polygon did not preserve sliding axis: %#v", hero.Position)
	}
}

func TestPolygonGeometryStaysDeterministicNearCoordLimits(t *testing.T) {
	t.Parallel()
	limit := maxAbsCoord - 1
	wall := polygonWall(
		"limit",
		Vec{X: 0, Y: -limit},
		Vec{X: limit, Y: 0},
		Vec{X: 0, Y: limit},
		Vec{X: -limit, Y: 0},
	)
	if err := ValidateWall(wall); err != nil {
		t.Fatalf("near-limit polygon was rejected: %v", err)
	}
	if !wallOverlapsRect(wall, Rect{
		MinX: -1,
		MinY: -1,
		MaxX: 1,
		MaxY: 1,
	}) {
		t.Fatal("near-limit polygon collision lost integer precision")
	}
	if minimum, maximum, ok := wallAxisCollisionInterval(
		wall,
		Body{HalfWidth: 1, HalfHeight: 1, Solid: true},
		0,
		true,
	); !ok || minimum >= 0 || maximum <= 0 {
		t.Fatalf(
			"near-limit sweep interval = (%d, %d, %v)",
			minimum,
			maximum,
			ok,
		)
	}

	outside := cloneWall(wall)
	outside.Points[1].X = maxAbsCoord + 1
	outside.Rect.MaxX = maxAbsCoord + 1
	if err := ValidateWall(outside); err == nil {
		t.Fatal("out-of-range fixed-point polygon was accepted")
	}
}

func TestPolygonCollisionGuardsSpawnAndSessionLoad(t *testing.T) {
	t.Parallel()
	config := baseConfig()
	config.Walls = []Wall{polygonWall(
		"diamond",
		Vec{X: Pixels(120), Y: Pixels(110)},
		Vec{X: Pixels(150), Y: Pixels(80)},
		Vec{X: Pixels(180), Y: Pixels(110)},
		Vec{X: Pixels(150), Y: Pixels(140)},
	)}
	simulation := mustNew(t, config)
	inside := previewEntity("inside", Pixels(150), Pixels(110))
	inside.Body.Solid = true
	if err := simulation.SpawnEntity(
		inside,
	); err == nil || !strings.Contains(err.Error(), "overlaps wall") {
		t.Fatalf("polygon-overlapping spawn error = %v", err)
	}

	before := simulation.SaveSession()
	corrupt := simulation.SaveSession()
	for index := range corrupt.Entities {
		if corrupt.Entities[index].ID == "hero" {
			corrupt.Entities[index].Position = Vec{
				X: Pixels(150),
				Y: Pixels(110),
			}
		}
	}
	if err := simulation.LoadSession(corrupt); err == nil ||
		!strings.Contains(err.Error(), "overlaps a wall") {
		t.Fatalf("polygon-overlapping session error = %v", err)
	}
	if got := simulation.SaveSession(); !reflect.DeepEqual(got, before) {
		t.Fatal("rejected polygon-overlapping session mutated simulation")
	}
}

func TestPolygonRenderFrameIsExactDetachedAndSetWallBecomesRectangle(
	t *testing.T,
) {
	t.Parallel()
	config := baseConfig()
	authored := polygonWall(
		"editable",
		Vec{X: Pixels(120), Y: Pixels(80)},
		Vec{X: Pixels(180), Y: Pixels(90)},
		Vec{X: Pixels(170), Y: Pixels(140)},
		Vec{X: Pixels(125), Y: Pixels(130)},
	)
	config.Walls = []Wall{authored}
	simulation := mustNew(t, config)
	expectedPoints := append([]Vec(nil), authored.Points...)

	config.Walls[0].Points[0].X = -999
	frame := simulation.RenderFrame()
	if !reflect.DeepEqual(frame.Walls[0].Points, expectedPoints) {
		t.Fatalf("render polygon differs from authored points: %#v", frame.Walls[0])
	}
	frame.Walls[0].Points[0].X = -999
	if simulation.RenderFrame().Walls[0].Points[0].X == -999 {
		t.Fatal("RenderFrame aliases polygon point storage")
	}

	replacement := Rect{
		MinX: Pixels(210),
		MinY: Pixels(80),
		MaxX: Pixels(230),
		MaxY: Pixels(140),
	}
	if err := simulation.SetWall("editable", replacement); err != nil {
		t.Fatal(err)
	}
	edited := simulation.RenderFrame().Walls[0]
	if edited.ID != "editable" || edited.Rect != replacement ||
		len(edited.Points) != 0 {
		t.Fatalf("polygon rectangle replacement = %#v", edited)
	}
}

func polygonWall(id string, points ...Vec) Wall {
	result := Wall{
		ID:     id,
		Points: append([]Vec(nil), points...),
		Rect: Rect{
			MinX: points[0].X,
			MinY: points[0].Y,
			MaxX: points[0].X,
			MaxY: points[0].Y,
		},
	}
	for _, point := range points[1:] {
		result.Rect.MinX = minCoord(result.Rect.MinX, point.X)
		result.Rect.MinY = minCoord(result.Rect.MinY, point.Y)
		result.Rect.MaxX = maxCoord(result.Rect.MaxX, point.X)
		result.Rect.MaxY = maxCoord(result.Rect.MaxY, point.Y)
	}
	return result
}
